import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _bookTitleController = TextEditingController();
  final _bookAuthorController = TextEditingController();
  final _bookIsbnController = TextEditingController();
  final _bookTotalController = TextEditingController(text: '1');
  final _bookAvailableController = TextEditingController(text: '1');

  int? _selectedBorrowStudent;
  int? _selectedBorrowBook;
  DateTime _borrowDate = DateTime.now();
  DateTime _borrowDueDate = DateTime.now().add(const Duration(days: 7));
  final _borrowPenaltyController = TextEditingController(text: '0');

  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _books = [];
  List<Map<String, dynamic>> _borrows = [];
  List<Map<String, dynamic>> _students = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _bookTitleController.dispose();
    _bookAuthorController.dispose();
    _bookIsbnController.dispose();
    _bookTotalController.dispose();
    _bookAvailableController.dispose();
    _borrowPenaltyController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      final dio = ref.read(dioProvider);
      final results = await Future.wait([
        dio.get('/books/'),
        dio.get('/borrows/'),
        dio.get('/students/'),
      ]);

      if (!mounted) return;

      setState(() {
        _books = _extractRows(results[0].data);
        _borrows = _extractRows(results[1].data);
        _students = _extractRows(results[2].data);

        _selectedBorrowBook ??= _books.isNotEmpty
            ? _asInt(_books.first['id'])
            : null;
        _selectedBorrowStudent ??= _students.isNotEmpty
            ? _asInt(_students.first['id'])
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      _showMessage('Erreur chargement bibliothèque: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createBook() async {
    final total = int.tryParse(_bookTotalController.text.trim());
    final available = int.tryParse(_bookAvailableController.text.trim());

    if (_bookTitleController.text.trim().isEmpty ||
        _bookAuthorController.text.trim().isEmpty ||
        _bookIsbnController.text.trim().isEmpty ||
        total == null ||
        available == null) {
      _showMessage('Complétez les champs livre.');
      return;
    }

    setState(() => _saving = true);

    try {
      await ref
          .read(dioProvider)
          .post(
            '/books/',
            data: {
              'title': _bookTitleController.text.trim(),
              'author': _bookAuthorController.text.trim(),
              'isbn': _bookIsbnController.text.trim(),
              'quantity_total': total,
              'quantity_available': available,
            },
          );

      if (!mounted) return;
      _bookTitleController.clear();
      _bookAuthorController.clear();
      _bookIsbnController.clear();
      _bookTotalController.text = '1';
      _bookAvailableController.text = '1';
      _showMessage('Livre créé avec succès.', isSuccess: true);
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Erreur création livre: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createBorrow() async {
    final student = _selectedBorrowStudent;
    final book = _selectedBorrowBook;
    final penalty = double.tryParse(_borrowPenaltyController.text.trim()) ?? 0;

    if (student == null || book == null) {
      _showMessage('Sélectionnez élève et livre.');
      return;
    }

    setState(() => _saving = true);

    try {
      await ref
          .read(dioProvider)
          .post(
            '/borrows/',
            data: {
              'student': student,
              'book': book,
              'borrowed_at': _apiDate(_borrowDate),
              'due_date': _apiDate(_borrowDueDate),
              'penalty_amount': penalty,
            },
          );

      if (!mounted) return;
      _showMessage('Emprunt enregistré.', isSuccess: true);
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Erreur enregistrement emprunt: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message, {bool isSuccess = false}) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    const successColor = Color(0xFF197A43);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: isSuccess ? successColor : null,
          content: Text(
            message,
            style: isSuccess ? const TextStyle(color: Colors.white) : null,
          ),
        ),
      );
  }

  Future<void> _refreshLibrary() async {
    await _loadData();
  }

  Widget _metricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return RefreshIndicator(
        onRefresh: _refreshLibrary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: const [
            SizedBox(
              height: 460,
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final studentsById = {for (final s in _students) _asInt(s['id']): s};
    final booksById = {for (final b in _books) _asInt(b['id']): b};

    final availableBooks = _books.where((b) {
      final qty = int.tryParse(b['quantity_available']?.toString() ?? '') ?? 0;
      return qty > 0;
    }).length;

    final overdueBorrows = _borrows.where((br) {
      final dueDateRaw = br['due_date']?.toString();
      if (dueDateRaw == null || dueDateRaw.isEmpty) return false;
      final dueDate = DateTime.tryParse(dueDateRaw);
      if (dueDate == null) return false;
      final returned =
          br['returned_at'] != null &&
          br['returned_at'].toString().trim().isNotEmpty;
      return !returned && dueDate.isBefore(DateTime.now());
    }).length;

    final createBookPanel = _sectionCard(
      title: 'Ajouter un livre',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _bookTitleController,
            decoration: const InputDecoration(labelText: 'Titre'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _bookAuthorController,
            decoration: const InputDecoration(labelText: 'Auteur'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _bookIsbnController,
            decoration: const InputDecoration(labelText: 'ISBN'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _bookTotalController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Quantite totale'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _bookAvailableController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Quantite disponible'),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _saving ? null : _createBook,
            child: const Text('Ajouter livre'),
          ),
        ],
      ),
    );

    final createBorrowPanel = _sectionCard(
      title: 'Enregistrer un emprunt',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<int>(
            initialValue: _selectedBorrowStudent,
            decoration: const InputDecoration(labelText: 'Eleve'),
            items: _students
                .map(
                  (s) => DropdownMenuItem<int>(
                    value: _asInt(s['id']),
                    child: Text(
                      '${s['matricule']} • ${s['user_full_name'] ?? ''}',
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _selectedBorrowStudent = v),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: _selectedBorrowBook,
            decoration: const InputDecoration(labelText: 'Livre'),
            items: _books
                .map(
                  (b) => DropdownMenuItem<int>(
                    value: _asInt(b['id']),
                    child: Text(
                      '${b['title']} (dispo: ${b['quantity_available']})',
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _selectedBorrowBook = v),
          ),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date emprunt'),
            subtitle: Text(_apiDate(_borrowDate)),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _borrowDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _borrowDate = picked);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date limite retour'),
            subtitle: Text(_apiDate(_borrowDueDate)),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _borrowDueDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _borrowDueDate = picked);
            },
          ),
          TextField(
            controller: _borrowPenaltyController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Penalite (optionnel)',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.tonal(
            onPressed: _saving ? null : _createBorrow,
            child: const Text('Creer emprunt'),
          ),
        ],
      ),
    );

    final booksPanel = _sectionCard(
      title: 'Livres disponibles',
      child: _books.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('Aucun livre enregistre'),
            )
          : Column(
              children: _books
                  .map(
                    (b) => Card(
                      child: ListTile(
                        title: Text('${b['title']}'),
                        subtitle: Text('${b['author']} • ISBN ${b['isbn']}'),
                        trailing: Text(
                          '${b['quantity_available']}/${b['quantity_total']}',
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
    );

    final borrowsPanel = _sectionCard(
      title: 'Historique emprunts',
      child: _borrows.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('Aucun emprunt enregistre'),
            )
          : Column(
              children: _borrows.map((br) {
                final student = studentsById[_asInt(br['student'])];
                final book = booksById[_asInt(br['book'])];
                return Card(
                  child: ListTile(
                    title: Text('${book?['title'] ?? 'Livre'}'),
                    subtitle: Text(
                      '${student?['matricule'] ?? ''} • ${student?['user_full_name'] ?? ''}\n'
                      '${br['borrowed_at']} -> ${br['due_date']}',
                    ),
                    isThreeLine: true,
                  ),
                );
              }).toList(),
            ),
    );

    return RefreshIndicator(
      onRefresh: _refreshLibrary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bibliotheque',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Gestion des livres et suivi des emprunts/retours.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : _loadData,
                icon: const Icon(Icons.sync),
                label: const Text('Actualiser'),
              ),
            ],
          ),
          if (_saving) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _metricChip('Livres', '${_books.length}'),
                _metricChip('Disponibles', '$availableBooks'),
                _metricChip('Emprunts', '${_borrows.length}'),
                _metricChip('Retards', '$overdueBorrows'),
                _metricChip('Eleves', '${_students.length}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1120;
              final leftPanel = Column(
                children: [
                  createBookPanel,
                  const SizedBox(height: 12),
                  createBorrowPanel,
                ],
              );
              final rightPanel = Column(
                children: [
                  booksPanel,
                  const SizedBox(height: 12),
                  borrowsPanel,
                ],
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: leftPanel),
                    const SizedBox(width: 12),
                    Expanded(flex: 5, child: rightPanel),
                  ],
                );
              }

              return Column(
                children: [leftPanel, const SizedBox(height: 12), rightPanel],
              );
            },
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _extractRows(dynamic data) {
    final List<dynamic> rows;
    if (data is Map<String, dynamic> && data['results'] is List) {
      rows = data['results'] as List<dynamic>;
    } else if (data is List<dynamic>) {
      rows = data;
    } else {
      rows = [];
    }

    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _apiDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }
}

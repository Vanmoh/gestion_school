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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur chargement bibliothèque: $error')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complétez les champs livre.')),
      );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Livre créé avec succès.')));
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur création livre: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createBorrow() async {
    final student = _selectedBorrowStudent;
    final book = _selectedBorrowBook;
    final penalty = double.tryParse(_borrowPenaltyController.text.trim()) ?? 0;

    if (student == null || book == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionnez élève et livre.')),
      );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Emprunt enregistré.')));
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur enregistrement emprunt: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final studentsById = {for (final s in _students) _asInt(s['id']): s};
    final booksById = {for (final b in _books) _asInt(b['id']): b};

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('Bibliothèque', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Gestion des livres et suivi des emprunts/retours.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ajouter un livre',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
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
                  decoration: const InputDecoration(
                    labelText: 'Quantité totale',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _bookAvailableController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantité disponible',
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _saving ? null : _createBook,
                  child: const Text('Ajouter livre'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Enregistrer un emprunt',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _selectedBorrowStudent,
                  decoration: const InputDecoration(labelText: 'Élève'),
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
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Pénalité (optionnel)',
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.tonal(
                  onPressed: _saving ? null : _createBorrow,
                  child: const Text('Créer emprunt'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Livres disponibles',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_books.isEmpty)
                  const Text('Aucun livre enregistré')
                else
                  ..._books.map(
                    (b) => Card(
                      child: ListTile(
                        title: Text('${b['title']}'),
                        subtitle: Text('${b['author']} • ISBN ${b['isbn']}'),
                        trailing: Text(
                          '${b['quantity_available']}/${b['quantity_total']}',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Historique emprunts',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_borrows.isEmpty)
                  const Text('Aucun emprunt enregistré')
                else
                  ..._borrows.map((br) {
                    final student = studentsById[_asInt(br['student'])];
                    final book = booksById[_asInt(br['book'])];
                    return Card(
                      child: ListTile(
                        title: Text('${book?['title'] ?? 'Livre'}'),
                        subtitle: Text(
                          '${student?['matricule'] ?? ''} • ${student?['user_full_name'] ?? ''}\n'
                          '${br['borrowed_at']} → ${br['due_date']}',
                        ),
                        isThreeLine: true,
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ],
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../domain/student.dart';
import '../students_controller.dart';
import '../../../../core/widgets/roster_pdf_preview_dialog.dart';

/// Liste des eleves d'une classe, a l'ecran puis sur papier.
///
/// La recherche ne filtre que l'affichage: une liste d'appel amputee des
/// eleves qui ne correspondent pas a une saisie n'a pas de sens. Les actions
/// portent donc toujours sur la classe entiere, et affichent leur nombre pour
/// que l'ecart avec ce qui est visible ne se decouvre pas apres coup.
class StudentRosterDialog extends ConsumerStatefulWidget {
  final int? classroomId;
  final String status;
  final List<Map<String, dynamic>> classrooms;

  const StudentRosterDialog({
    super.key,
    required this.classroomId,
    required this.status,
    required this.classrooms,
  });

  @override
  ConsumerState<StudentRosterDialog> createState() =>
      _StudentRosterDialogState();
}

class _StudentRosterDialogState extends ConsumerState<StudentRosterDialog> {
  final TextEditingController _searchController = TextEditingController();

  late int? _classroomId = widget.classroomId;
  late String _status = widget.status;
  String _query = '';

  List<Student> _students = const [];
  bool _loading = true;
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final students = await ref
          .read(studentsRepositoryProvider)
          .fetchStudents(
            classroomId: _classroomId,
            isArchived: _status == 'all' ? null : _status == 'archived',
            // Meme tri que le PDF: deux ordres differents pour un meme
            // document se remarquent des la premiere comparaison.
            ordering: 'user__last_name',
          );
      if (!mounted) return;
      setState(() {
        _students = students;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  List<Student> get _visibles {
    if (_query.trim().isEmpty) return _students;
    final needle = _query.trim().toLowerCase();
    return _students
        .where(
          (student) =>
              student.fullName.toLowerCase().contains(needle) ||
              student.matricule.toLowerCase().contains(needle),
        )
        .toList();
  }

  (int, int) get _effectifs {
    var garcons = 0;
    var filles = 0;
    for (final student in _students) {
      final genre = student.gender.toUpperCase();
      if (genre == 'M') garcons++;
      if (genre == 'F') filles++;
    }
    return (garcons, filles);
  }

  String get _classeLabel {
    if (_classroomId == null) return 'Toutes les classes';
    for (final row in widget.classrooms) {
      if (row['id'] == _classroomId) {
        return (row['name'] ?? 'Classe').toString();
      }
    }
    return 'Classe';
  }

  Future<void> _withBusy(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) _toast('Erreur : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() => _withBusy(() async {
    final bytes = await ref
        .read(studentsRepositoryProvider)
        .fetchClassRosterPdf(classroomId: _classroomId, status: _status);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  });

  /// Ouvre le document tel qu'il sera imprime.
  ///
  /// La table ci-dessus montre les donnees, pas la mise en page: l'en-tete de
  /// l'établissement et la colonne d'emargement n'existent que sur le papier.
  Future<void> _showDocument() async {
    final slug = _classeLabel.replaceAll(RegExp(r'\s+'), '_');
    await showDialog<void>(
      context: context,
      builder: (_) => RosterPdfPreviewDialog(
        titre: 'Liste des élèves — $_classeLabel',
        nomFichier: 'liste_$slug.pdf',
        charger: () => ref
            .read(studentsRepositoryProvider)
            .fetchClassRosterPdf(classroomId: _classroomId, status: _status),
      ),
    );
  }

  Future<void> _copyCsv() async {
    if (_students.isEmpty) {
      _toast('Aucun élève à exporter.');
      return;
    }

    const separateur = ';';
    final csv = StringBuffer()
      ..writeln(
        ['N°', 'Matricule', 'Nom et prénoms', 'Sexe', 'Naissance', 'Classe']
            .join(separateur),
      );

    for (var index = 0; index < _students.length; index++) {
      final student = _students[index];
      csv.writeln(
        [
          '${index + 1}',
          _cell(student.matricule),
          _cell(student.fullName),
          _cell(student.gender.toUpperCase()),
          _cell(_date(student.birthDate)),
          _cell(student.classroomName),
        ].join(separateur),
      );
    }

    await Clipboard.setData(ClipboardData(text: csv.toString()));
    if (mounted) {
      _toast('CSV copié (${_students.length} élèves).', succes: true);
    }
  }

  static String _cell(String value) =>
      '"${value.replaceAll('\n', ' ').trim().replaceAll('"', '""')}"';

  static String _date(DateTime? value) {
    if (value == null) return '';
    final jour = value.day.toString().padLeft(2, '0');
    final mois = value.month.toString().padLeft(2, '0');
    return '$jour/$mois/${value.year}';
  }

  void _toast(String message, {bool succes = false}) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: succes ? scheme.primary : scheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final (garcons, filles) = _effectifs;
    final visibles = _visibles;
    final filtre = _query.trim().isNotEmpty;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.groups_2_outlined, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Liste des élèves',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildSelectors(scheme),
              const SizedBox(height: 12),
              _buildEffectifBand(scheme, textTheme, garcons, filles),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: 'Rechercher dans la liste…',
                  border: const OutlineInputBorder(),
                  suffixIcon: filtre
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                ),
              ),
              if (filtre)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'La recherche ne change que l’affichage : '
                    '${visibles.length} sur ${_students.length}. '
                    'L’impression et l’export portent sur les '
                    '${_students.length} élèves.',
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Expanded(child: _buildTable(scheme, textTheme, visibles)),
              const SizedBox(height: 14),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectors(ColorScheme scheme) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 240,
          child: DropdownButtonFormField<int?>(
            initialValue: _classroomId,
            isDense: true,
            // Sans cela le bouton se dimensionne sur son item le plus large
            // ("Toutes les classes") et deborde de sa boite.
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Classe',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('Toutes les classes'),
              ),
              for (final row in widget.classrooms)
                DropdownMenuItem<int?>(
                  value: row['id'] as int?,
                  child: Text((row['name'] ?? '').toString()),
                ),
            ],
            onChanged: _loading
                ? null
                : (value) {
                    setState(() => _classroomId = value);
                    _load();
                  },
          ),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String>(
            initialValue: _status,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Statut',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'active', child: Text('Actifs')),
              DropdownMenuItem(value: 'archived', child: Text('Archivés')),
              DropdownMenuItem(value: 'all', child: Text('Tous')),
            ],
            onChanged: _loading
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _status = value);
                    _load();
                  },
          ),
        ),
      ],
    );
  }

  Widget _buildEffectifBand(
    ColorScheme scheme,
    TextTheme textTheme,
    int garcons,
    int filles,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _loading
            ? 'Chargement…'
            : 'Effectif : ${_students.length}  ·  $garcons G / $filles F'
                  '  ·  $_classeLabel',
        style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildTable(
    ColorScheme scheme,
    TextTheme textTheme,
    List<Student> visibles,
  ) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: scheme.error, size: 36),
            const SizedBox(height: 8),
            Text(_error, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }
    if (visibles.isEmpty) {
      return Center(
        child: Text(
          _students.isEmpty
              ? 'Aucun élève dans cette sélection.'
              : 'Aucun élève ne correspond à la recherche.',
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }

    return Scrollbar(
      child: SingleChildScrollView(
        child: SizedBox(
          width: double.infinity,
          child: DataTable(
            headingRowHeight: 40,
            dataRowMinHeight: 38,
            dataRowMaxHeight: 46,
            columns: const [
              DataColumn(label: Text('N°')),
              DataColumn(label: Text('Matricule')),
              DataColumn(label: Text('Nom et prénoms')),
              DataColumn(label: Text('Sexe')),
              DataColumn(label: Text('Naissance')),
            ],
            rows: [
              for (final student in visibles)
                DataRow(
                  cells: [
                    // Le numero suit la liste complete: renumeroter la vue
                    // filtree ferait diverger l'ecran du papier.
                    DataCell(Text('${_students.indexOf(student) + 1}')),
                    DataCell(Text(student.matricule)),
                    DataCell(Text(student.fullName)),
                    DataCell(
                      Text(
                        student.gender.toUpperCase().isEmpty
                            ? '—'
                            : student.gender.toUpperCase(),
                      ),
                    ),
                    DataCell(Text(_date(student.birthDate))),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActions() {
    final total = _students.length;
    final actif = !_loading && !_busy && total > 0;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.end,
      children: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
        OutlinedButton.icon(
          onPressed: actif ? _copyCsv : null,
          icon: const Icon(Icons.content_copy_outlined, size: 18),
          label: Text('Copier CSV ($total)'),
        ),
        OutlinedButton.icon(
          onPressed: actif ? _showDocument : null,
          icon: const Icon(Icons.description_outlined, size: 18),
          label: const Text('Afficher la liste'),
        ),
        FilledButton.icon(
          onPressed: actif ? _print : null,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.print_outlined, size: 18),
          label: Text('Imprimer ($total)'),
        ),
      ],
    );
  }
}

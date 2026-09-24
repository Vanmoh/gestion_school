import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../../core/permissions/module_permissions.dart';
import '../../../users/presentation/users_controller.dart';
import '../../../users/presentation/widgets/dialogue_acces_rouverts.dart';
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

  /// Ouvre la palette de l'élève cliqué, celle de « Gestion des élèves ».
  ///
  /// Une ligne ne menait nulle part: pour regarder un élève aperçu dans la
  /// liste, il fallait refermer la fenêtre et le chercher par son nom. Et la
  /// vue par classe, qui rendait ce service, ouvrait une présentation
  /// concurrente de la palette — deux fiches pour un même élève.
  final void Function(Student)? onOuvrirEleve;

  const StudentRosterDialog({
    super.key,
    required this.classroomId,
    required this.status,
    required this.classrooms,
    this.onOuvrirEleve,
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

  /// Identifie le chargement en cours: enchainer deux classes laissait la
  /// reponse la plus lente s'afficher sous l'en-tete de l'autre.
  int _chargementEnCours = 0;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    final ticket = ++_chargementEnCours;
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
      if (!mounted || ticket != _chargementEnCours) return;
      setState(() {
        _students = students;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || ticket != _chargementEnCours) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  /// Restreint la liste aux élèves dont l'inscription retient les documents.
  ///
  /// C'est la liste que le secrétariat sort pour relancer les familles: sans
  /// elle, il faudrait ouvrir les fiches une par une pour savoir qui n'est
  /// pas à jour.
  bool _inscriptionEnAttenteSeulement = false;

  List<Student> get _visibles {
    final base = _inscriptionEnAttenteSeulement
        ? _students
              .where((eleve) => eleve.inscriptionEnAttente)
              .toList(growable: false)
        : _students;
    if (_query.trim().isEmpty) return base;
    final needle = _query.trim().toLowerCase();
    return base
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

  /// Rouvrir un acces, c'est poser un mot de passe sur le compte de
  /// quelqu'un: cela releve de l'administration des comptes, pas de la
  /// consultation d'une liste de classe. Le serveur le verifie de toute
  /// facon; le bouton ne s'affiche pas pour rien.
  bool get _peutRouvrirLesAcces =>
      ref.read(currentPermissionsProvider).canWrite('users');

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

  /// Rend leurs acces aux familles de cette classe qui n'ont jamais pu entrer.
  ///
  /// Le geste vit ici parce que c'est le seul ecran qui raisonne par classe
  /// entiere. Le serveur ne touche qu'aux comptes jamais utilises: une
  /// famille qui se connecte deja garde son mot de passe, et une classe ne
  /// peut donc pas se retrouver dehors parce qu'on a voulu en depanner
  /// trois.
  Future<void> _rouvrirLesAcces() {
    final classe = _classroomId;
    if (classe == null) {
      // Rouvrir « toutes les classes » d'un geste n'a pas ete demande, et
      // se ferait sans que personne puisse relire ce qui a bouge.
      _toast('Choisissez une classe avant de rouvrir des accès.');
      return Future<void>.value();
    }

    return _withBusy(() async {
      final acces = await ref
          .read(usersRepositoryProvider)
          .rouvrirLesAcces(classroomId: classe);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        // Les mots de passe n'existent en clair qu'ici: fermer par megarde
        // obligerait a tout reinitialiser.
        barrierDismissible: false,
        builder: (_) => DialogueAccesRouverts(acces: acces, classe: _classeLabel),
      );
    });
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
        FilterChip(
          key: const Key('filtre-inscription-en-attente'),
          selected: _inscriptionEnAttenteSeulement,
          label: const Text('Inscription en attente'),
          avatar: const Icon(Icons.how_to_reg_outlined, size: 18),
          onSelected: _loading
              ? null
              : (valeur) => setState(
                  () => _inscriptionEnAttenteSeulement = valeur,
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

  /// Referme la fenêtre, puis ouvre la palette de l'élève.
  ///
  /// Dans cet ordre: la palette s'affiche dans la page qui est derrière, et
  /// la laisser sous une fenêtre ouverte la rendrait invisible.
  void _ouvrir(Student student) {
    final ouvrir = widget.onOuvrirEleve;
    if (ouvrir == null) return;
    Navigator.of(context).pop();
    ouvrir(student);
  }

  /// Les élèves groupés par classe, dans l'ordre alphabétique des classes.
  ///
  /// « Sans classe » ferme la marche: c'est une anomalie à traiter, pas une
  /// classe, et la placer entre deux niveaux la ferait passer pour telle.
  Map<String, List<Student>> _parClasse(List<Student> eleves) {
    const sansClasse = 'Sans classe';
    final groupes = <String, List<Student>>{};
    for (final eleve in eleves) {
      final nom = eleve.classroomName.trim().isEmpty
          ? sansClasse
          : eleve.classroomName.trim();
      groupes.putIfAbsent(nom, () => <Student>[]).add(eleve);
    }

    final noms = groupes.keys.where((nom) => nom != sansClasse).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (groupes.containsKey(sansClasse)) noms.add(sansClasse);

    return {for (final nom in noms) nom: groupes[nom]!};
  }

  Widget _buildGroupes(
    ColorScheme scheme,
    TextTheme textTheme,
    List<Student> visibles,
  ) {
    final groupes = _parClasse(visibles);

    return Scrollbar(
      child: ListView(
        children: [
          for (final entree in groupes.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
              child: Row(
                children: [
                  Icon(
                    Icons.groups_2_outlined,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    entree.key,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // L'effectif de la classe, et non celui de l'affichage:
                  // une recherche en cours ne doit pas faire croire qu'une
                  // classe a perdu des élèves.
                  Text(
                    '${entree.value.length} sur ${_effectifDeLaClasse(entree.key)}',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            for (final eleve in entree.value)
              ListTile(
                key: Key('eleve-${eleve.id}'),
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    eleve.fullName.characters.take(1).toString().toUpperCase(),
                    style: textTheme.labelMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                title: Text(eleve.fullName),
                subtitle: Text(eleve.matricule),
                trailing: widget.onOuvrirEleve == null
                    ? null
                    : const Icon(Icons.chevron_right),
                onTap: widget.onOuvrirEleve == null
                    ? null
                    : () => _ouvrir(eleve),
              ),
          ],
        ],
      ),
    );
  }

  int _effectifDeLaClasse(String nom) {
    const sansClasse = 'Sans classe';
    return _students
        .where(
          (eleve) =>
              (eleve.classroomName.trim().isEmpty
                  ? sansClasse
                  : eleve.classroomName.trim()) ==
              nom,
        )
        .length;
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

    // Sans classe choisie, la liste couvre l'école entière: elle se lit par
    // classe, avec son effectif. C'est ce que « Vue par classe » offrait à
    // part, et qui n'a plus de raison d'être un écran de son côté.
    if (_classroomId == null) {
      return _buildGroupes(scheme, textTheme, visibles);
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
                  onSelectChanged: widget.onOuvrirEleve == null
                      ? null
                      : (_) => _ouvrir(student),
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
        if (_peutRouvrirLesAcces)
          OutlinedButton.icon(
            key: const Key('rouvrir-les-acces'),
            onPressed: actif ? _rouvrirLesAcces : null,
            icon: const Icon(Icons.key_outlined, size: 18),
            label: const Text('Rouvrir les accès'),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/module_permissions.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/discipline_incident.dart';
import 'discipline_controller.dart';
import 'widgets/incident_review_dialog.dart';

class DisciplinePage extends ConsumerStatefulWidget {
  const DisciplinePage({super.key});

  @override
  ConsumerState<DisciplinePage> createState() => _DisciplinePageState();
}

class _DisciplinePageState extends ConsumerState<DisciplinePage> {
  final _descriptionController = TextEditingController();
  final _sanctionController = TextEditingController();
  final _searchController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  List<DisciplineStudentOption> _students = const [];
  List<DisciplineIncident> _incidents = const [];
  List<DisciplineCategoryOption> _categories = const [];

  int? _selectedStudentId;
  String? _selectedCategory;
  DateTime _incidentDate = DateTime.now();
  String _severity = 'medium';
  String _status = 'open';
  bool _parentNotified = false;

  String _filtreStatut = '';
  String _filtreGravite = '';

  /// Droits lus sur la matrice servie par le backend, et nulle part ailleurs.
  ///
  /// Une liste de roles recopiee dans le `build` cohabitait avec cette
  /// lecture: le promoteur, en lecture seule cote serveur, obtenait un
  /// formulaire entierement actif et n'apprenait le refus qu'au moment
  /// d'enregistrer. Les deux sources divergeaient, il n'en reste qu'une.
  ModulePermission get _droits =>
      ref.read(currentPermissionsProvider).of('discipline');

  /// L'enseignant declare mais n'arbitre pas.
  ///
  /// Ce n'est pas un niveau de droit -- la matrice lui accorde bien
  /// l'ecriture -- mais une regle metier que `perform_create` applique cote
  /// serveur en forcant statut ouvert, sanction vide et parents non informes.
  /// L'ecran la reflete plutot que de laisser saisir des champs qui seront
  /// silencieusement ecrases.
  bool get _estEnseignant =>
      ref.read(authControllerProvider).value?.role == 'teacher';

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadData);
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _sanctionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final repository = ref.read(disciplineRepositoryProvider);
      final authUser = ref.read(authControllerProvider).value;
      final peutDeclarer = _droits.canWrite;

      final resultats = await Future.wait([
        repository.fetchIncidents(
          search: _searchController.text,
          status: _filtreStatut,
          severity: _filtreGravite,
        ),
        // Le selecteur d'élèves ne sert qu'a declarer: un profil en lecture
        // seule n'a pas a payer le parcours complet de l'effectif.
        if (peutDeclarer)
          repository.fetchSelectableStudents(
            asTeacher: _estEnseignant,
            currentUserId: authUser?.id,
          )
        else
          Future.value(const <DisciplineStudentOption>[]),
        if (peutDeclarer)
          repository.fetchCategories()
        else
          Future.value(const <DisciplineCategoryOption>[]),
      ]);

      if (!mounted) return;
      final incidents = resultats[0] as List<DisciplineIncident>;
      final students = resultats[1] as List<DisciplineStudentOption>;
      final categories = resultats[2] as List<DisciplineCategoryOption>;

      setState(() {
        _incidents = incidents;
        _students = students;
        _categories = categories;
        final idsValides = students.map((row) => row.id).toSet();
        if (_selectedStudentId == null ||
            !idsValides.contains(_selectedStudentId)) {
          _selectedStudentId = students.isEmpty ? null : students.first.id;
        }
        final motifsValides = categories.map((row) => row.value).toSet();
        if (_selectedCategory == null ||
            !motifsValides.contains(_selectedCategory)) {
          _selectedCategory = categories.isEmpty ? null : categories.first.value;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erreur chargement discipline: $error';
        _loading = false;
      });
    }
  }

  Future<void> _createIncident() async {
    if (!_droits.canWrite) {
      _showMessage('Mode lecture seule: creation d\'incident non autorisée.');
      return;
    }

    final studentId = _selectedStudentId;
    final category = _selectedCategory ?? '';
    final description = _descriptionController.text.trim();

    if (studentId == null || category.isEmpty || description.isEmpty) {
      _showMessage('Complétez les champs obligatoires.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(disciplineRepositoryProvider).createIncident(
            studentId: studentId,
            incidentDate: _apiDate(_incidentDate),
            category: category,
            description: description,
            severity: _severity,
            sanction: _estEnseignant ? '' : _sanctionController.text.trim(),
            status: _estEnseignant ? 'open' : _status,
            parentNotified: _estEnseignant ? false : _parentNotified,
          );

      if (!mounted) return;
      _descriptionController.clear();
      _sanctionController.clear();
      setState(() {
        _severity = 'medium';
        _status = 'open';
        _parentNotified = false;
      });
      _showMessage('Incident disciplinaire enregistré.', isSuccess: true);
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Erreur enregistrement incident: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reviewIncident(DisciplineIncident incident) async {
    final resultat = await showDialog<IncidentReviewResult>(
      context: context,
      builder: (_) => IncidentReviewDialog(incident: incident),
    );
    if (resultat == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref.read(disciplineRepositoryProvider).updateIncident(
            id: incident.id,
            severity: resultat.severity,
            sanction: resultat.sanction,
            status: resultat.status,
            parentNotified: resultat.parentNotified,
          );
      if (!mounted) return;
      _showMessage('Incident mis à jour.', isSuccess: true);
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Erreur mise à jour incident: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteIncident(DisciplineIncident incident) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer l\'incident'),
        content: Text(
          'Supprimer définitivement l\'incident du ${incident.incidentDate} '
          'concernant ${incident.libelleEleve} ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref.read(disciplineRepositoryProvider).deleteIncident(incident.id);
      if (!mounted) return;
      _showMessage('Incident supprimé.', isSuccess: true);
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Erreur suppression incident: $error');
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final textTheme = Theme.of(context).textTheme;
    final droits = ref.watch(currentPermissionsProvider).of('discipline');
    final estEnseignant = _estEnseignant;
    final peutDeclarer = droits.canWrite;
    final peutArbitrer = droits.canWrite && !estEnseignant;
    final peutSupprimer = droits.canDelete;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text('Discipline', style: textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'Suivi des incidents disciplinaires et des sanctions.',
            style: textTheme.bodyMedium,
          ),
          if (estEnseignant) ...[
            const SizedBox(height: 6),
            Text(
              'Affichage limité aux élèves de vos classes. Vous pouvez déclarer un incident, sans appliquer de sanction ni le marquer comme traité.',
              style: textTheme.bodySmall,
            ),
          ],
          if (!peutDeclarer) ...[
            const SizedBox(height: 6),
            Text(
              'Mode lecture seule: consultation uniquement pour ce profil.',
              style: textTheme.bodySmall,
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (peutDeclarer) _buildDeclarationCard(estEnseignant),
          if (peutDeclarer) const SizedBox(height: 14),
          _buildIncidentsCard(
            peutArbitrer: peutArbitrer,
            peutSupprimer: peutSupprimer,
          ),
        ],
      ),
    );
  }

  Widget _buildDeclarationCard(bool estEnseignant) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Déclarer un incident',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              isExpanded: true,
              key: const Key('declaration-student'),
              initialValue: _selectedStudentId,
              decoration: const InputDecoration(labelText: 'Élève'),
              items: _students
                  .map(
                    (row) => DropdownMenuItem<int>(
                      value: row.id,
                      child: Text(row.libelle),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _selectedStudentId = value),
            ),
            if (_students.isEmpty) ...[
              const SizedBox(height: 6),
              Text(
                estEnseignant
                    ? 'Aucune classe ne vous est affectée: la déclaration est indisponible.'
                    : 'Aucun élève disponible pour la déclaration.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date de l\'incident'),
              subtitle: Text(_apiDate(_incidentDate)),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _incidentDate,
                  firstDate: DateTime(2020),
                  // Un incident se constate, il ne s'anticipe pas: une date
                  // future ouvrait une fiche impossible a rapprocher d'un
                  // fait, et le dossier eleve l'affichait quand meme.
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _incidentDate = picked);
              },
            ),
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: const Key('declaration-category'),
              initialValue: _selectedCategory,
              decoration: const InputDecoration(labelText: 'Motif'),
              items: _categories
                  .map(
                    (row) => DropdownMenuItem<String>(
                      value: row.value,
                      child: Text(row.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _selectedCategory = value),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Description *'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _severity,
              decoration: const InputDecoration(labelText: 'Gravité'),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Faible')),
                DropdownMenuItem(value: 'medium', child: Text('Moyenne')),
                DropdownMenuItem(value: 'high', child: Text('Élevée')),
              ],
              onChanged: (value) =>
                  setState(() => _severity = value ?? 'medium'),
            ),
            // Statut, sanction et information des parents relevent de
            // l'arbitrage: les montrer grises a l'enseignant laissait croire
            // a une saisie possible, le serveur les remettait a zero.
            if (!estEnseignant) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: const Key('declaration-status'),
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Statut'),
                items: const [
                  DropdownMenuItem(value: 'open', child: Text('Ouvert')),
                  DropdownMenuItem(value: 'resolved', child: Text('Traité')),
                ],
                onChanged: (value) => setState(() => _status = value ?? 'open'),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('declaration-sanction'),
                controller: _sanctionController,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Sanction (optionnel)',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _parentNotified,
                title: const Text('Parent informé'),
                onChanged: (value) => setState(() => _parentNotified = value),
              ),
            ],
            const SizedBox(height: 8),
            FilledButton(
              onPressed: (_saving || _students.isEmpty) ? null : _createIncident,
              child: const Text('Enregistrer incident'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncidentsCard({
    required bool peutArbitrer,
    required bool peutSupprimer,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final ouverts = _incidents.where((row) => row.estOuvert).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Incidents', style: textTheme.titleMedium),
                ),
                Text(
                  '${_incidents.length} au total • $ouverts ouvert(s)',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Filtres cote serveur: la liste etait tronquee a trente lignes
            // sans aucun moyen d'atteindre les suivantes.
            TextField(
              key: const Key('incidents-search'),
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _loadData(),
              decoration: InputDecoration(
                labelText: 'Rechercher (élève, matricule, motif, sanction)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Rechercher',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _loadData,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    key: const Key('filter-status'),
                    initialValue: _filtreStatut,
                    decoration: const InputDecoration(labelText: 'Statut'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('Tous')),
                      DropdownMenuItem(value: 'open', child: Text('Ouvert')),
                      DropdownMenuItem(
                        value: 'resolved',
                        child: Text('Traité'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() => _filtreStatut = value ?? '');
                      _loadData();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    key: const Key('filter-severity'),
                    initialValue: _filtreGravite,
                    decoration: const InputDecoration(labelText: 'Gravité'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('Toutes')),
                      DropdownMenuItem(value: 'low', child: Text('Faible')),
                      DropdownMenuItem(value: 'medium', child: Text('Moyenne')),
                      DropdownMenuItem(value: 'high', child: Text('Élevée')),
                    ],
                    onChanged: (value) {
                      setState(() => _filtreGravite = value ?? '');
                      _loadData();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_incidents.isEmpty)
              const Text('Aucun incident enregistré.')
            else
              ..._incidents.map(
                (incident) => _buildIncidentTile(
                  incident,
                  peutArbitrer: peutArbitrer,
                  peutSupprimer: peutSupprimer,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncidentTile(
    DisciplineIncident incident, {
    required bool peutArbitrer,
    required bool peutSupprimer,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final details = <String>[
      incident.libelleEleve,
      incident.description,
      if (incident.sanction.isNotEmpty) 'Sanction: ${incident.sanction}',
      if (incident.reportedByName.isNotEmpty)
        'Déclaré par ${incident.reportedByName}',
      if (incident.parentNotified) 'Parent informé',
      if (!incident.estOuvert && incident.jourDeCloture.isNotEmpty)
        'Traité le ${incident.jourDeCloture}',
    ];

    return Card(
      child: ListTile(
        title: Text(
          '${incident.libelleMotif} • '
          '${DisciplineIncident.libelleGravite(incident.severity)}',
        ),
        subtitle: Text(details.join('\n')),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(incident.incidentDate, style: textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(DisciplineIncident.libelleStatut(incident.status)),
              ],
            ),
            if (peutArbitrer)
              IconButton(
                key: Key('review-${incident.id}'),
                tooltip: 'Traiter',
                icon: const Icon(Icons.gavel),
                onPressed: _saving ? null : () => _reviewIncident(incident),
              ),
            if (peutSupprimer)
              IconButton(
                key: Key('delete-${incident.id}'),
                tooltip: 'Supprimer',
                icon: const Icon(Icons.delete_outline),
                onPressed: _saving ? null : () => _deleteIncident(incident),
              ),
          ],
        ),
      ),
    );
  }

  String _apiDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

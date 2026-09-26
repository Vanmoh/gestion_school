part of 'timetable_page.dart';

/// Les quatre panneaux de la grille horaire.
///
/// Ils vivaient dans un `build` de neuf cents lignes d'un seul bloc: filtres
/// et actions, tableau de la classe choisie, charge des enseignants,
/// recapitulatif par classe, puis l'assemblage. Aucun d'eux n'etait nommable,
/// donc aucun n'etait reperable: chercher « le bouton Publier » demandait de
/// derouler l'ecran entier.
///
/// Le decoupage suit celui de `grades_page`, deja en place dans le projet:
/// une `part` et une extension sur l'etat de la page, plutot qu'un widget a
/// part -- ces panneaux lisent une vingtaine de champs d'etat et appellent
/// une douzaine de methodes privees.
extension _PanneauxDuPlanning on _TimetablePageState {

  /// Les filtres, et les gestes qui portent sur la selection.
  Widget _panneauDesFiltresEtActions(_VueDuPlanning vue) {

    return _sectionCard(
      title: 'Filtres et actions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_scheduleApiSupported) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Text(
                'Backend planning non compatible: les routes horaires ne sont pas disponibles sur\n'
                '$_activeApiBaseUrl\n'
                'Configurez une API mise à jour via Connexion > Configuration API.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : _loadData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retester compatibilité API'),
                ),
                if (_usingCustomApiBaseUrl)
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _resetCustomApiUrlAndReload,
                    icon: const Icon(Icons.settings_backup_restore_outlined),
                    label: const Text('Réinitialiser URL API'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (!_isTeacherUser)
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'classroom',
                  label: Text('Par classe'),
                  icon: Icon(Icons.grid_view_outlined),
                ),
                ButtonSegment<String>(
                  value: 'teacher',
                  label: Text('Par enseignant'),
                  icon: Icon(Icons.badge_outlined),
                ),
              ],
              selected: {_viewMode},
              onSelectionChanged: (values) {
                final next = values.first;
                redessiner(() => _viewMode = next);
              },
            ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: _selectedClassroom,
            decoration: const InputDecoration(labelText: 'Classe'),
            items: vue.visibleClassrooms
                .map(
                  (row) => DropdownMenuItem<int>(
                    value: _asInt(row['id']),
                    child: Text('${row['name']}'),
                  ),
                )
                .toList(),
            onChanged: (value) {
              redessiner(() => _selectedClassroom = value);
            },
          ),
          if (vue.selectedClassId != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Indicateur(libelle: 'Statut planning', valeur: vue.selectedPublicationLabel),
                Indicateur(libelle: 'Horaires', valeur: '${vue.selectedSlots.length}'),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!_isTeacherUser)
                FilledButton.tonalIcon(
                  onPressed:
                      (_saving ||
                          !_scheduleApiSupported ||
                          vue.selectedClassId == null)
                      ? null
                      : _exportSelectedClassXlsx,
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('Exporter XLSX classe'),
                ),
              FilledButton.tonalIcon(
                onPressed: (_saving || vue.selectedClassId == null)
                    ? null
                    : _exportCurrentClassCsv,
                icon: const Icon(Icons.grid_on_outlined),
                label: const Text('Exporter Excel (CSV)'),
              ),
              FilledButton.tonalIcon(
                onPressed: _saving ? null : _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualiser'),
              ),
              if (!_isTeacherUser)
                FilledButton.tonalIcon(
                  onPressed: (_saving || !_scheduleApiSupported)
                      || vue.isReadOnlyMode
                      ? null
                      : _openDuplicateScheduleDialog,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Dupliquer planning'),
                ),
              // La génération remplace la saisie créneau par créneau, où il
              // fallait vérifier de tête qu'aucun enseignant n'était attendu
              // dans deux classes à la fois.
              if (!_isTeacherUser)
                FilledButton.icon(
                  onPressed: (_saving || !_scheduleApiSupported)
                      || vue.isReadOnlyMode
                      ? null
                      : () => _ouvrirLaGeneration(vue.selectedClassId),
                  icon: const Icon(Icons.auto_awesome_motion_outlined),
                  label: const Text('Générer automatiquement'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Actions rapides disponibles via les boutons flottants: ajout d\'horaire et impression PDF.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (!_isTeacherUser) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: (_saving || !_scheduleApiSupported)
                      ? null
                      : _exportGlobalXlsx,
                  icon: const Icon(Icons.dataset_outlined),
                  label: const Text('Export global XLSX'),
                ),
                OutlinedButton.icon(
                  onPressed: (_saving || !_scheduleApiSupported)
                      ? null
                      : _exportGlobalPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Export global PDF'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed:
                      (_saving ||
                          !_scheduleApiSupported ||
                          vue.selectedClassId == null ||
                      vue.selectedAssignments.isEmpty ||
                      vue.isReadOnlyMode)
                      ? null
                      : () => _publishSelectedClass(lockAfterPublish: true),
                  icon: const Icon(Icons.publish),
                  label: const Text('Publier + verrouiller'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      (_saving ||
                          !_scheduleApiSupported ||
                          vue.selectedClassId == null ||
                      vue.selectedAssignments.isEmpty ||
                      vue.isReadOnlyMode)
                      ? null
                      : () => _publishSelectedClass(lockAfterPublish: false),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Publier sans verrou'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      (_saving ||
                          !_scheduleApiSupported ||
                          vue.selectedClassId == null ||
                      !vue.selectedIsPublished ||
                      vue.isReadOnlyMode)
                      ? null
                      : () => _setSelectedClassLock(lock: !vue.selectedIsLocked),
                  icon: Icon(
                    vue.selectedIsLocked
                        ? Icons.lock_open_outlined
                        : Icons.lock_outline,
                  ),
                  label: Text(
                    vue.selectedIsLocked ? 'Déverrouiller' : 'Verrouiller',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      (_saving ||
                          !_scheduleApiSupported ||
                          vue.selectedClassId == null ||
                      !vue.selectedIsPublished ||
                      vue.isReadOnlyMode)
                      ? null
                      : _unpublishSelectedClass,
                  icon: const Icon(Icons.unpublished_outlined),
                  label: const Text('Repasser brouillon'),
                ),
              ],
            ),
          ],
          if (_viewMode == 'teacher') ...[
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'selected',
                  label: Text('Classe sélectionnée'),
                  icon: Icon(Icons.filter_1_outlined),
                ),
                ButtonSegment<String>(
                  value: 'all',
                  label: Text('Toutes classes'),
                  icon: Icon(Icons.filter_none_outlined),
                ),
              ],
              selected: {_teacherScope},
              onSelectionChanged: _isTeacherUser
                  ? null
                  : (values) {
                      redessiner(() => _teacherScope = values.first);
                    },
            ),
            const SizedBox(height: 6),
            Text(
              'Charge calculée sur ${vue.teacherWorkloads.length} enseignant(s).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  /// Le tableau horaire de la classe choisie.
  Widget _panneauDeLaClasseChoisie(_VueDuPlanning vue) {
    // Une locale plutot que le champ: Dart ne promeut pas un champ d'instance,
    // et la grille hebdomadaire exige un identifiant non nul.
    final classeChoisie = vue.selectedClassId;

    return _sectionCard(
      title: 'Tableau horaire - ${vue.selectedClassName}',
      child: classeChoisie == null
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('Sélectionnez une classe.'),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Indicateur(libelle: 
                      'Affectations classe', valeur:
                      '${vue.selectedAssignments.length}',
                    ),
                    Indicateur(libelle: 'Horaires classe', valeur: '${vue.selectedSlots.length}'),
                    Indicateur(libelle: 'Statut', valeur: vue.selectedPublicationLabel),
                  ],
                ),
                const SizedBox(height: 10),
                if (vue.selectedIsLocked)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Planning verrouillé: les modifications d\'horaires sont temporairement bloquées.',
                    ),
                  ),
                if (vue.selectedAssignments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'Aucune affectation pour cette classe. Créez des affectations puis des horaires.',
                    ),
                  )
                else ...[
                  TextField(
                    controller: _slotsSearchController,
                    onChanged: (_) => redessiner(() {}),
                    decoration: InputDecoration(
                      labelText: 'Filtre rapide (matière, enseignant, salle)',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _slotsSearchController.text.trim().isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _slotsSearchController.clear();
                                redessiner(() {});
                              },
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('Tous jours'),
                        selected: _mobileDayFilter == 'ALL',
                        onSelected: (_) {
                          redessiner(() => _mobileDayFilter = 'ALL');
                        },
                      ),
                      ..._TimetablePageState._dayOrder.map(
                        (dayCode) => ChoiceChip(
                          label: Text(_dayLabel(dayCode)),
                          selected: _mobileDayFilter == dayCode,
                          onSelected: (_) {
                            redessiner(() => _mobileDayFilter = dayCode);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildClassWeeklyGrid(
                    classId: classeChoisie,
                    classSlots: vue.selectedSlots,
                    dayFilter: _mobileDayFilter,
                    searchTerm: _slotsSearchController.text,
                    compact: vue.isNarrow,
                  ),
                ],
              ],
            ),
    );
  }

  /// Combien d'heures chaque enseignant porte.
  Widget _panneauDeLaChargeDesEnseignants(_VueDuPlanning vue) {

    return _sectionCard(
      title: _teacherScope == 'selected'
          ? 'Charge horaire - classe sélectionnée'
          : 'Charge horaire - toutes classes',
      child: vue.teacherWorkloads.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('Aucune charge disponible pour le filtre courant.'),
            )
          : FrozenColumnTable(
              frozenColumnWidth: 180,
              columnWidth: 104,
              frozenHeader: const Text('Enseignant'),
              headers: const [
                Text('Horaires'),
                Text('Classes'),
                Text('Lundi'),
                Text('Mardi'),
                Text('Mercredi'),
                Text('Jeudi'),
                Text('Vendredi'),
                Text('Samedi'),
                Text('Total h/sem.'),
                Text('Niveau'),
              ],
              frozenCells: [
                for (final row in vue.teacherWorkloads)
                  Text(
                    _teacherDisplayLabel(row.teacherName, row.teacherCode),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
              ],
              rows: [
                for (final row in vue.teacherWorkloads)
                  _teacherWorkloadCells(row),
              ],
            ),
    );
  }

  /// Ou en est chaque classe, d'un coup d'oeil.
  Widget _panneauParClasse(_VueDuPlanning vue) {

    return _sectionCard(
      title: 'Chaque classe a son emploi du temps',
      child: _classrooms.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('Aucune classe disponible.'),
            )
          : Column(
              children: _classrooms.map((classroom) {
                final classId = _asInt(classroom['id']);
                final className = (classroom['name'] ?? 'Classe $classId')
                    .toString();
                final classAssignments =
                    vue.assignmentsByClass[classId] ?? <Map<String, dynamic>>[];
                final classSlots =
                    vue.slotsByClass[classId] ?? <Map<String, dynamic>>[];
                final publication = vue.publicationByClass[classId];
                final classIsLocked = _asBool(publication?['is_locked']);
                final publicationLabel = _publicationLabel(publication);

                return Card(
                  child: ExpansionTile(
                    initiallyExpanded: classId == _selectedClassroom,
                    onExpansionChanged: (expanded) {
                      if (expanded) {
                        redessiner(() => _selectedClassroom = classId);
                      }
                    },
                    title: Text(className),
                    subtitle: Text(
                      '$publicationLabel • ${classSlots.length} horaire(s) • ${classAssignments.length} affectation(s)',
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed:
                              (_saving ||
                                  !_scheduleApiSupported ||
                              classIsLocked ||
                              vue.isReadOnlyMode)
                              ? null
                              : () =>
                                    _openSlotDialog(forceClassroomId: classId),
                          icon: const Icon(Icons.add),
                          label: const Text('Ajouter horaire'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (classAssignments.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('Aucune affectation pour cette classe.'),
                        )
                      else
                        _buildClassWeeklyGrid(
                          classId: classId,
                          classSlots: classSlots,
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

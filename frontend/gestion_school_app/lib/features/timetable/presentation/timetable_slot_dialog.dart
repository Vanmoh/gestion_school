part of 'timetable_page.dart';

/// Un créneau: sa classe, sa matière, son enseignant, son horaire.
///
/// Le geste unitaire de l'emploi du temps.
///
/// Le mécanisme `part` déplace le code sans le découpler: l'extension voit
/// les champs de la page comme avant.
extension _DialogueDUnCreneau on _TimetablePageState {
  Future<void> _openSlotDialog({
    Map<String, dynamic>? slot,
    int? forceClassroomId,
  }) async {
    if (_isTimetableReadOnlyRole()) {
      _showMessage('Mode lecture seule: modification des horaires non autorisée.');
      return;
    }

    if (!_requireScheduleApiSupported('gestion des horaires')) {
      return;
    }

    final classroomId = forceClassroomId ?? _selectedClassroom;
    if (classroomId == null || classroomId <= 0) {
      _showMessage('Sélectionnez une classe avant d\'ajouter un horaire.');
      return;
    }

    if (_isClassLockedById(classroomId)) {
      _showMessage(
        'Emploi du temps verrouillé pour cette classe. Déverrouillez avant modification.',
      );
      return;
    }

    final assignmentById = _assignmentById();
    final assignmentsByClass = _assignmentsByClass(assignmentById);
    final classAssignments =
        assignmentsByClass[classroomId] ?? <Map<String, dynamic>>[];

    if (classAssignments.isEmpty) {
      _showMessage(
        'Aucune affectation disponible pour cette classe. Créez d\'abord une affectation.',
      );
      return;
    }

    var selectedAssignment = _asInt(slot?['assignment']);
    final assignmentIds = classAssignments
        .map((row) => _asInt(row['id']))
        .toSet();
    if (selectedAssignment <= 0 ||
        !assignmentIds.contains(selectedAssignment)) {
      selectedAssignment = _asInt(classAssignments.first['id']);
    }

    var selectedDay = (slot?['day_of_week'] ?? _TimetablePageState._dayOrder.first).toString();
    if (!_TimetablePageState._dayOrder.contains(selectedDay)) {
      selectedDay = _TimetablePageState._dayOrder.first;
    }

    final startController = TextEditingController(
      text: _hhmm(slot?['start_time']),
    );
    final endController = TextEditingController(text: _hhmm(slot?['end_time']));
    final roomController = TextEditingController(
      text: (slot?['room'] ?? '').toString(),
    );
    final isEdit = slot != null;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        Future<void> pickTime(TextEditingController controller) async {
          final parsed = _parseTimeOfDay(controller.text.trim());
          final picked = await showTimePicker(
            context: dialogContext,
            initialTime: parsed ?? const TimeOfDay(hour: 8, minute: 0),
          );
          if (picked != null) {
            controller.text = _formatTimeOfDay(picked);
          }
        }

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            List<String> computeDialogConflicts() {
              final start = _parseTimeOfDay(startController.text.trim());
              final end = _parseTimeOfDay(endController.text.trim());
              if (start == null || end == null) {
                return const <String>[];
              }

              final startMinutes = start.hour * 60 + start.minute;
              final endMinutes = end.hour * 60 + end.minute;
              if (endMinutes <= startMinutes) {
                return const <String>[];
              }

              final excludeSlotId = isEdit
                  ? _asInt(slot['slotId'] ?? slot['id'])
                  : null;
              return _predictSlotConflicts(
                assignmentId: selectedAssignment,
                dayCode: selectedDay,
                start: start,
                end: end,
                room: roomController.text.trim(),
                excludeSlotId: excludeSlotId,
              );
            }

            final dialogConflicts = computeDialogConflicts();

            return AlertDialog(
              title: Text(
                isEdit ? 'Modifier un horaire' : 'Ajouter un horaire',
              ),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Classe: ${_classNameById(classroomId)}'),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: selectedAssignment,
                      decoration: const InputDecoration(
                        labelText: 'Affectation (matière / enseignant)',
                      ),
                      items: classAssignments
                          .map(
                            (row) => DropdownMenuItem<int>(
                              value: _asInt(row['id']),
                              child: Text(
                                '${row['subjectCode']} - ${row['subjectName']} • '
                                '${_teacherDisplayLabel(row['teacherName'], row['teacherCode'])}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedAssignment = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: selectedDay,
                      decoration: const InputDecoration(labelText: 'Jour'),
                      items: _TimetablePageState._dayOrder
                          .map(
                            (dayCode) => DropdownMenuItem<String>(
                              value: dayCode,
                              child: Text(_dayLabel(dayCode)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedDay = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: startController,
                            onChanged: (_) => setDialogState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Heure début (HH:MM)',
                              suffixIcon: IconButton(
                                onPressed: () => pickTime(startController),
                                icon: const Icon(Icons.access_time),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: endController,
                            onChanged: (_) => setDialogState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Heure fin (HH:MM)',
                              suffixIcon: IconButton(
                                onPressed: () => pickTime(endController),
                                icon: const Icon(Icons.access_time_filled),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Qui peut prendre ce créneau. La collecte des
                    // disponibilités s'arrêtait à elle-même: les
                    // déclarations étaient enregistrées puis oubliées, et
                    // celui qui posait un cours à la main plaçait à
                    // l'aveugle. Le serveur savait répondre; personne ne le
                    // lui demandait.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _montrerQuiEstDisponible(
                          jour: selectedDay,
                          debut: startController.text.trim(),
                          fin: endController.text.trim(),
                        ),
                        icon: const Icon(Icons.how_to_reg_outlined, size: 18),
                        label: const Text('Qui est disponible sur ce créneau ?'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: roomController,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Salle (optionnel)',
                      ),
                    ),
                    if (dialogConflicts.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Conflits détectés',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            ...dialogConflicts
                                .take(5)
                                .map(
                                  (message) => Text(
                                    '- $message',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: _saving
                      ? null
                      : () {
                          final start = _parseTimeOfDay(
                            startController.text.trim(),
                          );
                          final end = _parseTimeOfDay(
                            endController.text.trim(),
                          );

                          if (start == null || end == null) {
                            _showMessage(
                              'Heures invalides. Format attendu: HH:MM',
                            );
                            return;
                          }

                          final startMinutes = start.hour * 60 + start.minute;
                          final endMinutes = end.hour * 60 + end.minute;
                          if (endMinutes <= startMinutes) {
                            _showMessage(
                              'L\'heure de fin doit être après l\'heure de début.',
                            );
                            return;
                          }

                          if (dialogConflicts.isNotEmpty) {
                            _showMessage(
                              'Conflits détectés. Ajustez l\'horaire avant validation.',
                            );
                            return;
                          }

                          Navigator.of(dialogContext).pop(true);
                        },
                  child: Text(isEdit ? 'Modifier' : 'Ajouter'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirm != true) {
      startController.dispose();
      endController.dispose();
      roomController.dispose();
      return;
    }

    final start = _parseTimeOfDay(startController.text.trim());
    final end = _parseTimeOfDay(endController.text.trim());

    if (start == null || end == null) {
      _showMessage('Heures invalides. Format attendu: HH:MM');
      startController.dispose();
      endController.dispose();
      roomController.dispose();
      return;
    }

    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    if (endMinutes <= startMinutes) {
      _showMessage('L\'heure de fin doit être après l\'heure de début.');
      startController.dispose();
      endController.dispose();
      roomController.dispose();
      return;
    }

    final liveConflicts = _predictSlotConflicts(
      assignmentId: selectedAssignment,
      dayCode: selectedDay,
      start: start,
      end: end,
      room: roomController.text.trim(),
      excludeSlotId: isEdit ? _asInt(slot['slotId'] ?? slot['id']) : null,
    );
    if (liveConflicts.isNotEmpty) {
      _showMessage('Conflits détectés. Ajustez l\'horaire avant validation.');
      startController.dispose();
      endController.dispose();
      roomController.dispose();
      return;
    }

    final payload = {
      'assignment': selectedAssignment,
      'day_of_week': selectedDay,
      'start_time': _toApiTime(start),
      'end_time': _toApiTime(end),
      'room': roomController.text.trim(),
    };

    startController.dispose();
    endController.dispose();
    roomController.dispose();

    majEtat(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      if (isEdit) {
        final slotId = _asInt(slot['slotId'] ?? slot['id']);
        await dio.patch('/teacher-schedule-slots/$slotId/', data: payload);
      } else {
        await dio.post('/teacher-schedule-slots/', data: payload);
      }

      if (!mounted) return;
      _showMessage(
        isEdit ? 'Horaire modifié avec succès.' : 'Horaire ajouté avec succès.',
        isSuccess: true,
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _markScheduleApiUnsupportedFromError(error);
      _showMessage(
        'Erreur enregistrement horaire: ${_extractErrorMessage(error)}',
      );
    } finally {
      if (mounted) {
        majEtat(() => _saving = false);
      }
    }
  }

  /// Montre qui peut prendre le créneau saisi, du plus volontaire au moins
  /// disponible.
  ///
  /// Le serveur classe en quatre groupes: préférés, possibles, ceux qui
  /// n'ont rien déclaré, et ceux qui se sont dits indisponibles. Les
  /// silencieux forment un groupe à part entière — ne rien avoir dit n'est ni
  /// un oui ni un non, et l'administration a besoin de la nuance pour
  /// arbitrer.
  Future<void> _montrerQuiEstDisponible({
    required String jour,
    required String debut,
    required String fin,
  }) async {
    final heureDebut = _parseTimeOfDay(debut);
    final heureFin = _parseTimeOfDay(fin);
    if (heureDebut == null || heureFin == null) {
      _showMessage('Renseignez les heures de début et de fin (HH:MM).');
      return;
    }

    Map<String, dynamic> reponse;
    try {
      final resultat = await ref
          .read(dioProvider)
          .get(
            '/teacher-availability-slots/for-planning/',
            queryParameters: {
              'day': jour,
              'start': _toApiTime(heureDebut),
              'end': _toApiTime(heureFin),
            },
          );
      reponse = Map<String, dynamic>.from(resultat.data as Map);
    } catch (erreur) {
      _showMessage('Disponibilités indisponibles: ${_extractErrorMessage(erreur)}');
      return;
    }

    if (!mounted) return;

    List<Map<String, dynamic>> groupe(String cle) {
      final brut = reponse[cle];
      if (brut is! List) return const [];
      return brut.whereType<Map<String, dynamic>>().toList(growable: false);
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text(
            '${reponse['day_label'] ?? jour} '
            '${reponse['start_time'] ?? debut}-${reponse['end_time'] ?? fin}',
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _groupeDeDisponibilite(
                    titre: 'Volontaires',
                    sousTitre: 'Ont déclaré ce créneau comme préféré.',
                    couleur: scheme.primary,
                    lignes: groupe('preferred'),
                  ),
                  _groupeDeDisponibilite(
                    titre: 'Possibles',
                    sousTitre: 'Peuvent, sans en faire un souhait.',
                    couleur: scheme.tertiary,
                    lignes: groupe('possible'),
                  ),
                  _groupeDeDisponibilite(
                    titre: 'Sans réponse',
                    sousTitre:
                        "N'ont rien déclaré: ce n'est ni un oui ni un non.",
                    couleur: scheme.outline,
                    lignes: groupe('undeclared'),
                  ),
                  _groupeDeDisponibilite(
                    titre: 'Indisponibles',
                    sousTitre:
                        'Ont pris la peine d\'écrire non. Les placer reste '
                        'possible, la raison suivra le créneau.',
                    couleur: scheme.error,
                    lignes: groupe('unavailable'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  Widget _groupeDeDisponibilite({
    required String titre,
    required String sousTitre,
    required Color couleur,
    required List<Map<String, dynamic>> lignes,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 10, color: couleur),
              const SizedBox(width: 6),
              Text(
                '$titre (${lignes.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 2),
            child: Text(
              sousTitre,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (lignes.isEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 16, top: 4),
              child: Text('—'),
            )
          else
            for (final ligne in lignes)
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 4),
                child: Text(
                  [
                    ligne['teacher_name']?.toString() ?? '',
                    if ((ligne['declared_start'] ?? '') != '' &&
                        ligne['declared_start'] != null)
                      '(déclaré ${ligne['declared_start']}-${ligne['declared_end']})',
                    if ((ligne['note']?.toString() ?? '').isNotEmpty)
                      '— ${ligne['note']}',
                  ].join(' '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
        ],
      ),
    );
  }
}

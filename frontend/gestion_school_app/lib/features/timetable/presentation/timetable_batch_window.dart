part of 'timetable_page.dart';

/// La saisie de plusieurs créneaux d'un coup.
///
/// Trois cent soixante-dix lignes: poser une semaine entière n'est pas le
/// même geste que corriger un créneau.
///
/// Le mécanisme `part` déplace le code sans le découpler: l'extension voit
/// les champs de la page comme avant.
extension _FenetreDeSaisieEnLot on _TimetablePageState {
  Future<void> _openSlotBatchFloatingWindow({int? forceClassroomId}) async {
    if (_isTimetableReadOnlyRole()) {
      _showMessage('Mode lecture seule: ajout d\'horaire non autorise.');
      return;
    }

    if (!_requireScheduleApiSupported('ajout en lot des horaires')) {
      return;
    }

    final assignmentById = _assignmentById();
    final assignmentsByClass = _assignmentsByClass(assignmentById);
    final slotsByClass = _slotsByClass(assignmentById);
    final visibleClassrooms = _visibleClassrooms();

    if (visibleClassrooms.isEmpty) {
      _showMessage('Aucune classe disponible.');
      return;
    }

    int selectedClass = forceClassroomId ?? _selectedClassroom ?? _asInt(visibleClassrooms.first['id']);
    if (!visibleClassrooms.any((row) => _asInt(row['id']) == selectedClass)) {
      selectedClass = _asInt(visibleClassrooms.first['id']);
    }

    List<Map<String, dynamic>> classAssignments =
        assignmentsByClass[selectedClass] ?? <Map<String, dynamic>>[];
    if (classAssignments.isEmpty) {
      _showMessage('Aucune affectation disponible pour cette classe.');
      return;
    }

    int selectedAssignment = _asInt(classAssignments.first['id']);
    final selectedCells = <String>{};
    final roomController = TextEditingController();

    const fallbackRanges = <String>[
      '08:00-09:00',
      '09:00-10:00',
      '10:00-11:00',
      '11:00-12:00',
      '14:00-15:00',
      '15:00-16:00',
      '16:00-17:00',
    ];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final screenSize = MediaQuery.sizeOf(dialogContext);
            final dialogWidth = screenSize.width > 1200
                ? 1080.0
                : (screenSize.width * 0.94).clamp(320.0, 1080.0);
            final dialogHeight = screenSize.height > 900
                ? 820.0
                : (screenSize.height * 0.88).clamp(520.0, 820.0);
            final isLocked = _isClassLockedById(selectedClass);
            final classSlots =
                slotsByClass[selectedClass] ?? const <Map<String, dynamic>>[];
            final existingRanges = classSlots
                .map(_slotRange)
                .where((range) => range.trim().isNotEmpty)
                .toSet()
                .toList()
              ..sort((a, b) => _rangeStartMinutes(a).compareTo(_rangeStartMinutes(b)));
            final presetRanges = existingRanges.isNotEmpty
                ? existingRanges
                : fallbackRanges;
            final matrix = _classMatrix(classSlots);
            classAssignments =
                assignmentsByClass[selectedClass] ?? <Map<String, dynamic>>[];
            if (classAssignments.isNotEmpty &&
                !classAssignments.any(
                  (row) => _asInt(row['id']) == selectedAssignment,
                )) {
              selectedAssignment = _asInt(classAssignments.first['id']);
            }

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 20,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: dialogWidth,
                  maxHeight: dialogHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Ajouter des horaires par créneaux',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              DropdownButtonFormField<int>(
                                isExpanded: true,
                                initialValue: selectedClass,
                                decoration: const InputDecoration(
                                  labelText: 'Classe',
                                ),
                                items: visibleClassrooms
                                    .map(
                                      (row) => DropdownMenuItem<int>(
                                        value: _asInt(row['id']),
                                        child: Text(
                                          (row['name'] ?? '').toString(),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setDialogState(() {
                                    selectedClass = value;
                                    selectedCells.clear();
                                  });
                                },
                              ),
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
                                  setDialogState(
                                    () => selectedAssignment = value,
                                  );
                                },
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: roomController,
                                decoration: const InputDecoration(
                                  labelText: 'Salle (optionnel)',
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                existingRanges.isNotEmpty
                                    ? 'Créneaux de la classe: cliquez sur les cases libres à ajouter'
                                    : 'Créneaux: cliquez sur les cases libres à ajouter',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              Container(
                                constraints: BoxConstraints(
                                  maxHeight: dialogHeight - 290,
                                ),
                                child: SingleChildScrollView(
                                  child: FrozenColumnTable(
                                    frozenColumnWidth: 92,
                                    columnWidth: 132,
                                    minRowHeight: 64,
                                    cellPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    frozenHeader: const Text('Horaire'),
                                    headers: [
                                      for (final dayCode in _TimetablePageState._dayOrder)
                                        Text(_dayLabel(dayCode)),
                                    ],
                                    frozenCells: [
                                      for (final range in presetRanges)
                                        Text(
                                          range,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                    ],
                                    rows: [
                                      for (final range in presetRanges)
                                        [
                                          for (final dayCode in _TimetablePageState._dayOrder)
                                            _buildSlotPickerCell(
                                              range: range,
                                              dayCode: dayCode,
                                              slots:
                                                  (matrix[range] ??
                                                      const <String, List<Map<String, dynamic>>>{})[dayCode] ??
                                                  const <Map<String, dynamic>>[],
                                              selectedCells: selectedCells,
                                              isLocked: isLocked,
                                              setDialogState: setDialogState,
                                            ),
                                        ],
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${selectedCells.length} créneau(x) sélectionné(s)',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (isLocked) ...[
                                const SizedBox(height: 10),
                                const Text(
                                  'Planning verrouillé pour cette classe: ajoutez d\'abord un déverrouillage.',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _saving
                                ? null
                                : () => Navigator.of(dialogContext).pop(false),
                            child: const Text('Annuler'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: (_saving || _isClassLockedById(selectedClass))
                                ? null
                                : () {
                                    if (selectedCells.isEmpty) {
                                      _showMessage('Sélectionnez au moins une case de créneau.');
                                      return;
                                    }
                                    Navigator.of(dialogContext).pop(true);
                                  },
                            child: const Text('Ajouter les créneaux'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    final roomValue = roomController.text.trim();
    roomController.dispose();

    if (confirm != true) return;

    if (_isClassLockedById(selectedClass)) {
      _showMessage('Classe verrouillée: ajout impossible.');
      return;
    }

    final selections = selectedCells.toList()
      ..sort((a, b) {
        final left = a.split('|');
        final right = b.split('|');
        final byDay = _dayIndex(left.first).compareTo(_dayIndex(right.first));
        if (byDay != 0) return byDay;
        return _rangeStartMinutes(left.last).compareTo(_rangeStartMinutes(right.last));
      });

    majEtat(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      var created = 0;
      var skippedConflicts = 0;
      var failed = 0;
      final failedReasons = <String>{};

      for (final selection in selections) {
        final parts = selection.split('|');
        if (parts.length != 2) {
          failed += 1;
          continue;
        }

        final dayCode = parts.first;
        final range = parts.last;
        final rangeParts = range.split('-');
        if (rangeParts.length != 2) {
          failed += 1;
          continue;
        }

        final start = _parseTimeOfDay(rangeParts[0].trim());
        final end = _parseTimeOfDay(rangeParts[1].trim());
        if (start == null || end == null) {
          failed += 1;
          continue;
        }

        final conflicts = _predictSlotConflicts(
          assignmentId: selectedAssignment,
          dayCode: dayCode,
          start: start,
          end: end,
          room: roomValue,
        );
        if (conflicts.isNotEmpty) {
          skippedConflicts += 1;
          continue;
        }

        try {
          await dio.post(
            '/teacher-schedule-slots/',
            data: {
              'assignment': selectedAssignment,
              'day_of_week': dayCode,
              'start_time': _toApiTime(start),
              'end_time': _toApiTime(end),
              'room': roomValue,
            },
          );
          created += 1;
        } catch (error) {
          failed += 1;
          _markScheduleApiUnsupportedFromError(error);
          final reason = _extractErrorMessage(error).trim();
          if (reason.isNotEmpty) {
            failedReasons.add(reason);
          }
        }
      }

      if (!mounted) return;
      final summary =
          'Ajout en lot terminé: créés $created, conflits ignorés $skippedConflicts, échecs $failed.';
      if (failedReasons.isNotEmpty) {
        final firstReason = failedReasons.first;
        _showMessage('$summary Motif principal: $firstReason', isSuccess: created > 0);
      } else {
        _showMessage(summary, isSuccess: created > 0);
      }
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _markScheduleApiUnsupportedFromError(error);
      _showMessage('Erreur ajout en lot: ${_extractErrorMessage(error)}');
    } finally {
      if (mounted) {
        majEtat(() => _saving = false);
      }
    }
  }
}

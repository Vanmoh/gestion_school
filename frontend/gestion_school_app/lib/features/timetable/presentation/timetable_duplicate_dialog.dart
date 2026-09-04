part of 'timetable_page.dart';

/// La recopie d'un emploi du temps d'une semaine sur l'autre.
///
/// Elle ne saisit rien: elle reproduit, et ses règles lui sont propres.
///
/// Le mécanisme `part` déplace le code sans le découpler: l'extension voit
/// les champs de la page comme avant.
extension _DialogueDeDuplication on _TimetablePageState {
  Future<void> _openDuplicateScheduleDialog() async {
    if (_isTimetableReadOnlyRole()) {
      _showMessage('Mode lecture seule: duplication non autorisée.');
      return;
    }

    if (!_requireScheduleApiSupported('duplication de planning')) {
      return;
    }

    if (_classrooms.length < 2) {
      _showMessage(
        'Au moins deux classes sont nécessaires pour la duplication.',
      );
      return;
    }

    int sourceClass = _selectedClassroom ?? _asInt(_classrooms.first['id']);
    int targetClass = _asInt(_classrooms.first['id']);
    if (targetClass == sourceClass && _classrooms.length > 1) {
      targetClass = _asInt(_classrooms[1]['id']);
    }

    var overwrite = false;
    var keepRoom = true;
    final selectedDays = <String>{..._TimetablePageState._dayOrder};

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Duplication intelligente du planning'),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: sourceClass,
                      decoration: const InputDecoration(
                        labelText: 'Classe source',
                      ),
                      items: _classrooms
                          .map(
                            (row) => DropdownMenuItem<int>(
                              value: _asInt(row['id']),
                              child: Text((row['name'] ?? '').toString()),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          sourceClass = value;
                          if (targetClass == sourceClass) {
                            final alternative = _classrooms
                                .map((row) => _asInt(row['id']))
                                .firstWhere(
                                  (id) => id != sourceClass,
                                  orElse: () => sourceClass,
                                );
                            targetClass = alternative;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: targetClass,
                      decoration: const InputDecoration(
                        labelText: 'Classe cible',
                      ),
                      items: _classrooms
                          .map(
                            (row) => DropdownMenuItem<int>(
                              value: _asInt(row['id']),
                              child: Text((row['name'] ?? '').toString()),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => targetClass = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _TimetablePageState._dayOrder.map((dayCode) {
                        return FilterChip(
                          selected: selectedDays.contains(dayCode),
                          label: Text(_dayLabel(dayCode)),
                          onSelected: (enabled) {
                            setDialogState(() {
                              if (enabled) {
                                selectedDays.add(dayCode);
                              } else {
                                selectedDays.remove(dayCode);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: overwrite,
                      onChanged: (value) =>
                          setDialogState(() => overwrite = value),
                      title: const Text(
                        'Remplacer les horaires existants cible',
                      ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: keepRoom,
                      onChanged: (value) =>
                          setDialogState(() => keepRoom = value),
                      title: const Text('Conserver les salles'),
                    ),
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
                          if (sourceClass == targetClass) {
                            _showMessage(
                              'La classe source et la classe cible doivent être différentes.',
                            );
                            return;
                          }
                          if (selectedDays.isEmpty) {
                            _showMessage('Sélectionnez au moins un jour.');
                            return;
                          }
                          Navigator.of(dialogContext).pop(true);
                        },
                  child: const Text('Dupliquer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirm != true) {
      return;
    }

    majEtat(() => _saving = true);
    try {
      final response = await ref
          .read(dioProvider)
          .post(
            '/teacher-schedule-slots/duplicate_schedule/',
            data: {
              'source_classroom': sourceClass,
              'target_classroom': targetClass,
              'days': selectedDays.toList()..sort(),
              'overwrite': overwrite,
              'keep_room': keepRoom,
            },
          );

      final payload = Map<String, dynamic>.from(response.data as Map);
      final created = _asInt(payload['created']);
      final updated = _asInt(payload['updated']);
      final skippedConflicts = _asInt(payload['skipped_conflicts']);
      final skippedUnmapped = _asInt(payload['skipped_unmapped']);

      if (!mounted) return;
      _showMessage(
        'Duplication terminée: créés $created, mis à jour $updated, '
        'conflits $skippedConflicts, non mappés $skippedUnmapped.',
        isSuccess: true,
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _markScheduleApiUnsupportedFromError(error);
      _showMessage('Erreur duplication: ${_extractErrorMessage(error)}');
    } finally {
      if (mounted) {
        majEtat(() => _saving = false);
      }
    }
  }
}

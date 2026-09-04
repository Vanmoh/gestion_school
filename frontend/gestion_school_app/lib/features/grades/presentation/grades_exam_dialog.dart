part of 'grades_page.dart';

/// La saisie des résultats d'examen.
///
/// Elle partage le vocabulaire de la saisie des notes sans en être: les
/// mélanger dans un même fichier obligeait à lire les deux pour n'en
/// modifier qu'une.
///
/// Le mécanisme `part` déplace le code sans le découpler: l'extension voit les
/// champs de la page comme avant, et rien n'a eu à passer en paramètre.
extension _DialogueDesExamens on _GradesPageState {
  Future<void> _openExamEntryDialog() async {
    if (_refuseSiLectureSeule()) return;
    if (_isValidated) {
      _showMessage('Période validée par la direction: saisie verrouillée.');
      return;
    }

    if (_selectedClassroom == null ||
        _selectedAcademicYear == null ||
        _termController.text.trim().isEmpty) {
      _showMessage(
        'Sélectionnez classe, année et période avant la saisie examen.',
      );
      return;
    }

    final visibleClassrooms = _classroomsForCurrentRole();
    if (_students.isEmpty || visibleClassrooms.isEmpty) {
      _showMessage('Aucun élève ou matière disponible pour la saisie examen.');
      return;
    }

    int selectedClassroom =
        _selectedClassroom ?? _asInt(visibleClassrooms.first['id']);
    final initialSubjects = _subjectsForClassroom(selectedClassroom);
    if (initialSubjects.isEmpty) {
      _showMessage('Aucune matière attribuée à cette classe.');
      return;
    }

    int selectedSubject = _asInt(initialSubjects.first['id']);
    List<Map<String, dynamic>> dialogStudents = _studentsForClassroom(
      selectedClassroom,
    );
    final scoreControllers = <int, TextEditingController>{};
    Map<int, Map<String, dynamic>> existingByStudent = {};
    bool loadingRows = false;
    bool savingRows = false;
    bool initialized = false;
    String? dialogError;
    int createdCount = 0;
    int updatedCount = 0;
    int skippedCount = 0;

    void disposeDialogControllers() {
      for (final controller in scoreControllers.values) {
        controller.dispose();
      }
      scoreControllers.clear();
    }

    Future<void> loadDialogRows(StateSetter setDialogState) async {
      setDialogState(() {
        loadingRows = true;
        dialogError = null;
      });

      try {
        final loadedStudents = _studentsForClassroom(selectedClassroom);
        final sessionId = await _ensureExamSessionForCurrentPeriod();
        final loadedExisting = await _fetchExistingExamResultsForDialog(
          sessionId: sessionId,
          subjectId: selectedSubject,
        );

        disposeDialogControllers();
        for (final student in loadedStudents) {
          final studentId = _asInt(student['id']);
          final existing = loadedExisting[studentId];
          scoreControllers[studentId] = TextEditingController(
            text: (existing?['score'] ?? '').toString(),
          );
        }

        setDialogState(() {
          dialogStudents = loadedStudents;
          existingByStudent = loadedExisting;
          loadingRows = false;
        });
      } catch (error) {
        setDialogState(() {
          loadingRows = false;
          dialogError =
              'Erreur chargement notes examen: ${_extractFriendlyError(error)}';
        });
      }
    }

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            if (!initialized) {
              initialized = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted) {
                  loadDialogRows(setDialogState);
                }
              });
            }

            return AlertDialog(
              title: const Text('Saisie des notes examen'),
              content: SizedBox(
                width: 760,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Classe ID $selectedClassroom • Période ${_currentTermOrDefault()}',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            initialValue: selectedClassroom,
                            decoration: const InputDecoration(
                              labelText: 'Classe',
                            ),
                            items: _classroomsForCurrentRole()
                                .map(
                                  (row) => DropdownMenuItem<int>(
                                    value: _asInt(row['id']),
                                    child: Text('${row['name']}'),
                                  ),
                                )
                                .toList(),
                            onChanged: loadingRows || savingRows
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    setDialogState(() {
                                      selectedClassroom = value;
                                      final classSubjects =
                                          _subjectsForClassroom(
                                            selectedClassroom,
                                          );
                                      selectedSubject = classSubjects.isNotEmpty
                                          ? _asInt(classSubjects.first['id'])
                                          : 0;
                                    });
                                    loadDialogRows(setDialogState);
                                  },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            initialValue: selectedSubject > 0
                                ? selectedSubject
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Matière',
                            ),
                            items: _subjectsForClassroom(selectedClassroom)
                                .map(
                                  (row) => DropdownMenuItem<int>(
                                    value: _asInt(row['id']),
                                    child: Text(
                                      '${row['code']} - ${row['name']}',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: loadingRows || savingRows
                                ? null
                                : (value) {
                                    if (value == null || value <= 0) return;
                                    setDialogState(
                                      () => selectedSubject = value,
                                    );
                                    loadDialogRows(setDialogState);
                                  },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (dialogError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          dialogError!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    if (loadingRows)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (dialogStudents.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('Aucun élève trouvé pour cette classe.'),
                      )
                    else
                      Container(
                        constraints: const BoxConstraints(maxHeight: 340),
                        decoration: BoxDecoration(
                          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: dialogStudents.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final student = dialogStudents[index];
                            final studentId = _asInt(student['id']);
                            final controller =
                                scoreControllers[studentId] ??
                                TextEditingController();
                            scoreControllers[studentId] = controller;
                            final existing = existingByStudent[studentId];

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${student['matricule'] ?? ''} • ${(student['user_full_name'] ?? '').toString().trim()}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (existing != null)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 8),
                                      child: Tooltip(
                                        message:
                                            'Note examen existante: modification',
                                        child: Icon(
                                          Icons.edit_note_outlined,
                                          size: 18,
                                          color: Colors.orangeAccent,
                                        ),
                                      ),
                                    ),
                                  SizedBox(
                                    width: 130,
                                    child: TextField(
                                      controller: controller,
                                      enabled: !savingRows,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        labelText: 'Examen /20',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: savingRows
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: savingRows || loadingRows || dialogStudents.isEmpty
                      ? null
                      : () async {
                          for (final student in dialogStudents) {
                            final studentId = _asInt(student['id']);
                            final raw =
                                scoreControllers[studentId]?.text.trim() ?? '';
                            if (raw.isEmpty) {
                              continue;
                            }
                            final score = double.tryParse(
                              raw.replaceAll(',', '.'),
                            );
                            if (score == null || score < 0 || score > 20) {
                              setDialogState(() {
                                dialogError =
                                    'Note examen invalide pour ${(student['user_full_name'] ?? student['matricule'] ?? 'un élève')}.';
                              });
                              return;
                            }
                          }

                          setDialogState(() {
                            savingRows = true;
                            dialogError = null;
                          });

                          createdCount = 0;
                          updatedCount = 0;
                          skippedCount = 0;

                          try {
                            final dio = ref.read(dioProvider);
                            final sessionId =
                                await _ensureExamSessionForCurrentPeriod();
                            final existingMap =
                                await _fetchExistingExamResultsForDialog(
                                  sessionId: sessionId,
                                  subjectId: selectedSubject,
                                );

                            for (final student in dialogStudents) {
                              final studentId = _asInt(student['id']);
                              final raw =
                                  scoreControllers[studentId]?.text.trim() ??
                                  '';
                              if (raw.isEmpty) {
                                skippedCount += 1;
                                continue;
                              }
                              final score = double.tryParse(
                                raw.replaceAll(',', '.'),
                              );
                              if (score == null) {
                                continue;
                              }

                              final existing = existingMap[studentId];
                              if (existing != null) {
                                final resultId = _asInt(existing['id']);
                                await dio.patch(
                                  '/exam-results/$resultId/',
                                  data: {'score': score},
                                );
                                updatedCount += 1;
                              } else {
                                await dio.post(
                                  '/exam-results/',
                                  data: {
                                    'session': sessionId,
                                    'student': studentId,
                                    'subject': selectedSubject,
                                    'score': score,
                                  },
                                );
                                createdCount += 1;
                              }
                            }

                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (error) {
                            setDialogState(() {
                              savingRows = false;
                              dialogError =
                                  'Erreur enregistrement examen: ${_extractFriendlyError(error)}';
                            });
                          }
                        },
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    disposeDialogControllers();

    if (shouldSave != true) {
      return;
    }

    await _reloadGradesForCurrentFilters(showError: false);
    final touched = createdCount + updatedCount;
    if (touched > 0) {
      _showMessage(
        'Notes examen enregistrées: $createdCount ajoutées, $updatedCount modifiées, $skippedCount ignorées.',
        isSuccess: true,
      );
    } else {
      _showMessage('Aucune note examen enregistrée (champs vides).');
    }
  }
}

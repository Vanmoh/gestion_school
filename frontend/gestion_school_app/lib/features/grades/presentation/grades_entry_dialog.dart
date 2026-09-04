part of 'grades_page.dart';

/// La saisie des notes, sortie de l'écran qui la porte.
///
/// Cinq cent quatre-vingts lignes: c'est le geste principal de l'écran, et
/// il était noyé au milieu de tout le reste.
///
/// Le mécanisme `part` déplace le code sans le découpler: l'extension voit les
/// champs de la page comme avant, et rien n'a eu à passer en paramètre.
extension _DialogueDeSaisieDesNotes on _GradesPageState {
  Future<void> _openGradeEntryDialog() async {
    if (_refuseSiLectureSeule()) return;
    if (_isValidated) {
      _showMessage('Période validée par la direction: saisie verrouillée.');
      return;
    }

    if (_selectedClassroom == null ||
        _selectedAcademicYear == null ||
        _termController.text.trim().isEmpty) {
      _showMessage('Sélectionnez classe, année et période avant la saisie.');
      return;
    }

    final visibleClassrooms = _classroomsForCurrentRole();
    if (_students.isEmpty || visibleClassrooms.isEmpty) {
      _showMessage('Aucun élève ou matière disponible pour la saisie.');
      return;
    }

    int selectedClassroom =
        _selectedClassroom ?? _asInt(visibleClassrooms.first['id']);
    final initialSubjects = _subjectsForClassroom(selectedClassroom);
    if (initialSubjects.isEmpty) {
      _showMessage(
        'Aucune matière attribuée à cette classe. Configurez les attributions enseignant/matière.',
      );
      return;
    }

    int selectedSubject = _asInt(initialSubjects.first['id']);
    List<Map<String, dynamic>> dialogStudents = _studentsForClassroom(
      selectedClassroom,
    );
    final devoirControllers = <int, List<TextEditingController>>{};
    Map<int, Map<String, dynamic>> existingByStudent = {};
    int devoirCount = 3;
    bool loadingRows = false;
    bool savingRows = false;
    bool initialized = false;
    String? dialogError;
    int createdCount = 0;
    int updatedCount = 0;
    int skippedCount = 0;

    void disposeDialogControllers() {
      for (final controllers in devoirControllers.values) {
        for (final controller in controllers) {
          controller.dispose();
        }
      }
      devoirControllers.clear();
    }

    List<TextEditingController> ensureControllers(int studentId) {
      final existing = devoirControllers[studentId];
      if (existing == null) {
        final created = List.generate(
          devoirCount,
          (_) => TextEditingController(),
        );
        devoirControllers[studentId] = created;
        return created;
      }

      if (existing.length > devoirCount) {
        for (var i = devoirCount; i < existing.length; i++) {
          existing[i].dispose();
        }
        existing.removeRange(devoirCount, existing.length);
      }
      while (existing.length < devoirCount) {
        existing.add(TextEditingController());
      }
      return existing;
    }

    List<double> parseStudentScores(List<TextEditingController> controllers) {
      final scores = <double>[];
      for (final controller in controllers) {
        final raw = controller.text.trim();
        if (raw.isEmpty) {
          continue;
        }
        final parsed = double.tryParse(raw.replaceAll(',', '.'));
        if (parsed == null || parsed < 0 || parsed > 20) {
          throw const FormatException('INVALID_SCORE');
        }
        scores.add(parsed);
      }
      return scores;
    }

    Future<void> loadDialogRows(StateSetter setDialogState) async {
      setDialogState(() {
        loadingRows = true;
        dialogError = null;
      });

      try {
        final term = _currentTermOrDefault();
        final loadedStudents = _studentsForClassroom(selectedClassroom);

        final classSubjects = _subjectsForClassroom(selectedClassroom);
        final validSubjectIds = classSubjects
            .map((row) => _asInt(row['id']))
            .where((id) => id > 0)
            .toSet();

        if (validSubjectIds.isEmpty ||
            !validSubjectIds.contains(selectedSubject)) {
          disposeDialogControllers();
          setDialogState(() {
            dialogStudents = loadedStudents;
            existingByStudent = <int, Map<String, dynamic>>{};
            loadingRows = false;
            dialogError =
                'Aucune matière attribuée à cette classe. Configurez les attributions enseignant/matière.';
          });
          return;
        }

        final loadedExisting = await _fetchExistingGradesForDialog(
          classroomId: selectedClassroom,
          subjectId: selectedSubject,
          academicYearId: _selectedAcademicYear!,
          term: term,
        );

        disposeDialogControllers();
        var maxCount = 1;
        for (final student in loadedStudents) {
          final studentId = _asInt(student['id']);
          final scores = _homeworkScoresFromGradeRow(loadedExisting[studentId]);
          if (scores.length > maxCount) {
            maxCount = scores.length;
          }
        }

        devoirCount = math.max(devoirCount, maxCount);
        for (final student in loadedStudents) {
          final studentId = _asInt(student['id']);
          final scores = _homeworkScoresFromGradeRow(loadedExisting[studentId]);
          final controllers = <TextEditingController>[];
          for (var index = 0; index < devoirCount; index++) {
            final value = index < scores.length
                ? scores[index].toStringAsFixed(2)
                : '';
            controllers.add(TextEditingController(text: value));
          }
          devoirControllers[studentId] = controllers;
        }

        setDialogState(() {
          dialogStudents = loadedStudents;
          existingByStudent = loadedExisting;
          loadingRows = false;
        });
      } on DioException catch (error) {
        setDialogState(() {
          loadingRows = false;
          dialogError =
              'Erreur chargement élèves/notes: ${_extractDioErrorMessage(error)}';
        });
      } catch (error) {
        setDialogState(() {
          loadingRows = false;
          dialogError =
              'Erreur chargement élèves/notes: ${_extractFriendlyError(error)}';
        });
      }
    }

    final dialogAction = await showDialog<String>(
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
              title: const Text('Saisie des notes par classe'),
              content: SizedBox(
                width: 860,
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
                    Row(
                      children: [
                        Text('Devoirs: $devoirCount'),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: savingRows
                              ? null
                              : () {
                                  setDialogState(() {
                                    devoirCount += 1;
                                    for (final student in dialogStudents) {
                                      final studentId = _asInt(student['id']);
                                      ensureControllers(studentId);
                                    }
                                  });
                                },
                          icon: const Icon(Icons.add),
                          label: const Text('Ajouter devoir'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: (savingRows || devoirCount <= 1)
                              ? null
                              : () {
                                  setDialogState(() {
                                    devoirCount -= 1;
                                    for (final controllers
                                        in devoirControllers.values) {
                                      if (controllers.length > devoirCount) {
                                        final removed = controllers
                                            .removeLast();
                                        removed.dispose();
                                      }
                                    }
                                  });
                                },
                          icon: const Icon(Icons.remove),
                          label: const Text('Retirer devoir'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: savingRows
                              ? null
                              : () {
                                  Navigator.of(dialogContext).pop('imports');
                                },
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('Imports académiques'),
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
                        constraints: const BoxConstraints(maxHeight: 360),
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
                            final controllers = ensureControllers(studentId);
                            final existing = existingByStudent[studentId];

                            double? average;
                            try {
                              average = _averageHomeworkScores(
                                parseStudentScores(controllers),
                              );
                            } catch (_) {
                              average = null;
                            }

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
                                            'Notes existantes: modification',
                                        child: Icon(
                                          Icons.edit_note_outlined,
                                          size: 18,
                                          color: Colors.orangeAccent,
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    flex: 2,
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: [
                                          for (
                                            var devoirIndex = 0;
                                            devoirIndex < devoirCount;
                                            devoirIndex++
                                          )
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                right: 6,
                                              ),
                                              child: SizedBox(
                                                width: 82,
                                                child: TextField(
                                                  controller:
                                                      controllers[devoirIndex],
                                                  enabled: !savingRows,
                                                  onChanged: (_) =>
                                                      setDialogState(() {}),
                                                  keyboardType:
                                                      const TextInputType.numberWithOptions(
                                                        decimal: true,
                                                      ),
                                                  decoration: InputDecoration(
                                                    isDense: true,
                                                    labelText:
                                                        'D${devoirIndex + 1}',
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 100,
                                    child: Text(
                                      average == null
                                          ? 'Classe: -'
                                          : 'Classe: ${average.toStringAsFixed(2)}',
                                      textAlign: TextAlign.right,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelLarge,
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
                      : () => Navigator.of(dialogContext).pop(null),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: savingRows || loadingRows || dialogStudents.isEmpty
                      ? null
                      : () async {
                          final term = _currentTermOrDefault();
                          final academicYear = _selectedAcademicYear;
                          if (academicYear == null) {
                            setDialogState(() {
                              dialogError =
                                  'Année scolaire introuvable pour cet enregistrement.';
                            });
                            return;
                          }

                          for (final student in dialogStudents) {
                            final studentId = _asInt(student['id']);
                            try {
                              parseStudentScores(ensureControllers(studentId));
                            } on FormatException {
                              setDialogState(() {
                                dialogError =
                                    'Notes de devoir invalides pour ${(student['user_full_name'] ?? student['matricule'] ?? 'un élève')}.';
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
                            for (final student in dialogStudents) {
                              final studentId = _asInt(student['id']);
                              final scores = parseStudentScores(
                                ensureControllers(studentId),
                              );

                              if (scores.isEmpty) {
                                skippedCount += 1;
                                continue;
                              }

                              final existing = existingByStudent[studentId];
                              if (existing != null) {
                                final gradeId = _asInt(existing['id']);
                                await dio.patch(
                                  '/grades/$gradeId/',
                                  data: {'homework_scores': scores},
                                );
                                updatedCount += 1;
                              } else {
                                await dio.post(
                                  '/grades/',
                                  data: {
                                    'student': studentId,
                                    'subject': selectedSubject,
                                    'classroom': selectedClassroom,
                                    'academic_year': academicYear,
                                    'term': term,
                                    'homework_scores': scores,
                                  },
                                );
                                createdCount += 1;
                              }
                            }

                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop('save');
                            }
                          } catch (error) {
                            setDialogState(() {
                              savingRows = false;
                              dialogError =
                                  'Erreur enregistrement: ${_extractFriendlyError(error)}';
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

    if (dialogAction == 'imports') {
      if (!mounted) return;
      _openAcademicImports();
      return;
    }

    if (dialogAction != 'save') {
      return;
    }

    majEtat(() {
      _selectedClassroom = selectedClassroom;
      _selectedSubject = selectedSubject;
      final students = _studentsForClassroom(selectedClassroom);
      if (students.isNotEmpty) {
        _selectedStudent = _asInt(students.first['id']);
      }
    });

    await _refreshValidationStatus();
    await _reloadGradesForCurrentFilters(showError: true);

    final touched = createdCount + updatedCount;
    if (touched > 0) {
      _showMessage(
        'Enregistrement terminé: $createdCount ajoutées, $updatedCount modifiées, $skippedCount ignorées.',
        isSuccess: true,
      );
    } else {
      _showMessage('Aucune note enregistrée (champs vides).');
    }
  }
}

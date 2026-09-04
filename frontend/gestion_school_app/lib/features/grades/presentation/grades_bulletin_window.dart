part of 'grades_page.dart';

/// La fenêtre des bulletins, sortie de l'écran des notes.
///
/// Cinq cents lignes au milieu d'un fichier qui en comptait trois mille cinq
/// cents : on ne trouvait plus la saisie des notes, qui est pourtant ce que
/// l'écran fait au quotidien.
///
/// Le mécanisme `part` déplace le code sans le découper : l'extension voit les
/// champs de la page comme avant, et rien n'a eu à être passé en paramètre —
/// c'est ce qui rend le déplacement sûr sur cinq cents lignes qui manipulent
/// une douzaine de membres.
extension _DialogueDesBulletins on _GradesPageState {
  Future<void> _openBulletinFloatingWindow() async {
    if (_years.isEmpty) {
      _showMessage('Aucune année scolaire disponible.');
      return;
    }

    final visibleClassrooms = _classroomsForCurrentRole();
    if (visibleClassrooms.isEmpty) {
      _showMessage('Aucune classe disponible.');
      return;
    }

    var selectedClassroom = _selectedClassroom;
    if (selectedClassroom == null ||
        !visibleClassrooms.any(
          (row) => _asInt(row['id']) == selectedClassroom,
        )) {
      selectedClassroom = _asInt(visibleClassrooms.first['id']);
    }

    var selectedYear = _selectedAcademicYear;
    if (selectedYear == null ||
        !_years.any((row) => _asInt(row['id']) == selectedYear)) {
      selectedYear = _asInt(_years.first['id']);
    }

    var selectedTerm = _currentTermOrDefault();
    var search = '';

    Future<Map<int, int>> fetchRankMapForSelection({
      required int? classroomId,
      required int? academicYearId,
    }) async {
      if (classroomId == null || classroomId <= 0 || academicYearId == null || academicYearId <= 0) {
        return <int, int>{};
      }

      try {
        final dio = ref.read(dioProvider);
        // Sans `page_size`: le client HTTP recolle alors les pages de
        // lui-meme. Le parametre rendait la main a l'appelant, qui ne
        // suivait pas `next` -- au-dela de 500 lignes, les eleves manquants
        // perdaient leur rang et se retrouvaient releques en fin de liste,
        // sans que rien ne le signale.
        final response = await dio.get(
          '/student-history/',
          queryParameters: {
            'classroom': classroomId,
            'academic_year': academicYearId,
          },
        );

        final rows = _extractRows(response.data);
        final rankMap = <int, int>{};
        for (final row in rows) {
          final studentId = _asInt(row['student']);
          final rank = _asInt(row['rank']);
          if (studentId > 0 && rank > 0) {
            rankMap[studentId] = rank;
          }
        }
        return rankMap;
      } catch (_) {
        return <int, int>{};
      }
    }

    List<Map<String, dynamic>> sortStudentsByRank(
      List<Map<String, dynamic>> rows,
      Map<int, int> rankByStudent,
    ) {
      final sorted = List<Map<String, dynamic>>.from(rows);
      sorted.sort((a, b) {
        final aId = _asInt(a['id']);
        final bId = _asInt(b['id']);
        final rankA = rankByStudent[aId] ?? 1 << 30;
        final rankB = rankByStudent[bId] ?? 1 << 30;
        if (rankA != rankB) return rankA.compareTo(rankB);

        final aName = '${a['user_full_name'] ?? ''}'.toLowerCase();
        final bName = '${b['user_full_name'] ?? ''}'.toLowerCase();
        final byName = aName.compareTo(bName);
        if (byName != 0) return byName;

        final aMat = '${a['matricule'] ?? ''}'.toLowerCase();
        final bMat = '${b['matricule'] ?? ''}'.toLowerCase();
        final byMat = aMat.compareTo(bMat);
        if (byMat != 0) return byMat;

        return aId.compareTo(bId);
      });
      return sorted;
    }

    var rankByStudent = await fetchRankMapForSelection(
      classroomId: selectedClassroom,
      academicYearId: selectedYear,
    );
    var rankLoading = false;

    final initialStudents = sortStudentsByRank(
      _studentsForClassroom(selectedClassroom),
      rankByStudent,
    );

    int? selectedStudent = initialStudents.isNotEmpty
        ? _asInt(initialStudents.first['id'])
        : null;
    Future<Uint8List>? previewFuture = selectedStudent == null
        ? null
        : _fetchBulletinPdfBytes(
            studentId: selectedStudent,
            yearId: selectedYear,
            term: selectedTerm,
          );

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final classStudents = sortStudentsByRank(
              _studentsForClassroom(selectedClassroom),
              rankByStudent,
            );

            final visibleStudents = classStudents.where((row) {
              if (search.isEmpty) return true;
              final label =
                  '${row['matricule'] ?? ''} ${(row['user_full_name'] ?? '').toString().trim()}';
              return label.toLowerCase().contains(search);
            }).toList();

            return Dialog(
              insetPadding: const EdgeInsets.all(14),
              child: SizedBox(
                width: 1200,
                height: 760,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Impression bulletins',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          SizedBox(
                            width: 260,
                            child: DropdownButtonFormField<int>(
                              isExpanded: true,
                              initialValue: selectedClassroom,
                              decoration: const InputDecoration(
                                labelText: 'Classe',
                              ),
                              items: visibleClassrooms
                                  .map(
                                    (row) => DropdownMenuItem<int>(
                                      value: _asInt(row['id']),
                                      child: Text('${row['name'] ?? 'Classe'}'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) async {
                                if (value == null) return;
                                setDialogState(() {
                                  selectedClassroom = value;
                                  rankLoading = true;
                                });

                                final nextRankMap =
                                    await fetchRankMapForSelection(
                                      classroomId: value,
                                      academicYearId: selectedYear,
                                    );
                                if (!mounted) return;

                                setDialogState(() {
                                  rankByStudent = nextRankMap;
                                  rankLoading = false;
                                  final nextStudents = sortStudentsByRank(
                                    _studentsForClassroom(selectedClassroom),
                                    rankByStudent,
                                  );
                                  selectedStudent = nextStudents.isNotEmpty
                                      ? _asInt(nextStudents.first['id'])
                                      : null;
                                  previewFuture = selectedStudent == null
                                      ? null
                                      : _fetchBulletinPdfBytes(
                                          studentId: selectedStudent!,
                                          yearId: selectedYear,
                                          term: selectedTerm,
                                        );
                                });
                              },
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: DropdownButtonFormField<int>(
                              isExpanded: true,
                              initialValue: selectedYear,
                              decoration: const InputDecoration(
                                labelText: 'Année scolaire',
                              ),
                              items: _years
                                  .map(
                                    (row) => DropdownMenuItem<int>(
                                      value: _asInt(row['id']),
                                      child: Text('${row['name'] ?? 'Année'}'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) async {
                                if (value == null) return;
                                setDialogState(() {
                                  selectedYear = value;
                                  rankLoading = true;
                                });

                                final nextRankMap =
                                    await fetchRankMapForSelection(
                                      classroomId: selectedClassroom,
                                      academicYearId: value,
                                    );
                                if (!mounted) return;

                                setDialogState(() {
                                  rankByStudent = nextRankMap;
                                  rankLoading = false;
                                  final nextStudents = sortStudentsByRank(
                                    _studentsForClassroom(selectedClassroom),
                                    rankByStudent,
                                  );
                                  if (selectedStudent != null &&
                                      !nextStudents.any(
                                        (row) => _asInt(row['id']) == selectedStudent,
                                      )) {
                                    selectedStudent = nextStudents.isNotEmpty
                                        ? _asInt(nextStudents.first['id'])
                                        : null;
                                  }
                                  previewFuture = selectedStudent == null
                                      ? null
                                      : _fetchBulletinPdfBytes(
                                          studentId: selectedStudent!,
                                          yearId: selectedYear,
                                          term: selectedTerm,
                                        );
                                });
                              },
                            ),
                          ),
                          SizedBox(
                            width: 170,
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: selectedTerm,
                              decoration: const InputDecoration(
                                labelText: 'Période',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'T1',
                                  child: Text('T1'),
                                ),
                                DropdownMenuItem(
                                  value: 'T2',
                                  child: Text('T2'),
                                ),
                                DropdownMenuItem(
                                  value: 'T3',
                                  child: Text('T3'),
                                ),
                              ],
                              onChanged: (value) {
                                setDialogState(() {
                                  selectedTerm = value ?? 'T1';
                                  previewFuture = selectedStudent == null
                                      ? null
                                      : _fetchBulletinPdfBytes(
                                          studentId: selectedStudent!,
                                          yearId: selectedYear,
                                          term: selectedTerm,
                                        );
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Row(
                          children: [
                            SizedBox(
                              width: 320,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextField(
                                    decoration: const InputDecoration(
                                      labelText: 'Rechercher un élève',
                                      prefixIcon: Icon(Icons.search),
                                    ),
                                    onChanged: (value) {
                                      setDialogState(() {
                                        search = value.trim().toLowerCase();
                                      });
                                    },
                                  ),
                                  if (rankLoading)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 6),
                                      child: Text(
                                        'Tri par rang en cours...',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Theme.of(context).colorScheme.outlineVariant,
                                        ),
                                      ),
                                      child: visibleStudents.isEmpty
                                          ? const Center(
                                              child: Padding(
                                                padding: EdgeInsets.all(12),
                                                child: Text(
                                                  'Aucun élève trouvé.',
                                                ),
                                              ),
                                            )
                                          : ListView.separated(
                                              itemCount: visibleStudents.length,
                                              separatorBuilder: (_, _) =>
                                                  const Divider(height: 1),
                                              itemBuilder: (context, index) {
                                                final row =
                                                    visibleStudents[index];
                                                final rowId = _asInt(row['id']);
                                                final selected =
                                                    rowId == selectedStudent;
                                                final rankLabel = rankByStudent[rowId];
                                                final label =
                                                    '${row['matricule'] ?? ''} ${(row['user_full_name'] ?? '').toString().trim()}';
                                                return ListTile(
                                                  dense: true,
                                                  selected: selected,
                                                  title: Text(
                                                    label.trim(),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  subtitle: rankLabel == null
                                                      ? null
                                                      : Text('Rang: $rankLabel'),
                                                  onTap: () {
                                                    setDialogState(() {
                                                      selectedStudent = rowId;
                                                      previewFuture =
                                                          _fetchBulletinPdfBytes(
                                                            studentId: rowId,
                                                            yearId:
                                                                selectedYear,
                                                            term: selectedTerm,
                                                          );
                                                    });
                                                  },
                                                );
                                              },
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                                ),
                                child: selectedStudent == null
                                    ? const Center(
                                        child: Text(
                                          'Sélectionnez un élève pour afficher l\'aperçu.',
                                        ),
                                      )
                                    : FutureBuilder<Uint8List>(
                                        future: previewFuture,
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState ==
                                              ConnectionState.waiting) {
                                            return const Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            );
                                          }
                                          if (snapshot.hasError) {
                                            return Center(
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  12,
                                                ),
                                                child: Text(
                                                  'Erreur aperçu: ${snapshot.error}',
                                                ),
                                              ),
                                            );
                                          }

                                          final bytes = snapshot.data;
                                          if (bytes == null || bytes.isEmpty) {
                                            return const Center(
                                              child: Text(
                                                'Aperçu indisponible.',
                                              ),
                                            );
                                          }

                                          return PdfPreview(
                                            build: (_) async => bytes,
                                            allowSharing: false,
                                            allowPrinting: false,
                                            canChangeOrientation: false,
                                            canChangePageFormat: false,
                                            canDebug: false,
                                            maxPageWidth: 780,
                                            initialPageFormat:
                                                PdfPageFormat.a4.landscape,
                                          );
                                        },
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('Fermer'),
                          ),
                          FilledButton.icon(
                            onPressed: selectedStudent == null
                                ? null
                                : () async {
                                    Navigator.of(dialogContext).pop();
                                    await _printBulletin(
                                      studentId: selectedStudent,
                                      yearId: selectedYear,
                                      term: selectedTerm,
                                    );
                                  },
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Imprimer élève'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: classStudents.isEmpty
                                ? null
                                : () async {
                                    Navigator.of(dialogContext).pop();
                                    await _printClassBulletins(
                                      classroomId: selectedClassroom,
                                      yearId: selectedYear,
                                      term: selectedTerm,
                                    );
                                  },
                            icon: const Icon(Icons.groups_2_outlined),
                            label: const Text('Imprimer classe entière'),
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
  }
}

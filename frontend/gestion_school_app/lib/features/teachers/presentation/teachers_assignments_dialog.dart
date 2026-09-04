part of 'teachers_page.dart';

/// Les affectations d'un enseignant: quelles matières, dans quelles classes.
///
/// Trois cents lignes qui ne parlent que de cela.
///
/// Le mécanisme `part` déplace le code sans le découpler: l'extension voit
/// les champs de la page comme avant.
extension _DialogueDesAffectations on _TeachersPageState {
  Future<void> _openAssignmentManagementDialog() async {
    var currentPage = 1;
    const pageSize = 6;
    var searchQuery = '';
    var sortBy = 'teacher';
    var sortAscending = true;
    final searchController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredAssignments = _assignments.where((row) {
              if (searchQuery.isEmpty) {
                return true;
              }

              final teacher = _teacherById(_asInt(row['teacher']));
              final subject = _subjectById(_asInt(row['subject']));
              final classroom = _classroomById(_asInt(row['classroom']));
              final teacherLabel = teacher == null
                  ? '-'
                  : _teacherProfileLabel(teacher);
              final subjectLabel =
                  '${subject?['code'] ?? ''} ${subject?['name'] ?? ''}'.trim();
              final classroomLabel = (classroom?['name'] ?? '-').toString();

              return '$teacherLabel $subjectLabel $classroomLabel'
                  .toLowerCase()
                  .contains(searchQuery);
            }).toList();

            filteredAssignments.sort((a, b) {
              int result;
              if (sortBy == 'subject') {
                final leftSubject = _subjectById(_asInt(a['subject']));
                final rightSubject = _subjectById(_asInt(b['subject']));
                final left =
                    '${leftSubject?['code'] ?? ''} ${leftSubject?['name'] ?? ''}'
                        .trim()
                        .toLowerCase();
                final right =
                    '${rightSubject?['code'] ?? ''} ${rightSubject?['name'] ?? ''}'
                        .trim()
                        .toLowerCase();
                result = left.compareTo(right);
              } else if (sortBy == 'classroom') {
                final leftClassroom = _classroomById(_asInt(a['classroom']));
                final rightClassroom = _classroomById(_asInt(b['classroom']));
                final left = (leftClassroom?['name'] ?? '')
                    .toString()
                    .toLowerCase();
                final right = (rightClassroom?['name'] ?? '')
                    .toString()
                    .toLowerCase();
                result = left.compareTo(right);
              } else {
                final leftTeacher = _teacherById(_asInt(a['teacher']));
                final rightTeacher = _teacherById(_asInt(b['teacher']));
                final left = leftTeacher == null
                    ? ''
                    : _teacherProfileLabel(leftTeacher).toLowerCase();
                final right = rightTeacher == null
                    ? ''
                    : _teacherProfileLabel(rightTeacher).toLowerCase();
                result = left.compareTo(right);
              }
              return sortAscending ? result : -result;
            });

            final total = filteredAssignments.length;
            final totalPages = total == 0
                ? 1
                : ((total + pageSize - 1) ~/ pageSize);
            if (currentPage > totalPages) {
              currentPage = totalPages;
            }
            final start = (currentPage - 1) * pageSize;
            final end = start + pageSize > total ? total : start + pageSize;
            final pagedAssignments = total == 0
                ? <Map<String, dynamic>>[]
                : filteredAssignments.sublist(start, end);

            return AlertDialog(
              title: const Text('Gestion des affectations'),
              content: SizedBox(
                width: 880,
                child: _assignments.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('Aucune affectation disponible.'),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SizedBox(
                                  width: 300,
                                  child: TextField(
                                    controller: searchController,
                                    onChanged: (value) {
                                      setDialogState(() {
                                        searchQuery = value
                                            .trim()
                                            .toLowerCase();
                                        currentPage = 1;
                                      });
                                    },
                                    decoration: InputDecoration(
                                      labelText: 'Recherche affectation',
                                      prefixIcon: const Icon(Icons.search),
                                      suffixIcon: searchQuery.isEmpty
                                          ? null
                                          : IconButton(
                                              onPressed: () {
                                                searchController.clear();
                                                setDialogState(() {
                                                  searchQuery = '';
                                                  currentPage = 1;
                                                });
                                              },
                                              icon: const Icon(Icons.clear),
                                            ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 220,
                                  child: DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    initialValue: sortBy,
                                    decoration: const InputDecoration(
                                      labelText: 'Trier par',
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'teacher',
                                        child: Text('Enseignant'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'subject',
                                        child: Text('Matière'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'classroom',
                                        child: Text('Classe'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value == null) {
                                        return;
                                      }
                                      setDialogState(() {
                                        sortBy = value;
                                        currentPage = 1;
                                      });
                                    },
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    setDialogState(() {
                                      sortAscending = !sortAscending;
                                      currentPage = 1;
                                    });
                                  },
                                  icon: Icon(
                                    sortAscending
                                        ? Icons.arrow_upward_rounded
                                        : Icons.arrow_downward_rounded,
                                  ),
                                  label: Text(
                                    sortAscending ? 'Croissant' : 'Décroissant',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (pagedAssignments.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Text(
                                  'Aucune affectation pour ce filtre.',
                                ),
                              )
                            else
                              ...pagedAssignments.map((row) {
                                final teacher = _teacherById(
                                  _asInt(row['teacher']),
                                );
                                final subject = _subjectById(
                                  _asInt(row['subject']),
                                );
                                final classroom = _classroomById(
                                  _asInt(row['classroom']),
                                );
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  title: Text(
                                    teacher == null
                                        ? '-'
                                        : _teacherProfileLabel(teacher),
                                  ),
                                  subtitle: Text(
                                    '${subject?['code'] ?? ''} ${subject?['name'] ?? ''} - ${(classroom?['name'] ?? '-').toString()}',
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    enabled: !_saving,
                                    onSelected: (value) async {
                                      await _handleAssignmentMenuAction(
                                        value,
                                        row,
                                      );
                                      if (context.mounted) {
                                        setDialogState(() {});
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'show',
                                        child: Text('Afficher'),
                                      ),
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Modifier'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Supprimer'),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
              ),
              actions: [
                Text(
                  'Page $currentPage / $totalPages',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                IconButton(
                  tooltip: 'Page précédente',
                  onPressed: currentPage > 1
                      ? () => setDialogState(() => currentPage -= 1)
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                IconButton(
                  tooltip: 'Page suivante',
                  onPressed: currentPage < totalPages
                      ? () => setDialogState(() => currentPage += 1)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () async {
                          final created = await _openCreateAssignmentDialog();
                          if (created && context.mounted) {
                            setDialogState(() {});
                          }
                        },
                  icon: const Icon(Icons.add_link_rounded),
                  label: const Text('Ajouter une nouvelle affectation'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fermer'),
                ),
              ],
            );
          },
        );
      },
    );

    searchController.dispose();
  }
}

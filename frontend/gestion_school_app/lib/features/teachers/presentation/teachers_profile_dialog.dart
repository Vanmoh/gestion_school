part of 'teachers_page.dart';

/// La fiche d'un enseignant.
///
/// Distincte de ses affectations et de son compte.
///
/// Le mécanisme `part` déplace le code sans le découpler: l'extension voit
/// les champs de la page comme avant.
extension _DialogueDuProfil on _TeachersPageState {
  Future<void> _openProfileManagementDialog() async {
    var currentPage = 1;
    const pageSize = 6;
    var searchQuery = '';
    var sortBy = 'name';
    var sortAscending = true;
    final searchController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredProfiles = _teachers.where((profile) {
              if (searchQuery.isEmpty) {
                return true;
              }

              final user = _findUserById(_asInt(profile['user']));
              final name =
                  (user == null
                          ? _teacherProfileLabel(profile)
                          : _fullNameFromUser(user))
                      .toLowerCase();
              final code = (profile['employee_code'] ?? '')
                  .toString()
                  .toLowerCase();
              final hireDate = (profile['hire_date'] ?? '')
                  .toString()
                  .toLowerCase();

              return '$name $code $hireDate'.contains(searchQuery);
            }).toList();

            filteredProfiles.sort((a, b) {
              int result;
              if (sortBy == 'code') {
                final left = (a['employee_code'] ?? '')
                    .toString()
                    .toLowerCase();
                final right = (b['employee_code'] ?? '')
                    .toString()
                    .toLowerCase();
                result = left.compareTo(right);
              } else if (sortBy == 'hire_date') {
                final leftDate =
                    _parseApiDate((a['hire_date'] ?? '').toString()) ??
                    DateTime(1900);
                final rightDate =
                    _parseApiDate((b['hire_date'] ?? '').toString()) ??
                    DateTime(1900);
                result = leftDate.compareTo(rightDate);
              } else {
                final leftUser = _findUserById(_asInt(a['user']));
                final rightUser = _findUserById(_asInt(b['user']));
                final left =
                    (leftUser == null
                            ? _teacherProfileLabel(a)
                            : _fullNameFromUser(leftUser))
                        .toLowerCase();
                final right =
                    (rightUser == null
                            ? _teacherProfileLabel(b)
                            : _fullNameFromUser(rightUser))
                        .toLowerCase();
                result = left.compareTo(right);
              }

              return sortAscending ? result : -result;
            });

            final total = filteredProfiles.length;
            final totalPages = total == 0
                ? 1
                : ((total + pageSize - 1) ~/ pageSize);
            if (currentPage > totalPages) {
              currentPage = totalPages;
            }
            final start = (currentPage - 1) * pageSize;
            final end = start + pageSize > total ? total : start + pageSize;
            final pagedProfiles = total == 0
                ? <Map<String, dynamic>>[]
                : filteredProfiles.sublist(start, end);

            return AlertDialog(
              title: const Text('Gestion des profils enseignants'),
              content: SizedBox(
                width: 860,
                child: _teachers.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('Aucun profil enseignant disponible.'),
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
                                  width: 280,
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
                                      labelText: 'Recherche profil',
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
                                        value: 'name',
                                        child: Text('Nom'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'hire_date',
                                        child: Text('Date embauche'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'code',
                                        child: Text('Code employé'),
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
                            if (pagedProfiles.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Text('Aucun profil pour ce filtre.'),
                              )
                            else
                              ...pagedProfiles.map((profile) {
                                final user = _findUserById(
                                  _asInt(profile['user']),
                                );
                                final title = user == null
                                    ? _teacherProfileLabel(profile)
                                    : _fullNameFromUser(user);

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  title: Text(title),
                                  subtitle: Text(
                                    'Code: ${(profile['employee_code'] ?? '-').toString()}  •  Embauche: ${(profile['hire_date'] ?? '-').toString()}',
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    enabled: !_saving,
                                    onSelected: (value) async {
                                      await _handleProfileMenuAction(
                                        value,
                                        profile,
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
                          final created = await _openCreateProfileDialog();
                          if (created && context.mounted) {
                            setDialogState(() {});
                          }
                        },
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Ajouter un nouveau profil'),
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

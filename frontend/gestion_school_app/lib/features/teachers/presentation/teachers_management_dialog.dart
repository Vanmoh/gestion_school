part of 'teachers_page.dart';

/// La gestion d'un enseignant: activer, désactiver, retirer.
///
/// Les gestes lourds, séparés de la consultation.
///
/// Le mécanisme `part` déplace le code sans le découpler: l'extension voit
/// les champs de la page comme avant.
extension _DialogueDeGestion on _TeachersPageState {
  Future<void> _openTeacherManagementDialog() async {
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
            final filteredUsers = _teacherUsers.where((user) {
              if (searchQuery.isEmpty) {
                return true;
              }
              return _teacherUserSearchText(user).contains(searchQuery);
            }).toList();

            filteredUsers.sort((a, b) {
              int result;
              if (sortBy == 'username') {
                final left = (a['username'] ?? '').toString().toLowerCase();
                final right = (b['username'] ?? '').toString().toLowerCase();
                result = left.compareTo(right);
              } else if (sortBy == 'email') {
                final left = (a['email'] ?? '').toString().toLowerCase();
                final right = (b['email'] ?? '').toString().toLowerCase();
                result = left.compareTo(right);
              } else {
                final left = _fullNameFromUser(a).toLowerCase();
                final right = _fullNameFromUser(b).toLowerCase();
                result = left.compareTo(right);
              }
              return sortAscending ? result : -result;
            });

            final total = filteredUsers.length;
            final totalPages = total == 0
                ? 1
                : ((total + pageSize - 1) ~/ pageSize);
            if (currentPage > totalPages) {
              currentPage = totalPages;
            }
            final start = (currentPage - 1) * pageSize;
            final end = start + pageSize > total ? total : start + pageSize;
            final pagedUsers = total == 0
                ? <Map<String, dynamic>>[]
                : filteredUsers.sublist(start, end);

            return AlertDialog(
              title: const Text('Gestion des comptes enseignants'),
              content: SizedBox(
                width: 860,
                child: _teacherUsers.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('Aucun compte enseignant disponible.'),
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
                                      labelText: 'Recherche enseignant',
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
                                        value: 'username',
                                        child: Text('Username'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'email',
                                        child: Text('Email'),
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
                            if (pagedUsers.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Text('Aucun enseignant pour ce filtre.'),
                              )
                            else
                              ...pagedUsers.map((user) {
                                final userId = _asInt(user['id']);
                                final profile = _findTeacherProfileByUserId(
                                  userId,
                                );
                                final status = profile == null
                                    ? 'Profil non créé'
                                    : 'Profil créé';

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  title: Text(_fullNameFromUser(user)),
                                  subtitle: Text(status),
                                  trailing: PopupMenuButton<String>(
                                    enabled: !_saving,
                                    onSelected: (value) async {
                                      await _handleTeacherUserMenuAction(
                                        value,
                                        user,
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
                          final created = await _openCreateTeacherUserDialog();
                          if (created && context.mounted) {
                            setDialogState(() {});
                          }
                        },
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Ajouter un enseignant'),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/presentation/auth_controller.dart';

class TeachersPage extends ConsumerStatefulWidget {
  const TeachersPage({super.key});

  @override
  ConsumerState<TeachersPage> createState() => _TeachersPageState();
}

class _TeachersPageState extends ConsumerState<TeachersPage> {
  final _searchController = TextEditingController();
  final _employeeCodeController = TextEditingController();
  final _salaryController = TextEditingController();
  DateTime _hireDate = DateTime.now();

  int? _selectedTeacherUserId;
  int? _selectedTeacherId;
  int? _selectedSubjectId;
  int? _selectedClassroomId;

  bool _loading = true;
  bool _saving = false;
  String _profileFilter = 'all';

  List<Map<String, dynamic>> _teacherUsers = [];
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _classrooms = [];
  List<Map<String, dynamic>> _assignments = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _employeeCodeController.dispose();
    _salaryController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final dio = ref.read(dioProvider);

    try {
      final results = await Future.wait([
        dio.get('/auth/users/', queryParameters: {'role': 'teacher'}),
        dio.get('/teachers/'),
        dio.get('/subjects/'),
        dio.get('/classrooms/'),
        dio.get('/teacher-assignments/'),
      ]);

      if (!mounted) return;

      setState(() {
        _teacherUsers = _extractRows(results[0].data);
        _teachers = _extractRows(results[1].data);
        _subjects = _extractRows(results[2].data);
        _classrooms = _extractRows(results[3].data);
        _assignments = _extractRows(results[4].data);

        _selectedTeacherUserId ??= _teacherUsers.isNotEmpty
            ? _asInt(_teacherUsers.first['id'])
            : null;
        _selectedTeacherId ??= _teachers.isNotEmpty
            ? _asInt(_teachers.first['id'])
            : null;
        _selectedSubjectId ??= _subjects.isNotEmpty
            ? _asInt(_subjects.first['id'])
            : null;
        _selectedClassroomId ??= _classrooms.isNotEmpty
            ? _asInt(_classrooms.first['id'])
            : null;
      });
    } catch (error) {
      _showMessage('Erreur chargement enseignants: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createTeacherProfile() async {
    final userId = _selectedTeacherUserId;
    final employeeCode = _employeeCodeController.text.trim();
    final salary = double.tryParse(_salaryController.text.trim());

    if (userId == null || employeeCode.isEmpty || salary == null) {
      _showMessage('Complétez les champs enseignant.');
      return;
    }

    setState(() => _saving = true);

    try {
      await ref
          .read(dioProvider)
          .post(
            '/teachers/',
            data: {
              'user': userId,
              'employee_code': employeeCode,
              'hire_date': _apiDate(_hireDate),
              'salary_base': salary,
            },
          );

      if (!mounted) return;
      _employeeCodeController.clear();
      _salaryController.clear();
      _showMessage('Profil enseignant créé avec succès.', isSuccess: true);
      await _loadData();
    } catch (error) {
      _showMessage('Erreur création enseignant: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _createAssignment() async {
    final teacherId = _selectedTeacherId;
    final subjectId = _selectedSubjectId;
    final classroomId = _selectedClassroomId;

    if (teacherId == null || subjectId == null || classroomId == null) {
      _showMessage('Sélectionnez enseignant, matière et classe.');
      return;
    }

    setState(() => _saving = true);

    try {
      await ref
          .read(dioProvider)
          .post(
            '/teacher-assignments/',
            data: {
              'teacher': teacherId,
              'subject': subjectId,
              'classroom': classroomId,
            },
          );

      if (!mounted) return;
      _showMessage('Affectation créée avec succès.', isSuccess: true);
      await _loadData();
    } catch (error) {
      _showMessage('Erreur création affectation: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

<<<<<<< HEAD
  void _showMessage(String text, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isSuccess ? const Color(0xFF197A43) : null,
      ),
    );
=======
  Future<void> _deleteAssignment(int assignmentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Supprimer affectation'),
          content: const Text(
            'Confirmez-vous la suppression de cette affectation enseignant/matière/classe ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).delete('/teacher-assignments/$assignmentId/');
      if (!mounted) return;
      _showMessage('Affectation supprimée.', isSuccess: true);
      await _loadData();
    } catch (error) {
      _showMessage('Erreur suppression affectation: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _deleteTeacherProfile(Map<String, dynamic> profile) async {
    final profileId = _asInt(profile['id']);
    if (profileId <= 0) {
      _showMessage('Profil invalide.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Supprimer profil'),
          content: const Text(
            'Confirmez-vous la suppression de ce profil enseignant ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).delete('/teachers/$profileId/');
      if (!mounted) return;
      _showMessage('Profil supprimé.', isSuccess: true);
      await _loadData();
    } catch (error) {
      _showMessage('Erreur suppression profil: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _showProfileDialog(Map<String, dynamic> profile) async {
    final user = _findUserById(_asInt(profile['user']));
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Détails du profil'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailLine(
                  'Enseignant',
                  user == null ? '-' : _fullNameFromUser(user),
                ),
                _detailLine(
                  'Code employé',
                  (profile['employee_code'] ?? '-').toString(),
                ),
                _detailLine(
                  'Date embauche',
                  (profile['hire_date'] ?? '-').toString(),
                ),
                _detailLine(
                  'Salaire de base',
                  _formatMoney(profile['salary_base']),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editTeacherProfileDialog(Map<String, dynamic> profile) async {
    final employeeCodeController = TextEditingController(
      text: (profile['employee_code'] ?? '').toString(),
    );
    final salaryController = TextEditingController(
      text: (profile['salary_base'] ?? '').toString(),
    );
    DateTime selectedDate =
        _parseApiDate((profile['hire_date'] ?? '').toString()) ??
        DateTime.now();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Modifier profil enseignant'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: employeeCodeController,
                      decoration: const InputDecoration(
                        labelText: 'Code employé',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: salaryController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Salaire de base',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() => selectedDate = picked);
                          }
                        },
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text('Date: ${_apiDate(selectedDate)}'),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) {
      employeeCodeController.dispose();
      salaryController.dispose();
      return;
    }

    final employeeCode = employeeCodeController.text.trim();
    final salary = double.tryParse(salaryController.text.trim());
    employeeCodeController.dispose();
    salaryController.dispose();

    if (employeeCode.isEmpty || salary == null) {
      _showMessage('Informations invalides pour le profil.');
      return;
    }

    final profileId = _asInt(profile['id']);
    setState(() => _saving = true);
    try {
      await ref
          .read(dioProvider)
          .patch(
            '/teachers/$profileId/',
            data: {
              'employee_code': employeeCode,
              'salary_base': salary,
              'hire_date': _apiDate(selectedDate),
            },
          );
      if (!mounted) return;
      _showMessage('Profil modifié avec succès.', isSuccess: true);
      await _loadData();
    } catch (error) {
      _showMessage('Erreur modification profil: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _showAssignmentDialog(Map<String, dynamic> assignment) async {
    final teacher = _teacherById(_asInt(assignment['teacher']));
    final teacherLabel = teacher == null ? '-' : _teacherProfileLabel(teacher);
    final subject = _subjectById(_asInt(assignment['subject']));
    final classroom = _classroomById(_asInt(assignment['classroom']));

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Détails affectation'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailLine('Enseignant', teacherLabel),
                _detailLine(
                  'Matière',
                  '${subject?['code'] ?? ''} ${subject?['name'] ?? ''}'.trim(),
                ),
                _detailLine('Classe', (classroom?['name'] ?? '-').toString()),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editAssignmentDialog(Map<String, dynamic> assignment) async {
    int? teacherId = _asInt(assignment['teacher']);
    int? subjectId = _asInt(assignment['subject']);
    int? classroomId = _asInt(assignment['classroom']);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Modifier affectation'),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: teacherId,
                      decoration: const InputDecoration(
                        labelText: 'Enseignant',
                      ),
                      items: _teachers
                          .map(
                            (t) => DropdownMenuItem<int>(
                              value: _asInt(t['id']),
                              child: Text(_teacherProfileLabel(t)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => teacherId = value),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: subjectId,
                      decoration: const InputDecoration(labelText: 'Matière'),
                      items: _subjects
                          .map(
                            (s) => DropdownMenuItem<int>(
                              value: _asInt(s['id']),
                              child: Text(
                                '${s['code'] ?? ''} - ${s['name'] ?? ''}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => subjectId = value),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: classroomId,
                      decoration: const InputDecoration(labelText: 'Classe'),
                      items: _classrooms
                          .map(
                            (c) => DropdownMenuItem<int>(
                              value: _asInt(c['id']),
                              child: Text((c['name'] ?? '').toString()),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => classroomId = value),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true ||
        teacherId == null ||
        subjectId == null ||
        classroomId == null) {
      return;
    }

    final assignmentId = _asInt(assignment['id']);
    setState(() => _saving = true);
    try {
      await ref
          .read(dioProvider)
          .patch(
            '/teacher-assignments/$assignmentId/',
            data: {
              'teacher': teacherId,
              'subject': subjectId,
              'classroom': classroomId,
            },
          );
      if (!mounted) return;
      _showMessage('Affectation modifiée avec succès.', isSuccess: true);
      await _loadData();
    } catch (error) {
      _showMessage('Erreur modification affectation: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

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

  String _teacherUserSearchText(Map<String, dynamic> user) {
    final username = (user['username'] ?? '').toString().toLowerCase();
    final firstName = (user['first_name'] ?? '').toString().toLowerCase();
    final lastName = (user['last_name'] ?? '').toString().toLowerCase();
    final email = (user['email'] ?? '').toString().toLowerCase();
    final phone = (user['phone'] ?? '').toString().toLowerCase();
    final fullName = _fullNameFromUser(user).toLowerCase();
    return '$fullName $username $firstName $lastName $email $phone';
  }

  Future<void> _showTeacherUserDialog(Map<String, dynamic> user) async {
    final userId = _asInt(user['id']);
    final profile = _findTeacherProfileByUserId(userId);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Détails du compte enseignant'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailLine('Nom', _fullNameFromUser(user)),
                _detailLine('Username', (user['username'] ?? '-').toString()),
                _detailLine('Email', (user['email'] ?? '-').toString()),
                _detailLine('Téléphone', (user['phone'] ?? '-').toString()),
                _detailLine(
                  'Profil enseignant',
                  profile == null
                      ? 'Non créé'
                      : 'Créé (${(profile['employee_code'] ?? '-').toString()})',
                ),
              ],
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

  Future<void> _editTeacherUserDialog(Map<String, dynamic> user) async {
    final userId = _asInt(user['id']);
    if (userId <= 0) {
      _showMessage('Compte enseignant invalide.');
      return;
    }

    final usernameController = TextEditingController(
      text: (user['username'] ?? '').toString(),
    );
    final firstNameController = TextEditingController(
      text: (user['first_name'] ?? '').toString(),
    );
    final lastNameController = TextEditingController(
      text: (user['last_name'] ?? '').toString(),
    );
    final emailController = TextEditingController(
      text: (user['email'] ?? '').toString(),
    );
    final phoneController = TextEditingController(
      text: (user['phone'] ?? '').toString(),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        var savingDialog = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Modifier compte enseignant'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: 250,
                        child: TextField(
                          controller: usernameController,
                          enabled: !savingDialog,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: TextField(
                          controller: emailController,
                          enabled: !savingDialog,
                          decoration: const InputDecoration(labelText: 'Email'),
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: TextField(
                          controller: firstNameController,
                          enabled: !savingDialog,
                          decoration: const InputDecoration(
                            labelText: 'Prénom',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: TextField(
                          controller: lastNameController,
                          enabled: !savingDialog,
                          decoration: const InputDecoration(labelText: 'Nom'),
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: TextField(
                          controller: phoneController,
                          enabled: !savingDialog,
                          decoration: const InputDecoration(
                            labelText: 'Téléphone',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: savingDialog
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: savingDialog
                      ? null
                      : () async {
                          final username = usernameController.text.trim();
                          final firstName = firstNameController.text.trim();
                          final lastName = lastNameController.text.trim();
                          final email = emailController.text.trim();
                          final phone = phoneController.text.trim();

                          if (username.isEmpty ||
                              firstName.isEmpty ||
                              lastName.isEmpty ||
                              email.isEmpty) {
                            _showMessage(
                              'Username, prénom, nom et email sont obligatoires.',
                            );
                            return;
                          }

                          final authUser = ref
                              .read(authControllerProvider)
                              .value;
                          final existingEtablissement = _asInt(
                            user['etablissement'],
                          );
                          final targetEtablissement = existingEtablissement > 0
                              ? existingEtablissement
                              : (authUser?.etablissementId ?? 0);

                          setDialogState(() => savingDialog = true);
                          try {
                            await ref
                                .read(dioProvider)
                                .patch(
                                  '/auth/users/$userId/',
                                  data: {
                                    'username': username,
                                    'first_name': firstName,
                                    'last_name': lastName,
                                    'email': email,
                                    'phone': phone,
                                    'role': 'teacher',
                                    if (targetEtablissement > 0)
                                      'etablissement': targetEtablissement,
                                  },
                                );
                            if (context.mounted) {
                              Navigator.of(context).pop(true);
                            }
                          } catch (error) {
                            _showMessage('Erreur modification compte: $error');
                            if (context.mounted) {
                              setDialogState(() => savingDialog = false);
                            }
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

    usernameController.dispose();
    firstNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    phoneController.dispose();

    if (saved == true) {
      await _loadData();
      _showMessage('Compte enseignant modifié.', isSuccess: true);
    }
  }

  Future<void> _deleteTeacherUser(Map<String, dynamic> user) async {
    final userId = _asInt(user['id']);
    if (userId <= 0) {
      _showMessage('Compte enseignant invalide.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Supprimer compte enseignant'),
          content: const Text(
            'Confirmez-vous la suppression de ce compte enseignant ? Le profil et ses affectations associées seront également supprimés.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).delete('/auth/users/$userId/');
      if (!mounted) return;
      _showMessage('Compte enseignant supprimé.', isSuccess: true);
      await _loadData();
    } catch (error) {
      _showMessage('Erreur suppression compte: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<bool> _openCreateTeacherUserDialog() async {
    final usernameController = TextEditingController();
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final passwordController = TextEditingController();
    int? createdUserId;
    String createdUsername = '';

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        var savingDialog = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Ajouter un compte enseignant'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: 250,
                        child: TextField(
                          controller: usernameController,
                          enabled: !savingDialog,
                          decoration: const InputDecoration(
                            labelText: 'Username *',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: TextField(
                          controller: emailController,
                          enabled: !savingDialog,
                          decoration: const InputDecoration(
                            labelText: 'Email *',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: TextField(
                          controller: firstNameController,
                          enabled: !savingDialog,
                          decoration: const InputDecoration(
                            labelText: 'Prénom *',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: TextField(
                          controller: lastNameController,
                          enabled: !savingDialog,
                          decoration: const InputDecoration(labelText: 'Nom *'),
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: TextField(
                          controller: phoneController,
                          enabled: !savingDialog,
                          decoration: const InputDecoration(
                            labelText: 'Téléphone',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: TextField(
                          controller: passwordController,
                          enabled: !savingDialog,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Mot de passe *',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: savingDialog
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: savingDialog
                      ? null
                      : () async {
                          final username = usernameController.text.trim();
                          createdUsername = username.toLowerCase();
                          final firstName = firstNameController.text.trim();
                          final lastName = lastNameController.text.trim();
                          final email = emailController.text.trim();
                          final phone = phoneController.text.trim();
                          final password = passwordController.text;

                          if (username.isEmpty ||
                              firstName.isEmpty ||
                              lastName.isEmpty ||
                              email.isEmpty ||
                              password.isEmpty) {
                            _showMessage(
                              'Complétez tous les champs obligatoires.',
                            );
                            return;
                          }

                          final authUser = ref
                              .read(authControllerProvider)
                              .value;

                          setDialogState(() => savingDialog = true);
                          try {
                            final response = await ref
                                .read(dioProvider)
                                .post(
                                  '/auth/register/',
                                  data: {
                                    'username': username,
                                    'first_name': firstName,
                                    'last_name': lastName,
                                    'email': email,
                                    'phone': phone,
                                    'password': password,
                                    'role': 'teacher',
                                    if (authUser?.etablissementId != null)
                                      'etablissement':
                                          authUser!.etablissementId,
                                  },
                                );
                            final payload = response.data;
                            if (payload is Map<String, dynamic>) {
                              createdUserId = _asInt(payload['id']);
                            }
                            if (context.mounted) {
                              Navigator.of(context).pop(true);
                            }
                          } catch (error) {
                            _showMessage('Erreur création compte: $error');
                            if (context.mounted) {
                              setDialogState(() => savingDialog = false);
                            }
                          }
                        },
                  child: const Text('Créer compte'),
                ),
              ],
            );
          },
        );
      },
    );

    usernameController.dispose();
    firstNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();

    if (created == true) {
      await _loadData();
      if (!mounted) {
        return true;
      }
      _showMessage('Compte enseignant créé.', isSuccess: true);

      var targetUserId = (createdUserId != null && createdUserId! > 0)
          ? createdUserId
          : null;

      if (targetUserId == null) {
        final createdUser = _teacherUsers.firstWhere(
          (u) =>
              (u['username'] ?? '').toString().trim().toLowerCase() ==
              createdUsername,
          orElse: () => <String, dynamic>{},
        );
        final fallbackId = _asInt(createdUser['id']);
        if (fallbackId > 0) {
          targetUserId = fallbackId;
        }
      }

      final createProfileNow = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Créer le profil maintenant ?'),
            content: const Text(
              'Le compte enseignant est créé. Voulez-vous ouvrir directement la création du profil enseignant ?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Plus tard'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Créer profil'),
              ),
            ],
          );
        },
      );

      if (createProfileNow == true) {
        await _openCreateProfileDialog(preferredUserId: targetUserId);
      }
      return true;
    }
    return false;
  }

  Future<void> _handleTeacherUserMenuAction(
    String action,
    Map<String, dynamic> user,
  ) async {
    if (action == 'show') {
      await _showTeacherUserDialog(user);
      return;
    }
    if (action == 'edit') {
      await _editTeacherUserDialog(user);
      return;
    }
    if (action == 'delete') {
      await _deleteTeacherUser(user);
    }
  }

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
                                  subtitle: Text(
                                    '${(user['username'] ?? '-').toString()}  •  ${(user['email'] ?? '-').toString()}  •  $status',
                                  ),
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

  Future<bool> _openCreateProfileDialog({int? preferredUserId}) async {
    if (_teacherUsers.isEmpty) {
      _showMessage('Aucun compte enseignant disponible.');
      return false;
    }

    int? selectedUserId;
    final preferredId = preferredUserId ?? 0;
    if (preferredId > 0 && _findTeacherProfileByUserId(preferredId) == null) {
      for (final user in _teacherUsers) {
        if (_asInt(user['id']) == preferredId) {
          selectedUserId = preferredId;
          break;
        }
      }
    }

    if (selectedUserId == null) {
      for (final user in _teacherUsers) {
        if (_findTeacherProfileByUserId(_asInt(user['id'])) == null) {
          selectedUserId = _asInt(user['id']);
          break;
        }
      }
    }
    selectedUserId ??= _asInt(_teacherUsers.first['id']);

    final employeeCodeController = TextEditingController();
    final salaryController = TextEditingController();
    DateTime hireDate = DateTime.now();

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        var savingDialog = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Ajouter un nouveau profil'),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: selectedUserId,
                      decoration: const InputDecoration(
                        labelText: 'Compte enseignant',
                      ),
                      items: _teacherUsers
                          .map(
                            (u) => DropdownMenuItem<int>(
                              value: _asInt(u['id']),
                              child: Text(_teacherUserActionLabel(u)),
                            ),
                          )
                          .toList(),
                      onChanged: savingDialog
                          ? null
                          : (value) {
                              setDialogState(() => selectedUserId = value);
                            },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: employeeCodeController,
                      enabled: !savingDialog,
                      decoration: const InputDecoration(
                        labelText: 'Code employé',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: salaryController,
                      enabled: !savingDialog,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Salaire de base',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: savingDialog
                            ? null
                            : () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: hireDate,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setDialogState(() => hireDate = picked);
                                }
                              },
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text('Date: ${_apiDate(hireDate)}'),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: savingDialog
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: savingDialog
                      ? null
                      : () async {
                          final userId = selectedUserId;
                          final employeeCode = employeeCodeController.text
                              .trim();
                          final salary = double.tryParse(
                            salaryController.text.trim(),
                          );

                          if (userId == null ||
                              employeeCode.isEmpty ||
                              salary == null) {
                            _showMessage(
                              'Complétez les informations requises.',
                            );
                            return;
                          }

                          if (_findTeacherProfileByUserId(userId) != null) {
                            _showMessage(
                              'Ce compte possède déjà un profil enseignant.',
                            );
                            return;
                          }

                          setDialogState(() => savingDialog = true);
                          try {
                            await ref
                                .read(dioProvider)
                                .post(
                                  '/teachers/',
                                  data: {
                                    'user': userId,
                                    'employee_code': employeeCode,
                                    'hire_date': _apiDate(hireDate),
                                    'salary_base': salary,
                                  },
                                );
                            if (context.mounted) {
                              Navigator.of(context).pop(true);
                            }
                          } catch (error) {
                            _showMessage('Erreur création profil: $error');
                            if (context.mounted) {
                              setDialogState(() => savingDialog = false);
                            }
                          }
                        },
                  child: const Text('Créer profil'),
                ),
              ],
            );
          },
        );
      },
    );

    employeeCodeController.dispose();
    salaryController.dispose();

    if (created == true) {
      await _loadData();
      _showMessage('Profil enseignant créé avec succès.', isSuccess: true);
      return true;
    }
    return false;
  }

  Future<bool> _openCreateAssignmentDialog() async {
    if (_teachers.isEmpty || _subjects.isEmpty || _classrooms.isEmpty) {
      _showMessage(
        'Impossible de créer une affectation: enseignant, matière ou classe manquant.',
      );
      return false;
    }

    int? selectedTeacherId = _asInt(_teachers.first['id']);
    int? selectedSubjectId = _asInt(_subjects.first['id']);
    int? selectedClassroomId = _asInt(_classrooms.first['id']);

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        var savingDialog = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Ajouter une nouvelle affectation'),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: selectedTeacherId,
                      decoration: const InputDecoration(
                        labelText: 'Enseignant',
                      ),
                      items: _teachers
                          .map(
                            (t) => DropdownMenuItem<int>(
                              value: _asInt(t['id']),
                              child: Text(_teacherProfileLabel(t)),
                            ),
                          )
                          .toList(),
                      onChanged: savingDialog
                          ? null
                          : (value) {
                              setDialogState(() => selectedTeacherId = value);
                            },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: selectedSubjectId,
                      decoration: const InputDecoration(labelText: 'Matière'),
                      items: _subjects
                          .map(
                            (s) => DropdownMenuItem<int>(
                              value: _asInt(s['id']),
                              child: Text(
                                '${s['code'] ?? ''} - ${s['name'] ?? ''}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: savingDialog
                          ? null
                          : (value) {
                              setDialogState(() => selectedSubjectId = value);
                            },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: selectedClassroomId,
                      decoration: const InputDecoration(labelText: 'Classe'),
                      items: _classrooms
                          .map(
                            (c) => DropdownMenuItem<int>(
                              value: _asInt(c['id']),
                              child: Text((c['name'] ?? '').toString()),
                            ),
                          )
                          .toList(),
                      onChanged: savingDialog
                          ? null
                          : (value) {
                              setDialogState(() => selectedClassroomId = value);
                            },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: savingDialog
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: savingDialog
                      ? null
                      : () async {
                          final teacherId = selectedTeacherId;
                          final subjectId = selectedSubjectId;
                          final classroomId = selectedClassroomId;

                          if (teacherId == null ||
                              subjectId == null ||
                              classroomId == null) {
                            _showMessage(
                              'Complétez les informations requises.',
                            );
                            return;
                          }

                          setDialogState(() => savingDialog = true);
                          try {
                            await ref
                                .read(dioProvider)
                                .post(
                                  '/teacher-assignments/',
                                  data: {
                                    'teacher': teacherId,
                                    'subject': subjectId,
                                    'classroom': classroomId,
                                  },
                                );
                            if (context.mounted) {
                              Navigator.of(context).pop(true);
                            }
                          } catch (error) {
                            _showMessage('Erreur création affectation: $error');
                            if (context.mounted) {
                              setDialogState(() => savingDialog = false);
                            }
                          }
                        },
                  child: const Text('Créer affectation'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created == true) {
      await _loadData();
      _showMessage('Affectation créée avec succès.', isSuccess: true);
      return true;
    }
    return false;
  }

  Future<void> _handleProfileMenuAction(
    String action,
    Map<String, dynamic> profile,
  ) async {
    if (action == 'show') {
      await _showProfileDialog(profile);
      return;
    }
    if (action == 'edit') {
      await _editTeacherProfileDialog(profile);
      return;
    }
    if (action == 'delete') {
      await _deleteTeacherProfile(profile);
    }
  }

  Future<void> _handleAssignmentMenuAction(
    String action,
    Map<String, dynamic> assignment,
  ) async {
    if (action == 'show') {
      await _showAssignmentDialog(assignment);
      return;
    }
    if (action == 'edit') {
      await _editAssignmentDialog(assignment);
      return;
    }
    if (action == 'delete') {
      await _deleteAssignment(_asInt(assignment['id']));
    }
  }

  void _showMessage(String text, {bool isSuccess = false}) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            text,
            style: isSuccess ? const TextStyle(color: Colors.white) : null,
          ),
          backgroundColor: isSuccess ? const Color(0xFF197A43) : null,
        ),
      );
>>>>>>> main
  }

  Map<String, dynamic>? _findTeacherProfileByUserId(int userId) {
    for (final teacher in _teachers) {
      if (_asInt(teacher['user']) == userId) {
        return teacher;
      }
    }
    return null;
  }

  String _fullNameFromUser(Map<String, dynamic> user) {
    final first = (user['first_name'] ?? '').toString().trim();
    final last = (user['last_name'] ?? '').toString().trim();
    final full = '$first $last'.trim();
    if (full.isNotEmpty) {
      return full;
    }
    final username = (user['username'] ?? '').toString().trim();
    return username.isEmpty ? 'Utilisateur' : username;
  }

<<<<<<< HEAD
  List<Map<String, dynamic>> _buildDirectoryRows() {
    final rows = <Map<String, dynamic>>[];
    final handledTeacherIds = <int>{};

    for (final user in _teacherUsers) {
      final userId = _asInt(user['id']);
      final teacher = _findTeacherProfileByUserId(userId);
      if (teacher != null) {
        handledTeacherIds.add(_asInt(teacher['id']));
      }
      rows.add({'user': user, 'teacher': teacher});
    }

    for (final teacher in _teachers) {
      final teacherId = _asInt(teacher['id']);
      if (handledTeacherIds.contains(teacherId)) {
        continue;
      }
      rows.add({
        'user': <String, dynamic>{
          'id': _asInt(teacher['user']),
          'username': 'teacher_${_asInt(teacher['user'])}',
          'first_name': '',
          'last_name': '',
          'email': '',
          'phone': '',
        },
        'teacher': teacher,
      });
    }

    final query = _searchController.text.trim().toLowerCase();

    return rows.where((row) {
      final teacher = row['teacher'] as Map<String, dynamic>?;
      final user = row['user'] as Map<String, dynamic>;

      final hasProfile = teacher != null;
      if (_profileFilter == 'with_profile' && !hasProfile) {
        return false;
      }
      if (_profileFilter == 'without_profile' && hasProfile) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final fullName = _fullNameFromUser(user).toLowerCase();
      final username = (user['username'] ?? '').toString().toLowerCase();
      final employeeCode = (teacher?['employee_code'] ?? '')
          .toString()
          .toLowerCase();
      final haystack = '$fullName $username $employeeCode';
      return haystack.contains(query);
    }).toList()..sort((a, b) {
      final left = _fullNameFromUser(
        a['user'] as Map<String, dynamic>,
      ).toLowerCase();
      final right = _fullNameFromUser(
        b['user'] as Map<String, dynamic>,
      ).toLowerCase();
      return left.compareTo(right);
    });
  }

  void _syncSelectionWithRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      if (_selectedTeacherUserId != null || _selectedTeacherId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _selectedTeacherUserId = null;
            _selectedTeacherId = null;
          });
        });
      }
      return;
    }

    final hasCurrent = rows.any(
      (row) =>
          _asInt((row['user'] as Map<String, dynamic>)['id']) ==
          _selectedTeacherUserId,
    );

    if (!hasCurrent) {
      final first = rows.first;
      final user = first['user'] as Map<String, dynamic>;
      final teacher = first['teacher'] as Map<String, dynamic>?;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selectedTeacherUserId = _asInt(user['id']);
          _selectedTeacherId = teacher == null ? null : _asInt(teacher['id']);
        });
      });
    }
  }

  Future<void> _pickHireDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _hireDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _hireDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final teacherById = {for (final t in _teachers) _asInt(t['id']): t};
    final subjectById = {for (final s in _subjects) _asInt(s['id']): s};
    final classroomById = {for (final c in _classrooms) _asInt(c['id']): c};

    final directoryRows = _buildDirectoryRows();
    _syncSelectionWithRows(directoryRows);

    Map<String, dynamic>? selectedRow;
    for (final row in directoryRows) {
      final user = row['user'] as Map<String, dynamic>;
      if (_asInt(user['id']) == _selectedTeacherUserId) {
        selectedRow = row;
        break;
      }
    }
    selectedRow ??= directoryRows.isEmpty ? null : directoryRows.first;

    final selectedUser = selectedRow?['user'] as Map<String, dynamic>?;
    final selectedProfile = selectedRow?['teacher'] as Map<String, dynamic>?;

    final selectedTeacherAssignments = selectedProfile == null
        ? <Map<String, dynamic>>[]
        : _assignments
              .where(
                (row) =>
                    _asInt(row['teacher']) == _asInt(selectedProfile['id']),
              )
              .toList();

    final usersCount = _teacherUsers.length;
    final profileCount = _teachers.length;
    final pendingProfilesCount = usersCount - profileCount < 0
        ? 0
        : usersCount - profileCount;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'Gestion des enseignants',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Annuaire enseignants, fiches profils et affectations pédagogiques.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _metricChip('Comptes enseignants', '$usersCount'),
                _metricChip('Profils créés', '$profileCount'),
                _metricChip('Profils à créer', '$pendingProfilesCount'),
                _metricChip('Affectations', '${_assignments.length}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Recherche enseignant',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.trim().isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 230,
                  child: DropdownButtonFormField<String>(
                    initialValue: _profileFilter,
                    decoration: const InputDecoration(
                      labelText: 'Filtrer profils',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Tous')),
                      DropdownMenuItem(
                        value: 'with_profile',
                        child: Text('Avec profil'),
                      ),
                      DropdownMenuItem(
                        value: 'without_profile',
                        child: Text('Sans profil'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() => _profileFilter = value ?? 'all');
                    },
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () {
                          _searchController.clear();
                          setState(() {
                            _profileFilter = 'all';
                          });
                        },
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('Réinitialiser'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1100;

              final directoryPanel = Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Annuaire enseignants (${directoryRows.length})',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    if (directoryRows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Center(child: Text('Aucun enseignant trouvé.')),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: directoryRows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final row = directoryRows[index];
                          final user = row['user'] as Map<String, dynamic>;
                          final profile =
                              row['teacher'] as Map<String, dynamic>?;
                          final userId = _asInt(user['id']);
                          final selected = userId == _selectedTeacherUserId;

                          return Material(
                            color: selected
                                ? colorScheme.primary.withValues(alpha: 0.12)
                                : colorScheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () {
                                setState(() {
                                  _selectedTeacherUserId = userId;
                                  _selectedTeacherId = profile == null
                                      ? null
                                      : _asInt(profile['id']);
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  8,
                                  10,
                                  8,
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      child: Text(
                                        _fullNameFromUser(user)
                                            .trim()
                                            .split(' ')
                                            .where((p) => p.isNotEmpty)
                                            .take(2)
                                            .map((p) => p[0].toUpperCase())
                                            .join(),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _fullNameFromUser(user),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleSmall,
                                          ),
                                          Text(
                                            '@${(user['username'] ?? '').toString()}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    profile == null
                                        ? _statusTag(
                                            context,
                                            label: 'Profil manquant',
                                            color: const Color(0xFFB25D24),
                                          )
                                        : _statusTag(
                                            context,
                                            label:
                                                'Code ${profile['employee_code'] ?? '-'}',
                                            color: const Color(0xFF2968C8),
                                          ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              );

              final detailsPanel = Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: selectedUser == null
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Center(
                          child: Text('Sélectionnez un enseignant à gauche.'),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Fiche enseignant',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              _metricChip(
                                'Nom',
                                _fullNameFromUser(selectedUser),
                              ),
                              _metricChip(
                                'Username',
                                (selectedUser['username'] ?? '-').toString(),
                              ),
                              _metricChip(
                                'Email',
                                (selectedUser['email'] ?? '-').toString(),
                              ),
                              _metricChip(
                                'Téléphone',
                                (selectedUser['phone'] ?? '-').toString(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (selectedProfile != null)
                            Container(
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                              decoration: BoxDecoration(
                                color: colorScheme.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                              child: Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                children: [
                                  _metricChip(
                                    'Code employé',
                                    (selectedProfile['employee_code'] ?? '-')
                                        .toString(),
                                  ),
                                  _metricChip(
                                    'Date embauche',
                                    (selectedProfile['hire_date'] ?? '-')
                                        .toString(),
                                  ),
                                  _metricChip(
                                    'Salaire base',
                                    _formatMoney(
                                      selectedProfile['salary_base'],
                                    ),
                                  ),
                                  _metricChip(
                                    'Affectations',
                                    '${selectedTeacherAssignments.length}',
                                  ),
                                ],
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF3E8),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFFFD3AF),
                                ),
                              ),
                              child: const Text(
                                'Ce compte enseignant n\'a pas encore de profil. Complétez la section ci-dessous.',
                              ),
                            ),
                          const SizedBox(height: 10),
                          Text(
                            'Créer un profil enseignant',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              SizedBox(
                                width: 260,
                                child: DropdownButtonFormField<int>(
                                  initialValue: _selectedTeacherUserId,
                                  decoration: const InputDecoration(
                                    labelText: 'Compte utilisateur',
                                  ),
                                  items: _teacherUsers
                                      .map(
                                        (u) => DropdownMenuItem<int>(
                                          value: _asInt(u['id']),
                                          child: Text(_userLabel(u)),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedTeacherUserId = value;
                                      final profile = value == null
                                          ? null
                                          : _findTeacherProfileByUserId(value);
                                      _selectedTeacherId = profile == null
                                          ? null
                                          : _asInt(profile['id']);
                                    });
                                  },
                                ),
                              ),
                              SizedBox(
                                width: 170,
                                child: TextField(
                                  controller: _employeeCodeController,
                                  decoration: const InputDecoration(
                                    labelText: 'Code employé',
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 170,
                                child: TextField(
                                  controller: _salaryController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Salaire base',
                                  ),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _saving ? null : _pickHireDate,
                                icon: const Icon(Icons.calendar_month_outlined),
                                label: Text(_apiDate(_hireDate)),
                              ),
                              FilledButton.icon(
                                onPressed: _saving
                                    ? null
                                    : _createTeacherProfile,
                                icon: const Icon(
                                  Icons.person_add_alt_1_rounded,
                                ),
                                label: const Text('Créer profil'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Créer une affectation',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              SizedBox(
                                width: 220,
                                child: DropdownButtonFormField<int>(
                                  initialValue: _selectedTeacherId,
                                  decoration: const InputDecoration(
                                    labelText: 'Enseignant (profil)',
                                  ),
                                  items: _teachers
                                      .map(
                                        (t) => DropdownMenuItem<int>(
                                          value: _asInt(t['id']),
                                          child: Text(
                                            '${t['employee_code'] ?? '-'} (ID ${t['id']})',
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    setState(() => _selectedTeacherId = value);
                                  },
                                ),
                              ),
                              SizedBox(
                                width: 220,
                                child: DropdownButtonFormField<int>(
                                  initialValue: _selectedSubjectId,
                                  decoration: const InputDecoration(
                                    labelText: 'Matière',
                                  ),
                                  items: _subjects
                                      .map(
                                        (s) => DropdownMenuItem<int>(
                                          value: _asInt(s['id']),
                                          child: Text(
                                            '${s['code'] ?? ''} - ${s['name'] ?? ''}',
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    setState(() => _selectedSubjectId = value);
                                  },
                                ),
                              ),
                              SizedBox(
                                width: 220,
                                child: DropdownButtonFormField<int>(
                                  initialValue: _selectedClassroomId,
                                  decoration: const InputDecoration(
                                    labelText: 'Classe',
                                  ),
                                  items: _classrooms
                                      .map(
                                        (c) => DropdownMenuItem<int>(
                                          value: _asInt(c['id']),
                                          child: Text(
                                            '${c['name'] ?? ''} (ID ${c['id'] ?? ''})',
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    setState(
                                      () => _selectedClassroomId = value,
                                    );
                                  },
                                ),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _saving ? null : _createAssignment,
                                icon: const Icon(Icons.link_outlined),
                                label: const Text('Créer affectation'),
                              ),
                            ],
                          ),
                        ],
                      ),
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: directoryPanel),
                    const SizedBox(width: 12),
                    Expanded(flex: 5, child: detailsPanel),
                  ],
                );
              }

              return Column(
                children: [
                  directoryPanel,
                  const SizedBox(height: 12),
                  detailsPanel,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Affectations existantes',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                if (_assignments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('Aucune affectation enregistrée.'),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Enseignant')),
                        DataColumn(label: Text('Code')),
                        DataColumn(label: Text('Matière')),
                        DataColumn(label: Text('Classe')),
                      ],
                      rows: _assignments.map((row) {
                        final teacher = teacherById[_asInt(row['teacher'])];
                        final userId = _asInt(teacher?['user']);
                        Map<String, dynamic>? user;
                        for (final item in _teacherUsers) {
                          if (_asInt(item['id']) == userId) {
                            user = item;
                            break;
                          }
                        }
                        final subject = subjectById[_asInt(row['subject'])];
                        final classroom =
                            classroomById[_asInt(row['classroom'])];

                        return DataRow(
                          cells: [
                            DataCell(
                              Text(
                                user == null ? '-' : _fullNameFromUser(user),
                              ),
                            ),
                            DataCell(
                              Text(
                                (teacher?['employee_code'] ?? '-').toString(),
                              ),
                            ),
                            DataCell(
                              Text(
                                '${subject?['code'] ?? ''} ${subject?['name'] ?? ''}'
                                    .trim(),
                              ),
                            ),
                            DataCell(
                              Text((classroom?['name'] ?? '-').toString()),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
=======
  Future<void> _pickHireDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _hireDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _hireDate = picked);
    }
  }

  Widget _buildTeachersKpiPanel({
    required int usersCount,
    required int profileCount,
    required int pendingProfilesCount,
  }) {
    return _panelSurface(
      context,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _metricChip('Comptes enseignants', '$usersCount'),
          _metricChip('Profils créés', '$profileCount'),
          _metricChip('Profils à créer', '$pendingProfilesCount'),
          _metricChip('Affectations', '${_assignments.length}'),
        ],
      ),
    );
  }

  Widget _buildTeachersManagementHub() {
    return _panelSurface(
      context,
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Gestion centralisée via fenêtres dédiées',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _saving ? null : _openTeacherManagementDialog,
                icon: const Icon(Icons.groups_2_outlined),
                label: const Text('Gérer enseignant'),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : _openProfileManagementDialog,
                icon: const Icon(Icons.manage_accounts_outlined),
                label: const Text('Gérer profils'),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : _openAssignmentManagementDialog,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('Gérer affectations'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTeacherFocusPanel({
    required Map<String, dynamic>? selectedUser,
    required Map<String, dynamic>? selectedProfile,
    required List<Map<String, dynamic>> selectedTeacherAssignments,
    required ColorScheme colorScheme,
  }) {
    return _panelSurface(
      context,
      child: selectedUser == null
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'Sélectionnez un enseignant dans Gérer profils.',
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fiche enseignant',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _metricChip('Nom', _fullNameFromUser(selectedUser)),
                    _metricChip(
                      'Username',
                      (selectedUser['username'] ?? '-').toString(),
                    ),
                    _metricChip(
                      'Email',
                      (selectedUser['email'] ?? '-').toString(),
                    ),
                    _metricChip(
                      'Téléphone',
                      (selectedUser['phone'] ?? '-').toString(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (selectedProfile != null)
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        _metricChip(
                          'Code employé',
                          (selectedProfile['employee_code'] ?? '-').toString(),
                        ),
                        _metricChip(
                          'Date embauche',
                          (selectedProfile['hire_date'] ?? '-').toString(),
                        ),
                        _metricChip(
                          'Salaire base',
                          _formatMoney(selectedProfile['salary_base']),
                        ),
                        _metricChip(
                          'Affectations',
                          '${selectedTeacherAssignments.length}',
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E8),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFD3AF)),
                    ),
                    child: const Text(
                      'Ce compte enseignant n\'a pas encore de profil. Complétez la section ci-dessous.',
                    ),
                  ),
                const SizedBox(height: 14),
                _actionHeader(
                  context,
                  title: 'Mode action guidé',
                  subtitle:
                      'Etape 1: créer le profil, puis Etape 2: affecter la matière à la classe.',
                ),
                const SizedBox(height: 10),
                _actionSection(
                  context,
                  step: 'Etape 1',
                  title: 'Créer un profil enseignant',
                  subtitle:
                      'Choisissez un compte utilisateur enseignant puis complétez les informations RH.',
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: 280,
                        child: DropdownButtonFormField<int>(
                          initialValue: _selectedTeacherUserId,
                          decoration: const InputDecoration(
                            labelText: 'Compte enseignant',
                          ),
                          items: _teacherUsers
                              .map(
                                (u) => DropdownMenuItem<int>(
                                  value: _asInt(u['id']),
                                  child: Text(_teacherUserActionLabel(u)),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedTeacherUserId = value;
                              final profile = value == null
                                  ? null
                                  : _findTeacherProfileByUserId(value);
                              _selectedTeacherId = profile == null
                                  ? null
                                  : _asInt(profile['id']);
                            });
                          },
                        ),
                      ),
                      SizedBox(
                        width: 190,
                        child: TextField(
                          controller: _employeeCodeController,
                          decoration: const InputDecoration(
                            labelText: 'Code employé',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 170,
                        child: TextField(
                          controller: _salaryController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Salaire de base',
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _pickHireDate,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text(_apiDate(_hireDate)),
                      ),
                      FilledButton.icon(
                        onPressed: _saving ? null : _createTeacherProfile,
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Valider profil'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _actionSection(
                  context,
                  step: 'Etape 2',
                  title: 'Créer une affectation',
                  subtitle:
                      'Affectez un enseignant profilé à une matière et une classe.',
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: 260,
                        child: DropdownButtonFormField<int>(
                          initialValue: _selectedTeacherId,
                          decoration: const InputDecoration(
                            labelText: 'Enseignant',
                          ),
                          items: _teachers
                              .map(
                                (t) => DropdownMenuItem<int>(
                                  value: _asInt(t['id']),
                                  child: Text(_teacherProfileLabel(t)),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() => _selectedTeacherId = value);
                          },
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: DropdownButtonFormField<int>(
                          initialValue: _selectedSubjectId,
                          decoration: const InputDecoration(
                            labelText: 'Matière',
                          ),
                          items: _subjects
                              .map(
                                (s) => DropdownMenuItem<int>(
                                  value: _asInt(s['id']),
                                  child: Text(
                                    '${s['code'] ?? ''} - ${s['name'] ?? ''}',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() => _selectedSubjectId = value);
                          },
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<int>(
                          initialValue: _selectedClassroomId,
                          decoration: const InputDecoration(
                            labelText: 'Classe',
                          ),
                          items: _classrooms
                              .map(
                                (c) => DropdownMenuItem<int>(
                                  value: _asInt(c['id']),
                                  child: Text((c['name'] ?? '').toString()),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() => _selectedClassroomId = value);
                          },
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _saving ? null : _createAssignment,
                        icon: const Icon(Icons.link_outlined),
                        label: const Text('Valider affectation'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCompact = MediaQuery.sizeOf(context).width < 900;
    if (_selectedTeacherUserId == null && _teacherUsers.isNotEmpty) {
      _selectedTeacherUserId = _asInt(_teacherUsers.first['id']);
    }

    final selectedUser = _findUserById(_selectedTeacherUserId ?? 0);
    final selectedProfile = selectedUser == null
        ? null
        : _findTeacherProfileByUserId(_asInt(selectedUser['id']));

    if (selectedProfile != null &&
        _selectedTeacherId != _asInt(selectedProfile['id'])) {
      _selectedTeacherId = _asInt(selectedProfile['id']);
    }

    final selectedTeacherAssignments = selectedProfile == null
        ? <Map<String, dynamic>>[]
        : _assignments
              .where(
                (row) =>
                    _asInt(row['teacher']) == _asInt(selectedProfile['id']),
              )
              .toList();

    final usersCount = _teacherUsers.length;
    final profileCount = _teachers.length;
    final pendingProfilesCount = usersCount - profileCount < 0
        ? 0
        : usersCount - profileCount;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 14 : 20,
          vertical: 16,
        ),
        children: [
          Text(
            'Gestion des enseignants',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Annuaire, profils et affectations pédagogiques dans une seule vue.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _buildTeachersKpiPanel(
            usersCount: usersCount,
            profileCount: profileCount,
            pendingProfilesCount: pendingProfilesCount,
          ),
          const SizedBox(height: 14),
          _buildTeachersManagementHub(),
          const SizedBox(height: 14),
          _buildTeacherFocusPanel(
            selectedUser: selectedUser,
            selectedProfile: selectedProfile,
            selectedTeacherAssignments: selectedTeacherAssignments,
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }

  Widget _metricChip(String label, String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 170),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _panelSurface(
    BuildContext context, {
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(12, 12, 12, 12),
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: child,
    );
  }

  Widget _actionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _actionSection(
    BuildContext context, {
    required String step,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
>>>>>>> main
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
<<<<<<< HEAD
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
=======
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _statusTag(context, label: step, color: const Color(0xFF2968C8)),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          child,
>>>>>>> main
        ],
      ),
    );
  }

  Widget _statusTag(
    BuildContext context, {
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _formatMoney(dynamic value) {
    final amount = double.tryParse(value?.toString() ?? '') ?? 0;
    final normalized = amount.toStringAsFixed(0);
    final grouped = normalized.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]} ',
    );
    return '$grouped FCFA';
  }

  List<Map<String, dynamic>> _extractRows(dynamic data) {
    final List<dynamic> rows;
    if (data is Map<String, dynamic> && data['results'] is List) {
      rows = data['results'] as List<dynamic>;
    } else if (data is List<dynamic>) {
      rows = data;
    } else {
      rows = [];
    }

    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _apiDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  String _userLabel(Map<String, dynamic> user) {
    final first = (user['first_name'] ?? '').toString().trim();
    final last = (user['last_name'] ?? '').toString().trim();
    final full = '$first $last'.trim();
    final username = (user['username'] ?? '').toString().trim();
    return full.isNotEmpty ? '$full ($username)' : username;
  }

  String _teacherUserActionLabel(Map<String, dynamic> user) {
    final userId = _asInt(user['id']);
    final base = _userLabel(user);
    final hasProfile = _findTeacherProfileByUserId(userId) != null;
    return hasProfile
        ? '$base  -  profil déjà créé'
        : '$base  -  nouveau profil';
  }

  String _teacherProfileLabel(Map<String, dynamic> teacherProfile) {
    final code = (teacherProfile['employee_code'] ?? '').toString().trim();
    final userId = _asInt(teacherProfile['user']);
    Map<String, dynamic>? user;
    for (final row in _teacherUsers) {
      if (_asInt(row['id']) == userId) {
        user = row;
        break;
      }
    }

    final fullName = user == null
        ? 'Enseignant'
        : _fullNameFromUser(user).trim();
    if (code.isEmpty) {
      return fullName;
    }
    return '$fullName  -  $code';
  }

  Map<String, dynamic>? _findUserById(int userId) {
    for (final row in _teacherUsers) {
      if (_asInt(row['id']) == userId) {
        return row;
      }
    }
    return null;
  }

  Map<String, dynamic>? _teacherById(int teacherId) {
    for (final row in _teachers) {
      if (_asInt(row['id']) == teacherId) {
        return row;
      }
    }
    return null;
  }

  Map<String, dynamic>? _subjectById(int subjectId) {
    for (final row in _subjects) {
      if (_asInt(row['id']) == subjectId) {
        return row;
      }
    }
    return null;
  }

  Map<String, dynamic>? _classroomById(int classroomId) {
    for (final row in _classrooms) {
      if (_asInt(row['id']) == classroomId) {
        return row;
      }
    }
    return null;
  }

  DateTime? _parseApiDate(String value) {
    final parts = value.split('-');
    if (parts.length != 3) {
      return null;
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) {
      return null;
    }
    return DateTime(year, month, day);
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text('$label: $value'),
    );
  }
}

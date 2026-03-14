import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

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

  void _showMessage(String text, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isSuccess ? const Color(0xFF197A43) : null,
      ),
    );
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
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
}

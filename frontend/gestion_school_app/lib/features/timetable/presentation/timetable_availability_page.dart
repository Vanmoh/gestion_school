import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../models/etablissement.dart';
import '../../auth/presentation/auth_controller.dart';

class TeacherAvailabilityPage extends ConsumerStatefulWidget {
  const TeacherAvailabilityPage({super.key});

  @override
  ConsumerState<TeacherAvailabilityPage> createState() =>
      _TeacherAvailabilityPageState();
}

class _TeacherAvailabilityPageState
    extends ConsumerState<TeacherAvailabilityPage> {
  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _days = [];

  int? _selectedTeacherId;
  int? _gridTeacherFilterId;
  String _gridMode = 'global';
  int _startHour = 7;
  int _endHour = 18;
  int _slotMinutes = 60;
  int _rowsPerPage = 8;
  int _currentPage = 1;

  static const List<int> _rowsPerPageOptions = [6, 8, 10, 12, 16];
  static const List<int> _slotMinutesOptions = [30, 45, 60, 90, 120];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<List<Map<String, dynamic>>> _loadRowsSafely(
    Dio dio, {
    required String path,
  }) async {
    try {
      final response = await dio.get(path);
      return _extractRows(response.data);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final dio = ref.read(dioProvider);
    final user = ref.read(authControllerProvider).value;
    final isTeacherUser = user?.role == 'teacher';

    try {
      final teachers = await _loadRowsSafely(dio, path: '/teachers/');

      int? selectedTeacherId = _selectedTeacherId;
      if (isTeacherUser) {
        final ownTeacher = teachers.firstWhere(
          (row) => _asInt(row['user']) == user!.id,
          orElse: () => <String, dynamic>{},
        );
        final ownTeacherId = _asInt(ownTeacher['id']);
        if (ownTeacherId > 0) {
          selectedTeacherId = ownTeacherId;
        }
      } else if ((selectedTeacherId ?? 0) <= 0 && teachers.isNotEmpty) {
        selectedTeacherId = _asInt(teachers.first['id']);
      }

      // Availability occupancy must always be global.
      // If we filter by teacher, slots taken by others appear as "Disponible"
      // and fail only at POST validation time.

      final gridResponse = await dio.get(
        '/teacher-availability-slots/grid/',
        queryParameters: {
          '_ts': DateTime.now().millisecondsSinceEpoch,
          'start_hour': _startHour,
          'end_hour': _endHour,
          'slot_minutes': _slotMinutes,
        },
      );

      if (!mounted) return;

      final data = gridResponse.data;
      final daysRaw = data is Map<String, dynamic> ? data['days'] : null;
      final days = (daysRaw is List)
          ? daysRaw
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
          : <Map<String, dynamic>>[];

      setState(() {
        _teachers = teachers;
        _days = days;
        _selectedTeacherId = selectedTeacherId;
        _gridTeacherFilterId ??= selectedTeacherId;
        if (isTeacherUser) {
          _gridMode = 'mine';
          _gridTeacherFilterId = selectedTeacherId;
        }

        final rowCount = _rowCountFromDays(days);
        final totalPages = rowCount == 0
            ? 1
            : ((rowCount + _rowsPerPage - 1) ~/ _rowsPerPage);
        if (_currentPage > totalPages) {
          _currentPage = totalPages;
        }
      });
    } catch (_) {
      if (!mounted) return;
      _showMessage('Erreur lors du chargement des disponibilites enseignants.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _reserveCell(Map<String, dynamic> cell) async {
    final teacherId = _selectedTeacherId;
    final selectedEtablissement = ref.read(etablissementProvider).selected;
    if (teacherId == null || teacherId <= 0) {
      _showMessage('Selectionnez un enseignant avant de reserver un creneau.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(dioProvider)
          .post(
            '/teacher-availability-slots/',
            data: {
              'teacher': teacherId,
              'day_of_week': cell['day_of_week'],
              'start_time': cell['start_time'],
              'end_time': cell['end_time'],
              if (selectedEtablissement != null)
                'etablissement': selectedEtablissement.id,
            },
          );

      if (!mounted) return;
      _showMessage('Creneau reserve.', isSuccess: true);
      await _loadData();
    } on DioException catch (error) {
      if (!mounted) return;
      _showMessage(_extractErrorMessage(error));
    } catch (_) {
      if (!mounted) return;
      _showMessage('Erreur de reservation.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _releaseCell(Map<String, dynamic> cell) async {
    final availabilityId = _asInt(cell['availability_id']);
    if (availabilityId <= 0) {
      _showMessage('Creneau invalide.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(dioProvider)
          .delete('/teacher-availability-slots/$availabilityId/');
      if (!mounted) return;
      _showMessage('Declaration supprimee.', isSuccess: true);
      await _loadData();
    } catch (_) {
      if (!mounted) return;
      _showMessage('Impossible de supprimer ce creneau.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _extractErrorMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      const orderedKeys = [
        'non_field_errors',
        'detail',
        'teacher',
        'etablissement',
        'day_of_week',
        'start_time',
        'end_time',
      ];

      for (final key in orderedKeys) {
        final value = data[key];
        if (value is List && value.isNotEmpty) {
          return '$key: ${value.map((item) => item.toString()).join(' | ')}';
        }
        if (value is String && value.trim().isNotEmpty) {
          return '$key: ${value.trim()}';
        }
      }

      for (final entry in data.entries) {
        final value = entry.value;
        if (value is List && value.isNotEmpty) {
          return '${entry.key}: ${value.map((item) => item.toString()).join(' | ')}';
        }
        if (value is String && value.trim().isNotEmpty) {
          return '${entry.key}: ${value.trim()}';
        }
      }
    }

    if (data is List && data.isNotEmpty) {
      return data.map((item) => item.toString()).join(' | ');
    }

    if (data is String && data.trim().isNotEmpty) {
      return data.trim();
    }

    final fallback = error.message?.trim();
    if (fallback != null && fallback.isNotEmpty) {
      return fallback;
    }

    return 'Ce creneau est deja indisponible.';
  }

  void _showMessage(String message, {bool isSuccess = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isSuccess ? Colors.green.shade700 : null,
        ),
      );
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _hhmm(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(text);
    if (match == null) return text;
    final h = int.tryParse(match.group(1) ?? '') ?? 0;
    final m = int.tryParse(match.group(2) ?? '') ?? 0;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _teacherLabel(Map<String, dynamic> teacher) {
    final fullName = (teacher['user_full_name'] ?? '').toString().trim();
    if (fullName.isNotEmpty) return fullName;
    final firstName = (teacher['user_first_name'] ?? '').toString().trim();
    final lastName = (teacher['user_last_name'] ?? '').toString().trim();
    final merged = '$firstName $lastName'.trim();
    if (merged.isNotEmpty) return merged;
    final username = (teacher['user_username'] ?? '').toString().trim();
    if (username.isNotEmpty) return username;
    return (teacher['employee_code'] ?? 'Enseignant').toString();
  }

  int _rowCountFromDays(List<Map<String, dynamic>> days) {
    if (days.isEmpty) {
      return 0;
    }
    final first = days.first['cells'];
    if (first is! List) {
      return 0;
    }
    return first.length;
  }

  Future<void> _applyGridConfig() async {
    if (_endHour <= _startHour) {
      _showMessage(
        'Heure de fin invalide: elle doit etre apres l\'heure de debut.',
      );
      return;
    }

    setState(() => _currentPage = 1);
    await _loadData();
  }

  List<Map<String, dynamic>> _extractRows(dynamic data) {
    final List<dynamic> rows;
    if (data is Map<String, dynamic> && data['results'] is List) {
      rows = data['results'] as List<dynamic>;
    } else if (data is List<dynamic>) {
      rows = data;
    } else {
      rows = const [];
    }

    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authControllerProvider).value;
    final isTeacherUser = authUser?.role == 'teacher';

    final cellsByDay = <String, List<Map<String, dynamic>>>{
      for (final day in _days)
        (day['day_of_week'] ?? '').toString():
            ((day['cells'] as List?)
                ?.whereType<Map>()
                .map((cell) => Map<String, dynamic>.from(cell))
                .toList() ??
            <Map<String, dynamic>>[]),
    };
    final orderedDayKeys = _days
        .map((day) => (day['day_of_week'] ?? '').toString())
        .where((code) => code.isNotEmpty)
        .toList();

    final rowCount = orderedDayKeys.isEmpty
        ? 0
        : (cellsByDay[orderedDayKeys.first]?.length ?? 0);
    final totalPages = rowCount == 0
        ? 1
        : ((rowCount + _rowsPerPage - 1) ~/ _rowsPerPage);
    final boundedCurrentPage = _currentPage > totalPages
        ? totalPages
        : _currentPage;
    final startRow = rowCount == 0
        ? 0
        : (boundedCurrentPage - 1) * _rowsPerPage;
    final endRowExclusive = (startRow + _rowsPerPage) > rowCount
        ? rowCount
        : (startRow + _rowsPerPage);
    final visibleRowCount = rowCount == 0 ? 0 : (endRowExclusive - startRow);

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Disponibilite enseignant',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Declaration separee des cours. Un creneau reserve devient indisponible pour les autres.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!isTeacherUser)
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                    initialValue: _gridMode,
                    decoration: const InputDecoration(
                      labelText: 'Vue grille',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'global',
                        child: Text('Vue globale'),
                      ),
                      DropdownMenuItem(
                        value: 'mine',
                        child: Text('Mes disponibilites'),
                      ),
                    ],
                    onChanged: (_saving || _loading)
                        ? null
                        : (value) async {
                            if (value == null || value == _gridMode) {
                              return;
                            }
                            setState(() {
                              _gridMode = value;
                              _currentPage = 1;
                            });
                            await _loadData();
                          },
                  ),
                )
              else
                const Chip(label: Text('Vue: Mes disponibilites')),
              SizedBox(
                width: 320,
                child: DropdownButtonFormField<int>(
                  initialValue: _selectedTeacherId,
                  decoration: const InputDecoration(
                    labelText: 'Enseignant declarant',
                    border: OutlineInputBorder(),
                  ),
                  items: _teachers
                      .map(
                        (teacher) => DropdownMenuItem<int>(
                          value: _asInt(teacher['id']),
                          child: Text(_teacherLabel(teacher)),
                        ),
                      )
                      .toList(),
                  onChanged: (isTeacherUser || _saving)
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _selectedTeacherId = value);
                        },
                ),
              ),
              if (!isTeacherUser)
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<int?>(
                    initialValue: _gridTeacherFilterId,
                    decoration: const InputDecoration(
                      labelText: 'Filtre enseignant (grille)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Tous les enseignants'),
                      ),
                      ..._teachers.map(
                        (teacher) => DropdownMenuItem<int?>(
                          value: _asInt(teacher['id']),
                          child: Text(_teacherLabel(teacher)),
                        ),
                      ),
                    ],
                    onChanged: (_saving || _loading || _gridMode == 'mine')
                        ? null
                        : (value) async {
                            setState(() {
                              _gridTeacherFilterId = value;
                              _currentPage = 1;
                            });
                            await _loadData();
                          },
                  ),
                ),
              FilledButton.icon(
                onPressed: (_loading || _saving) ? null : _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualiser'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<int>(
                  initialValue: _startHour,
                  decoration: const InputDecoration(
                    labelText: 'Debut',
                    border: OutlineInputBorder(),
                  ),
                  items: List.generate(16, (index) => 6 + index).map((hour) {
                    return DropdownMenuItem<int>(
                      value: hour,
                      child: Text('${hour.toString().padLeft(2, '0')}:00'),
                    );
                  }).toList(),
                  onChanged: (_saving || _loading)
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _startHour = value);
                        },
                ),
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<int>(
                  initialValue: _endHour,
                  decoration: const InputDecoration(
                    labelText: 'Fin',
                    border: OutlineInputBorder(),
                  ),
                  items: List.generate(16, (index) => 9 + index).map((hour) {
                    return DropdownMenuItem<int>(
                      value: hour,
                      child: Text('${hour.toString().padLeft(2, '0')}:00'),
                    );
                  }).toList(),
                  onChanged: (_saving || _loading)
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _endHour = value);
                        },
                ),
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<int>(
                  initialValue: _slotMinutes,
                  decoration: const InputDecoration(
                    labelText: 'Pas (minutes)',
                    border: OutlineInputBorder(),
                  ),
                  items: _slotMinutesOptions
                      .map(
                        (minutes) => DropdownMenuItem<int>(
                          value: minutes,
                          child: Text('$minutes min'),
                        ),
                      )
                      .toList(),
                  onChanged: (_saving || _loading)
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _slotMinutes = value);
                        },
                ),
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<int>(
                  initialValue: _rowsPerPage,
                  decoration: const InputDecoration(
                    labelText: 'Lignes/page',
                    border: OutlineInputBorder(),
                  ),
                  items: _rowsPerPageOptions
                      .map(
                        (rows) => DropdownMenuItem<int>(
                          value: rows,
                          child: Text('$rows'),
                        ),
                      )
                      .toList(),
                  onChanged: (_saving || _loading)
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _rowsPerPage = value;
                            _currentPage = 1;
                          });
                        },
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: (_saving || _loading) ? null : _applyGridConfig,
                icon: const Icon(Icons.tune),
                label: const Text('Appliquer'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Chip(
                avatar: Icon(
                  Icons.circle,
                  size: 12,
                  color: Colors.green.shade700,
                ),
                label: const Text('Disponible'),
              ),
              const SizedBox(width: 8),
              Chip(
                avatar: Icon(
                  Icons.circle,
                  size: 12,
                  color: Colors.red.shade700,
                ),
                label: const Text('Indisponible'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (rowCount == 0 || orderedDayKeys.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Aucune grille disponible.'),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 14,
                columns: [
                  const DataColumn(label: Text('Horaire')),
                  ...orderedDayKeys.map((dayCode) {
                    final label = _days
                        .firstWhere(
                          (day) =>
                              (day['day_of_week'] ?? '').toString() == dayCode,
                          orElse: () => <String, dynamic>{'day_label': dayCode},
                        )['day_label']
                        .toString();
                    return DataColumn(label: Text(label));
                  }),
                ],
                rows: List<DataRow>.generate(visibleRowCount, (visibleIndex) {
                  final index = startRow + visibleIndex;
                  final firstDayCell = cellsByDay[orderedDayKeys.first]![index];
                  final timeLabel =
                      '${_hhmm(firstDayCell['start_time'])}-${_hhmm(firstDayCell['end_time'])}';

                  return DataRow(
                    cells: [
                      DataCell(Text(timeLabel)),
                      ...orderedDayKeys.map((dayCode) {
                        final cell = cellsByDay[dayCode]![index];
                        final status = (cell['status'] ?? 'disponible')
                            .toString();
                        final takenBy = (cell['teacher_name'] ?? '').toString();
                        final isAvailable = status == 'disponible';
                        final isOwnedBySelected =
                            _asInt(cell['teacher']) > 0 &&
                            _asInt(cell['teacher']) == _selectedTeacherId;

                        if (isAvailable) {
                          return DataCell(
                            FilledButton.tonal(
                              onPressed: _saving
                                  ? null
                                  : () => _reserveCell(cell),
                              child: const Text('Disponible'),
                            ),
                          );
                        }

                        if (isOwnedBySelected) {
                          return DataCell(
                            OutlinedButton(
                              onPressed: _saving
                                  ? null
                                  : () => _releaseCell(cell),
                              child: const Text('Choisi (annuler)'),
                            ),
                          );
                        }

                        return DataCell(
                          Tooltip(
                            message: takenBy.isEmpty
                                ? 'Indisponible'
                                : 'Reserve par $takenBy',
                            child: FilledButton(
                              onPressed: null,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red.shade700,
                              ),
                              child: const Text('Indisponible'),
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                }),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Page $boundedCurrentPage / $totalPages'),
              Text('Lignes: $visibleRowCount / $rowCount'),
              IconButton(
                tooltip: 'Premiere page',
                onPressed: (_saving || _loading || boundedCurrentPage <= 1)
                    ? null
                    : () => setState(() => _currentPage = 1),
                icon: const Icon(Icons.first_page),
              ),
              IconButton(
                tooltip: 'Page precedente',
                onPressed: (_saving || _loading || boundedCurrentPage <= 1)
                    ? null
                    : () =>
                          setState(() => _currentPage = boundedCurrentPage - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Page suivante',
                onPressed:
                    (_saving || _loading || boundedCurrentPage >= totalPages)
                    ? null
                    : () =>
                          setState(() => _currentPage = boundedCurrentPage + 1),
                icon: const Icon(Icons.chevron_right),
              ),
              IconButton(
                tooltip: 'Derniere page',
                onPressed:
                    (_saving || _loading || boundedCurrentPage >= totalPages)
                    ? null
                    : () => setState(() => _currentPage = totalPages),
                icon: const Icon(Icons.last_page),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

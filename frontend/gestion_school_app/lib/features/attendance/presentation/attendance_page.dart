import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../domain/attendance_student.dart';
import 'attendance_controller.dart';

class AttendancePage extends ConsumerStatefulWidget {
  const AttendancePage({super.key});

  @override
  ConsumerState<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends ConsumerState<AttendancePage> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _conduiteController = TextEditingController(text: '18');

  int? _selectedStudentId;
  DateTime _selectedDate = DateTime.now();
  bool _isAbsent = true;
  bool _isLate = false;

  @override
  void dispose() {
    _reasonController.dispose();
    _conduiteController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isSuccess = false}) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    const successColor = Color(0xFF197A43);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: isSuccess ? successColor : null,
          content: Text(
            message,
            style: isSuccess ? const TextStyle(color: Colors.white) : null,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(attendanceStudentsProvider);
    final attendancesAsync = ref.watch(attendancesProvider);
    final statsAsync = ref.watch(attendanceMonthlyStatsProvider);
    final mutationState = ref.watch(attendanceMutationProvider);
    final authState = ref.watch(authControllerProvider);
    final userRole = authState.valueOrNull?.role;
    final canEditConduite =
        userRole == 'supervisor' || userRole == 'super_admin';

    ref.listen<AsyncValue<void>>(attendanceMutationProvider, (prev, next) {
      if (prev?.isLoading == true && !next.isLoading && mounted) {
        if (next.hasError) {
          _showMessage('Erreur enregistrement: ${next.error}');
        } else {
          _showMessage('Absence/retard enregistré', isSuccess: true);
          _reasonController.clear();
          if (canEditConduite) {
            _conduiteController.text = '18';
          }
          setState(() {
            _isAbsent = true;
            _isLate = false;
            _selectedDate = DateTime.now();
          });
        }
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Gestion des absences')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          statsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Text('Erreur stats: $error'),
            data: (stats) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Statistiques mensuelles (${stats.month})'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _smallStat(
                          'Enregistrements',
                          stats.totalRecords.toString(),
                        ),
                        _smallStat('Absences', stats.absences.toString()),
                        _smallStat('Retards', stats.lates.toString()),
                        _smallStat(
                          'Justificatifs',
                          stats.justifications.toString(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 180,
                      child: LineChart(
                        LineChartData(
                          titlesData: const FlTitlesData(show: true),
                          lineBarsData: [
                            LineChartBarData(
                              spots: [
                                for (var i = 0; i < stats.daily.length; i++)
                                  FlSpot(
                                    i.toDouble(),
                                    stats.daily[i].absences.toDouble(),
                                  ),
                              ],
                              isCurved: true,
                            ),
                            LineChartBarData(
                              spots: [
                                for (var i = 0; i < stats.daily.length; i++)
                                  FlSpot(
                                    i.toDouble(),
                                    stats.daily[i].lates.toDouble(),
                                  ),
                              ],
                              isCurved: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Saisie absence/retard'),
                    const SizedBox(height: 10),
                    studentsAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (error, _) => Text('Erreur élèves: $error'),
                      data: (students) {
                        if (students.isEmpty) {
                          return const Text('Aucun élève disponible');
                        }
                        _selectedStudentId ??= students.first.id;
                        return DropdownButtonFormField<int>(
                          initialValue: _selectedStudentId,
                          items: students
                              .map(
                                (student) => DropdownMenuItem<int>(
                                  value: student.id,
                                  child: Text(_studentLabel(student)),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _selectedStudentId = value),
                          decoration: const InputDecoration(labelText: 'Élève'),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Date'),
                      subtitle: Text(_formatDate(_selectedDate)),
                      trailing: IconButton(
                        icon: const Icon(Icons.calendar_month),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() => _selectedDate = picked);
                          }
                        },
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _isAbsent,
                      title: const Text('Absent'),
                      onChanged: (value) => setState(() => _isAbsent = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _isLate,
                      title: const Text('Retard'),
                      onChanged: (value) => setState(() => _isLate = value),
                    ),
                    TextFormField(
                      controller: _reasonController,
                      decoration: const InputDecoration(
                        labelText: 'Motif / remarque',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _conduiteController,
                      enabled: canEditConduite,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Conduite (/20)',
                        helperText: canEditConduite
                            ? 'Modifiable par surveillant/super admin.'
                            : 'Lecture seule: modifiable par surveillant/super admin.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: mutationState.isLoading
                          ? null
                          : () async {
                              final studentId = _selectedStudentId;
                              if (studentId == null) {
                                return;
                              }

                              double? conduite;
                              if (canEditConduite) {
                                conduite = double.tryParse(
                                  _conduiteController.text.trim().replaceAll(
                                    ',',
                                    '.',
                                  ),
                                );
                                if (conduite == null ||
                                    conduite < 0 ||
                                    conduite > 20) {
                                  _showMessage(
                                    'La conduite doit être comprise entre 0 et 20.',
                                  );
                                  return;
                                }
                              }

                              await ref
                                  .read(attendanceMutationProvider.notifier)
                                  .createAttendance(
                                    studentId: studentId,
                                    date: _apiDate(_selectedDate),
                                    isAbsent: _isAbsent,
                                    isLate: _isLate,
                                    reason: _reasonController.text.trim(),
                                    conduite: conduite,
                                  );
                            },
                      child: mutationState.isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Enregistrer'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Historique'),
          const SizedBox(height: 8),
          attendancesAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (error, _) => Text('Erreur absences: $error'),
            data: (items) {
              if (items.isEmpty) {
                return const Text('Aucune donnée');
              }
              return Column(
                children: items
                    .map(
                      (item) => Card(
                        child: ListTile(
                          title: Text(
                            '${item.studentFullName} (${item.studentMatricule})',
                          ),
                          subtitle: Text(
                            '${item.date} • ${item.isAbsent ? 'Absent' : 'Présent'} • ${item.isLate ? 'Retard' : 'À l\'heure'} • Conduite: ${item.conduite.toStringAsFixed(2)}',
                          ),
                          trailing: item.reason.isEmpty
                              ? null
                              : Tooltip(
                                  message: item.reason,
                                  child: const Icon(Icons.info_outline),
                                ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _smallStat(String title, String value) {
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _studentLabel(AttendanceStudent student) {
    return '${student.fullName} (${student.matricule})';
  }

  String _formatDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  String _apiDate(DateTime value) => _formatDate(value);
}

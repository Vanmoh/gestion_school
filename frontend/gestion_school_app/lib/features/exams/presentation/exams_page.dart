import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'exams_controller.dart';

class ExamsPage extends ConsumerStatefulWidget {
  const ExamsPage({super.key});

  @override
  ConsumerState<ExamsPage> createState() => _ExamsPageState();
}

class _ExamsPageState extends ConsumerState<ExamsPage> {
  final _sessionTitleController = TextEditingController();
  DateTime _sessionStart = DateTime.now();
  DateTime _sessionEnd = DateTime.now().add(const Duration(days: 3));
  int? _selectedAcademicYear;
  String _selectedSessionTerm = 'T1';

  DateTime _planningDate = DateTime.now();
  TimeOfDay _planningStart = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _planningEnd = const TimeOfDay(hour: 10, minute: 0);
  int? _selectedPlanningSession;
  int? _selectedPlanningClassroom;
  int? _selectedPlanningSubject;

  int? _selectedInvigilationPlanning;
  int? _selectedInvigilationSupervisor;

  final _resultScoreController = TextEditingController();
  int? _selectedResultSession;
  int? _selectedResultStudent;
  int? _selectedResultSubject;

  @override
  void dispose() {
    _sessionTitleController.dispose();
    _resultScoreController.dispose();
    super.dispose();
  }

  Future<void> _refreshExams() async {
    ref.invalidate(examSessionsProvider);
    ref.invalidate(examPlanningsProvider);
    ref.invalidate(examResultsProvider);
    ref.invalidate(examInvigilationsProvider);
    ref.invalidate(examAcademicYearsProvider);
    ref.invalidate(examClassroomsProvider);
    ref.invalidate(examSubjectsProvider);
    ref.invalidate(examStudentsProvider);
    ref.invalidate(examSupervisorsProvider);
    await Future<void>.delayed(const Duration(milliseconds: 120));
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

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(examSessionsProvider);
    final planningsAsync = ref.watch(examPlanningsProvider);
    final resultsAsync = ref.watch(examResultsProvider);
    final invigilationsAsync = ref.watch(examInvigilationsProvider);
    final yearsAsync = ref.watch(examAcademicYearsProvider);
    final classroomsAsync = ref.watch(examClassroomsProvider);
    final subjectsAsync = ref.watch(examSubjectsProvider);
    final studentsAsync = ref.watch(examStudentsProvider);
    final supervisorsAsync = ref.watch(examSupervisorsProvider);
    final mutationState = ref.watch(examMutationProvider);
    final planningsSnapshot = planningsAsync.valueOrNull ?? const [];
    final sessionsCount = sessionsAsync.valueOrNull?.length ?? 0;
    final planningsCount = planningsAsync.valueOrNull?.length ?? 0;
    final resultsCount = resultsAsync.valueOrNull?.length ?? 0;
    final invigilationsCount = invigilationsAsync.valueOrNull?.length ?? 0;
    final colorScheme = Theme.of(context).colorScheme;

    ref.listen<AsyncValue<void>>(examMutationProvider, (prev, next) {
      if (prev?.isLoading == true && !next.isLoading && mounted) {
        if (next.hasError) {
          _showMessage('Erreur: ${next.error}');
        } else {
          _showMessage('Opération examen réussie', isSuccess: true);
        }
      }
    });

    return RefreshIndicator(
      onRefresh: _refreshExams,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gestion des examens',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sessions, plannings et publication des resultats.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: mutationState.isLoading ? null : _refreshExams,
                icon: const Icon(Icons.sync),
                label: const Text('Actualiser'),
              ),
            ],
          ),
          if (mutationState.isLoading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 12),
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
                _metricChip('Sessions', '$sessionsCount'),
                _metricChip('Plannings', '$planningsCount'),
                _metricChip('Surveillances', '$invigilationsCount'),
                _metricChip('Resultats', '$resultsCount'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Créer une session d\'examen'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _sessionTitleController,
                    decoration: const InputDecoration(
                      labelText: 'Titre session',
                    ),
                  ),
                  const SizedBox(height: 10),
                  yearsAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Erreur années: $e'),
                    data: (years) {
                      if (years.isEmpty) {
                        return const Text('Aucune année scolaire');
                      }
                      _selectedAcademicYear ??= years.first.id;
                      return DropdownButtonFormField<int>(
                        initialValue: _selectedAcademicYear,
                        items: years
                            .map(
                              (y) => DropdownMenuItem<int>(
                                value: y.id,
                                child: Text(y.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedAcademicYear = value),
                        decoration: const InputDecoration(
                          labelText: 'Année scolaire',
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSessionTerm,
                    items: const [
                      DropdownMenuItem(value: 'T1', child: Text('T1')),
                      DropdownMenuItem(value: 'T2', child: Text('T2')),
                      DropdownMenuItem(value: 'T3', child: Text('T3')),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedSessionTerm = value ?? 'T1');
                    },
                    decoration: const InputDecoration(labelText: 'Période'),
                  ),
                  const SizedBox(height: 8),
                  _datePickerTile(
                    label: 'Date début',
                    value: _sessionStart,
                    onPick: (v) => setState(() => _sessionStart = v),
                  ),
                  _datePickerTile(
                    label: 'Date fin',
                    value: _sessionEnd,
                    onPick: (v) => setState(() => _sessionEnd = v),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: mutationState.isLoading
                        ? null
                        : () async {
                            final academicYear = _selectedAcademicYear;
                            if (academicYear == null ||
                                _sessionTitleController.text.trim().isEmpty) {
                              return;
                            }
                            await ref
                                .read(examMutationProvider.notifier)
                                .createSession(
                                  title: _sessionTitleController.text.trim(),
                                  term: _selectedSessionTerm,
                                  academicYear: academicYear,
                                  startDate: _apiDate(_sessionStart),
                                  endDate: _apiDate(_sessionEnd),
                                );
                          },
                    child: const Text('Créer session'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Créer un planning examen'),
                  const SizedBox(height: 10),
                  sessionsAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Erreur sessions: $e'),
                    data: (sessions) {
                      if (sessions.isEmpty) {
                        return const Text('Créez d\'abord une session');
                      }
                      _selectedPlanningSession ??= sessions.first.id;
                      _selectedResultSession ??= sessions.first.id;
                      return DropdownButtonFormField<int>(
                        initialValue: _selectedPlanningSession,
                        items: sessions
                            .map(
                              (s) => DropdownMenuItem<int>(
                                value: s.id,
                                child: Text('#${s.id} [${s.term}] ${s.title}'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedPlanningSession = v),
                        decoration: const InputDecoration(labelText: 'Session'),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  classroomsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (e, _) => Text('Erreur classes: $e'),
                    data: (classrooms) {
                      if (classrooms.isEmpty) {
                        return const Text('Aucune classe');
                      }
                      _selectedPlanningClassroom ??= classrooms.first.id;
                      return DropdownButtonFormField<int>(
                        initialValue: _selectedPlanningClassroom,
                        items: classrooms
                            .map(
                              (c) => DropdownMenuItem<int>(
                                value: c.id,
                                child: Text(c.label),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedPlanningClassroom = v),
                        decoration: const InputDecoration(labelText: 'Classe'),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  subjectsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (e, _) => Text('Erreur matières: $e'),
                    data: (subjects) {
                      if (subjects.isEmpty) return const Text('Aucune matière');
                      _selectedPlanningSubject ??= subjects.first.id;
                      _selectedResultSubject ??= subjects.first.id;
                      return DropdownButtonFormField<int>(
                        initialValue: _selectedPlanningSubject,
                        items: subjects
                            .map(
                              (s) => DropdownMenuItem<int>(
                                value: s.id,
                                child: Text(s.label),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedPlanningSubject = v),
                        decoration: const InputDecoration(labelText: 'Matière'),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  _datePickerTile(
                    label: 'Date examen',
                    value: _planningDate,
                    onPick: (v) => setState(() => _planningDate = v),
                  ),
                  _timePickerTile(
                    label: 'Heure début',
                    value: _planningStart,
                    onPick: (v) => setState(() => _planningStart = v),
                  ),
                  _timePickerTile(
                    label: 'Heure fin',
                    value: _planningEnd,
                    onPick: (v) => setState(() => _planningEnd = v),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonal(
                    onPressed: mutationState.isLoading
                        ? null
                        : () async {
                            final session = _selectedPlanningSession;
                            final classroom = _selectedPlanningClassroom;
                            final subject = _selectedPlanningSubject;
                            if (session == null ||
                                classroom == null ||
                                subject == null) {
                              return;
                            }
                            await ref
                                .read(examMutationProvider.notifier)
                                .createPlanning(
                                  session: session,
                                  classroom: classroom,
                                  subject: subject,
                                  examDate: _apiDate(_planningDate),
                                  startTime: _apiTime(_planningStart),
                                  endTime: _apiTime(_planningEnd),
                                );
                          },
                    child: const Text('Créer planning'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Publier un résultat'),
                  const SizedBox(height: 10),
                  sessionsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (e, _) => Text('Erreur sessions: $e'),
                    data: (sessions) {
                      if (sessions.isEmpty) return const Text('Aucune session');
                      _selectedResultSession ??= sessions.first.id;
                      return DropdownButtonFormField<int>(
                        initialValue: _selectedResultSession,
                        items: sessions
                            .map(
                              (s) => DropdownMenuItem<int>(
                                value: s.id,
                                child: Text('#${s.id} [${s.term}] ${s.title}'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedResultSession = v),
                        decoration: const InputDecoration(labelText: 'Session'),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  studentsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (e, _) => Text('Erreur élèves: $e'),
                    data: (students) {
                      if (students.isEmpty) return const Text('Aucun élève');
                      _selectedResultStudent ??= students.first.id;
                      return DropdownButtonFormField<int>(
                        initialValue: _selectedResultStudent,
                        items: students
                            .map(
                              (s) => DropdownMenuItem<int>(
                                value: s.id,
                                child: Text(s.label),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedResultStudent = v),
                        decoration: const InputDecoration(labelText: 'Élève'),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  subjectsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (e, _) => Text('Erreur matières: $e'),
                    data: (subjects) {
                      if (subjects.isEmpty) return const Text('Aucune matière');
                      _selectedResultSubject ??= subjects.first.id;
                      return DropdownButtonFormField<int>(
                        initialValue: _selectedResultSubject,
                        items: subjects
                            .map(
                              (s) => DropdownMenuItem<int>(
                                value: s.id,
                                child: Text(s.label),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedResultSubject = v),
                        decoration: const InputDecoration(labelText: 'Matière'),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _resultScoreController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Score'),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonal(
                    onPressed: mutationState.isLoading
                        ? null
                        : () async {
                            final session = _selectedResultSession;
                            final student = _selectedResultStudent;
                            final subject = _selectedResultSubject;
                            final score = double.tryParse(
                              _resultScoreController.text.trim(),
                            );
                            if (session == null ||
                                student == null ||
                                subject == null ||
                                score == null) {
                              return;
                            }
                            await ref
                                .read(examMutationProvider.notifier)
                                .createResult(
                                  session: session,
                                  student: student,
                                  subject: subject,
                                  score: score,
                                );
                          },
                    child: const Text('Publier résultat'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Attribuer un surveillant'),
                  const SizedBox(height: 10),
                  planningsAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Erreur plannings: $e'),
                    data: (plannings) {
                      if (plannings.isEmpty) {
                        return const Text('Créez d\'abord un planning examen');
                      }
                      _selectedInvigilationPlanning ??= plannings.first.id;
                      return DropdownButtonFormField<int>(
                        initialValue: _selectedInvigilationPlanning,
                        items: plannings
                            .map(
                              (p) => DropdownMenuItem<int>(
                                value: p.id,
                                child: Text(
                                  '#${p.id} • ${p.examDate} • ${p.startTime} - ${p.endTime}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedInvigilationPlanning = v),
                        decoration: const InputDecoration(
                          labelText: 'Planning',
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  supervisorsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (e, _) => Text('Erreur surveillants: $e'),
                    data: (supervisors) {
                      if (supervisors.isEmpty) {
                        return const Text(
                          'Aucun surveillant trouvé. Créez un utilisateur avec rôle "supervisor".',
                        );
                      }
                      _selectedInvigilationSupervisor ??= supervisors.first.id;
                      return DropdownButtonFormField<int>(
                        initialValue: _selectedInvigilationSupervisor,
                        items: supervisors
                            .map(
                              (s) => DropdownMenuItem<int>(
                                value: s.id,
                                child: Text(s.label),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedInvigilationSupervisor = v),
                        decoration: const InputDecoration(
                          labelText: 'Surveillant',
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonal(
                    onPressed: mutationState.isLoading
                        ? null
                        : () async {
                            final planning = _selectedInvigilationPlanning;
                            final supervisor = _selectedInvigilationSupervisor;
                            if (planning == null || supervisor == null) {
                              return;
                            }
                            await ref
                                .read(examMutationProvider.notifier)
                                .createInvigilation(
                                  planning: planning,
                                  supervisor: supervisor,
                                );
                          },
                    child: const Text('Attribuer surveillant'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle('Sessions existantes'),
          sessionsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Erreur sessions: $e'),
            data: (sessions) => Column(
              children: sessions
                  .map(
                    (s) => Card(
                      child: ListTile(
                        title: Text('[${s.term}] ${s.title}'),
                        subtitle: Text('${s.startDate} → ${s.endDate}'),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          _sectionTitle('Plannings existants'),
          planningsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Erreur planning: $e'),
            data: (rows) => Column(
              children: rows
                  .map(
                    (p) => Card(
                      child: ListTile(
                        title: Text(
                          'Session #${p.sessionId} / Classe #${p.classroomId} / Matière #${p.subjectId}',
                        ),
                        subtitle: Text(
                          '${p.examDate} • ${p.startTime} - ${p.endTime}',
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          _sectionTitle('Surveillants attribués'),
          invigilationsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Erreur surveillances: $e'),
            data: (items) {
              if (items.isEmpty) {
                return const Text('Aucune attribution de surveillant');
              }
              final planningById = {
                for (final planning in planningsSnapshot) planning.id: planning,
              };
              return Column(
                children: items
                    .map(
                      (item) => Card(
                        child: ListTile(
                          title: Text(item.supervisorName),
                          subtitle: Text(
                            planningById[item.planningId] == null
                                ? 'Planning #${item.planningId}'
                                : 'Planning #${item.planningId} • ${planningById[item.planningId]!.examDate} ${planningById[item.planningId]!.startTime}-${planningById[item.planningId]!.endTime}',
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 12),
          _sectionTitle('Résultats publiés'),
          resultsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Erreur résultats: $e'),
            data: (rows) => Column(
              children: rows
                  .map(
                    (r) => Card(
                      child: ListTile(
                        title: Text(
                          'Session #${r.sessionId} / Élève #${r.studentId} / Matière #${r.subjectId}',
                        ),
                        subtitle: Text('Score: ${r.score.toStringAsFixed(2)}'),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _datePickerTile({
    required String label,
    required DateTime value,
    required ValueChanged<DateTime> onPick,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(_apiDate(value)),
      trailing: const Icon(Icons.calendar_month),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked != null) onPick(picked);
      },
    );
  }

  Widget _timePickerTile({
    required String label,
    required TimeOfDay value,
    required ValueChanged<TimeOfDay> onPick,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(_apiTime(value)),
      trailing: const Icon(Icons.schedule),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: value,
        );
        if (picked != null) onPick(picked);
      },
    );
  }

  String _apiDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  String _apiTime(TimeOfDay value) {
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:00';
  }
}

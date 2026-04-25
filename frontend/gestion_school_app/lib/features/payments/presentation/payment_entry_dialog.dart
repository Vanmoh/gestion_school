import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/domain/auth_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../students/domain/student.dart';
import '../../students/presentation/students_controller.dart';
import '../presentation/payments_controller.dart';

Future<bool?> showGuidedPaymentEntryDialog({
  required BuildContext context,
  required WidgetRef ref,
  String title = 'Nouveau paiement',
  Student? initialStudent,
  int? initialClassroomId,
  String preferredFeeType = 'registration',
  bool lockStudentSelection = false,
  Future<void> Function()? onPaymentSaved,
}) async {
  final compact = MediaQuery.of(context).size.width < 920;

  final dialog = _GuidedPaymentEntryDialog(
    title: title,
    initialStudent: initialStudent,
    initialClassroomId: initialClassroomId,
    preferredFeeType: preferredFeeType,
    lockStudentSelection: lockStudentSelection,
    onPaymentSaved: onPaymentSaved,
  );

  if (compact) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: dialog,
          ),
        );
      },
    );
  }

  return showDialog<bool>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.transparent,
      child: dialog,
    ),
  );
}

class _GuidedPaymentEntryDialog extends ConsumerStatefulWidget {
  const _GuidedPaymentEntryDialog({
    required this.title,
    required this.preferredFeeType,
    this.initialStudent,
    this.initialClassroomId,
    this.lockStudentSelection = false,
    this.onPaymentSaved,
  });

  final String title;
  final Student? initialStudent;
  final int? initialClassroomId;
  final String preferredFeeType;
  final bool lockStudentSelection;
  final Future<void> Function()? onPaymentSaved;

  @override
  ConsumerState<_GuidedPaymentEntryDialog> createState() =>
      _GuidedPaymentEntryDialogState();
}

class _GuidedPaymentEntryDialogState
    extends ConsumerState<_GuidedPaymentEntryDialog> {
  static const List<String> _paymentMethods = [
    'Especes',
    'Mobile Money',
    'Virement',
    'Cheque',
    'Carte',
    'Autre',
  ];
  static const List<String> _feeTypes = ['registration', 'monthly', 'exam'];

  final TextEditingController _studentSearchController =
      TextEditingController();
  final TextEditingController _amountDueController = TextEditingController();
  final TextEditingController _paymentAmountController =
      TextEditingController();
  final TextEditingController _referenceController = TextEditingController();

  List<Map<String, dynamic>> _classrooms = const [];
  List<Map<String, dynamic>> _academicYears = const [];
  List<Student> _students = const [];
  List<_FeeOption> _fees = const [];

  int? _selectedClassroomId;
  Student? _selectedStudent;
  int? _selectedFeeId;
  int? _selectedAcademicYearId;
  String _selectedFeeType = 'registration';
  String _selectedMethod = _paymentMethods.first;
  DateTime _selectedDueDate = DateTime.now();

  bool _bootLoading = true;
  bool _studentsLoading = false;
  bool _feesLoading = false;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _selectedClassroomId = widget.initialClassroomId ?? widget.initialStudent?.classroomId;
    _selectedStudent = widget.initialStudent;
    _selectedFeeType = _normalizeFeeType(widget.preferredFeeType);
    _loadBootstrap();
  }

  @override
  void dispose() {
    _studentSearchController.dispose();
    _amountDueController.dispose();
    _paymentAmountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _loadBootstrap() async {
    setState(() {
      _bootLoading = true;
      _loadError = null;
    });

    try {
      final repository = ref.read(studentsRepositoryProvider);
      final results = await Future.wait([
        repository.fetchClassrooms(),
        repository.fetchAcademicYears(),
      ]);

      final classrooms = results[0];
      final years = results[1];

      if (!mounted) {
        return;
      }

      _classrooms = classrooms;
      _academicYears = years;
      _selectedAcademicYearId ??= _resolveDefaultAcademicYearId(years);
      _selectedClassroomId ??= _extractId(classrooms.isEmpty ? null : classrooms.first['id']);

      if (_selectedStudent != null && _selectedStudent!.classroomId != null) {
        _selectedClassroomId = _selectedStudent!.classroomId;
      }

      if (_selectedClassroomId != null) {
        await _loadStudentsForClassroom();
      }

      if (_selectedStudent != null) {
        await _loadFeesForStudent(_selectedStudent!);
      }

      if (mounted) {
        setState(() => _bootLoading = false);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _bootLoading = false;
        _loadError = error.toString();
      });
    }
  }

  Future<void> _loadStudentsForClassroom() async {
    final classroomId = _selectedClassroomId;
    if (classroomId == null) {
      setState(() => _students = const []);
      return;
    }

    setState(() => _studentsLoading = true);
    try {
      final loaded = await ref.read(studentsRepositoryProvider).fetchStudents(
            classroomId: classroomId,
            isArchived: false,
            ordering: 'user__last_name,user__first_name',
          );
      loaded.sort((left, right) => left.fullName.compareTo(right.fullName));

      if (!mounted) {
        return;
      }

      final selectedStillExists = _selectedStudent != null &&
          loaded.any((student) => student.id == _selectedStudent!.id);

      setState(() {
        _students = loaded;
        if (!selectedStillExists && !widget.lockStudentSelection) {
          _selectedStudent = null;
          _fees = const [];
          _selectedFeeId = null;
        }
      });
    } finally {
      if (mounted) {
        setState(() => _studentsLoading = false);
      }
    }
  }

  Future<void> _loadFeesForStudent(Student student) async {
    setState(() {
      _feesLoading = true;
      _selectedStudent = student;
    });
    try {
      final rows = await ref.read(studentsRepositoryProvider).fetchStudentFees(student.id);
      final fees = rows
          .whereType<Map<String, dynamic>>()
          .map(_FeeOption.fromMap)
          .toList(growable: false);

      if (!mounted) {
        return;
      }

      setState(() {
        _fees = fees;
        _syncSelectedFeeWithType(resetAmount: true);
      });
    } finally {
      if (mounted) {
        setState(() => _feesLoading = false);
      }
    }
  }

  void _syncSelectedFeeWithType({bool resetAmount = false}) {
    final preferred = _fees.where((fee) => fee.feeType == _selectedFeeType).toList();
    preferred.sort((left, right) {
      if (left.balance > 0 && right.balance <= 0) {
        return -1;
      }
      if (left.balance <= 0 && right.balance > 0) {
        return 1;
      }
      return right.id.compareTo(left.id);
    });

    final matched = preferred.isEmpty ? null : preferred.first;
    _selectedFeeId = matched?.id;
    _selectedAcademicYearId ??= matched?.academicYearId;
    if (matched?.dueDate != null) {
      _selectedDueDate = matched!.dueDate!;
    }
    if (resetAmount) {
      final amount = matched == null
          ? ''
          : (matched.balance > 0 ? matched.balance : matched.amountDue).toStringAsFixed(0);
      _paymentAmountController.text = amount;
    }
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDueDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _selectedDueDate = picked);
  }

  Future<int> _ensureFeeId() async {
    if (_selectedFeeId != null) {
      return _selectedFeeId!;
    }

    final student = _selectedStudent;
    final academicYearId = _selectedAcademicYearId;
    final amountDue = double.tryParse(
      _amountDueController.text.trim().replaceAll(',', '.'),
    );
    if (student == null) {
      throw Exception('Selectionnez un eleve.');
    }
    if (academicYearId == null) {
      throw Exception('Selectionnez une annee scolaire.');
    }
    if (amountDue == null || amountDue <= 0) {
      throw Exception('Montant du frais invalide.');
    }

    final created = await ref.read(studentsRepositoryProvider).createStudentFee(
          studentId: student.id,
          academicYearId: academicYearId,
          feeType: _selectedFeeType,
          amountDue: amountDue,
          dueDate: _selectedDueDate,
        );

    final fee = _FeeOption.fromMap(created);
    if (!mounted) {
      return fee.id;
    }

    setState(() {
      _fees = [..._fees, fee];
      _selectedFeeId = fee.id;
      _paymentAmountController.text = fee.balance.toStringAsFixed(0);
    });
    return fee.id;
  }

  Future<void> _submit() async {
    final student = _selectedStudent;
    if (student == null) {
      _showError('Selectionnez un eleve.');
      return;
    }

    final amount = double.tryParse(
      _paymentAmountController.text.trim().replaceAll(',', '.'),
    );
    if (amount == null || amount <= 0) {
      _showError('Montant du paiement invalide.');
      return;
    }

    setState(() => _saving = true);
    try {
      final feeId = await _ensureFeeId();
      await ref.read(studentsRepositoryProvider).createPayment(
            feeId: feeId,
            amount: amount,
            method: _selectedMethod,
            reference: _referenceController.text.trim(),
          );

      ref.invalidate(paymentsProvider);
      ref.invalidate(paymentsPaginatedProvider);
      ref.invalidate(feesProvider);
      ref.invalidate(studentsProvider);

      if (widget.onPaymentSaved != null) {
        await widget.onPaymentSaved!();
      }

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  int? _resolveDefaultAcademicYearId(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      final isCurrent = row['is_current'];
      if (isCurrent == true) {
        return _extractId(row['id']);
      }
    }
    if (rows.isEmpty) {
      return null;
    }
    return _extractId(rows.first['id']);
  }

  int? _extractId(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  String _normalizeFeeType(String value) {
    if (_feeTypes.contains(value)) {
      return value;
    }
    return 'registration';
  }

  String _feeTypeLabel(String value) {
    switch (value) {
      case 'registration':
        return 'Frais inscription';
      case 'monthly':
        return 'Scolarite';
      case 'exam':
        return 'Frais examen';
      default:
        return value;
    }
  }

  String _academicYearLabel(Map<String, dynamic> row) {
    final name = row['name']?.toString().trim() ?? '';
    return name.isEmpty ? 'Annee scolaire' : name;
  }

  String _cashierLabel(AuthUser? user) {
    if (user == null) {
      return 'Utilisateur non charge';
    }
    final name = user.fullName.trim().isEmpty ? user.username : user.fullName.trim();
    return '$name • ${user.role}';
  }

  String _formatMoney(double value) {
    final whole = value.round().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      final reversedIndex = whole.length - i;
      buffer.write(whole[i]);
      if (reversedIndex > 1 && reversedIndex % 3 == 1) {
        buffer.write(' ');
      }
    }
    return '${buffer.toString()} FCFA';
  }

  String _formatDate(DateTime value) {
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  }

  String _studentInitial(Student student) {
    final fullName = student.fullName.trim();
    if (fullName.isEmpty) {
      return '?';
    }
    return fullName.characters.first.toUpperCase();
  }

  int _openFeeCount() {
    return _fees.where((fee) => fee.balance > 0).length;
  }

  double _openFeeBalance() {
    return _fees.fold<double>(
      0,
      (sum, fee) => sum + (fee.balance > 0 ? fee.balance : 0),
    );
  }

  String _selectedFeeStateLabel(_FeeOption? fee) {
    if (fee == null) {
      return 'Creation auto du frais';
    }
    if (fee.balance > 0) {
      return 'Frais existant avec solde';
    }
    return 'Frais solde';
  }

  Color _methodAccentColor(String method, ColorScheme colorScheme) {
    switch (method) {
      case 'Especes':
        return const Color(0xFF0F8A5F);
      case 'Mobile Money':
        return const Color(0xFF9A5B00);
      case 'Virement':
        return const Color(0xFF0B63C7);
      case 'Cheque':
        return const Color(0xFF6E3CBC);
      case 'Carte':
        return const Color(0xFFAD1457);
      default:
        return colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final authUser = ref.watch(authControllerProvider).valueOrNull;
    final filteredStudents = _students.where((student) {
      final search = _studentSearchController.text.trim().toLowerCase();
      if (search.isEmpty) {
        return true;
      }
      final haystack = '${student.fullName} ${student.matricule}'.toLowerCase();
      return haystack.contains(search);
    }).toList(growable: false);
    final selectedFee = _fees.where((fee) => fee.id == _selectedFeeId).firstOrNull;
    final feeNeedsCreation = selectedFee == null;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.surface,
            colorScheme.surfaceContainerLowest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 34,
            offset: Offset(0, 22),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 780),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: _bootLoading
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ))
              : _loadError != null
                  ? _ErrorState(message: _loadError!, onRetry: _loadBootstrap)
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 860;
                        final body = compact
                            ? Column(
                                children: [
                                  _buildHeader(authUser),
                                  const SizedBox(height: 14),
                                  _buildLeftPane(filteredStudents),
                                  const SizedBox(height: 14),
                                  _buildRightPane(selectedFee, feeNeedsCreation, authUser),
                                ],
                              )
                            : Column(
                                children: [
                                  _buildHeader(authUser),
                                  const SizedBox(height: 14),
                                  Expanded(
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(flex: 11, child: _buildLeftPane(filteredStudents)),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          flex: 10,
                                          child: _buildRightPane(selectedFee, feeNeedsCreation, authUser),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );

                        return body;
                      },
                    ),
        ),
      ),
    );
  }

  Widget _buildHeader(AuthUser? authUser) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primaryContainer.withValues(alpha: 0.92),
                  colorScheme.tertiaryContainer.withValues(alpha: 0.88),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Encaissement guide: classe, eleve, type de frais, puis validation immediate par le caissier actif.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StepChip(label: '1. Classe'),
                    _StepChip(label: '2. Eleve'),
                    _StepChip(label: '3. Frais & encaissement'),
                    if (widget.lockStudentSelection)
                      const _StepChip(label: 'Mode post-inscription'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          constraints: const BoxConstraints(maxWidth: 290),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Caissier actif',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Text(
                _cashierLabel(authUser),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Figé automatiquement par le serveur.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton.filledTonal(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLeftPane(List<Student> filteredStudents) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: colorScheme.surfaceContainerLow,
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Selection classe et eleve',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choisissez d abord la classe, puis cliquez sur l eleve concerne pour charger ses frais.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricPill(
                label: 'Classes',
                value: '${_classrooms.length}',
              ),
              _MetricPill(
                label: 'Eleves visibles',
                value: '${filteredStudents.length}',
              ),
              _MetricPill(
                label: 'Selection rapide',
                value: 'Tactile',
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _selectedClassroomId,
            decoration: const InputDecoration(labelText: 'Classe'),
            items: _classrooms
                .map(
                  (row) => DropdownMenuItem<int>(
                    value: _extractId(row['id']),
                    child: Text(row['name']?.toString() ?? 'Classe'),
                  ),
                )
                .toList(growable: false),
            onChanged: widget.lockStudentSelection
                ? null
                : (value) async {
                    setState(() {
                      _selectedClassroomId = value;
                      _selectedStudent = null;
                      _fees = const [];
                      _selectedFeeId = null;
                      _studentSearchController.clear();
                    });
                    await _loadStudentsForClassroom();
                  },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _studentSearchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Recherche eleve',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          if (_selectedStudent != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primaryContainer.withValues(alpha: 0.9),
                    colorScheme.secondaryContainer.withValues(alpha: 0.72),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: colorScheme.surface.withValues(alpha: 0.9),
                    child: Text(
                      _studentInitial(_selectedStudent!),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedStudent!.fullName,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_selectedStudent!.matricule} • ${_selectedStudent!.classroomName}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _MetricPill(label: 'Frais ouverts', value: '${_openFeeCount()}'),
                            _MetricPill(
                              label: 'Solde global',
                              value: _formatMoney(_openFeeBalance()),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _studentsLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredStudents.isEmpty
                    ? const Center(child: Text('Aucun eleve dans cette classe.'))
                    : ListView.separated(
                        itemCount: filteredStudents.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final student = filteredStudents[index];
                          final selected = _selectedStudent?.id == student.id;
                          return Material(
                            color: selected
                                ? colorScheme.primaryContainer.withValues(alpha: 0.82)
                                : colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            elevation: selected ? 1.5 : 0,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                await _loadFeesForStudent(student);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: selected
                                          ? colorScheme.surface.withValues(alpha: 0.92)
                                          : colorScheme.surfaceContainerHighest,
                                      child: Text(_studentInitial(student)),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            student.fullName,
                                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${student.matricule}${student.classroomName.trim().isEmpty ? '' : ' • ${student.classroomName}'}',
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.touch_app_outlined,
                                                size: 15,
                                                color: selected
                                                    ? colorScheme.primary
                                                    : colorScheme.outline,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                selected
                                                    ? 'Eleve actif pour encaissement'
                                                    : 'Toucher pour charger les frais',
                                                style: Theme.of(context).textTheme.labelSmall,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (selected)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primary.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Icon(
                                          Icons.check_circle,
                                          color: colorScheme.primary,
                                        ),
                                      )
                                    else
                                      const Icon(Icons.chevron_right),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPane(
    _FeeOption? selectedFee,
    bool feeNeedsCreation,
    AuthUser? authUser,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: colorScheme.surfaceContainerLow,
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Frais et validation',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Selection du type de frais, creation automatique si necessaire, puis validation du paiement.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_selectedStudent != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedStudent!.fullName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_selectedStudent!.matricule} • ${_selectedStudent!.classroomName}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MetricPill(
                          label: 'Etat',
                          value: _selectedFeeStateLabel(selectedFee),
                        ),
                        _MetricPill(
                          label: 'Type actif',
                          value: _feeTypeLabel(_selectedFeeType),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _feeTypes
                  .map(
                    (type) => ChoiceChip(
                      label: Text(_feeTypeLabel(type)),
                      selected: _selectedFeeType == type,
                      showCheckmark: false,
                      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      onSelected: _selectedStudent == null
                          ? null
                          : (_) {
                              setState(() {
                                _selectedFeeType = type;
                                _syncSelectedFeeWithType(resetAmount: true);
                              });
                            },
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 12),
            if (_selectedStudent == null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: colorScheme.surface,
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
                ),
                child: const Text('Choisissez d abord une classe puis un eleve.'),
              )
            else if (_feesLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (selectedFee != null)
              _FeeSummaryCard(
                title: _feeTypeLabel(selectedFee.feeType),
                feeId: selectedFee.id,
                amountDue: _formatMoney(selectedFee.amountDue),
                amountPaid: _formatMoney(selectedFee.amountPaid),
                balance: _formatMoney(selectedFee.balance),
                dueDate: selectedFee.dueDate == null ? '-' : _formatDate(selectedFee.dueDate!),
              )
            else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: colorScheme.outlineVariant,
                  ),
                  color: colorScheme.surface,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aucun ${_feeTypeLabel(_selectedFeeType).toLowerCase()} existant pour cet eleve.',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Le frais sera cree automatiquement pendant l encaissement.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: _selectedAcademicYearId,
                      decoration: const InputDecoration(labelText: 'Annee scolaire'),
                      items: _academicYears
                          .map(
                            (row) => DropdownMenuItem<int>(
                              value: _extractId(row['id']),
                              child: Text(_academicYearLabel(row)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) => setState(() => _selectedAcademicYearId = value),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amountDueController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Montant du frais'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: _pickDueDate,
                          icon: const Icon(Icons.event_outlined),
                          label: Text(_formatDate(_selectedDueDate)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            Text(
              'Encaissement',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _paymentAmountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: feeNeedsCreation ? 'Montant a encaisser' : 'Montant a encaisser (reste)',
                prefixIcon: const Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _selectedMethod,
              decoration: const InputDecoration(labelText: 'Methode'),
              items: _paymentMethods
                  .map(
                    (method) => DropdownMenuItem<String>(
                      value: method,
                      child: Text(method),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _selectedMethod = value);
              },
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _methodAccentColor(_selectedMethod, colorScheme).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _methodAccentColor(_selectedMethod, colorScheme).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    color: _methodAccentColor(_selectedMethod, colorScheme),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Methode active: $_selectedMethod',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: _methodAccentColor(_selectedMethod, colorScheme),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _referenceController,
              decoration: const InputDecoration(
                labelText: 'Reference',
                prefixIcon: Icon(Icons.qr_code_2_outlined),
                helperText: 'Obligatoire pour Mobile Money, Virement, Cheque et Carte.',
              ),
            ),
            const SizedBox(height: 10),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Caissier actif',
                border: OutlineInputBorder(),
              ),
              child: Text(_cashierLabel(authUser)),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.secondaryContainer.withValues(alpha: 0.82),
                    colorScheme.primaryContainer.withValues(alpha: 0.9),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedFee == null
                        ? 'Le systeme va creer le frais puis enregistrer l encaissement.'
                        : 'Le paiement sera rattache au frais existant selectionne.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Controle serveur actif: caissier fige, references verifiees et surpaiement refuse.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                        child: const Text('Annuler'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _saving ? null : _submit,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                        ),
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.payments_outlined),
                        label: Text(
                          selectedFee == null ? 'Creer et encaisser' : 'Encaisser maintenant',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeeOption {
  const _FeeOption({
    required this.id,
    required this.feeType,
    required this.amountDue,
    required this.amountPaid,
    required this.balance,
    this.academicYearId,
    this.dueDate,
  });

  final int id;
  final String feeType;
  final double amountDue;
  final double amountPaid;
  final double balance;
  final int? academicYearId;
  final DateTime? dueDate;

  static _FeeOption fromMap(Map<String, dynamic> map) {
    double toDouble(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }
      return double.tryParse(value?.toString() ?? '0') ?? 0;
    }

    int toInt(dynamic value) {
      if (value is int) {
        return value;
      }
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    final dueRaw = map['due_date']?.toString();
    return _FeeOption(
      id: toInt(map['id']),
      feeType: map['fee_type']?.toString() ?? 'registration',
      amountDue: toDouble(map['amount_due']),
      amountPaid: toDouble(map['amount_paid']),
      balance: toDouble(map['balance']),
      academicYearId: map['academic_year'] == null ? null : toInt(map['academic_year']),
      dueDate: dueRaw == null || dueRaw.isEmpty ? null : DateTime.tryParse(dueRaw),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.26)),
      ),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$label: ',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            TextSpan(
              text: value,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeeSummaryCard extends StatelessWidget {
  const _FeeSummaryCard({
    required this.title,
    required this.feeId,
    required this.amountDue,
    required this.amountPaid,
    required this.balance,
    required this.dueDate,
  });

  final String title;
  final int feeId;
  final String amountDue;
  final String amountPaid;
  final String balance;
  final String dueDate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.76),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('Frais #$feeId'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _MetricPill(label: 'Du', value: amountDue),
              _MetricPill(label: 'Paye', value: amountPaid),
              _MetricPill(label: 'Reste', value: balance),
              _MetricPill(label: 'Echeance', value: dueDate),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Reessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
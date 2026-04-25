import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../auth/presentation/auth_controller.dart';
import '../domain/payment.dart';
import '../domain/student_fee.dart';
import 'payment_entry_dialog.dart';
import 'payments_controller.dart';

class PaymentsPage extends ConsumerStatefulWidget {
  const PaymentsPage({super.key});

  @override
  ConsumerState<PaymentsPage> createState() => _PaymentsPageState();
}

enum _FinancePeriod { day, week, month, all }

class _PaymentsPageState extends ConsumerState<PaymentsPage> {
  static const List<int> _pageSizeOptions = [15, 25, 50, 100];
  static const List<String> _paymentMethodOptions = [
    'Especes',
    'Mobile Money',
    'Virement',
    'Cheque',
    'Carte',
    'Autre',
  ];

  final _searchController = TextEditingController();
  final _payrollMonthController = TextEditingController();

  int? _selectedFeeId;
  int? _selectedPaymentId;
  String _methodFilter = 'all';
  int _currentPage = 1;
  int _pageSize = 25;
  String _searchTerm = '';
  Timer? _searchDebounce;
  bool _financeBusy = false;
  List<Map<String, dynamic>> _financePayrolls = [];
  List<Map<String, dynamic>> _financeExpenses = [];
  _FinancePeriod _financePeriod = _FinancePeriod.month;

  static const List<String> _expenseCategoryOptions = [
    'Salaires enseignants',
    'Salaires personnels',
    'Utilites',
    'Maintenance',
    'Fournitures',
    'Taxes',
    'Transport',
    'Loyer',
    'Charges operationnelles',
    'Autres',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _payrollMonthController.text =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    Future<void>.microtask(_loadTeacherFinanceSection);
  }

  bool _isTeacherFinanceVisible(String? role) {
    return role == 'super_admin' || role == 'supervisor' || role == 'accountant';
  }

  bool _isTeacherFinanceReadOnly(String? role) {
    return role == 'accountant';
  }

  String _toApiDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  String _normalizePointageBusinessMessage(String raw) {
    final normalized = raw.trim();
    final lower = normalized.toLowerCase();

    if (lower.contains('dimanche')) {
      return 'Pointage refuse: le dimanche est interdit. Choisissez un jour autorise (lundi a samedi).';
    }

    if (lower.contains("aucun creneau") || lower.contains("emploi du temps")) {
      return 'Pointage bloque: aucun creneau d\'emploi du temps pour cet enseignant a cette date. Configurez le planning du jour puis reessayez.';
    }

    return normalized;
  }

  String _extractApiErrorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;

      if (data is Map<String, dynamic>) {
        for (final entry in data.entries) {
          final value = entry.value;
          if (value is List && value.isNotEmpty) {
            return _normalizePointageBusinessMessage(
              value.map((item) => item.toString()).join(' | '),
            );
          }
          if (value is String && value.trim().isNotEmpty) {
            return _normalizePointageBusinessMessage(value);
          }
        }
      }

      if (data is List && data.isNotEmpty) {
        return _normalizePointageBusinessMessage(
          data.map((item) => item.toString()).join(' | '),
        );
      }

      if (data is String && data.trim().isNotEmpty) {
        return _normalizePointageBusinessMessage(data);
      }

      final status = error.response?.statusCode;
      if (status != null) {
        return 'Requete refusee (HTTP $status).';
      }

      return error.message ?? error.toString();
    }

    return error.toString();
  }

  Future<void> _loadTeacherFinanceSection() async {
    final authUser = ref.read(authControllerProvider).value;
    if (!_isTeacherFinanceVisible(authUser?.role)) {
      return;
    }

    try {
      final repo = ref.read(paymentsRepositoryProvider);
      final results = await Future.wait([
        repo.fetchTeacherPayrolls(
          month: _payrollMonthController.text.trim(),
        ),
        repo.fetchExpenses(),
      ]);
      final payrolls = results[0];
      final expenses = results[1];

      if (!mounted) {
        return;
      }

      setState(() {
        _financePayrolls = payrolls;
        _financeExpenses = expenses;
      });
    } catch (error) {
      _showMessage('Erreur chargement paie horaire: $error');
    }
  }

  Future<void> _generateTeacherPayroll() async {
    final month = _payrollMonthController.text.trim();
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(month)) {
      _showMessage('Mois invalide. Utilisez le format YYYY-MM.');
      return;
    }

    setState(() => _financeBusy = true);
    try {
      await ref
          .read(paymentsRepositoryProvider)
          .generateTeacherPayroll(month: month);
      _showMessage('Paie horaire generee avec succes.', isSuccess: true);
      await _loadTeacherFinanceSection();
    } catch (error) {
      _showMessage('Erreur generation paie horaire: $error');
    } finally {
      if (mounted) {
        setState(() => _financeBusy = false);
      }
    }
  }

  Future<void> _validatePayrollLevelOne(int payrollId) async {
    setState(() => _financeBusy = true);
    try {
      await ref.read(paymentsRepositoryProvider).validateTeacherPayrollLevelOne(payrollId);
      _showMessage('Validation niveau 1 enregistree.', isSuccess: true);
      await _loadTeacherFinanceSection();
    } catch (error) {
      _showMessage('Erreur validation niveau 1: ${_extractApiErrorMessage(error)}');
    } finally {
      if (mounted) setState(() => _financeBusy = false);
    }
  }

  Future<void> _validatePayrollLevelTwo(int payrollId) async {
    setState(() => _financeBusy = true);
    try {
      await ref.read(paymentsRepositoryProvider).validateTeacherPayrollLevelTwo(payrollId);
      _showMessage('Validation niveau 2 enregistree.', isSuccess: true);
      await _loadTeacherFinanceSection();
    } catch (error) {
      _showMessage('Erreur validation niveau 2: ${_extractApiErrorMessage(error)}');
    } finally {
      if (mounted) setState(() => _financeBusy = false);
    }
  }

  Future<void> _resetPayrollValidation(int payrollId) async {
    setState(() => _financeBusy = true);
    try {
      await ref.read(paymentsRepositoryProvider).resetTeacherPayrollValidation(payrollId);
      _showMessage('Validation reinitialisee.', isSuccess: true);
      await _loadTeacherFinanceSection();
    } catch (error) {
      _showMessage('Erreur reinitialisation validation: ${_extractApiErrorMessage(error)}');
    } finally {
      if (mounted) setState(() => _financeBusy = false);
    }
  }

  Future<void> _validateExpenseLevelOne(int expenseId) async {
    setState(() => _financeBusy = true);
    try {
      await ref.read(paymentsRepositoryProvider).validateExpenseLevelOne(expenseId);
      _showMessage('Dépense validée niveau 1.', isSuccess: true);
      await _loadTeacherFinanceSection();
    } catch (error) {
      _showMessage('Erreur validation dépense N1: ${_extractApiErrorMessage(error)}');
    } finally {
      if (mounted) setState(() => _financeBusy = false);
    }
  }

  Future<void> _validateExpenseLevelTwo(int expenseId) async {
    setState(() => _financeBusy = true);
    try {
      await ref.read(paymentsRepositoryProvider).validateExpenseLevelTwo(expenseId);
      _showMessage('Dépense validée niveau 2.', isSuccess: true);
      await _loadTeacherFinanceSection();
    } catch (error) {
      _showMessage('Erreur validation dépense N2: ${_extractApiErrorMessage(error)}');
    } finally {
      if (mounted) setState(() => _financeBusy = false);
    }
  }

  Future<void> _resetExpenseValidation(int expenseId) async {
    setState(() => _financeBusy = true);
    try {
      await ref.read(paymentsRepositoryProvider).resetExpenseValidation(expenseId);
      _showMessage('Validation dépense réinitialisée.', isSuccess: true);
      await _loadTeacherFinanceSection();
    } catch (error) {
      _showMessage('Erreur reset dépense: ${_extractApiErrorMessage(error)}');
    } finally {
      if (mounted) setState(() => _financeBusy = false);
    }
  }

  Future<void> _openExpenseDialog({Map<String, dynamic>? expense}) async {
    final formKey = GlobalKey<FormState>();
    final labelController = TextEditingController(
      text: (expense?['label'] ?? '').toString(),
    );
    final amountController = TextEditingController(
      text: expense == null
          ? ''
          : ((double.tryParse(expense['amount']?.toString() ?? '0') ?? 0)
                .toStringAsFixed(0)),
    );
    final notesController = TextEditingController(
      text: (expense?['notes'] ?? '').toString(),
    );

    DateTime selectedDate = expense?['date'] != null
        ? (DateTime.tryParse(expense!['date'].toString()) ?? DateTime.now())
        : DateTime.now();
    String selectedCategory = (expense?['category'] ?? '').toString().trim();
    if (!_expenseCategoryOptions.contains(selectedCategory)) {
      selectedCategory = _expenseCategoryOptions.first;
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        bool saving = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(expense == null ? 'Nouvelle depense' : 'Modifier depense'),
              content: SizedBox(
                width: 460,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: labelController,
                        decoration: const InputDecoration(labelText: 'Libelle'),
                        validator: (value) => (value == null || value.trim().isEmpty)
                            ? 'Libelle requis'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Montant'),
                        validator: (value) {
                          final parsed = double.tryParse((value ?? '').trim());
                          if (parsed == null || parsed <= 0) {
                            return 'Montant invalide';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCategory,
                        decoration: const InputDecoration(labelText: 'Categorie'),
                        items: _expenseCategoryOptions
                            .map((item) => DropdownMenuItem<String>(
                                  value: item,
                                  child: Text(item),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => selectedCategory = value);
                        },
                      ),
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: saving
                            ? null
                            : () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now(),
                                );
                                if (picked == null) return;
                                setDialogState(() => selectedDate = picked);
                              },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Date depense'),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_toApiDate(selectedDate)),
                              const Icon(Icons.calendar_today_outlined, size: 18),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: 'Notes'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;

                          setDialogState(() => saving = true);
                          try {
                            final repo = ref.read(paymentsRepositoryProvider);
                            final amount = double.parse(amountController.text.trim());
                            final expenseDate = _toApiDate(selectedDate);
                            if (expense == null) {
                              await repo.createExpense(
                                label: labelController.text.trim(),
                                amount: amount,
                                date: expenseDate,
                                category: selectedCategory,
                                notes: notesController.text.trim(),
                              );
                            } else {
                              await repo.updateExpense(
                                expenseId: (expense['id'] as num).toInt(),
                                label: labelController.text.trim(),
                                amount: amount,
                                date: expenseDate,
                                category: selectedCategory,
                                notes: notesController.text.trim(),
                              );
                            }
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (error) {
                            _showMessage('Erreur depense: ${_extractApiErrorMessage(error)}');
                            setDialogState(() => saving = false);
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    labelController.dispose();
    amountController.dispose();
    notesController.dispose();

    if (saved == true) {
      _showMessage(
        expense == null ? 'Depense enregistree.' : 'Depense modifiee.',
        isSuccess: true,
      );
      await _loadTeacherFinanceSection();
    }
  }

  Future<void> _deleteExpense(Map<String, dynamic> expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Supprimer depense'),
          content: Text(
            'Voulez-vous supprimer la depense "${(expense['label'] ?? '-').toString()}" ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB42318)),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    setState(() => _financeBusy = true);
    try {
      await ref
          .read(paymentsRepositoryProvider)
          .deleteExpense((expense['id'] as num).toInt());
      _showMessage('Depense supprimee.', isSuccess: true);
      await _loadTeacherFinanceSection();
    } catch (error) {
      _showMessage('Erreur suppression depense: ${_extractApiErrorMessage(error)}');
    } finally {
      if (mounted) setState(() => _financeBusy = false);
    }
  }

  String _payrollStageLabel(Map<String, dynamic> row) {
    final stage = (row['validation_stage'] ?? '').toString();
    if (stage == 'level_two') return 'N2 valide';
    if (stage == 'level_one') return 'N1 valide';
    return 'Brouillon';
  }

  String _expenseStageLabel(Map<String, dynamic> row) {
    final stage = (row['validation_stage'] ?? '').toString();
    if (stage == 'level_two') return 'N2 valide';
    if (stage == 'level_one') return 'N1 valide';
    return 'Brouillon';
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _payrollMonthController.dispose();
    super.dispose();
  }

  Future<void> _refreshPayments() async {
    final query = PaymentsPageQuery(
      page: _currentPage,
      pageSize: _pageSize,
      search: _searchTerm,
      method: _methodFilter == 'all' ? null : _methodFilter,
    );
    ref.invalidate(paymentsPaginatedProvider(query));
    ref.invalidate(feesProvider);
    try {
      await Future.wait([
        ref.read(paymentsPaginatedProvider(query).future),
        ref.read(feesProvider.future),
      ]);
      await _loadTeacherFinanceSection();
    } catch (_) {
      // Keep pull-to-refresh responsive even when API is temporarily unavailable.
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _searchTerm = value.trim();
        _currentPage = 1;
      });
    });
  }

  void _showMessage(
    String text, {
    bool isSuccess = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
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
          action: (actionLabel != null && onAction != null)
              ? SnackBarAction(
                  label: actionLabel,
                  onPressed: onAction,
                )
              : null,
        ),
      );
  }

  Future<void> _printReceipt(int paymentId) async {
    final repo = ref.read(paymentsRepositoryProvider);
    final bytes = await repo.fetchReceiptPdf(paymentId);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  String _formatMoney(num value) {
    final normalized = value.toStringAsFixed(0);
    final grouped = normalized.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]} ',
    );
    return '$grouped FCFA';
  }

  String _formatDate(String raw) {
    final date = DateTime.tryParse(raw);
    if (date == null) {
      return raw.isEmpty ? '-' : raw;
    }
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _feeLabel(StudentFeeItem fee) {
    return '#${fee.id} • ${fee.studentFullName} (${fee.studentMatricule}) • ${fee.feeType} • Solde ${_formatMoney(fee.balance)}';
  }

  String _financePeriodLabel(_FinancePeriod value) {
    switch (value) {
      case _FinancePeriod.day:
        return 'Jour';
      case _FinancePeriod.week:
        return 'Semaine';
      case _FinancePeriod.month:
        return 'Mois';
      case _FinancePeriod.all:
        return 'Tout';
    }
  }

  DateTime _dayStart(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  bool _isInPeriod(DateTime? value, _FinancePeriod period) {
    if (value == null) {
      return false;
    }
    if (period == _FinancePeriod.all) {
      return true;
    }

    final today = _dayStart(DateTime.now());
    final target = _dayStart(value.toLocal());

    switch (period) {
      case _FinancePeriod.day:
        return target == today;
      case _FinancePeriod.week:
        final weekday = today.weekday;
        final start = today.subtract(Duration(days: weekday - 1));
        final end = start.add(const Duration(days: 7));
        return !target.isBefore(start) && target.isBefore(end);
      case _FinancePeriod.month:
        return target.year == today.year && target.month == today.month;
      case _FinancePeriod.all:
        return true;
    }
  }

  String _csvEscape(String input) {
    final needsQuote = input.contains(',') || input.contains('"') || input.contains('\n');
    if (!needsQuote) {
      return input;
    }
    return '"${input.replaceAll('"', '""')}"';
  }

  String _periodCode(_FinancePeriod period) {
    switch (period) {
      case _FinancePeriod.day:
        return 'jour';
      case _FinancePeriod.week:
        return 'semaine';
      case _FinancePeriod.month:
        return 'mois';
      case _FinancePeriod.all:
        return 'tout';
    }
  }

  String _timestampSuffix() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
  }

  ({String? from, String? to}) _periodDateBounds(_FinancePeriod period) {
    if (period == _FinancePeriod.all) {
      return (from: null, to: null);
    }
    final today = _dayStart(DateTime.now());
    switch (period) {
      case _FinancePeriod.day:
        final value = _toApiDate(today);
        return (from: value, to: value);
      case _FinancePeriod.week:
        final weekday = today.weekday;
        final start = today.subtract(Duration(days: weekday - 1));
        final end = start.add(const Duration(days: 6));
        return (from: _toApiDate(start), to: _toApiDate(end));
      case _FinancePeriod.month:
        final start = DateTime(today.year, today.month, 1);
        final end = (today.month == 12)
            ? DateTime(today.year + 1, 1, 0)
            : DateTime(today.year, today.month + 1, 0);
        return (from: _toApiDate(start), to: _toApiDate(end));
      case _FinancePeriod.all:
        return (from: null, to: null);
    }
  }

  Future<void> _saveTextExport({
    required String content,
    required String fileName,
    required String dialogTitle,
    required String successMessage,
  }) async {
    try {
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(content)),
      );

      if (savePath == null && !kIsWeb) {
        _showMessage('Export annule.');
        return;
      }

      _showMessage(successMessage, isSuccess: true);
      return;
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: content));
      _showMessage(
        'Export indisponible: contenu copie dans le presse-papiers.',
        isSuccess: true,
      );
    }
  }

  Future<void> _savePdfExport({
    required Uint8List bytes,
    required String fileName,
    required String dialogTitle,
    required String successMessage,
  }) async {
    try {
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        bytes: bytes,
      );

      if (savePath == null && !kIsWeb) {
        _showMessage('Export PDF annule.');
        return;
      }

      _showMessage(successMessage, isSuccess: true);
      return;
    } catch (_) {
      await Printing.layoutPdf(onLayout: (_) async => bytes);
      _showMessage(
        'Export PDF ouvert dans la boite d\'impression.',
        isSuccess: true,
      );
    }
  }

  String _buildExpensesCsv(List<Map<String, dynamic>> rows) {
    final buffer = StringBuffer();
    buffer.writeln('id,date,libelle,categorie,montant,validation,paye_le,notes');

    for (final row in rows) {
      final amount = double.tryParse(row['amount']?.toString() ?? '0') ?? 0;
      buffer.writeln(
        [
          _csvEscape((row['id'] ?? '').toString()),
          _csvEscape((row['date'] ?? '').toString()),
          _csvEscape((row['label'] ?? '').toString()),
          _csvEscape((row['category'] ?? '').toString()),
          _csvEscape(amount.toStringAsFixed(0)),
          _csvEscape(_expenseStageLabel(row)),
          _csvEscape((row['paid_on'] ?? '').toString()),
          _csvEscape((row['notes'] ?? '').toString()),
        ].join(','),
      );
    }

    return buffer.toString();
  }

  String _buildPaymentsCsv(List<PaymentItem> rows) {
    final buffer = StringBuffer();
    buffer.writeln('id,date,eleve,matricule,type_frais,montant,methode,reference');

    for (final row in rows) {
      buffer.writeln(
        [
          _csvEscape(row.id.toString()),
          _csvEscape(row.createdAt),
          _csvEscape(row.studentFullName),
          _csvEscape(row.studentMatricule),
          _csvEscape(row.feeType),
          _csvEscape(row.amount.toStringAsFixed(0)),
          _csvEscape(row.method),
          _csvEscape(row.reference),
        ].join(','),
      );
    }

    return buffer.toString();
  }

  Future<Uint8List> _buildJournalPdf({
    required String title,
    required String subtitle,
    required List<String> summaryLines,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final doc = pw.Document();
    final generatedAt = _formatDate(DateTime.now().toIso8601String());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (_) {
          return [
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                border: pw.Border.all(color: PdfColors.blue200),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue900,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(subtitle),
                  pw.SizedBox(height: 4),
                  pw.Text('Genere le: $generatedAt'),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Wrap(
              spacing: 10,
              runSpacing: 8,
              children: summaryLines
                  .map(
                    (line) => pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey100,
                        border: pw.Border.all(color: PdfColors.grey400),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: pw.Text(line),
                    ),
                  )
                  .toList(growable: false),
            ),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: rows,
              border: pw.TableBorder.all(color: PdfColors.grey400),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                fontSize: 10,
              ),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue700),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(6),
            ),
          ];
        },
      ),
    );

    return doc.save();
  }

  Future<List<PaymentItem>> _loadPaymentExportRows({
    required String search,
    required String? method,
    required _FinancePeriod period,
  }) async {
    final rows = await ref.read(paymentsRepositoryProvider).fetchPaymentsForJournal(
          search: search,
          method: method,
        );
    final sorted = _filteredPayments(rows);
    return sorted
        .where((payment) => _isInPeriod(DateTime.tryParse(payment.createdAt), period))
        .toList(growable: false);
  }

  Future<void> _exportExpensesCsv(List<Map<String, dynamic>> rows) async {
    final bounds = _periodDateBounds(_financePeriod);
    try {
      final bytes = await ref.read(paymentsRepositoryProvider).exportExpensesJournal(
            format: 'csv',
            dateFrom: bounds.from,
            dateTo: bounds.to,
          );
      await _saveTextExport(
        content: utf8.decode(bytes, allowMalformed: true),
        fileName: 'journal_depenses_${_periodCode(_financePeriod)}_${_timestampSuffix()}.csv',
        dialogTitle: 'Enregistrer le journal des depenses',
        successMessage: 'Export CSV depenses backend reussi.',
      );
      return;
    } catch (_) {
      if (rows.isEmpty) {
        _showMessage('Aucune depense a exporter pour cette periode.');
        return;
      }

      final csv = _buildExpensesCsv(rows);
      await _saveTextExport(
        content: csv,
        fileName: 'journal_depenses_${_periodCode(_financePeriod)}_${_timestampSuffix()}.csv',
        dialogTitle: 'Enregistrer le journal des depenses',
        successMessage: 'Export CSV depenses reussi (${rows.length} lignes).',
      );
    }
  }

  Future<void> _exportExpensesPdf(List<Map<String, dynamic>> rows) async {
    final bounds = _periodDateBounds(_financePeriod);
    try {
      final bytes = await ref.read(paymentsRepositoryProvider).exportExpensesJournal(
            format: 'pdf',
            dateFrom: bounds.from,
            dateTo: bounds.to,
          );
      await _savePdfExport(
        bytes: bytes,
        fileName: 'journal_depenses_${_periodCode(_financePeriod)}_${_timestampSuffix()}.pdf',
        dialogTitle: 'Exporter le journal des depenses en PDF',
        successMessage: 'Export PDF depenses backend reussi.',
      );
      return;
    } catch (_) {
      if (rows.isEmpty) {
        _showMessage('Aucune depense a exporter en PDF pour cette periode.');
        return;
      }

      final bytes = await _buildJournalPdf(
        title: 'Journal des depenses',
        subtitle: 'Periode ${_financePeriodLabel(_financePeriod).toLowerCase()} • ${rows.length} ligne(s)',
        summaryLines: [
          'Periode: ${_financePeriodLabel(_financePeriod)}',
          'Depenses: ${rows.length}',
          'Montant total: ${_formatMoney(rows.fold<double>(0, (sum, row) => sum + (double.tryParse(row['amount']?.toString() ?? '0') ?? 0)))}',
        ],
        headers: const ['Date', 'Libelle', 'Categorie', 'Montant', 'Validation', 'Paye le'],
        rows: rows
            .map(
              (row) => [
                (row['date'] ?? '-').toString(),
                (row['label'] ?? '-').toString(),
                (row['category'] ?? '-').toString(),
                _formatMoney(double.tryParse(row['amount']?.toString() ?? '0') ?? 0),
                _expenseStageLabel(row),
                ((row['paid_on'] ?? '').toString().trim().isEmpty) ? '-' : (row['paid_on'] ?? '-').toString(),
              ],
            )
            .toList(growable: false),
      );

      await _savePdfExport(
        bytes: bytes,
        fileName: 'journal_depenses_${_periodCode(_financePeriod)}_${_timestampSuffix()}.pdf',
        dialogTitle: 'Exporter le journal des depenses en PDF',
        successMessage: 'Export PDF depenses reussi (${rows.length} lignes).',
      );
    }
  }

  Future<void> _exportPaymentsCsv({required String search, required String? method}) async {
    final bounds = _periodDateBounds(_financePeriod);
    try {
      final bytes = await ref.read(paymentsRepositoryProvider).exportPaymentsJournal(
            format: 'csv',
            search: search,
            method: method,
            dateFrom: bounds.from,
            dateTo: bounds.to,
          );
      await _saveTextExport(
        content: utf8.decode(bytes, allowMalformed: true),
        fileName: 'journal_encaissements_${_periodCode(_financePeriod)}_${_timestampSuffix()}.csv',
        dialogTitle: 'Enregistrer le journal des encaissements',
        successMessage: 'Export CSV encaissements backend reussi.',
      );
      return;
    } catch (_) {
      final rows = await _loadPaymentExportRows(
        search: search,
        method: method,
        period: _financePeriod,
      );
      if (rows.isEmpty) {
        _showMessage('Aucun encaissement a exporter pour cette periode.');
        return;
      }

      final csv = _buildPaymentsCsv(rows);
      await _saveTextExport(
        content: csv,
        fileName: 'journal_encaissements_${_periodCode(_financePeriod)}_${_timestampSuffix()}.csv',
        dialogTitle: 'Enregistrer le journal des encaissements',
        successMessage: 'Export CSV encaissements reussi (${rows.length} lignes).',
      );
    }
  }

  Future<void> _exportPaymentsPdf({required String search, required String? method}) async {
    final bounds = _periodDateBounds(_financePeriod);
    try {
      final bytes = await ref.read(paymentsRepositoryProvider).exportPaymentsJournal(
            format: 'pdf',
            search: search,
            method: method,
            dateFrom: bounds.from,
            dateTo: bounds.to,
          );
      await _savePdfExport(
        bytes: bytes,
        fileName: 'journal_encaissements_${_periodCode(_financePeriod)}_${_timestampSuffix()}.pdf',
        dialogTitle: 'Exporter le journal des encaissements en PDF',
        successMessage: 'Export PDF encaissements backend reussi.',
      );
      return;
    } catch (_) {
      final rows = await _loadPaymentExportRows(
        search: search,
        method: method,
        period: _financePeriod,
      );
      if (rows.isEmpty) {
        _showMessage('Aucun encaissement a exporter en PDF pour cette periode.');
        return;
      }

      final amountTotal = rows.fold<double>(0, (sum, payment) => sum + payment.amount);
      final bytes = await _buildJournalPdf(
        title: 'Journal des encaissements',
        subtitle: 'Periode ${_financePeriodLabel(_financePeriod).toLowerCase()} • ${rows.length} ligne(s)',
        summaryLines: [
          'Periode: ${_financePeriodLabel(_financePeriod)}',
          'Encaissements: ${rows.length}',
          'Montant total: ${_formatMoney(amountTotal)}',
        ],
        headers: const ['Date', 'Eleve', 'Matricule', 'Type frais', 'Montant', 'Methode', 'Reference'],
        rows: rows
            .map(
              (payment) => [
                _formatDate(payment.createdAt),
                payment.studentFullName,
                payment.studentMatricule,
                payment.feeType,
                _formatMoney(payment.amount),
                payment.method,
                payment.reference.isEmpty ? '-' : payment.reference,
              ],
            )
            .toList(growable: false),
      );

      await _savePdfExport(
        bytes: bytes,
        fileName: 'journal_encaissements_${_periodCode(_financePeriod)}_${_timestampSuffix()}.pdf',
        dialogTitle: 'Exporter le journal des encaissements en PDF',
        successMessage: 'Export PDF encaissements reussi (${rows.length} lignes).',
      );
    }
  }

  List<PaymentItem> _filteredPayments(List<PaymentItem> payments) {
    final rows = payments.toList();

    rows.sort((left, right) {
      final lDate = DateTime.tryParse(left.createdAt);
      final rDate = DateTime.tryParse(right.createdAt);
      if (lDate == null && rDate == null) return right.id.compareTo(left.id);
      if (lDate == null) return 1;
      if (rDate == null) return -1;
      return rDate.compareTo(lDate);
    });

    return rows;
  }

  void _syncSelectedPayment(List<PaymentItem> rows) {
    if (rows.isEmpty) {
      if (_selectedPaymentId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _selectedPaymentId = null);
        });
      }
      return;
    }

    final exists = rows.any((payment) => payment.id == _selectedPaymentId);
    if (!exists) {
      final fallbackId = rows.first.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedPaymentId = fallbackId);
      });
    }
  }

  void _syncSelectedFee(List<StudentFeeItem> fees) {
    if (fees.isEmpty) {
      if (_selectedFeeId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _selectedFeeId = null);
        });
      }
      return;
    }

    final exists = fees.any((fee) => fee.id == _selectedFeeId);
    if (!exists) {
      final defaultFeeId = fees.first.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedFeeId = defaultFeeId);
      });
    }
  }

  PaymentItem? _selectedPayment(List<PaymentItem> rows) {
    for (final payment in rows) {
      if (payment.id == _selectedPaymentId) {
        return payment;
      }
    }
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _openPaymentDetails(PaymentItem payment) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Details paiement'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow('Eleve', payment.studentFullName),
                _detailRow('Matricule', payment.studentMatricule),
                _detailRow('Type frais', payment.feeType),
                _detailRow('Montant', _formatMoney(payment.amount)),
                _detailRow('Methode', payment.method),
                _detailRow(
                  'Reference',
                  payment.reference.isEmpty ? '-' : payment.reference,
                ),
                _detailRow('Date', _formatDate(payment.createdAt)),
                _detailRow('ID paiement', '#${payment.id}'),
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

  Future<void> _openPaymentDialog({
    PaymentItem? payment,
    required List<StudentFeeItem> fees,
  }) async {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController(
      text: payment == null ? '' : payment.amount.toStringAsFixed(0),
    );
    final referenceController = TextEditingController(text: payment?.reference ?? '');

    var editFeeId = payment?.feeId ?? _selectedFeeId ?? (fees.isEmpty ? null : fees.first.id);
    var selectedMethod = payment?.method ?? _paymentMethodOptions.first;
    var saving = false;

    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(payment == null ? 'Nouveau paiement' : 'Modifier paiement'),
              content: SizedBox(
                width: 460,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        initialValue: editFeeId,
                        decoration: const InputDecoration(
                          labelText: 'Frais eleve',
                        ),
                        items: fees
                            .map(
                              (fee) => DropdownMenuItem<int>(
                                value: fee.id,
                                child: Text(
                                  _feeLabel(fee),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => editFeeId = value);
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Montant'),
                        validator: (value) {
                          final parsed = double.tryParse(value ?? '');
                          if (parsed == null || parsed <= 0) {
                            return 'Montant invalide';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _paymentMethodOptions.contains(selectedMethod)
                            ? selectedMethod
                            : _paymentMethodOptions.first,
                        decoration: const InputDecoration(labelText: 'Methode'),
                        items: _paymentMethodOptions
                            .map(
                              (item) => DropdownMenuItem<String>(
                                value: item,
                                child: Text(item),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => selectedMethod = value);
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: referenceController,
                        decoration: const InputDecoration(
                          labelText: 'Reference',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }
                          if (editFeeId == null) {
                            _showMessage('Selectionnez un frais eleve.');
                            return;
                          }

                          setDialogState(() => saving = true);

                          if (payment == null) {
                            await ref
                                .read(paymentMutationProvider.notifier)
                                .createPayment(
                                  feeId: editFeeId!,
                                  amount: double.parse(amountController.text),
                                  method: selectedMethod,
                                  reference: referenceController.text.trim(),
                                );
                          } else {
                            await ref
                                .read(paymentMutationProvider.notifier)
                                .updatePayment(
                                  paymentId: payment.id,
                                  feeId: editFeeId!,
                                  amount: double.parse(amountController.text),
                                  method: selectedMethod,
                                  reference: referenceController.text.trim(),
                                );
                          }

                          final mutation = ref.read(paymentMutationProvider);
                          if (mutation.hasError) {
                            _showMessage(
                              payment == null
                                  ? 'Erreur creation paiement: ${mutation.error}'
                                  : 'Erreur modification paiement: ${mutation.error}',
                            );
                            setDialogState(() => saving = false);
                            return;
                          }

                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop(true);
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    amountController.dispose();
    referenceController.dispose();

    if (updated == true) {
      _showMessage(
        payment == null
            ? 'Paiement enregistre avec succes.'
            : 'Paiement modifie avec succes.',
        isSuccess: true,
      );
    }
  }

  Future<void> _openEditDialog(PaymentItem payment, List<StudentFeeItem> fees) {
    return _openPaymentDialog(payment: payment, fees: fees);
  }

  Future<void> _openCreatePaymentDialog(List<StudentFeeItem> fees) {
    return showGuidedPaymentEntryDialog(
      context: context,
      ref: ref,
      title: 'Fenetre flottante d\'encaissement',
    ).then((saved) {
      if (saved == true && mounted) {
        _showMessage('Paiement enregistre avec succes.', isSuccess: true);
      }
    });
  }

  Future<void> _deletePayment(PaymentItem payment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Supprimer paiement'),
          content: Text(
            'Voulez-vous supprimer le paiement #${payment.id} de ${_formatMoney(payment.amount)} ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB42318),
              ),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await ref
        .read(paymentMutationProvider.notifier)
        .deletePayment(paymentId: payment.id);

    final mutation = ref.read(paymentMutationProvider);
    if (mutation.hasError) {
      _showMessage('Erreur suppression paiement: ${mutation.error}');
      return;
    }

    if (_selectedPaymentId == payment.id) {
      setState(() => _selectedPaymentId = null);
    }
    _showMessage('Paiement supprime avec succes.', isSuccess: true);
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

  Widget _methodTag(BuildContext context, String method) {
    final color = method.toLowerCase().contains('mobile')
        ? const Color(0xFF2A8E58)
        : method.toLowerCase().contains('virement')
        ? const Color(0xFF2D6FD6)
        : const Color(0xFFB9721B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        method,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authControllerProvider).value;
    final isTeacherFinanceVisible = _isTeacherFinanceVisible(authUser?.role);
    final isTeacherFinanceReadOnly = _isTeacherFinanceReadOnly(authUser?.role);
    final query = PaymentsPageQuery(
      page: _currentPage,
      pageSize: _pageSize,
      search: _searchTerm,
      method: _methodFilter == 'all' ? null : _methodFilter,
    );
    final paymentsAsync = ref.watch(paymentsPaginatedProvider(query));
    final feesAsync = ref.watch(feesProvider);
    final mutationState = ref.watch(paymentMutationProvider);
    final isMutating = mutationState.isLoading;
    final colorScheme = Theme.of(context).colorScheme;

    return feesAsync.when(
      loading: () => RefreshIndicator(
        onRefresh: _refreshPayments,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: const [
            SizedBox(
              height: 460,
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      ),
      error: (error, _) => RefreshIndicator(
        onRefresh: _refreshPayments,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Impossible de charger les frais eleves',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text('Erreur: $error'),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _refreshPayments,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reessayer'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      data: (fees) {
        _syncSelectedFee(fees);

        return paymentsAsync.when(
          loading: () => RefreshIndicator(
            onRefresh: _refreshPayments,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(18),
              children: const [
                SizedBox(
                  height: 460,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
            ),
          ),
          error: (error, _) => RefreshIndicator(
            onRefresh: _refreshPayments,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(18),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Impossible de charger les paiements',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text('Erreur: $error'),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _refreshPayments,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reessayer'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          data: (pageData) {
            final payments = pageData.results;
            final filteredPayments = _filteredPayments(payments);
            final periodPayments = payments.where((payment) {
              return _isInPeriod(DateTime.tryParse(payment.createdAt), _financePeriod);
            }).toList(growable: false);
            final visiblePayments = filteredPayments.where((payment) {
              return _isInPeriod(DateTime.tryParse(payment.createdAt), _financePeriod);
            }).toList(growable: false);
            _syncSelectedPayment(visiblePayments);
            final selectedPayment = _selectedPayment(visiblePayments);
            final periodExpenses = _financeExpenses.where((row) {
              return _isInPeriod(
                DateTime.tryParse((row['date'] ?? '').toString()),
                _financePeriod,
              );
            }).toList(growable: false);
            final periodValidatedExpenses = periodExpenses
                .where((row) => (row['validation_stage'] ?? '').toString() == 'level_two')
                .toList(growable: false);
            final periodIncomeAmount = periodPayments.fold<double>(
              0,
              (sum, payment) => sum + payment.amount,
            );
            final periodValidatedExpensesAmount = periodValidatedExpenses.fold<double>(
              0,
              (sum, row) => sum + (double.tryParse(row['amount']?.toString() ?? '0') ?? 0),
            );
            final periodNetTreasury = periodIncomeAmount - periodValidatedExpensesAmount;
            final expenseDraftCount = periodExpenses
                .where((row) => (row['validation_stage'] ?? '').toString() == 'draft')
                .length;
            final expensePendingLevelTwoCount = periodExpenses
                .where((row) => (row['validation_stage'] ?? '').toString() == 'level_one')
                .length;
            final expenseValidatedCount = periodExpenses
                .where((row) => (row['validation_stage'] ?? '').toString() == 'level_two')
                .length;
            final totalExpensesAmount = periodExpenses.fold<double>(
              0,
              (sum, row) => sum + (double.tryParse(row['amount']?.toString() ?? '0') ?? 0),
            );

            final totalPaid = payments.fold<double>(
              0,
              (sum, payment) => sum + payment.amount,
            );
            final periodPaymentMethods = <String, double>{};
            for (final payment in periodPayments) {
              periodPaymentMethods.update(
                payment.method,
                (value) => value + payment.amount,
                ifAbsent: () => payment.amount,
              );
            }
            final paymentMethodEntries = periodPaymentMethods.entries.toList()
              ..sort((left, right) => right.value.compareTo(left.value));
            final dominantMethodLabel = paymentMethodEntries.isEmpty
                ? '-'
                : '${paymentMethodEntries.first.key} • ${_formatMoney(paymentMethodEntries.first.value)}';
            final outstandingFees = fees
                .where((fee) => fee.balance > 0)
                .toList();
            final outstandingTotal = outstandingFees.fold<double>(
              0,
              (sum, fee) => sum + fee.balance,
            );

            final methodOptions = <String>{'all'};
            for (final payment in payments) {
              if (payment.method.trim().isNotEmpty) {
                methodOptions.add(payment.method);
              }
            }

            return RefreshIndicator(
              onRefresh: _refreshPayments,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(18),
                children: [
                  Text(
                    'Paiements & Facturation',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Reglements, suivi des soldes eleves et generation de recus PDF.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
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
                          'Encaissements & entrees d\'argent',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Journal des encaissements avec filtres, creation par dialogue et exports CSV/PDF.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final compact = constraints.maxWidth < 940;
                            final searchField = SizedBox(
                              width: compact ? double.infinity : 270,
                              child: TextField(
                                controller: _searchController,
                                onChanged: _onSearchChanged,
                                decoration: InputDecoration(
                                  labelText: 'Recherche paiement',
                                  prefixIcon: const Icon(Icons.search),
                                  suffixIcon: _searchController.text.trim().isEmpty
                                      ? null
                                      : IconButton(
                                          onPressed: () {
                                            _searchDebounce?.cancel();
                                            _searchController.clear();
                                            setState(() {
                                              _searchTerm = '';
                                              _currentPage = 1;
                                            });
                                          },
                                          icon: const Icon(Icons.clear),
                                        ),
                                ),
                              ),
                            );
                            final methodField = SizedBox(
                              width: compact ? double.infinity : 220,
                              child: DropdownButtonFormField<String>(
                                initialValue: _methodFilter,
                                decoration: const InputDecoration(
                                  labelText: 'Filtrer par methode',
                                ),
                                items: methodOptions
                                    .map(
                                      (method) => DropdownMenuItem<String>(
                                        value: method,
                                        child: Text(
                                          method == 'all'
                                              ? 'Toutes les methodes'
                                              : method,
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: (value) {
                                  setState(() {
                                    _methodFilter = value ?? 'all';
                                    _currentPage = 1;
                                  });
                                },
                              ),
                            );
                            final periodField = SizedBox(
                              width: compact ? double.infinity : 170,
                              child: DropdownButtonFormField<_FinancePeriod>(
                                initialValue: _financePeriod,
                                decoration: const InputDecoration(labelText: 'Periode'),
                                items: _FinancePeriod.values
                                    .map(
                                      (item) => DropdownMenuItem<_FinancePeriod>(
                                        value: item,
                                        child: Text(_financePeriodLabel(item)),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => _financePeriod = value);
                                },
                              ),
                            );
                            final actions = Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed: isMutating ? null : () => _openCreatePaymentDialog(fees),
                                  icon: const Icon(Icons.add_card_outlined),
                                  label: const Text('Nouveau paiement'),
                                ),
                                FilledButton.icon(
                                  onPressed: isMutating
                                      ? null
                                      : () => _exportPaymentsCsv(
                                            search: _searchTerm,
                                            method: _methodFilter == 'all' ? null : _methodFilter,
                                          ),
                                  icon: const Icon(Icons.download_outlined),
                                  label: const Text('Exporter CSV'),
                                ),
                                FilledButton.tonalIcon(
                                  onPressed: isMutating
                                      ? null
                                      : () => _exportPaymentsPdf(
                                            search: _searchTerm,
                                            method: _methodFilter == 'all' ? null : _methodFilter,
                                          ),
                                  icon: const Icon(Icons.picture_as_pdf_outlined),
                                  label: const Text('Exporter PDF'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: isMutating
                                      ? null
                                      : () {
                                          _searchDebounce?.cancel();
                                          _searchController.clear();
                                          setState(() {
                                            _methodFilter = 'all';
                                            _searchTerm = '';
                                            _currentPage = 1;
                                            _financePeriod = _FinancePeriod.month;
                                          });
                                        },
                                  icon: const Icon(Icons.filter_alt_off_outlined),
                                  label: const Text('Reinitialiser'),
                                ),
                              ],
                            );

                            if (compact) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  searchField,
                                  const SizedBox(height: 8),
                                  methodField,
                                  const SizedBox(height: 8),
                                  periodField,
                                  const SizedBox(height: 8),
                                  actions,
                                ],
                              );
                            }

                            return Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [searchField, methodField, periodField, actions],
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _metricChip('Periode', _financePeriodLabel(_financePeriod)),
                            _metricChip('Encaissements', '${periodPayments.length}'),
                            _metricChip('Montant periode', _formatMoney(periodIncomeAmount)),
                            _metricChip('Mode dominant', dominantMethodLabel),
                            _metricChip('Frais impayes', '${outstandingFees.length}'),
                            _metricChip('Solde restant', _formatMoney(outstandingTotal)),
                            _metricChip('Montant page', _formatMoney(totalPaid)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          pageData.count == 0
                              ? 'Aucun résultat'
                              : 'Page $_currentPage • ${visiblePayments.length} visible(s) sur ${payments.length} ligne(s) de la page • ${pageData.count} total',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        if (visiblePayments.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 18),
                            child: Center(
                              child: Text('Aucun paiement correspondant a cette periode.'),
                            ),
                          )
                        else
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Date')),
                                DataColumn(label: Text('Eleve')),
                                DataColumn(label: Text('Matricule')),
                                DataColumn(label: Text('Type frais')),
                                DataColumn(label: Text('Montant')),
                                DataColumn(label: Text('Methode')),
                                DataColumn(label: Text('Reference')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows: visiblePayments.map((payment) {
                                final selected = payment.id == _selectedPaymentId;
                                return DataRow(
                                  selected: selected,
                                  onSelectChanged: (_) {
                                    setState(() => _selectedPaymentId = payment.id);
                                  },
                                  cells: [
                                    DataCell(Text(_formatDate(payment.createdAt))),
                                    DataCell(Text(payment.studentFullName)),
                                    DataCell(Text(payment.studentMatricule)),
                                    DataCell(Text(payment.feeType)),
                                    DataCell(Text(_formatMoney(payment.amount))),
                                    DataCell(_methodTag(context, payment.method)),
                                    DataCell(Text(payment.reference.isEmpty ? '-' : payment.reference)),
                                    DataCell(
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          OutlinedButton(
                                            onPressed: () => _openPaymentDetails(payment),
                                            child: const Text('Afficher'),
                                          ),
                                          OutlinedButton(
                                            onPressed: isMutating ? null : () => _openEditDialog(payment, fees),
                                            child: const Text('Modifier'),
                                          ),
                                          FilledButton.tonal(
                                            onPressed: () async {
                                              try {
                                                await _printReceipt(payment.id);
                                              } catch (error) {
                                                _showMessage('Erreur generation PDF: $error');
                                              }
                                            },
                                            child: const Text('Recu PDF'),
                                          ),
                                          TextButton(
                                            onPressed: isMutating ? null : () => _deletePayment(payment),
                                            child: const Text('Supprimer'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(growable: false),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                const Text('Lignes/page:'),
                                DropdownButton<int>(
                                  value: _pageSize,
                                  items: _pageSizeOptions
                                      .map(
                                        (rows) => DropdownMenuItem<int>(
                                          value: rows,
                                          child: Text('$rows'),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) {
                                    if (value == null || value == _pageSize) {
                                      return;
                                    }
                                    setState(() {
                                      _pageSize = value;
                                      _currentPage = 1;
                                    });
                                  },
                                ),
                              ],
                            ),
                            Wrap(
                              spacing: 6,
                              children: [
                                IconButton(
                                  tooltip: 'Page précédente',
                                  onPressed: pageData.hasPrevious
                                      ? () => setState(() => _currentPage -= 1)
                                      : null,
                                  icon: const Icon(Icons.chevron_left),
                                ),
                                IconButton(
                                  tooltip: 'Page suivante',
                                  onPressed: pageData.hasNext
                                      ? () => setState(() => _currentPage += 1)
                                      : null,
                                  icon: const Icon(Icons.chevron_right),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (selectedPayment != null) ...[
                          const SizedBox(height: 12),
                          Divider(color: colorScheme.outlineVariant),
                          const SizedBox(height: 10),
                          Text(
                            'Recu selectionne',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              _metricChip('Eleve', selectedPayment.studentFullName),
                              _metricChip('Matricule', selectedPayment.studentMatricule),
                              _metricChip('Type frais', selectedPayment.feeType),
                              _metricChip('Montant', _formatMoney(selectedPayment.amount)),
                              _metricChip('Methode', selectedPayment.method),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: () => _openPaymentDetails(selectedPayment),
                                icon: const Icon(Icons.visibility_outlined),
                                label: const Text('Afficher'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: isMutating ? null : () => _openEditDialog(selectedPayment, fees),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Modifier'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () async {
                                  try {
                                    await _printReceipt(selectedPayment.id);
                                  } catch (error) {
                                    _showMessage('Erreur generation PDF: $error');
                                  }
                                },
                                icon: const Icon(Icons.picture_as_pdf),
                                label: const Text('Imprimer recu'),
                              ),
                              FilledButton.icon(
                                onPressed: isMutating ? null : () => _deletePayment(selectedPayment),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFB42318),
                                ),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Supprimer'),
                              ),
                            ],
                          ),
                        ],
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
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Frais en attente',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        if (outstandingFees.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('Aucun solde restant.'),
                          )
                        else
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Eleve')),
                                DataColumn(label: Text('Matricule')),
                                DataColumn(label: Text('Type frais')),
                                DataColumn(label: Text('Montant du')),
                                DataColumn(label: Text('Solde')),
                              ],
                              rows: outstandingFees
                                  .map(
                                    (fee) => DataRow(
                                      cells: [
                                        DataCell(Text(fee.studentFullName)),
                                        DataCell(Text(fee.studentMatricule)),
                                        DataCell(Text(fee.feeType)),
                                        DataCell(
                                          Text(_formatMoney(fee.amountDue)),
                                        ),
                                        DataCell(
                                          Text(_formatMoney(fee.balance)),
                                        ),
                                      ],
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isTeacherFinanceVisible) ...[
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
                            'Paie horaire enseignants',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isTeacherFinanceReadOnly
                                ? 'Mode lecture seule (Comptable): consultation et validation niveau 2.'
                                : 'Generation de la paie mensuelle et validation du workflow N1/N2.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              SizedBox(
                                width: 180,
                                child: TextField(
                                  controller: _payrollMonthController,
                                  decoration: const InputDecoration(labelText: 'Mois paie (YYYY-MM)'),
                                ),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: (isTeacherFinanceReadOnly || _financeBusy)
                                    ? null
                                    : _generateTeacherPayroll,
                                icon: const Icon(Icons.calculate_outlined),
                                label: const Text('Generer paie horaire'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _loadTeacherFinanceSection,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Actualiser'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Synthese paie horaire (${_financePayrolls.length})',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          if (_financePayrolls.isEmpty)
                            const Text('Aucune paie horaire generee pour ce mois.')
                          else
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('Enseignant')),
                                  DataColumn(label: Text('Mois')),
                                  DataColumn(label: Text('H. attribuees')),
                                  DataColumn(label: Text('H. travaillees')),
                                  DataColumn(label: Text('Taux horaire')),
                                  DataColumn(label: Text('Montant')),
                                  DataColumn(label: Text('Validation')),
                                  DataColumn(label: Text('Actions')),
                                ],
                                rows: _financePayrolls.map((row) {
                                  final payrollId = (row['id'] as num?)?.toInt();
                                  final teacherName = row['teacher_full_name']?.toString() ?? 'Enseignant';
                                  final month = row['month']?.toString() ?? '-';
                                  final attributed = row['hours_attributed']?.toString() ?? '0';
                                  final worked = row['hours_worked']?.toString() ?? '0';
                                  final rate = double.tryParse(row['hourly_rate']?.toString() ?? '0') ?? 0;
                                  final amount = double.tryParse(row['amount']?.toString() ?? '0') ?? 0;
                                  final stage = (row['validation_stage'] ?? '').toString();
                                  final canL1 = (authUser?.role == 'supervisor' || authUser?.role == 'super_admin') &&
                                      stage != 'level_two' &&
                                      payrollId != null;
                                  final canL2 = (authUser?.role == 'accountant' || authUser?.role == 'super_admin') &&
                                      stage == 'level_one' &&
                                      payrollId != null;
                                  final canReset = authUser?.role == 'super_admin' && payrollId != null;

                                  return DataRow(
                                    cells: [
                                      DataCell(Text(teacherName)),
                                      DataCell(Text(month)),
                                      DataCell(Text(attributed)),
                                      DataCell(Text(worked)),
                                      DataCell(Text('${_formatMoney(rate)}/h')),
                                      DataCell(Text(_formatMoney(amount))),
                                      DataCell(Text(_payrollStageLabel(row))),
                                      DataCell(
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            if (canL1)
                                              OutlinedButton(
                                                onPressed: _financeBusy
                                                    ? null
                                                    : () => _validatePayrollLevelOne(payrollId),
                                                child: const Text('Valider N1'),
                                              ),
                                            if (canL2)
                                              FilledButton.tonal(
                                                onPressed: _financeBusy
                                                    ? null
                                                    : () => _validatePayrollLevelTwo(payrollId),
                                                child: const Text('Valider N2'),
                                              ),
                                            if (canReset)
                                              TextButton(
                                                onPressed: _financeBusy
                                                    ? null
                                                    : () => _resetPayrollValidation(payrollId),
                                                child: const Text('Reset'),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(growable: false),
                              ),
                            ),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dépenses & sorties d\'argent',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Workflow de validation N1/N2 pour toutes les charges avant paiement final.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final compact = constraints.maxWidth < 940;
                              final periodField = SizedBox(
                                width: compact ? double.infinity : 170,
                                child: DropdownButtonFormField<_FinancePeriod>(
                                  initialValue: _financePeriod,
                                  decoration: const InputDecoration(labelText: 'Periode'),
                                  items: _FinancePeriod.values
                                      .map(
                                        (item) => DropdownMenuItem<_FinancePeriod>(
                                          value: item,
                                          child: Text(_financePeriodLabel(item)),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() => _financePeriod = value);
                                  },
                                ),
                              );
                              final actions = Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed: _financeBusy ? null : () => _openExpenseDialog(),
                                    icon: const Icon(Icons.add_card_outlined),
                                    label: const Text('Nouvelle depense'),
                                  ),
                                  FilledButton.icon(
                                    onPressed: _financeBusy ? null : () => _exportExpensesCsv(periodExpenses),
                                    icon: const Icon(Icons.download_outlined),
                                    label: const Text('Exporter CSV'),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: _financeBusy ? null : () => _exportExpensesPdf(periodExpenses),
                                    icon: const Icon(Icons.picture_as_pdf_outlined),
                                    label: const Text('Exporter PDF'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _financeBusy ? null : _loadTeacherFinanceSection,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Actualiser depenses'),
                                  ),
                                ],
                              );

                              if (compact) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    periodField,
                                    const SizedBox(height: 8),
                                    actions,
                                  ],
                                );
                              }

                              return Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [periodField, actions],
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _metricChip('Periode', _financePeriodLabel(_financePeriod)),
                              _metricChip('Dépenses', '${periodExpenses.length}'),
                              _metricChip('Brouillons', '$expenseDraftCount'),
                              _metricChip('En attente N2', '$expensePendingLevelTwoCount'),
                              _metricChip('Validées', '$expenseValidatedCount'),
                              _metricChip('Montant total', _formatMoney(totalExpensesAmount)),
                              _metricChip('Encaissements', _formatMoney(periodIncomeAmount)),
                              _metricChip(
                                'Depenses validees',
                                _formatMoney(periodValidatedExpensesAmount),
                              ),
                              _metricChip('Tresorerie nette', _formatMoney(periodNetTreasury)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (periodExpenses.isEmpty)
                            const Text('Aucune dépense enregistrée.')
                          else
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('Libellé')),
                                  DataColumn(label: Text('Date')),
                                  DataColumn(label: Text('Catégorie')),
                                  DataColumn(label: Text('Montant')),
                                  DataColumn(label: Text('Validation')),
                                  DataColumn(label: Text('Paiement')),
                                  DataColumn(label: Text('Actions')),
                                ],
                                rows: periodExpenses.map((row) {
                                  final expenseId = (row['id'] as num?)?.toInt();
                                  final stage = (row['validation_stage'] ?? '').toString();
                                  final canL1 = (authUser?.role == 'supervisor' || authUser?.role == 'super_admin') &&
                                      stage != 'level_two' &&
                                      expenseId != null;
                                  final canL2 = (authUser?.role == 'accountant' || authUser?.role == 'super_admin') &&
                                      stage == 'level_one' &&
                                      expenseId != null;
                                  final canReset = authUser?.role == 'super_admin' && expenseId != null;
                                  final amount = double.tryParse(row['amount']?.toString() ?? '0') ?? 0;
                                  final paidOn = row['paid_on']?.toString();

                                  return DataRow(
                                    cells: [
                                      DataCell(Text((row['label'] ?? '-').toString())),
                                      DataCell(Text((row['date'] ?? '-').toString())),
                                      DataCell(Text((row['category'] ?? '-').toString())),
                                      DataCell(Text(_formatMoney(amount))),
                                      DataCell(Text(_expenseStageLabel(row))),
                                      DataCell(Text((paidOn == null || paidOn.isEmpty) ? '-' : paidOn)),
                                      DataCell(
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            if (expenseId != null)
                                              OutlinedButton(
                                                onPressed: _financeBusy || stage == 'level_two'
                                                    ? null
                                                    : () => _openExpenseDialog(expense: row),
                                                child: const Text('Modifier'),
                                              ),
                                            if (expenseId != null)
                                              TextButton(
                                                onPressed: _financeBusy || stage == 'level_two'
                                                    ? null
                                                    : () => _deleteExpense(row),
                                                child: const Text('Supprimer'),
                                              ),
                                            if (canL1)
                                              OutlinedButton(
                                                onPressed: _financeBusy
                                                    ? null
                                                    : () => _validateExpenseLevelOne(expenseId),
                                                child: const Text('Valider N1'),
                                              ),
                                            if (canL2)
                                              FilledButton.tonal(
                                                onPressed: _financeBusy
                                                    ? null
                                                    : () => _validateExpenseLevelTwo(expenseId),
                                                child: const Text('Valider N2'),
                                              ),
                                            if (canReset)
                                              TextButton(
                                                onPressed: _financeBusy
                                                    ? null
                                                    : () => _resetExpenseValidation(expenseId),
                                                child: const Text('Reset'),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(growable: false),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (selectedPayment != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recu selectionne',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          _detailRow(
                            'Paiement',
                            '#${selectedPayment.id} • ${_formatMoney(selectedPayment.amount)}',
                          ),
                          _detailRow('Eleve', selectedPayment.studentFullName),
                          _detailRow(
                            'Date',
                            _formatDate(selectedPayment.createdAt),
                          ),
                          const SizedBox(height: 6),
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              try {
                                await _printReceipt(selectedPayment.id);
                              } catch (error) {
                                _showMessage('Erreur generation PDF: $error');
                              }
                            },
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('Imprimer le recu PDF'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

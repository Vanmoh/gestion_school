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

import '../../../core/network/api_client.dart';
import '../../../core/providers/navigation_intents.dart';
import '../../../core/permissions/module_permissions.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/payment.dart';
import '../domain/student_fee.dart';
import 'payment_entry_dialog.dart';
import 'payments_controller.dart';
import 'widgets/finance_communs.dart';

class PaymentsPage extends ConsumerStatefulWidget {
  const PaymentsPage({super.key});

  @override
  ConsumerState<PaymentsPage> createState() => _PaymentsPageState();
}

enum _FinancePeriod { day, week, month, all }

enum _PaymentRowAction { view, edit, print, delete }

class _ClassKpiRow {
  final String className;
  final int feeCount;
  final int studentCount;
  final int overdueCount;
  final double totalDue;
  final double totalPaid;
  final double totalOutstanding;

  const _ClassKpiRow({
    required this.className,
    required this.feeCount,
    required this.studentCount,
    required this.overdueCount,
    required this.totalDue,
    required this.totalPaid,
    required this.totalOutstanding,
  });

  double get recoveryRate => totalDue <= 0 ? 0 : (totalPaid / totalDue);
}

class _LateFeeAlert {
  final int feeId;
  final String className;
  final String studentFullName;
  final String studentMatricule;
  final String feeType;
  final String dueDateRaw;
  final int daysLate;
  final double balance;

  const _LateFeeAlert({
    required this.feeId,
    required this.className,
    required this.studentFullName,
    required this.studentMatricule,
    required this.feeType,
    required this.dueDateRaw,
    required this.daysLate,
    required this.balance,
  });
}

class _LateStudentSummary {
  final String studentKey;
  final String studentFullName;
  final String studentMatricule;
  final String className;
  final int lateFeesCount;
  final int maxDaysLate;
  final double totalBalance;

  const _LateStudentSummary({
    required this.studentKey,
    required this.studentFullName,
    required this.studentMatricule,
    required this.className,
    required this.lateFeesCount,
    required this.maxDaysLate,
    required this.totalBalance,
  });
}

class _LateTrendMetrics {
  final int current7Count;
  final int previous7Count;
  final int current30Count;
  final int previous30Count;
  final double current7Amount;
  final double previous7Amount;
  final double current30Amount;
  final double previous30Amount;

  const _LateTrendMetrics({
    required this.current7Count,
    required this.previous7Count,
    required this.current30Count,
    required this.previous30Count,
    required this.current7Amount,
    required this.previous7Amount,
    required this.current30Amount,
    required this.previous30Amount,
  });
}

class _ReminderHistoryEntry {
  final DateTime createdAt;
  final String action;
  final String scope;
  final int itemCount;
  final double totalAmount;

  const _ReminderHistoryEntry({
    required this.createdAt,
    required this.action,
    required this.scope,
    required this.itemCount,
    required this.totalAmount,
  });
}

class _PaymentsPageState extends ConsumerState<PaymentsPage>
    with SingleTickerProviderStateMixin {
  static const List<int> _pageSizeOptions = [15, 25, 50, 100];
  static const List<int> _outstandingPageSizeOptions = [10, 20, 40];
  static const List<int> _reminderHistoryPageSizeOptions = [8, 15, 30];
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
  int _outstandingPage = 1;
  int _outstandingPageSize = 10;
  bool _outstandingExpanded = false;
  final Set<int> _selectedPaymentIds = <int>{};
  final Set<int> _selectedOutstandingFeeIds = <int>{};
  final Set<String> _expandedOutstandingClasses = <String>{};
  String _searchTerm = '';
  Timer? _searchDebounce;
  bool _financeBusy = false;
  List<Map<String, dynamic>> _financePayrolls = [];
  List<Map<String, dynamic>> _financeExpenses = [];
  _FinancePeriod _financePeriod = _FinancePeriod.all;
  int _lateAlertMinDays = 7;
  final List<_ReminderHistoryEntry> _reminderHistory = <_ReminderHistoryEntry>[];
  String _reminderHistoryActionFilter = 'all';
  String _reminderHistoryPeriodFilter = 'all';
  String _reminderHistorySort = 'date_desc';
  final TextEditingController _reminderHistorySearchController = TextEditingController();
  String _reminderHistorySearchTerm = '';
  int _reminderHistoryPage = 1;
  int _reminderHistoryPageSize = 8;
  bool _openingGuidedDialogFromIntent = false;

  static const List<String> _expenseCategoryOptions = [
    'Salaires enseignants',
    'Salaires personnels',
    'Utilités',
    'Maintenance',
    'Fournitures',
    'Taxes',
    'Transport',
    'Loyer',
    'Charges opérationnelles',
    'Autres',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _payrollMonthController.text =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    Future<void>.microtask(() async {
      await _loadReminderHistory();
      await _loadTeacherFinanceSection();
      await _consumeGuidedPaymentIntentIfNeeded();
    });
  }

  /// Le controleur de la barre d'onglets, recree quand leur nombre change.
  ///
  /// Un droit revoque en cours de session ferme un onglet: sans cette
  /// verification, le controleur garderait l'ancienne longueur et TabBar
  /// leverait avant d'afficher quoi que ce soit.
  TabController? _ongletsControleur;
  int _nombreDOnglets = 0;

  TabController _controleurDOnglets(int nombre) {
    final existant = _ongletsControleur;
    if (existant == null || _nombreDOnglets != nombre) {
      existant?.dispose();
      _ongletsControleur = TabController(length: nombre, vsync: this);
      _nombreDOnglets = nombre;
    }
    return _ongletsControleur!;
  }

  /// Les reglements en fiches, pour l'ecran etroit.
  ///
  /// Le mode compact existait deja, mais rendait le meme tableau a neuf
  /// colonnes: on le parcourait lateralement, un geste que l'application ne
  /// demande nulle part ailleurs. Une fiche par reglement porte les memes
  /// informations dans l'ordre ou on les lit -- qui, combien, quand.
  Widget _fichesReglements({
    required List<PaymentItem> reglements,
    required List<StudentFeeItem> fees,
    required bool isMutating,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final reglement in reglements)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: reglement.id == _selectedPaymentId
                ? scheme.primaryContainer
                : null,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _selectedPaymentId = reglement.id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: _selectedPaymentIds.contains(reglement.id),
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                _selectedPaymentIds.add(reglement.id);
                              } else {
                                _selectedPaymentIds.remove(reglement.id);
                              }
                            });
                          },
                        ),
                        Expanded(
                          child: Text(
                            reglement.studentFullName,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          montantEnFrancs(reglement.amount),
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        PopupMenuButton<_PaymentRowAction>(
                          tooltip: 'Actions',
                          onSelected: (action) => _handlePaymentRowAction(
                            action: action,
                            payment: reglement,
                            fees: fees,
                            isMutating: isMutating,
                          ),
                          itemBuilder: (context) => const [
                            PopupMenuItem<_PaymentRowAction>(
                              value: _PaymentRowAction.view,
                              child: Text('Afficher'),
                            ),
                            PopupMenuItem<_PaymentRowAction>(
                              value: _PaymentRowAction.edit,
                              child: Text('Modifier'),
                            ),
                            PopupMenuItem<_PaymentRowAction>(
                              value: _PaymentRowAction.print,
                              child: Text('Imprimer reçu'),
                            ),
                            PopupMenuItem<_PaymentRowAction>(
                              value: _PaymentRowAction.delete,
                              child: Text('Annuler paiement'),
                            ),
                          ],
                          child: const Icon(Icons.more_vert),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 12, top: 2),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            _formatDate(reglement.createdAt),
                            style: textTheme.bodySmall,
                          ),
                          Text(reglement.feeType, style: textTheme.bodySmall),
                          _methodTag(context, reglement.method),
                          Text(
                            '${_classLabel(reglement.classroomName)} • ${reglement.studentMatricule}',
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Ce que la famille vient chercher: ce qu'elle doit, ce qu'elle a payé.
  ///
  /// Le parent et l'eleve recevaient l'ecran du comptable -- recherche de
  /// reglements, indicateurs par classe, historique des relances, classement
  /// des retards. Leurs donnees etaient bien cloisonnees par le serveur, qui
  /// ne leur rend que leur dossier: ces blocs etaient donc calcules sur leur
  /// seul enfant. Pas une fuite, un ecran sans objet pour eux.
  List<Widget> _sectionMesFrais({
    required BuildContext context,
    required ColorScheme scheme,
    required List<StudentFeeItem> fraisDus,
    required List<PaymentItem> reglements,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final totalDu = fraisDus.fold<double>(0, (somme, frais) => somme + frais.balance);

    Widget bloc(String titre, String vide, List<Widget> lignes) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titre, style: textTheme.titleSmall),
            const SizedBox(height: 10),
            if (lignes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  vide,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ...lignes,
          ],
        ),
      );
    }

    return <Widget>[
      bloc(
        'Ce qui reste à payer',
        'Rien à payer pour le moment.',
        [
          for (final frais in fraisDus)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(frais.feeType),
              subtitle: Text(
                frais.dueDate.isEmpty
                    ? frais.studentFullName
                    : '${frais.studentFullName} • échéance ${_formatDate(frais.dueDate)}',
              ),
              trailing: Text(
                montantEnFrancs(frais.balance),
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (fraisDus.isNotEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total dû', style: textTheme.titleSmall),
                  Text(
                    montantEnFrancs(totalDu),
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 12),
      bloc(
        'Règlements effectués',
        'Aucun règlement enregistré.',
        [
          for (final reglement in reglements)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(reglement.feeType),
              subtitle: Text(
                '${_formatDate(reglement.createdAt)} • ${reglement.method}',
              ),
              trailing: Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    montantEnFrancs(reglement.amount),
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Télécharger le reçu',
                    onPressed: () => _printReceipt(reglement.id),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                  ),
                ],
              ),
            ),
        ],
      ),
    ];
  }

  /// L'etat de la caisse, constant d'un onglet a l'autre.
  ///
  /// La tresorerie n'apparait qu'a qui voit les depenses: sans elles, le
  /// solde net n'aurait aucun sens. Elle vire au rouge quand elle passe sous
  /// zero -- c'est le seul chiffre de cette ligne qui appelle une reaction.
  Widget _ligneDeSynthese({
    required ColorScheme scheme,
    required double encaisse,
    required double impayes,
    double? tresorerie,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          // La periode n'y figure pas: le filtre juste au-dessus l'affiche
          // deja, et cette ligne ne porte que des montants.
          IndicateurFinance(
            libelle: 'Montant encaissé',
            valeur: montantEnFrancs(encaisse),
          ),
          IndicateurFinance(
            libelle: 'Impayés',
            valeur: montantEnFrancs(impayes),
          ),
          if (tresorerie != null)
            IndicateurFinance(
              libelle: 'Trésorerie nette',
              valeur: montantEnFrancs(tresorerie),
              couleur: tresorerie < 0 ? scheme.error : null,
            ),
        ],
      ),
    );
  }

  /// Le corps d'un onglet: meme defilement et meme geste de rafraichissement
  /// pour tous, ecrits une fois.
  Widget _ongletDefilant(List<Widget> contenu) {
    return RefreshIndicator(
      onRefresh: _refreshPayments,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: contenu,
      ),
    );
  }

  @override
  void dispose() {
    _ongletsControleur?.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _payrollMonthController.dispose();
    _reminderHistorySearchController.dispose();
    super.dispose();
  }

  Future<void> _loadReminderHistory() async {
    try {
      final storage = ref.read(tokenStorageProvider);
      final raw = await storage.reminderHistory();
      if (raw == null || raw.trim().isEmpty) {
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return;
      }

      final parsed = <_ReminderHistoryEntry>[];
      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        final map = Map<String, dynamic>.from(item);
        final createdAt = DateTime.tryParse(map['created_at']?.toString() ?? '');
        if (createdAt == null) {
          continue;
        }
        final itemCount = int.tryParse(map['item_count']?.toString() ?? '0') ?? 0;
        final totalAmount = double.tryParse(map['total_amount']?.toString() ?? '0') ?? 0;
        parsed.add(
          _ReminderHistoryEntry(
            createdAt: createdAt,
            action: map['action']?.toString() ?? '',
            scope: map['scope']?.toString() ?? '',
            itemCount: itemCount,
            totalAmount: totalAmount,
          ),
        );
      }

      if (parsed.isEmpty || !mounted) {
        return;
      }

      setState(() {
        _reminderHistory
          ..clear()
          ..addAll(parsed.take(30));
      });
    } catch (_) {
      // Ignore malformed local payload and keep UI usable.
    }
  }

  Future<void> _persistReminderHistory() async {
    try {
      final storage = ref.read(tokenStorageProvider);
      if (_reminderHistory.isEmpty) {
        await storage.clearReminderHistory();
        return;
      }

      final payload = _reminderHistory
          .map(
            (entry) => <String, dynamic>{
              'created_at': entry.createdAt.toIso8601String(),
              'action': entry.action,
              'scope': entry.scope,
              'item_count': entry.itemCount,
              'total_amount': entry.totalAmount,
            },
          )
          .toList(growable: false);
      await storage.saveReminderHistory(jsonEncode(payload));
    } catch (_) {
      // Silent failure: history remains available in-memory.
    }
  }

  Future<void> _consumeGuidedPaymentIntentIfNeeded() async {
    if (!mounted || _openingGuidedDialogFromIntent) {
      return;
    }
    final shouldOpen = ref.read(financeOpenGuidedPaymentIntentProvider);
    if (!shouldOpen) {
      return;
    }

    ref.read(financeOpenGuidedPaymentIntentProvider.notifier).state = false;
    _openingGuidedDialogFromIntent = true;
    try {
      await showGuidedPaymentEntryDialog(
        context: context,
        ref: ref,
        title: 'Fenetre flottante d\'encaissement',
      );
    } finally {
      _openingGuidedDialogFromIntent = false;
    }
  }

  /// Paie enseignants: module distinct des finances courantes, avec sa
  /// double validation. Les droits viennent de la matrice du backend.
  bool _isTeacherFinanceVisible(String? role) {
    return ref.read(currentPermissionsProvider).canRead('payroll');
  }

  bool _isTeacherFinanceReadOnly(String? role) {
    return !ref.read(currentPermissionsProvider).canWrite('payroll');
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
      _showMessage('Paie horaire générée avec succès.', isSuccess: true);
      await _loadTeacherFinanceSection();
    } catch (error) {
      _showMessage('Erreur génération paie horaire: $error');
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
              title: Text(expense == null ? 'Nouvelle dépense' : 'Modifier dépense'),
              content: SizedBox(
                width: 460,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: labelController,
                        decoration: const InputDecoration(labelText: 'Libellé'),
                        validator: (value) => (value == null || value.trim().isEmpty)
                            ? 'Libellé requis'
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
                        isExpanded: true,
                        initialValue: selectedCategory,
                        decoration: const InputDecoration(labelText: 'Catégorie'),
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
                          decoration: const InputDecoration(labelText: 'Date dépense'),
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
                            _showMessage('Erreur dépense: ${_extractApiErrorMessage(error)}');
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
        expense == null ? 'Dépense enregistree.' : 'Dépense modifiee.',
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
          title: const Text('Supprimer dépense'),
          content: Text(
            'Voulez-vous supprimer la dépense "${(expense['label'] ?? '-').toString()}" ?',
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
      _showMessage('Dépense supprimee.', isSuccess: true);
      await _loadTeacherFinanceSection();
    } catch (error) {
      _showMessage('Erreur suppression dépense: ${_extractApiErrorMessage(error)}');
    } finally {
      if (mounted) setState(() => _financeBusy = false);
    }
  }

  String _payrollStageLabel(Map<String, dynamic> row) {
    final stage = (row['validation_stage'] ?? '').toString();
    if (stage == 'level_two') return 'N2 validé';
    if (stage == 'level_one') return 'N1 validé';
    return 'Brouillon';
  }

  String _expenseStageLabel(Map<String, dynamic> row) {
    final stage = (row['validation_stage'] ?? '').toString();
    if (stage == 'level_two') return 'N2 validé';
    if (stage == 'level_one') return 'N1 validé';
    return 'Brouillon';
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

  Future<void> _printMultipleReceipts() async {
    final ids = _selectedPaymentIds.toList(growable: false)..sort();
    if (ids.isEmpty) {
      _showMessage('Sélectionnez au moins un encaissement.');
      return;
    }

    final repo = ref.read(paymentsRepositoryProvider);
    try {
      final bytes = await repo.fetchBatchReceiptsPdf(ids);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
      _showMessage('Impression lancée pour ${ids.length} reçu(x).', isSuccess: true);
    } catch (_) {
      try {
        for (final paymentId in ids) {
          final bytes = await repo.fetchReceiptPdf(paymentId);
          await Printing.layoutPdf(onLayout: (_) async => bytes);
        }
        _showMessage(
          'Impression fallback lancée pour ${ids.length} reçu(x).',
          isSuccess: true,
        );
      } catch (error) {
        _showMessage('Erreur impression multiple: $error');
      }
    }
  }

  Future<void> _collectSelectedFeesInBulk(List<StudentFeeItem> allOutstandingFees) async {
    final selectedFees = allOutstandingFees
        .where((fee) => _selectedOutstandingFeeIds.contains(fee.id) && fee.balance > 0)
        .toList(growable: false);
    if (selectedFees.isEmpty) {
      _showMessage('Sélectionnez au moins un frais en attente.');
      return;
    }

    final methodNotifier = ValueNotifier<String>(_paymentMethodOptions.first);
    final amountController = TextEditingController();
    final referenceController = TextEditingController();

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Encaissement en lot'),
            content: SizedBox(
              width: 430,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${selectedFees.length} frais sélectionnés.'),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<String>(
                    valueListenable: methodNotifier,
                    builder: (context, selectedMethod, _) {
                      return DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: selectedMethod,
                        decoration: const InputDecoration(labelText: 'Méthode'),
                        items: _paymentMethodOptions
                            .map(
                              (item) => DropdownMenuItem<String>(
                                value: item,
                                child: Text(item),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value != null) {
                            methodNotifier.value = value;
                          }
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Montant par frais (optionnel)',
                      helperText: 'Laisser vide pour encaisser le solde complet de chaque frais.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: referenceController,
                    decoration: const InputDecoration(labelText: 'Référence (optionnel)'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Encaisser'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        return;
      }

      final fixedAmount = double.tryParse(
        amountController.text.trim().replaceAll(',', '.'),
      );
      if (amountController.text.trim().isNotEmpty && (fixedAmount == null || fixedAmount <= 0)) {
        _showMessage('Montant par frais invalide.');
        return;
      }

      setState(() => _financeBusy = true);
      final repo = ref.read(paymentsRepositoryProvider);
      final selectedMethod = methodNotifier.value;
      final reference = referenceController.text.trim();
      var created = 0;

      for (final fee in selectedFees) {
        final baseAmount = fixedAmount ?? fee.balance;
        final amount = baseAmount > fee.balance ? fee.balance : baseAmount;
        if (amount <= 0) {
          continue;
        }
        await repo.createPayment(
          feeId: fee.id,
          amount: amount,
          method: selectedMethod,
          reference: reference,
        );
        created += 1;
      }

      ref.invalidate(paymentsProvider);
      ref.invalidate(paymentsPaginatedProvider);
      ref.invalidate(feesProvider);

      setState(() {
        _selectedOutstandingFeeIds.clear();
      });

      _showMessage('Encaissement en lot terminé: $created paiement(s) créé(s).', isSuccess: true);
      await _refreshPayments();
    } catch (error) {
      _showMessage('Erreur encaissement en lot: ${_extractApiErrorMessage(error)}');
    } finally {
      if (mounted) {
        setState(() => _financeBusy = false);
      }
      methodNotifier.dispose();
      amountController.dispose();
      referenceController.dispose();
    }
  }

  String _formatMoney(num value) => montantEnFrancs(value);

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
                  pw.Text('Généré le : $generatedAt'),
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
        dialogTitle: 'Enregistrer le journal des dépenses',
        successMessage: 'Export CSV dépenses backend reussi.',
      );
      return;
    } catch (_) {
      if (rows.isEmpty) {
        _showMessage('Aucune dépense à exporter pour cette période.');
        return;
      }

      final csv = _buildExpensesCsv(rows);
      await _saveTextExport(
        content: csv,
        fileName: 'journal_depenses_${_periodCode(_financePeriod)}_${_timestampSuffix()}.csv',
        dialogTitle: 'Enregistrer le journal des dépenses',
        successMessage: 'Export CSV dépenses reussi (${rows.length} lignes).',
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
        dialogTitle: 'Exporter le journal des dépenses en PDF',
        successMessage: 'Export PDF dépenses backend reussi.',
      );
      return;
    } catch (_) {
      if (rows.isEmpty) {
        _showMessage('Aucune dépense à exporter en PDF pour cette période.');
        return;
      }

      final bytes = await _buildJournalPdf(
        title: 'Journal des dépenses',
        subtitle: 'Période ${_financePeriodLabel(_financePeriod).toLowerCase()} • ${rows.length} ligne(s)',
        summaryLines: [
          'Période: ${_financePeriodLabel(_financePeriod)}',
          'Dépenses: ${rows.length}',
          'Montant total: ${_formatMoney(rows.fold<double>(0, (sum, row) => sum + (double.tryParse(row['amount']?.toString() ?? '0') ?? 0)))}',
        ],
        headers: const ['Date', 'Libellé', 'Catégorie', 'Montant', 'Validation', 'Paye le'],
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
        dialogTitle: 'Exporter le journal des dépenses en PDF',
        successMessage: 'Export PDF dépenses reussi (${rows.length} lignes).',
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
        _showMessage('Aucun encaissement a exporter pour cette période.');
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
        _showMessage('Aucun encaissement a exporter en PDF pour cette période.');
        return;
      }

      final amountTotal = rows.fold<double>(0, (sum, payment) => sum + payment.amount);
      final bytes = await _buildJournalPdf(
        title: 'Journal des encaissements',
        subtitle: 'Période ${_financePeriodLabel(_financePeriod).toLowerCase()} • ${rows.length} ligne(s)',
        summaryLines: [
          'Période: ${_financePeriodLabel(_financePeriod)}',
          'Encaissements: ${rows.length}',
          'Montant total: ${_formatMoney(amountTotal)}',
        ],
        headers: const ['Date', 'Élève', 'Matricule', 'Type frais', 'Montant', 'Méthode', 'Référence'],
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

  String _classLabel(String raw) {
    final cleaned = raw.trim();
    return cleaned.isEmpty ? 'Sans classe' : cleaned;
  }

  DateTime? _parseDateOnly(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null) {
      return null;
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  List<_ClassKpiRow> _buildClassKpis(List<StudentFeeItem> fees) {
    final today = _dayStart(DateTime.now());
    final grouped = <String, List<StudentFeeItem>>{};
    for (final fee in fees) {
      final key = _classLabel(fee.classroomName);
      grouped.putIfAbsent(key, () => <StudentFeeItem>[]).add(fee);
    }

    final rows = <_ClassKpiRow>[];
    grouped.forEach((className, classFees) {
      var totalDue = 0.0;
      var totalOutstanding = 0.0;
      var overdueCount = 0;
      final studentKeys = <String>{};

      for (final fee in classFees) {
        totalDue += fee.amountDue;
        totalOutstanding += fee.balance;

        final dueDate = _parseDateOnly(fee.dueDate);
        if (fee.balance > 0 && dueDate != null && dueDate.isBefore(today)) {
          overdueCount += 1;
        }

        final matricule = fee.studentMatricule.trim();
        if (matricule.isNotEmpty) {
          studentKeys.add(matricule);
        } else {
          studentKeys.add('${fee.studentFullName}_${fee.id}');
        }
      }

      rows.add(
        _ClassKpiRow(
          className: className,
          feeCount: classFees.length,
          studentCount: studentKeys.length,
          overdueCount: overdueCount,
          totalDue: totalDue,
          totalPaid: totalDue - totalOutstanding,
          totalOutstanding: totalOutstanding,
        ),
      );
    });

    rows.sort((a, b) {
      final byOutstanding = b.totalOutstanding.compareTo(a.totalOutstanding);
      if (byOutstanding != 0) {
        return byOutstanding;
      }
      return a.className.compareTo(b.className);
    });
    return rows;
  }

  List<_LateFeeAlert> _buildLateFeeAlerts(List<StudentFeeItem> fees) {
    final today = _dayStart(DateTime.now());
    final alerts = <_LateFeeAlert>[];
    for (final fee in fees) {
      if (fee.balance <= 0) {
        continue;
      }
      final dueDate = _parseDateOnly(fee.dueDate);
      if (dueDate == null || !dueDate.isBefore(today)) {
        continue;
      }

      alerts.add(
        _LateFeeAlert(
          feeId: fee.id,
          className: _classLabel(fee.classroomName),
          studentFullName: fee.studentFullName,
          studentMatricule: fee.studentMatricule,
          feeType: fee.feeType,
          dueDateRaw: fee.dueDate,
          daysLate: today.difference(dueDate).inDays,
          balance: fee.balance,
        ),
      );
    }

    alerts.sort((a, b) {
      final byDays = b.daysLate.compareTo(a.daysLate);
      if (byDays != 0) {
        return byDays;
      }
      return b.balance.compareTo(a.balance);
    });
    return alerts;
  }

  List<_LateFeeAlert> _applyLateAlertThreshold(List<_LateFeeAlert> rows) {
    return rows.where((row) => row.daysLate >= _lateAlertMinDays).toList(growable: false);
  }

  String _buildLateAlertsCsv(List<_LateFeeAlert> rows) {
    final buffer = StringBuffer();
    buffer.writeln('fee_id,classe,eleve,matricule,type_frais,echeance,jours_retard,solde');

    for (final row in rows) {
      buffer.writeln(
        [
          _csvEscape(row.feeId.toString()),
          _csvEscape(row.className),
          _csvEscape(row.studentFullName),
          _csvEscape(row.studentMatricule),
          _csvEscape(row.feeType),
          _csvEscape(row.dueDateRaw),
          _csvEscape(row.daysLate.toString()),
          _csvEscape(row.balance.toStringAsFixed(0)),
        ].join(','),
      );
    }

    return buffer.toString();
  }

  String _buildClassReminderMessage({
    required String className,
    required List<_LateFeeAlert> alerts,
  }) {
    final buffer = StringBuffer();
    final total = alerts.fold<double>(0, (sum, row) => sum + row.balance);
    buffer.writeln('Objet: Relance paiement - Classe $className');
    buffer.writeln('');
    buffer.writeln('Bonjour,');
    buffer.writeln(
      'Merci de regulariser les frais en retard pour la classe $className. Montant total en attente: ${_formatMoney(total)}.',
    );
    buffer.writeln('');
    buffer.writeln('Détails prioritaires:');
    for (final alert in alerts.take(12)) {
      buffer.writeln(
        '- ${alert.studentFullName} (${alert.studentMatricule.isEmpty ? '-' : alert.studentMatricule}) | ${alert.feeType} | ${alert.daysLate} j de retard | ${_formatMoney(alert.balance)}',
      );
    }
    if (alerts.length > 12) {
      buffer.writeln('- ... et ${alerts.length - 12} autre(s) dossier(s).');
    }
    buffer.writeln('');
    buffer.writeln('Cordialement,');
    buffer.writeln('Service Finances');
    return buffer.toString();
  }

  List<_LateStudentSummary> _buildTopLateStudents(List<_LateFeeAlert> alerts) {
    final grouped = <String, _LateStudentSummary>{};
    for (final alert in alerts) {
      final key = alert.studentMatricule.trim().isEmpty
          ? '${alert.className}|${alert.studentFullName}'
          : alert.studentMatricule.trim();
      final previous = grouped[key];
      if (previous == null) {
        grouped[key] = _LateStudentSummary(
          studentKey: key,
          studentFullName: alert.studentFullName,
          studentMatricule: alert.studentMatricule,
          className: alert.className,
          lateFeesCount: 1,
          maxDaysLate: alert.daysLate,
          totalBalance: alert.balance,
        );
        continue;
      }
      grouped[key] = _LateStudentSummary(
        studentKey: key,
        studentFullName: previous.studentFullName,
        studentMatricule: previous.studentMatricule,
        className: previous.className,
        lateFeesCount: previous.lateFeesCount + 1,
        maxDaysLate: alert.daysLate > previous.maxDaysLate ? alert.daysLate : previous.maxDaysLate,
        totalBalance: previous.totalBalance + alert.balance,
      );
    }

    final rows = grouped.values.toList(growable: false);
    rows.sort((a, b) {
      final byDays = b.maxDaysLate.compareTo(a.maxDaysLate);
      if (byDays != 0) {
        return byDays;
      }
      return b.totalBalance.compareTo(a.totalBalance);
    });
    return rows;
  }

  _LateTrendMetrics _buildLateTrendMetrics(List<StudentFeeItem> fees) {
    final today = _dayStart(DateTime.now());

    var current7Count = 0;
    var previous7Count = 0;
    var current30Count = 0;
    var previous30Count = 0;
    var current7Amount = 0.0;
    var previous7Amount = 0.0;
    var current30Amount = 0.0;
    var previous30Amount = 0.0;

    for (final fee in fees) {
      if (fee.balance <= 0) {
        continue;
      }
      final dueDate = _parseDateOnly(fee.dueDate);
      if (dueDate == null || !dueDate.isBefore(today)) {
        continue;
      }

      final daysLate = today.difference(dueDate).inDays;

      if (daysLate <= 7) {
        current7Count += 1;
        current7Amount += fee.balance;
      } else if (daysLate <= 14) {
        previous7Count += 1;
        previous7Amount += fee.balance;
      }

      if (daysLate <= 30) {
        current30Count += 1;
        current30Amount += fee.balance;
      } else if (daysLate <= 60) {
        previous30Count += 1;
        previous30Amount += fee.balance;
      }
    }

    return _LateTrendMetrics(
      current7Count: current7Count,
      previous7Count: previous7Count,
      current30Count: current30Count,
      previous30Count: previous30Count,
      current7Amount: current7Amount,
      previous7Amount: previous7Amount,
      current30Amount: current30Amount,
      previous30Amount: previous30Amount,
    );
  }

  Future<void> _copyClassReminder({
    required String className,
    required List<_LateFeeAlert> alerts,
  }) async {
    final message = _buildClassReminderMessage(className: className, alerts: alerts);
    final total = alerts.fold<double>(0, (sum, row) => sum + row.balance);
    await Clipboard.setData(ClipboardData(text: message));
    _recordReminderHistory(
      action: 'Relance classe',
      scope: className,
      itemCount: alerts.length,
      totalAmount: total,
    );
    _showMessage(
      'Message de relance copie pour la classe $className (${alerts.length} dossier(s)).',
      isSuccess: true,
    );
  }

  void _recordReminderHistory({
    required String action,
    required String scope,
    required int itemCount,
    required double totalAmount,
  }) {
    setState(() {
      _reminderHistory.insert(
        0,
        _ReminderHistoryEntry(
          createdAt: DateTime.now(),
          action: action,
          scope: scope,
          itemCount: itemCount,
          totalAmount: totalAmount,
        ),
      );
      if (_reminderHistory.length > 30) {
        _reminderHistory.removeRange(30, _reminderHistory.length);
      }
      _reminderHistoryPage = 1;
    });
    unawaited(_persistReminderHistory());
  }

  String _reminderHistoryAsText([List<_ReminderHistoryEntry>? rows]) {
    final source = rows ?? _reminderHistory;
    if (source.isEmpty) {
      return 'Aucun historique de relance.';
    }
    final buffer = StringBuffer();
    for (final entry in source) {
      buffer.writeln(
        '${_formatDate(entry.createdAt.toIso8601String())} | ${entry.action} | ${entry.scope} | ${entry.itemCount} dossier(s) | ${_formatMoney(entry.totalAmount)}',
      );
    }
    return buffer.toString();
  }

  String _buildReminderHistoryCsv(List<_ReminderHistoryEntry> rows) {
    final buffer = StringBuffer();
    buffer.writeln('date,action,scope,nombre_dossiers,montant_total');
    for (final entry in rows) {
      buffer.writeln(
        [
          _csvEscape(entry.createdAt.toIso8601String()),
          _csvEscape(entry.action),
          _csvEscape(entry.scope),
          _csvEscape(entry.itemCount.toString()),
          _csvEscape(entry.totalAmount.toStringAsFixed(0)),
        ].join(','),
      );
    }
    return buffer.toString();
  }

  List<_ReminderHistoryEntry> _filteredReminderHistory() {
    final text = _reminderHistorySearchTerm.trim().toLowerCase();
    final rows = _reminderHistory.where((entry) {
      if (_reminderHistoryActionFilter != 'all' && entry.action != _reminderHistoryActionFilter) {
        return false;
      }
      if (!_matchesReminderPeriod(entry.createdAt)) {
        return false;
      }
      if (text.isEmpty) {
        return true;
      }
      return entry.action.toLowerCase().contains(text) || entry.scope.toLowerCase().contains(text);
    }).toList(growable: false);

    rows.sort((left, right) {
      switch (_reminderHistorySort) {
        case 'date_asc':
          return left.createdAt.compareTo(right.createdAt);
        case 'amount_desc':
          return right.totalAmount.compareTo(left.totalAmount);
        case 'amount_asc':
          return left.totalAmount.compareTo(right.totalAmount);
        case 'count_desc':
          return right.itemCount.compareTo(left.itemCount);
        case 'count_asc':
          return left.itemCount.compareTo(right.itemCount);
        case 'date_desc':
        default:
          return right.createdAt.compareTo(left.createdAt);
      }
    });

    return rows;
  }

  bool _matchesReminderPeriod(DateTime value) {
    if (_reminderHistoryPeriodFilter == 'all') {
      return true;
    }
    final now = _dayStart(DateTime.now());
    final target = _dayStart(value.toLocal());
    if (_reminderHistoryPeriodFilter == 'today') {
      return target == now;
    }
    if (_reminderHistoryPeriodFilter == '7d') {
      final start = now.subtract(const Duration(days: 6));
      return !target.isBefore(start) && !target.isAfter(now);
    }
    if (_reminderHistoryPeriodFilter == '30d') {
      final start = now.subtract(const Duration(days: 29));
      return !target.isBefore(start) && !target.isAfter(now);
    }
    return true;
  }

  String _reminderPeriodLabel(String value) {
    switch (value) {
      case 'today':
        return 'Aujourd\'hui';
      case '7d':
        return '7 jours';
      case '30d':
        return '30 jours';
      case 'all':
      default:
        return 'Tout';
    }
  }

  Map<String, List<_LateFeeAlert>> _groupLateAlertsByClass(List<_LateFeeAlert> alerts) {
    final grouped = <String, List<_LateFeeAlert>>{};
    for (final alert in alerts) {
      grouped.putIfAbsent(alert.className, () => <_LateFeeAlert>[]).add(alert);
    }
    final sortedKeys = grouped.keys.toList()..sort();
    final sorted = <String, List<_LateFeeAlert>>{};
    for (final key in sortedKeys) {
      final rows = grouped[key]!;
      rows.sort((a, b) {
        final byDays = b.daysLate.compareTo(a.daysLate);
        if (byDays != 0) {
          return byDays;
        }
        return b.balance.compareTo(a.balance);
      });
      sorted[key] = rows;
    }
    return sorted;
  }

  String _buildClassRemindersCsv(Map<String, List<_LateFeeAlert>> groupedAlerts) {
    final buffer = StringBuffer();
    buffer.writeln('classe,nb_alertes,montant_total,message_relance');
    groupedAlerts.forEach((className, alerts) {
      final total = alerts.fold<double>(0, (sum, row) => sum + row.balance);
      final message = _buildClassReminderMessage(className: className, alerts: alerts);
      buffer.writeln(
        [
          _csvEscape(className),
          _csvEscape(alerts.length.toString()),
          _csvEscape(total.toStringAsFixed(0)),
          _csvEscape(message),
        ].join(','),
      );
    });
    return buffer.toString();
  }

  Future<void> _copyGlobalReminders(Map<String, List<_LateFeeAlert>> groupedAlerts) async {
    final blocks = <String>[];
    var totalItems = 0;
    var totalAmount = 0.0;
    groupedAlerts.forEach((className, alerts) {
      blocks.add(_buildClassReminderMessage(className: className, alerts: alerts));
      totalItems += alerts.length;
      totalAmount += alerts.fold<double>(0, (sum, row) => sum + row.balance);
    });

    final message = blocks.join('\n\n------------------------------\n\n');
    await Clipboard.setData(ClipboardData(text: message));
    _recordReminderHistory(
      action: 'Relance globale',
      scope: '${groupedAlerts.length} classes',
      itemCount: totalItems,
      totalAmount: totalAmount,
    );
    _showMessage(
      'Relance globale copiée (${groupedAlerts.length} classe(s)).',
      isSuccess: true,
    );
  }

  void _selectLateAlertFee({
    required _LateFeeAlert alert,
    required List<StudentFeeItem> outstandingFees,
  }) {
    final index = outstandingFees.indexWhere((fee) => fee.id == alert.feeId);
    if (index < 0) {
      return;
    }

    final targetPage = (index ~/ _outstandingPageSize) + 1;
    setState(() {
      _selectedOutstandingFeeIds.add(alert.feeId);
      _outstandingExpanded = true;
      _outstandingPage = targetPage;
    });
  }

  Map<String, List<StudentFeeItem>> _groupOutstandingByClass(List<StudentFeeItem> fees) {
    final grouped = <String, List<StudentFeeItem>>{};
    for (final fee in fees) {
      final key = _classLabel(fee.classroomName);
      grouped.putIfAbsent(key, () => <StudentFeeItem>[]).add(fee);
    }
    final sortedKeys = grouped.keys.toList()..sort();
    final sorted = <String, List<StudentFeeItem>>{};
    for (final key in sortedKeys) {
      final rows = grouped[key]!;
      rows.sort((a, b) => a.studentFullName.compareTo(b.studentFullName));
      sorted[key] = rows;
    }
    return sorted;
  }

  Future<void> _handlePaymentRowAction({
    required _PaymentRowAction action,
    required PaymentItem payment,
    required List<StudentFeeItem> fees,
    required bool isMutating,
  }) async {
    switch (action) {
      case _PaymentRowAction.view:
        await _openPaymentDetails(payment);
        break;
      case _PaymentRowAction.edit:
        if (isMutating) return;
        await _openEditDialog(payment, fees);
        break;
      case _PaymentRowAction.print:
        try {
          await _printReceipt(payment.id);
        } catch (error) {
          _showMessage('Erreur génération PDF: $error');
        }
        break;
      case _PaymentRowAction.delete:
        if (isMutating) return;
        await _deletePayment(payment);
        break;
    }
  }

  Future<void> _openSelectedPaymentDrawer({
    required PaymentItem payment,
    required List<StudentFeeItem> fees,
    required bool isMutating,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reçu sélectionné',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                _detailRow('Élève', payment.studentFullName),
                _detailRow('Matricule', payment.studentMatricule),
                _detailRow('Classe', _classLabel(payment.classroomName)),
                _detailRow('Type frais', payment.feeType),
                _detailRow('Montant', _formatMoney(payment.amount)),
                _detailRow('Méthode', payment.method),
                _detailRow('Date', _formatDate(payment.createdAt)),
                _detailRow('Référence', payment.reference.isEmpty ? '-' : payment.reference),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await _openPaymentDetails(payment);
                      },
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Afficher'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: isMutating
                          ? null
                          : () async {
                              Navigator.of(context).pop();
                              await _openEditDialog(payment, fees);
                            },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Modifier'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        try {
                          await _printReceipt(payment.id);
                        } catch (error) {
                          _showMessage('Erreur génération PDF: $error');
                        }
                      },
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Imprimer'),
                    ),
                    FilledButton.icon(
                      onPressed: isMutating
                          ? null
                          : () async {
                              Navigator.of(context).pop();
                              await _deletePayment(payment);
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFB42318),
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Annuler paiement'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPaymentDetails(PaymentItem payment) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Détails paiement'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow('Élève', payment.studentFullName),
                _detailRow('Matricule', payment.studentMatricule),
                _detailRow('Type frais', payment.feeType),
                _detailRow('Montant', _formatMoney(payment.amount)),
                _detailRow('Méthode', payment.method),
                _detailRow(
                  'Référence',
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
                          labelText: 'Frais élève',
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
                        isExpanded: true,
                        initialValue: _paymentMethodOptions.contains(selectedMethod)
                            ? selectedMethod
                            : _paymentMethodOptions.first,
                        decoration: const InputDecoration(labelText: 'Méthode'),
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
                          labelText: 'Référence',
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
                            _showMessage('Sélectionnez un frais élève.');
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
                                  ? 'Erreur création paiement: ${mutation.error}'
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
            ? 'Paiement enregistré avec succès.'
            : 'Paiement modifié avec succès.',
        isSuccess: true,
      );
    }
  }

  Future<void> _openEditDialog(PaymentItem payment, List<StudentFeeItem> fees) {
    return _openPaymentDialog(payment: payment, fees: fees);
  }

  Future<void> _openCreatePaymentDialog() {
    return showGuidedPaymentEntryDialog(
      context: context,
      ref: ref,
      title: 'Fenetre flottante d\'encaissement',
    ).then((saved) {
      if (saved == true && mounted) {
        _showMessage('Paiement enregistré avec succès.', isSuccess: true);
      }
    });
  }

  Future<void> _deletePayment(PaymentItem payment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Annuler paiement'),
          content: Text(
            'Voulez-vous annuler le paiement #${payment.id} de ${_formatMoney(payment.amount)} ? Cette operation est tracée.',
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
              child: const Text('Annuler paiement'),
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
      _showMessage('Erreur annulation paiement: ${mutation.error}');
      return;
    }

    if (_selectedPaymentId == payment.id) {
      setState(() => _selectedPaymentId = null);
    }
    _showMessage('Paiement annulé avec succès.', isSuccess: true);
  }

  Widget _metricChip(String label, String value) =>
      IndicateurFinance(libelle: label, valeur: value);

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

  /// La paie horaire enseignants, avec sa double validation N1/N2.
  ///
  /// Extraite de l'arbre des finances eleves: le censeur, a qui la matrice
  /// confie la validation de niveau 1, et l'enseignant, a qui elle donne sa
  /// propre fiche, n'ont aucun droit sur les frais eleves. Tant que cette
  /// section vivait derriere leur chargement, ils tombaient sur « Impossible
  /// de charger les frais eleves » au lieu de la paie qu'ils viennent voir.
  List<Widget> _sectionPaieEnseignants({
    required BuildContext context,
    required ColorScheme colorScheme,
    required bool lectureSeule,
    required String? role,
  }) {
    return <Widget>[
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
              lectureSeule
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
                  onPressed: (lectureSeule || _financeBusy)
                      ? null
                      : _generateTeacherPayroll,
                  icon: const Icon(Icons.calculate_outlined),
                  label: const Text('Générer paie horaire'),
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
              const Text('Aucune paie horaire générée pour ce mois.')
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
                      final canL1 = (role == 'censor' || role == 'super_admin') &&
                        stage != 'level_two' &&
                        payrollId != null;
                    final canL2 = (role == 'accountant' || role == 'super_admin') &&
                        stage == 'level_one' &&
                        payrollId != null;
                    final canReset = role == 'super_admin' && payrollId != null;

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
    ];
  }

  /// L'ecran reduit a la paie, pour qui n'a pas les finances eleves.
  Widget _pagePaieSeule({
    required BuildContext context,
    required bool visible,
    required bool lectureSeule,
    required String? role,
  }) {
    if (!visible) {
      // Ni finances eleves ni paie: le menu n'aurait pas du ouvrir cette
      // entree. On le dit plutot que de laisser une page blanche.
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Aucune section des finances ne vous est ouverte.'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshPayments,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: _sectionPaieEnseignants(
          context: context,
          colorScheme: Theme.of(context).colorScheme,
          lectureSeule: lectureSeule,
          role: role,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(financeOpenGuidedPaymentIntentProvider, (previous, next) {
      if (next) {
        Future<void>.microtask(_consumeGuidedPaymentIntentIfNeeded);
      }
    });

    final authUser = ref.watch(authControllerProvider).value;
    final isTeacherFinanceVisible = _isTeacherFinanceVisible(authUser?.role);
    final isTeacherFinanceReadOnly = _isTeacherFinanceReadOnly(authUser?.role);
    final droits = ref.watch(currentPermissionsProvider);

    // Le censeur et l'enseignant entrent ici pour la paie, sans aucun droit sur
    // les finances eleves. Charger les frais leur vaudrait un refus du serveur
    // et l'ecran d'erreur qui va avec, a la place de ce qu'ils viennent faire.
    if (!droits.canRead('finance')) {
      return _pagePaieSeule(
        context: context,
        visible: isTeacherFinanceVisible,
        lectureSeule: isTeacherFinanceReadOnly,
        role: authUser?.role,
      );
    }

    // Le parent et l'eleve lisent leurs propres frais, pas la caisse de
    // l'ecole: la portee restreinte de leur droit est ce qui les separe du
    // reste du module.
    final laFamille = droits.of('finance').scoped;
    final peutVoirLesDepenses = !laFamille;

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
                      'Impossible de charger les frais élèves',
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
            final classKpiRows = _buildClassKpis(fees);
            final lateFeeAlerts = _buildLateFeeAlerts(fees);
            final filteredLateFeeAlerts = _applyLateAlertThreshold(lateFeeAlerts);
            final criticalLateAlerts = filteredLateFeeAlerts.where((row) => row.daysLate >= 15).length;
            final topLateStudents = _buildTopLateStudents(filteredLateFeeAlerts);
            final lateTrends = _buildLateTrendMetrics(fees);
            final classReminderGroups = _groupLateAlertsByClass(filteredLateFeeAlerts);
            final filteredReminderHistory = _filteredReminderHistory();
            final reminderActionOptions = <String>{'all', ..._reminderHistory.map((entry) => entry.action)}
              .toList()
              ..sort();
            final reminderPages = filteredReminderHistory.isEmpty
                ? 1
                : (filteredReminderHistory.length / _reminderHistoryPageSize).ceil();
            var safeReminderPage = _reminderHistoryPage;
            if (safeReminderPage > reminderPages) {
              safeReminderPage = reminderPages;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (_reminderHistoryPage != safeReminderPage) {
                  setState(() => _reminderHistoryPage = safeReminderPage);
                }
              });
            }
            if (safeReminderPage < 1) {
              safeReminderPage = 1;
            }
            final reminderStart = (safeReminderPage - 1) * _reminderHistoryPageSize;
            final reminderEnd = filteredReminderHistory.isEmpty
                ? 0
                : (reminderStart + _reminderHistoryPageSize).clamp(0, filteredReminderHistory.length);
            final visibleReminderHistory = filteredReminderHistory.isEmpty
                ? const <_ReminderHistoryEntry>[]
                : filteredReminderHistory.sublist(reminderStart, reminderEnd);
            final outstandingTotal = outstandingFees.fold<double>(
              0,
              (sum, fee) => sum + fee.balance,
            );
            final outstandingPages = outstandingFees.isEmpty
                ? 1
                : (outstandingFees.length / _outstandingPageSize).ceil();
            var safeOutstandingPage = _outstandingPage;
            if (safeOutstandingPage > outstandingPages) {
              safeOutstandingPage = outstandingPages;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (_outstandingPage != safeOutstandingPage) {
                  setState(() => _outstandingPage = safeOutstandingPage);
                }
              });
            }
            if (safeOutstandingPage < 1) {
              safeOutstandingPage = 1;
            }
            final outstandingStart = (safeOutstandingPage - 1) * _outstandingPageSize;
            final outstandingEnd = outstandingFees.isEmpty
                ? 0
                : (outstandingStart + _outstandingPageSize).clamp(0, outstandingFees.length);
            final visibleOutstandingFees = outstandingFees.isEmpty
                ? const <StudentFeeItem>[]
                : outstandingFees.sublist(outstandingStart, outstandingEnd);

            final methodOptions = <String>{'all'};
            for (final payment in payments) {
              if (payment.method.trim().isNotEmpty) {
                methodOptions.add(payment.method);
              }
            }

            // Les onglets ouverts a ce profil, dans l'ordre d'affichage.
            //
            // Les quatre metiers de cet ecran -- encaisser, relancer, depenser,
            // payer les enseignants -- etaient empiles dans une seule colonne
            // qu'il fallait parcourir du haut en bas. Le comptable qui encaisse
            // et le censeur qui valide la paie arrivaient au meme endroit, et
            // descendaient chacun chercher le sien.
            //
            // Meme patron que « Emargements »: un onglet ferme n'apparait pas,
            // et la barre disparait quand il n'en reste qu'un.
            final ongletsOuverts = <_OngletFinance>[
              // La famille ne gere pas la caisse: elle vient voir sa facture.
              // Un onglet, et rien d'autre.
              if (laFamille)
                _OngletFinance(
                  libelle: 'Mes frais',
                  icone: Icons.account_balance_wallet_outlined,
                  contenu: _ongletDefilant(
                    _sectionMesFrais(
                      context: context,
                      scheme: colorScheme,
                      fraisDus: outstandingFees,
                      reglements: visiblePayments,
                    ),
                  ),
                ),
              if (!laFamille)
              _OngletFinance(
                libelle: 'Encaissements',
                icone: Icons.point_of_sale_outlined,
                contenu: _ongletDefilant([
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
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _metricChip('Encaissements', '${periodPayments.length}'),
                                  _metricChip('Mode dominant', dominantMethodLabel),
                                  _metricChip('Frais impayés', '${outstandingFees.length}'),
                                  _metricChip('Montant affiché', _formatMoney(totalPaid)),
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
                                    child: Text('Aucun paiement correspondant a cette période.'),
                                  ),
                                )
                              else
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final compact = constraints.maxWidth < 1080;

                                    final paymentsTable = SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: DataTable(
                                        columns: [
                                          DataColumn(
                                            label: Checkbox(
                                              tristate: true,
                                              value: visiblePayments.isEmpty
                                                  ? false
                                                  : visiblePayments.every(
                                                      (p) => _selectedPaymentIds.contains(p.id),
                                                    )
                                                  ? true
                                                  : visiblePayments.any(
                                                      (p) => _selectedPaymentIds.contains(p.id),
                                                    )
                                                  ? null
                                                  : false,
                                              onChanged: (value) {
                                                setState(() {
                                                  if (value == true) {
                                                    _selectedPaymentIds.addAll(
                                                      visiblePayments.map((p) => p.id),
                                                    );
                                                  } else {
                                                    _selectedPaymentIds.removeAll(
                                                      visiblePayments.map((p) => p.id),
                                                    );
                                                  }
                                                });
                                              },
                                            ),
                                          ),
                                          const DataColumn(label: Text('Date')),
                                          const DataColumn(label: Text('Élève')),
                                          const DataColumn(label: Text('Classe')),
                                          const DataColumn(label: Text('Matricule')),
                                          const DataColumn(label: Text('Type frais')),
                                          const DataColumn(label: Text('Montant')),
                                          const DataColumn(label: Text('Méthode')),
                                          const DataColumn(label: Text('Actions')),
                                        ],
                                        rows: visiblePayments.map((payment) {
                                          final selected = payment.id == _selectedPaymentId;
                                          return DataRow(
                                            selected: selected,
                                            onSelectChanged: (_) {
                                              setState(() => _selectedPaymentId = payment.id);
                                            },
                                            cells: [
                                              DataCell(
                                                Checkbox(
                                                  value: _selectedPaymentIds.contains(payment.id),
                                                  onChanged: (value) {
                                                    setState(() {
                                                      if (value == true) {
                                                        _selectedPaymentIds.add(payment.id);
                                                      } else {
                                                        _selectedPaymentIds.remove(payment.id);
                                                      }
                                                    });
                                                  },
                                                ),
                                              ),
                                              DataCell(Text(_formatDate(payment.createdAt))),
                                              DataCell(Text(payment.studentFullName)),
                                              DataCell(Text(_classLabel(payment.classroomName))),
                                              DataCell(Text(payment.studentMatricule)),
                                              DataCell(Text(payment.feeType)),
                                              DataCell(Text(_formatMoney(payment.amount))),
                                              DataCell(_methodTag(context, payment.method)),
                                              DataCell(
                                                PopupMenuButton<_PaymentRowAction>(
                                                  tooltip: 'Actions',
                                                  onSelected: (action) {
                                                    _handlePaymentRowAction(
                                                      action: action,
                                                      payment: payment,
                                                      fees: fees,
                                                      isMutating: isMutating,
                                                    );
                                                  },
                                                  itemBuilder: (context) => const [
                                                    PopupMenuItem<_PaymentRowAction>(
                                                      value: _PaymentRowAction.view,
                                                      child: Text('Afficher'),
                                                    ),
                                                    PopupMenuItem<_PaymentRowAction>(
                                                      value: _PaymentRowAction.edit,
                                                      child: Text('Modifier'),
                                                    ),
                                                    PopupMenuItem<_PaymentRowAction>(
                                                      value: _PaymentRowAction.print,
                                                      child: Text('Imprimer reçu'),
                                                    ),
                                                    PopupMenuItem<_PaymentRowAction>(
                                                      value: _PaymentRowAction.delete,
                                                      child: Text('Annuler paiement'),
                                                    ),
                                                  ],
                                                  child: const Icon(Icons.more_vert),
                                                ),
                                              ),
                                            ],
                                          );
                                        }).toList(growable: false),
                                      ),
                                    );

                                    if (compact) {
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          if (selectedPayment != null)
                                            Padding(
                                              padding: const EdgeInsets.only(bottom: 8),
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: FilledButton.tonalIcon(
                                                  onPressed: () => _openSelectedPaymentDrawer(
                                                    payment: selectedPayment,
                                                    fees: fees,
                                                    isMutating: isMutating,
                                                  ),
                                                  icon: const Icon(Icons.receipt_long_outlined),
                                                  label: Text(
                                                    'Reçu sélectionné • ${selectedPayment.studentMatricule}',
                                                  ),
                                                ),
                                              ),
                                            ),
                                          _fichesReglements(
                                            reglements: visiblePayments,
                                            fees: fees,
                                            isMutating: isMutating,
                                          ),
                                        ],
                                      );
                                    }

                                    return Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: paymentsTable),
                                        const SizedBox(width: 12),
                                        SizedBox(
                                          width: 320,
                                          child: selectedPayment == null
                                              ? Card(
                                                  child: Padding(
                                                    padding: const EdgeInsets.all(12),
                                                    child: Text(
                                                      'Sélectionnez un encaissement pour afficher le détail.',
                                                      style: Theme.of(context).textTheme.bodyMedium,
                                                    ),
                                                  ),
                                                )
                                              : Card(
                                                  child: Padding(
                                                    padding: const EdgeInsets.all(12),
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          'Reçu sélectionné',
                                                          style: Theme.of(context).textTheme.titleSmall,
                                                        ),
                                                        const SizedBox(height: 8),
                                                        _detailRow('Élève', selectedPayment.studentFullName),
                                                        _detailRow('Matricule', selectedPayment.studentMatricule),
                                                        _detailRow('Classe', _classLabel(selectedPayment.classroomName)),
                                                        _detailRow('Type frais', selectedPayment.feeType),
                                                        _detailRow('Montant', _formatMoney(selectedPayment.amount)),
                                                        _detailRow('Méthode', selectedPayment.method),
                                                        _detailRow('Date', _formatDate(selectedPayment.createdAt)),
                                                        _detailRow(
                                                          'Référence',
                                                          selectedPayment.reference.isEmpty
                                                              ? '-'
                                                              : selectedPayment.reference,
                                                        ),
                                                        const SizedBox(height: 8),
                                                        Wrap(
                                                          spacing: 6,
                                                          runSpacing: 6,
                                                          children: [
                                                            FilledButton.tonalIcon(
                                                              onPressed: () => _openPaymentDetails(selectedPayment),
                                                              icon: const Icon(Icons.visibility_outlined),
                                                              label: const Text('Afficher'),
                                                            ),
                                                            FilledButton.tonalIcon(
                                                              onPressed: isMutating
                                                                  ? null
                                                                  : () => _openEditDialog(selectedPayment, fees),
                                                              icon: const Icon(Icons.edit_outlined),
                                                              label: const Text('Modifier'),
                                                            ),
                                                            FilledButton.tonalIcon(
                                                              onPressed: () async {
                                                                try {
                                                                  await _printReceipt(selectedPayment.id);
                                                                } catch (error) {
                                                                  _showMessage('Erreur génération PDF: $error');
                                                                }
                                                              },
                                                              icon: const Icon(Icons.picture_as_pdf_outlined),
                                                              label: const Text('Imprimer'),
                                                            ),
                                                            FilledButton.icon(
                                                              onPressed: isMutating
                                                                  ? null
                                                                  : () => _deletePayment(selectedPayment),
                                                              style: FilledButton.styleFrom(
                                                                backgroundColor: const Color(0xFFB42318),
                                                              ),
                                                              icon: const Icon(Icons.delete_outline),
                                                              label: const Text('Annuler paiement'),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      ],
                                    );
                                  },
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
                              const SizedBox(height: 2),
                            ],
                          ),
                        ),
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
                                  'Reçu sélectionné',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                _detailRow(
                                  'Paiement',
                                  '#${selectedPayment.id} • ${_formatMoney(selectedPayment.amount)}',
                                ),
                                _detailRow('Élève', selectedPayment.studentFullName),
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
                                      _showMessage('Erreur génération PDF: $error');
                                    }
                                  },
                                  icon: const Icon(Icons.picture_as_pdf_outlined),
                                  label: const Text('Imprimer le reçu PDF'),
                                ),
                              ],
                            ),
                          ),
                      ],
                ]),
              ),
              if (!laFamille)
              _OngletFinance(
                libelle: 'Impayés & relances',
                icone: Icons.notifications_active_outlined,
                contenu: _ongletDefilant([
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
                                'KPI par classe & alertes retard',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _metricChip('Classes suivies', '${classKpiRows.length}'),
                                  _metricChip('Alertes retard', '${filteredLateFeeAlerts.length}'),
                                  _metricChip('Retards critiques', '$criticalLateAlerts'),
                                ],
                              ),
                              const SizedBox(height: 8),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final compact = constraints.maxWidth < 860;
                                  final trendTile7 = Container(
                                    width: compact ? double.infinity : 260,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Tendance retard <= 7 jours',
                                          style: Theme.of(context).textTheme.labelLarge,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Actuel: ${lateTrends.current7Count} | Précédent: ${lateTrends.previous7Count}',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                        const SizedBox(height: 4),
                                        LinearProgressIndicator(
                                          value: (lateTrends.current7Count + lateTrends.previous7Count) == 0
                                              ? 0
                                              : lateTrends.current7Count /
                                                  (lateTrends.current7Count + lateTrends.previous7Count),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Montant actuel: ${_formatMoney(lateTrends.current7Amount)}',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  );
                                  final trendTile30 = Container(
                                    width: compact ? double.infinity : 260,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Tendance retard <= 30 jours',
                                          style: Theme.of(context).textTheme.labelLarge,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Actuel: ${lateTrends.current30Count} | Précédent: ${lateTrends.previous30Count}',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                        const SizedBox(height: 4),
                                        LinearProgressIndicator(
                                          value: (lateTrends.current30Count + lateTrends.previous30Count) == 0
                                              ? 0
                                              : lateTrends.current30Count /
                                                  (lateTrends.current30Count + lateTrends.previous30Count),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Montant actuel: ${_formatMoney(lateTrends.current30Amount)}',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  );
                                  return Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [trendTile7, trendTile30],
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  const Text('Seuil retard:'),
                                  DropdownButton<int>(
                                    value: _lateAlertMinDays,
                                    items: const [
                                      DropdownMenuItem(value: 1, child: Text('>= 1 jour')),
                                      DropdownMenuItem(value: 7, child: Text('>= 7 jours')),
                                      DropdownMenuItem(value: 15, child: Text('>= 15 jours')),
                                      DropdownMenuItem(value: 30, child: Text('>= 30 jours')),
                                    ],
                                    onChanged: (value) {
                                      if (value == null) {
                                        return;
                                      }
                                      setState(() => _lateAlertMinDays = value);
                                    },
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: filteredLateFeeAlerts.isEmpty
                                        ? null
                                        : () async {
                                            final csv = _buildLateAlertsCsv(filteredLateFeeAlerts);
                                            await _saveTextExport(
                                              content: csv,
                                              fileName:
                                                  'alertes_retard_${_lateAlertMinDays}j_${_timestampSuffix()}.csv',
                                              dialogTitle: 'Exporter les alertes retard',
                                              successMessage:
                                                  'Export CSV alertes retard reussi (${filteredLateFeeAlerts.length} lignes).',
                                            );
                                            final totalAmount = filteredLateFeeAlerts.fold<double>(
                                              0,
                                              (sum, row) => sum + row.balance,
                                            );
                                            _recordReminderHistory(
                                              action: 'Export alertes retard',
                                              scope: 'Seuil ${_lateAlertMinDays}j',
                                              itemCount: filteredLateFeeAlerts.length,
                                              totalAmount: totalAmount,
                                            );
                                          },
                                    icon: const Icon(Icons.download_outlined),
                                    label: const Text('Exporter alertes CSV'),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: classReminderGroups.isEmpty
                                        ? null
                                        : () => _copyGlobalReminders(classReminderGroups),
                                    icon: const Icon(Icons.campaign_outlined),
                                    label: const Text('Relance globale'),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: classReminderGroups.isEmpty
                                        ? null
                                        : () async {
                                            final totalAmount = classReminderGroups.values
                                                .expand((rows) => rows)
                                                .fold<double>(0, (sum, row) => sum + row.balance);
                                            final totalItems = classReminderGroups.values
                                                .fold<int>(0, (sum, rows) => sum + rows.length);
                                            final csv = _buildClassRemindersCsv(classReminderGroups);
                                            await _saveTextExport(
                                              content: csv,
                                              fileName:
                                                  'relances_classes_${_lateAlertMinDays}j_${_timestampSuffix()}.csv',
                                              dialogTitle: 'Exporter relances par classe',
                                              successMessage:
                                                  'Export CSV relances classes reussi (${classReminderGroups.length} classes).',
                                            );
                                            _recordReminderHistory(
                                              action: 'Export relances classes',
                                              scope: '${classReminderGroups.length} classes',
                                              itemCount: totalItems,
                                              totalAmount: totalAmount,
                                            );
                                          },
                                    icon: const Icon(Icons.file_download_outlined),
                                    label: const Text('Exporter relances classes'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(
                                    'Historique des relances',
                                    style: Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '(${filteredReminderHistory.length}/${_reminderHistory.length})',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: filteredReminderHistory.isEmpty
                                        ? null
                                        : () async {
                                            final text = _reminderHistoryAsText(filteredReminderHistory);
                                            await Clipboard.setData(ClipboardData(text: text));
                                            _showMessage('Historique copie dans le presse-papiers.', isSuccess: true);
                                          },
                                    icon: const Icon(Icons.copy_all_outlined, size: 16),
                                    label: const Text('Copier'),
                                  ),
                                  TextButton.icon(
                                    onPressed: filteredReminderHistory.isEmpty
                                        ? null
                                        : () async {
                                            final csv = _buildReminderHistoryCsv(filteredReminderHistory);
                                            await _saveTextExport(
                                              content: csv,
                                              fileName: 'historique_relances_${_timestampSuffix()}.csv',
                                              dialogTitle: 'Exporter historique des relances',
                                              successMessage:
                                                  'Export CSV historique relances reussi (${filteredReminderHistory.length} lignes).',
                                            );
                                            final totalAmount = filteredReminderHistory.fold<double>(
                                              0,
                                              (sum, entry) => sum + entry.totalAmount,
                                            );
                                            _recordReminderHistory(
                                              action: 'Export historique relances',
                                              scope:
                                                  'Filtre $_reminderHistoryActionFilter / ${_reminderPeriodLabel(_reminderHistoryPeriodFilter)} / tri $_reminderHistorySort',
                                              itemCount: filteredReminderHistory.length,
                                              totalAmount: totalAmount,
                                            );
                                          },
                                    icon: const Icon(Icons.download_outlined, size: 16),
                                    label: const Text('Exporter CSV'),
                                  ),
                                  TextButton.icon(
                                    onPressed: _reminderHistory.isEmpty
                                        ? null
                                        : () {
                                            setState(() {
                                              _reminderHistory.clear();
                                              _reminderHistoryPage = 1;
                                            });
                                            unawaited(_persistReminderHistory());
                                            _showMessage('Historique des relances vide.', isSuccess: true);
                                          },
                                    icon: const Icon(Icons.clear_all_outlined, size: 16),
                                    label: const Text('Vider'),
                                  ),
                                ],
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  SizedBox(
                                    width: 220,
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      initialValue: _reminderHistoryActionFilter,
                                      decoration: const InputDecoration(labelText: 'Filtrer action'),
                                      items: reminderActionOptions
                                          .map(
                                            (value) => DropdownMenuItem<String>(
                                              value: value,
                                              child: Text(value == 'all' ? 'Toutes' : value),
                                            ),
                                          )
                                          .toList(growable: false),
                                      onChanged: (value) {
                                        setState(() {
                                          _reminderHistoryActionFilter = value ?? 'all';
                                          _reminderHistoryPage = 1;
                                        });
                                      },
                                    ),
                                  ),
                                  SizedBox(
                                    width: 180,
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      initialValue: _reminderHistoryPeriodFilter,
                                      decoration: const InputDecoration(labelText: 'Période'),
                                      items: const ['all', 'today', '7d', '30d']
                                          .map(
                                            (value) => DropdownMenuItem<String>(
                                              value: value,
                                              child: Text(
                                                value == 'all'
                                                    ? 'Tout'
                                                    : value == 'today'
                                                    ? 'Aujourd\'hui'
                                                    : value == '7d'
                                                    ? '7 jours'
                                                    : '30 jours',
                                              ),
                                            ),
                                          )
                                          .toList(growable: false),
                                      onChanged: (value) {
                                        setState(() {
                                          _reminderHistoryPeriodFilter = value ?? 'all';
                                          _reminderHistoryPage = 1;
                                        });
                                      },
                                    ),
                                  ),
                                  SizedBox(
                                    width: 260,
                                    child: TextField(
                                      controller: _reminderHistorySearchController,
                                      decoration: const InputDecoration(
                                        labelText: 'Recherche classe/action',
                                        prefixIcon: Icon(Icons.search),
                                      ),
                                      onChanged: (value) {
                                        setState(() {
                                          _reminderHistorySearchTerm = value;
                                          _reminderHistoryPage = 1;
                                        });
                                      },
                                    ),
                                  ),
                                  SizedBox(
                                    width: 220,
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      initialValue: _reminderHistorySort,
                                      decoration: const InputDecoration(labelText: 'Tri'),
                                      items: const [
                                        DropdownMenuItem(value: 'date_desc', child: Text('Date décroissante')),
                                        DropdownMenuItem(value: 'date_asc', child: Text('Date croissante')),
                                        DropdownMenuItem(value: 'amount_desc', child: Text('Montant décroissant')),
                                        DropdownMenuItem(value: 'amount_asc', child: Text('Montant croissant')),
                                        DropdownMenuItem(value: 'count_desc', child: Text('Dossiers décroissants')),
                                        DropdownMenuItem(value: 'count_asc', child: Text('Dossiers croissants')),
                                      ],
                                      onChanged: (value) {
                                        setState(() {
                                          _reminderHistorySort = value ?? 'date_desc';
                                          _reminderHistoryPage = 1;
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              if (filteredReminderHistory.isEmpty)
                                const Text('Aucune action de relance enregistrée pour le moment.')
                              else
                                ...visibleReminderHistory.map((entry) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${_formatDate(entry.createdAt.toIso8601String())} • ${entry.action} • ${entry.scope}',
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${entry.itemCount} dossier(s) • ${_formatMoney(entry.totalAmount)}',
                                          style: Theme.of(context).textTheme.labelSmall,
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              if (filteredReminderHistory.isNotEmpty)
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
                                          value: _reminderHistoryPageSize,
                                          items: _reminderHistoryPageSizeOptions
                                              .map(
                                                (rows) => DropdownMenuItem<int>(
                                                  value: rows,
                                                  child: Text('$rows'),
                                                ),
                                              )
                                              .toList(growable: false),
                                          onChanged: (value) {
                                            if (value == null || value == _reminderHistoryPageSize) {
                                              return;
                                            }
                                            setState(() {
                                              _reminderHistoryPageSize = value;
                                              _reminderHistoryPage = 1;
                                            });
                                          },
                                        ),
                                        Text(
                                          'Affichage ${reminderStart + 1}-$reminderEnd sur ${filteredReminderHistory.length}',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        IconButton(
                                          tooltip: 'Page précédente',
                                          onPressed: safeReminderPage > 1
                                              ? () => setState(() => _reminderHistoryPage -= 1)
                                              : null,
                                          icon: const Icon(Icons.chevron_left),
                                        ),
                                        IconButton(
                                          tooltip: 'Page suivante',
                                          onPressed: safeReminderPage < reminderPages
                                              ? () => setState(() => _reminderHistoryPage += 1)
                                              : null,
                                          icon: const Icon(Icons.chevron_right),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 10),
                              if (classKpiRows.isEmpty)
                                const Text('Aucun frais disponible pour calculer les KPI.')
                              else
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    columns: const [
                                      DataColumn(label: Text('Classe')),
                                      DataColumn(label: Text('Élèves')),
                                      DataColumn(label: Text('Frais')),
                                      DataColumn(label: Text('Montant dû')),
                                      DataColumn(label: Text('Montant paye')),
                                      DataColumn(label: Text('Solde')),
                                      DataColumn(label: Text('Taux recouvrement')),
                                      DataColumn(label: Text('Retards')),
                                      DataColumn(label: Text('Relance')),
                                    ],
                                    rows: classKpiRows.take(15).map((row) {
                                      final isAlert = row.totalOutstanding > 0 && row.overdueCount > 0;
                                      final classAlerts = filteredLateFeeAlerts
                                          .where((item) => item.className == row.className)
                                          .toList(growable: false);
                                      return DataRow(
                                        color: isAlert
                                            ? WidgetStateProperty.resolveWith(
                                                (_) => const Color(0xFFFEEFE8),
                                              )
                                            : null,
                                        cells: [
                                          DataCell(Text(row.className)),
                                          DataCell(Text('${row.studentCount}')),
                                          DataCell(Text('${row.feeCount}')),
                                          DataCell(Text(_formatMoney(row.totalDue))),
                                          DataCell(Text(_formatMoney(row.totalPaid))),
                                          DataCell(Text(_formatMoney(row.totalOutstanding))),
                                          DataCell(Text('${(row.recoveryRate * 100).toStringAsFixed(1)} %')),
                                          DataCell(Text('${row.overdueCount}')),
                                          DataCell(
                                            classAlerts.isEmpty
                                                ? const Text('-')
                                                : OutlinedButton.icon(
                                                    onPressed: () => _copyClassReminder(
                                                      className: row.className,
                                                      alerts: classAlerts,
                                                    ),
                                                    icon: const Icon(Icons.content_copy, size: 16),
                                                    label: const Text('Relance'),
                                                  ),
                                          ),
                                        ],
                                      );
                                    }).toList(growable: false),
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Text(
                                'Top 10 élèves les plus en retard',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 6),
                              if (topLateStudents.isEmpty)
                                const Text('Aucun élève en retard sur le seuil sélectionné.')
                              else
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    columns: const [
                                      DataColumn(label: Text('Élève')),
                                      DataColumn(label: Text('Classe')),
                                      DataColumn(label: Text('Matricule')),
                                      DataColumn(label: Text('Frais en retard')),
                                      DataColumn(label: Text('Retard max')),
                                      DataColumn(label: Text('Solde total')),
                                    ],
                                    rows: topLateStudents.take(10).map((row) {
                                      return DataRow(
                                        cells: [
                                          DataCell(Text(row.studentFullName)),
                                          DataCell(Text(row.className)),
                                          DataCell(Text(row.studentMatricule.isEmpty ? '-' : row.studentMatricule)),
                                          DataCell(Text('${row.lateFeesCount}')),
                                          DataCell(Text('${row.maxDaysLate} j')),
                                          DataCell(Text(_formatMoney(row.totalBalance))),
                                        ],
                                      );
                                    }).toList(growable: false),
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Text(
                                'Top alertes retard',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 6),
                              if (filteredLateFeeAlerts.isEmpty)
                                const Text('Aucun retard de paiement détecté.')
                              else
                                ...filteredLateFeeAlerts.take(8).map((alert) {
                                  final dueDate = _parseDateOnly(alert.dueDateRaw);
                                  final dueLabel = dueDate == null
                                      ? (alert.dueDateRaw.isEmpty ? '-' : alert.dueDateRaw)
                                      : '${dueDate.day.toString().padLeft(2, '0')}/${dueDate.month.toString().padLeft(2, '0')}/${dueDate.year}';
                                  final severityColor = alert.daysLate >= 30
                                      ? const Color(0xFFB42318)
                                      : alert.daysLate >= 15
                                      ? const Color(0xFFB54708)
                                      : const Color(0xFF2D6FD6);
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: severityColor.withValues(alpha: 0.5)),
                                      color: severityColor.withValues(alpha: 0.08),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.warning_amber_rounded, color: severityColor, size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${alert.studentFullName} (${alert.studentMatricule.isEmpty ? '-' : alert.studentMatricule}) • ${alert.className}\n'
                                            '${alert.feeType} • Echéance: $dueLabel • Retard: ${alert.daysLate} j • Solde: ${_formatMoney(alert.balance)}',
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () => _selectLateAlertFee(
                                            alert: alert,
                                            outstandingFees: outstandingFees,
                                          ),
                                          child: const Text('Sélectionner'),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
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
                              ExpansionTile(
                                initiallyExpanded: _outstandingExpanded,
                                onExpansionChanged: (expanded) {
                                  setState(() => _outstandingExpanded = expanded);
                                },
                                tilePadding: EdgeInsets.zero,
                                title: Text(
                                  'Frais en attente • ${outstandingFees.length}',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                childrenPadding: const EdgeInsets.only(bottom: 4),
                                children: [
                                  if (outstandingFees.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 8),
                                      child: Text('Aucun solde restant.'),
                                    )
                                  else ...[
                                    Text(
                                      'Affichage ${outstandingStart + 1}-$outstandingEnd sur ${outstandingFees.length} frais en attente',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        FilledButton.tonalIcon(
                                          onPressed: (_financeBusy || _selectedOutstandingFeeIds.isEmpty)
                                              ? null
                                              : () => _collectSelectedFeesInBulk(outstandingFees),
                                          icon: const Icon(Icons.point_of_sale_outlined),
                                          label: Text(
                                            'Encaisser sélection (${_selectedOutstandingFeeIds.length})',
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: _selectedOutstandingFeeIds.isEmpty
                                              ? null
                                              : () {
                                                  setState(() => _selectedOutstandingFeeIds.clear());
                                                },
                                          icon: const Icon(Icons.clear_all),
                                          label: const Text('Vider la sélection'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    ..._groupOutstandingByClass(visibleOutstandingFees).entries.map((entry) {
                                      final className = entry.key;
                                      final classRows = entry.value;
                                      final expanded = _expandedOutstandingClasses.contains(className);
                                      final classFeeIds = classRows.map((row) => row.id).toList(growable: false);
                                      final allClassSelected = classFeeIds.isNotEmpty &&
                                          classFeeIds.every(_selectedOutstandingFeeIds.contains);
                                      final someClassSelected = classFeeIds.any(_selectedOutstandingFeeIds.contains);
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                                          ),
                                        ),
                                        child: ExpansionTile(
                                          initiallyExpanded: expanded,
                                          onExpansionChanged: (value) {
                                            setState(() {
                                              if (value) {
                                                _expandedOutstandingClasses.add(className);
                                              } else {
                                                _expandedOutstandingClasses.remove(className);
                                              }
                                            });
                                          },
                                          title: Row(
                                            children: [
                                              Checkbox(
                                                tristate: true,
                                                value: allClassSelected
                                                    ? true
                                                    : someClassSelected
                                                    ? null
                                                    : false,
                                                onChanged: (value) {
                                                  setState(() {
                                                    if (value == true) {
                                                      _selectedOutstandingFeeIds.addAll(classFeeIds);
                                                    } else {
                                                      _selectedOutstandingFeeIds.removeAll(classFeeIds);
                                                    }
                                                  });
                                                },
                                              ),
                                              Expanded(
                                                child: Text('Classe $className • ${classRows.length}'),
                                              ),
                                            ],
                                          ),
                                          children: [
                                            SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              child: DataTable(
                                                columns: const [
                                                  DataColumn(label: Text('Sel.')),
                                                  DataColumn(label: Text('Élève')),
                                                  DataColumn(label: Text('Matricule')),
                                                  DataColumn(label: Text('Type frais')),
                                                  DataColumn(label: Text('Montant dû')),
                                                  DataColumn(label: Text('Solde')),
                                                ],
                                                rows: classRows
                                                    .map(
                                                      (fee) => DataRow(
                                                        cells: [
                                                          DataCell(
                                                            Checkbox(
                                                              value: _selectedOutstandingFeeIds.contains(fee.id),
                                                              onChanged: (value) {
                                                                setState(() {
                                                                  if (value == true) {
                                                                    _selectedOutstandingFeeIds.add(fee.id);
                                                                  } else {
                                                                    _selectedOutstandingFeeIds.remove(fee.id);
                                                                  }
                                                                });
                                                              },
                                                            ),
                                                          ),
                                                          DataCell(Text(fee.studentFullName)),
                                                          DataCell(Text(fee.studentMatricule)),
                                                          DataCell(Text(fee.feeType)),
                                                          DataCell(Text(_formatMoney(fee.amountDue))),
                                                          DataCell(Text(_formatMoney(fee.balance))),
                                                        ],
                                                      ),
                                                    )
                                                    .toList(growable: false),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
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
                                              value: _outstandingPageSize,
                                              items: _outstandingPageSizeOptions
                                                  .map(
                                                    (rows) => DropdownMenuItem<int>(
                                                      value: rows,
                                                      child: Text('$rows'),
                                                    ),
                                                  )
                                                  .toList(growable: false),
                                              onChanged: (value) {
                                                if (value == null || value == _outstandingPageSize) {
                                                  return;
                                                }
                                                setState(() {
                                                  _outstandingPageSize = value;
                                                  _outstandingPage = 1;
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
                                              onPressed: safeOutstandingPage > 1
                                                  ? () => setState(() => _outstandingPage -= 1)
                                                  : null,
                                              icon: const Icon(Icons.chevron_left),
                                            ),
                                            IconButton(
                                              tooltip: 'Page suivante',
                                              onPressed: safeOutstandingPage < outstandingPages
                                                  ? () => setState(() => _outstandingPage += 1)
                                                  : null,
                                              icon: const Icon(Icons.chevron_right),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                ]),
              ),
              if (peutVoirLesDepenses)
                _OngletFinance(
                  libelle: 'Dépenses',
                  icone: Icons.receipt_long_outlined,
                  contenu: _ongletDefilant([
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
                                      isExpanded: true,
                                      initialValue: _financePeriod,
                                      decoration: const InputDecoration(labelText: 'Période'),
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
                                        label: const Text('Nouvelle dépense'),
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
                                        label: const Text('Actualiser dépenses'),
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
                                  _metricChip('Dépenses', '${periodExpenses.length}'),
                                  _metricChip('Brouillons', '$expenseDraftCount'),
                                  _metricChip('En attente N2', '$expensePendingLevelTwoCount'),
                                  _metricChip('Validées', '$expenseValidatedCount'),
                                  _metricChip('Montant total', _formatMoney(totalExpensesAmount)),
                                  _metricChip(
                                    'Dépenses validees',
                                    _formatMoney(periodValidatedExpensesAmount),
                                  ),
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
                                        final canL1 = (authUser?.role == 'censor' || authUser?.role == 'super_admin') &&
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
                  ]),
                ),
              if (isTeacherFinanceVisible)
                _OngletFinance(
                  libelle: 'Paie enseignants',
                  icone: Icons.payments_outlined,
                  contenu: _ongletDefilant(
                    _sectionPaieEnseignants(
                      context: context,
                      colorScheme: colorScheme,
                      lectureSeule: isTeacherFinanceReadOnly,
                      role: authUser?.role,
                    ),
                  ),
                ),
            ];
            final controleurOnglets = _controleurDOnglets(ongletsOuverts.length);


            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 940;
                      final searchField = SizedBox(
                        width: compact ? double.infinity : 270,
                        child: TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            labelText: 'Rechercher un règlement',
                            // Une barre qui annonce « Recherche » ne dit pas
                            // qu'un matricule ou une référence de reçu
                            // suffisent aussi.
                            hintText: 'Nom, matricule ou référence',
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
                          isExpanded: true,
                          initialValue: _methodFilter,
                          decoration: const InputDecoration(
                            labelText: 'Filtrer par méthode',
                          ),
                          items: methodOptions
                              .map(
                                (method) => DropdownMenuItem<String>(
                                  value: method,
                                  child: Text(
                                    method == 'all' ? 'Toutes les méthodes' : method,
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
                          isExpanded: true,
                          initialValue: _financePeriod,
                          decoration: const InputDecoration(labelText: 'Période'),
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
                            onPressed: isMutating ? null : _openCreatePaymentDialog,
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
                          FilledButton.tonalIcon(
                            onPressed: (isMutating || _selectedPaymentIds.isEmpty)
                                ? null
                                : _printMultipleReceipts,
                            icon: const Icon(Icons.print_outlined),
                            label: Text('Imprimer sélection (${_selectedPaymentIds.length})'),
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
                                      _financePeriod = _FinancePeriod.all;
                                      _selectedPaymentIds.clear();
                                      _selectedOutstandingFeeIds.clear();
                                    });
                                  },
                            icon: const Icon(Icons.filter_alt_off_outlined),
                            label: const Text('Réinitialiser'),
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
                ),
                // L'etat de la caisse, au meme endroit quel que soit l'onglet.
                //
                // Ces chiffres etaient disperses dans quatre blocs, a des
                // hauteurs de page differentes -- deux d'entre eux portaient
                // meme deux noms selon l'endroit. Les remonter ici les rend
                // lisibles d'un coup d'oeil, et le detail reste dans son
                // onglet.
                _ligneDeSynthese(
                  scheme: colorScheme,
                  encaisse: periodIncomeAmount,
                  impayes: outstandingTotal,
                  tresorerie: peutVoirLesDepenses ? periodNetTreasury : null,
                ),
                // La barre ne sert a rien devant un seul onglet: le profil
                // qui n'en ouvre qu'un y est deja.
                if (ongletsOuverts.length > 1)
                  Material(
                    color: colorScheme.surface,
                    child: TabBar(
                      controller: controleurOnglets,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: [
                        for (final onglet in ongletsOuverts)
                          Tab(
                            icon: Icon(onglet.icone, size: 19),
                            text: onglet.libelle,
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: controleurOnglets,
                    children: [
                      for (final onglet in ongletsOuverts) onglet.contenu,
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Un onglet du module Finances: son nom, son icone, ce qu'il montre.
class _OngletFinance {
  final String libelle;
  final IconData icone;
  final Widget contenu;

  const _OngletFinance({
    required this.libelle,
    required this.icone,
    required this.contenu,
  });
}

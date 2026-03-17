import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../domain/payment.dart';
import '../domain/student_fee.dart';
import 'payments_controller.dart';

class PaymentsPage extends ConsumerStatefulWidget {
  const PaymentsPage({super.key});

  @override
  ConsumerState<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends ConsumerState<PaymentsPage> {
  final _formKey = GlobalKey<FormState>();
  final _searchController = TextEditingController();
  final _amountController = TextEditingController();
  final _methodController = TextEditingController(text: 'Especes');
  final _referenceController = TextEditingController();

  int? _selectedFeeId;
  int? _selectedPaymentId;
  String _methodFilter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    _amountController.dispose();
    _methodController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _refreshPayments() async {
    ref.invalidate(paymentsProvider);
    ref.invalidate(feesProvider);
    try {
      await Future.wait([
        ref.read(paymentsProvider.future),
        ref.read(feesProvider.future),
      ]);
    } catch (_) {
      // Keep pull-to-refresh responsive even when API is temporarily unavailable.
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

  List<PaymentItem> _filteredPayments(List<PaymentItem> payments) {
    final query = _searchController.text.trim().toLowerCase();

    final rows = payments.where((payment) {
      if (_methodFilter != 'all' && payment.method != _methodFilter) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final haystack =
          '${payment.studentFullName} ${payment.studentMatricule} ${payment.method} ${payment.feeType} ${payment.reference}'
              .toLowerCase();
      return haystack.contains(query);
    }).toList();

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

  Future<void> _createPayment() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final feeId = _selectedFeeId;
    if (feeId == null) {
      _showMessage('Selectionnez un frais eleve.');
      return;
    }

    await ref
        .read(paymentMutationProvider.notifier)
        .createPayment(
          feeId: feeId,
          amount: double.parse(_amountController.text.trim()),
          method: _methodController.text.trim(),
          reference: _referenceController.text.trim(),
        );

    final mutation = ref.read(paymentMutationProvider);
    if (mutation.hasError) {
      _showMessage('Erreur creation paiement: ${mutation.error}');
      return;
    }

    _amountController.clear();
    _referenceController.clear();
    _showMessage('Paiement enregistre avec succes.', isSuccess: true);
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

  Future<void> _openEditDialog(
    PaymentItem payment,
    List<StudentFeeItem> fees,
  ) async {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController(
      text: payment.amount.toStringAsFixed(0),
    );
    final methodController = TextEditingController(text: payment.method);
    final referenceController = TextEditingController(text: payment.reference);

    var editFeeId = payment.feeId;
    var saving = false;

    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Modifier paiement'),
              content: SizedBox(
                width: 460,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: editFeeId,
                        decoration: const InputDecoration(
                          labelText: 'Frais eleve',
                        ),
                        items: fees
                            .map(
                              (fee) => DropdownMenuItem<int>(
                                value: fee.id,
                                child: Text(_feeLabel(fee)),
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
                      TextFormField(
                        controller: methodController,
                        decoration: const InputDecoration(labelText: 'Methode'),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Champ requis'
                            : null,
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

                          setDialogState(() => saving = true);

                          await ref
                              .read(paymentMutationProvider.notifier)
                              .updatePayment(
                                paymentId: payment.id,
                                feeId: editFeeId,
                                amount: double.parse(amountController.text),
                                method: methodController.text.trim(),
                                reference: referenceController.text.trim(),
                              );

                          final mutation = ref.read(paymentMutationProvider);
                          if (mutation.hasError) {
                            _showMessage(
                              'Erreur modification paiement: ${mutation.error}',
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
    methodController.dispose();
    referenceController.dispose();

    if (updated == true) {
      _showMessage('Paiement modifie avec succes.', isSuccess: true);
    }
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
    final paymentsAsync = ref.watch(paymentsProvider);
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
          data: (payments) {
            final filteredPayments = _filteredPayments(payments);
            _syncSelectedPayment(filteredPayments);
            final selectedPayment = _selectedPayment(filteredPayments);

            final totalPaid = payments.fold<double>(
              0,
              (sum, payment) => sum + payment.amount,
            );
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
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.55,
                        ),
                      ),
                    ),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _metricChip('Paiements', '${payments.length}'),
                        _metricChip(
                          'Montant encaisse',
                          _formatMoney(totalPaid),
                        ),
                        _metricChip(
                          'Frais impayes',
                          '${outstandingFees.length}',
                        ),
                        _metricChip(
                          'Solde restant',
                          _formatMoney(outstandingTotal),
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
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 290,
                          child: TextField(
                            controller: _searchController,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Recherche paiement',
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
                          width: 240,
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
                                .toList(),
                            onChanged: (value) {
                              setState(() => _methodFilter = value ?? 'all');
                            },
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: isMutating
                              ? null
                              : () {
                                  _searchController.clear();
                                  setState(() => _methodFilter = 'all');
                                },
                          icon: const Icon(Icons.filter_alt_off_outlined),
                          label: const Text('Reinitialiser'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 1120;

                      final historyPanel = Container(
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
                              'Historique paiements (${filteredPayments.length})',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            if (filteredPayments.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 18),
                                child: Center(
                                  child: Text('Aucun paiement correspondant.'),
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: filteredPayments.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final payment = filteredPayments[index];
                                  final selected =
                                      payment.id == _selectedPaymentId;

                                  return Material(
                                    color: selected
                                        ? colorScheme.primary.withValues(
                                            alpha: 0.12,
                                          )
                                        : colorScheme.surface,
                                    borderRadius: BorderRadius.circular(10),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () {
                                        setState(
                                          () => _selectedPaymentId = payment.id,
                                        );
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
                                            const CircleAvatar(
                                              radius: 18,
                                              child: Icon(
                                                Icons.receipt_long_outlined,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    payment.studentFullName,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.titleSmall,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${payment.studentMatricule} • ${payment.feeType}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.bodySmall,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  _formatMoney(payment.amount),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                ),
                                                const SizedBox(height: 2),
                                                _methodTag(
                                                  context,
                                                  payment.method,
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 4),
                                            PopupMenuButton<String>(
                                              tooltip: 'Actions paiement',
                                              onSelected: (value) async {
                                                if (value == 'view') {
                                                  await _openPaymentDetails(
                                                    payment,
                                                  );
                                                  return;
                                                }
                                                if (value == 'edit') {
                                                  await _openEditDialog(
                                                    payment,
                                                    fees,
                                                  );
                                                  return;
                                                }
                                                if (value == 'print') {
                                                  try {
                                                    await _printReceipt(
                                                      payment.id,
                                                    );
                                                  } catch (error) {
                                                    _showMessage(
                                                      'Erreur generation PDF: $error',
                                                    );
                                                  }
                                                  return;
                                                }
                                                if (value == 'delete') {
                                                  await _deletePayment(payment);
                                                }
                                              },
                                              itemBuilder: (_) => const [
                                                PopupMenuItem<String>(
                                                  value: 'view',
                                                  child: Text('Afficher'),
                                                ),
                                                PopupMenuItem<String>(
                                                  value: 'edit',
                                                  child: Text('Modifier'),
                                                ),
                                                PopupMenuItem<String>(
                                                  value: 'print',
                                                  child: Text('Imprimer recu'),
                                                ),
                                                PopupMenuItem<String>(
                                                  value: 'delete',
                                                  child: Text('Supprimer'),
                                                ),
                                              ],
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
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Detail paiement',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            if (selectedPayment == null)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 18),
                                child: Text(
                                  'Selectionnez un paiement a gauche.',
                                ),
                              )
                            else ...[
                              Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                children: [
                                  _metricChip(
                                    'Eleve',
                                    selectedPayment.studentFullName,
                                  ),
                                  _metricChip(
                                    'Matricule',
                                    selectedPayment.studentMatricule,
                                  ),
                                  _metricChip(
                                    'Type frais',
                                    selectedPayment.feeType,
                                  ),
                                  _metricChip(
                                    'Montant',
                                    _formatMoney(selectedPayment.amount),
                                  ),
                                  _metricChip(
                                    'Methode',
                                    selectedPayment.method,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed: () =>
                                        _openPaymentDetails(selectedPayment),
                                    icon: const Icon(Icons.visibility_outlined),
                                    label: const Text('Afficher'),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: isMutating
                                        ? null
                                        : () => _openEditDialog(
                                            selectedPayment,
                                            fees,
                                          ),
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Modifier'),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: () async {
                                      try {
                                        await _printReceipt(selectedPayment.id);
                                      } catch (error) {
                                        _showMessage(
                                          'Erreur generation PDF: $error',
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.picture_as_pdf),
                                    label: const Text('Imprimer recu'),
                                  ),
                                  FilledButton.icon(
                                    onPressed: isMutating
                                        ? null
                                        : () => _deletePayment(selectedPayment),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFFB42318),
                                    ),
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Supprimer'),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            Divider(color: colorScheme.outlineVariant),
                            const SizedBox(height: 10),
                            Text(
                              'Nouveau paiement',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      SizedBox(
                                        width: 360,
                                        child: DropdownButtonFormField<int>(
                                          initialValue: _selectedFeeId,
                                          decoration: const InputDecoration(
                                            labelText: 'Frais eleve',
                                          ),
                                          items: fees
                                              .map(
                                                (fee) => DropdownMenuItem<int>(
                                                  value: fee.id,
                                                  child: Text(_feeLabel(fee)),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (value) => setState(
                                            () => _selectedFeeId = value,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 150,
                                        child: TextFormField(
                                          controller: _amountController,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: const InputDecoration(
                                            labelText: 'Montant',
                                          ),
                                          validator: (value) {
                                            final parsed = double.tryParse(
                                              value ?? '',
                                            );
                                            if (parsed == null || parsed <= 0) {
                                              return 'Montant invalide';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                      SizedBox(
                                        width: 170,
                                        child: TextFormField(
                                          controller: _methodController,
                                          decoration: const InputDecoration(
                                            labelText: 'Methode',
                                          ),
                                          validator: (value) =>
                                              (value == null ||
                                                  value.trim().isEmpty)
                                              ? 'Champ requis'
                                              : null,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 190,
                                        child: TextFormField(
                                          controller: _referenceController,
                                          decoration: const InputDecoration(
                                            labelText: 'Reference',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                    onPressed: isMutating
                                        ? null
                                        : _createPayment,
                                    icon: isMutating
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.add_card_outlined),
                                    label: const Text('Enregistrer paiement'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );

                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 6, child: historyPanel),
                            const SizedBox(width: 12),
                            Expanded(flex: 5, child: detailsPanel),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          historyPanel,
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

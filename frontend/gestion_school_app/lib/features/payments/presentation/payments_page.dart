import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../domain/student_fee.dart';
import 'payments_controller.dart';

class PaymentsPage extends ConsumerStatefulWidget {
  const PaymentsPage({super.key});

  @override
  ConsumerState<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends ConsumerState<PaymentsPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _methodController = TextEditingController(text: 'Espèces');
  final _referenceController = TextEditingController();
  int? _selectedFeeId;

  @override
  void dispose() {
    _amountController.dispose();
    _methodController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _printReceipt(int paymentId) async {
    final repo = ref.read(paymentsRepositoryProvider);
    final bytes = await repo.fetchReceiptPdf(paymentId);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  @override
  Widget build(BuildContext context) {
    final paymentsAsync = ref.watch(paymentsProvider);
    final feesAsync = ref.watch(feesProvider);
    final mutationState = ref.watch(paymentMutationProvider);

    ref.listen<AsyncValue<void>>(paymentMutationProvider, (prev, next) {
      if (prev?.isLoading == true && !next.isLoading && mounted) {
        if (next.hasError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur création paiement: ${next.error}')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Paiement enregistré avec succès')),
          );
          _amountController.clear();
          _referenceController.clear();
        }
      }
    });

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Paiements & Facturation',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Enregistrez les règlements et générez les reçus PDF.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Nouveau paiement'),
                    const SizedBox(height: 12),
                    feesAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (error, _) => Text('Erreur frais: $error'),
                      data: (fees) {
                        if (fees.isEmpty) {
                          return const Text('Aucun frais disponible');
                        }
                        _selectedFeeId ??= fees.first.id;
                        return DropdownButtonFormField<int>(
                          initialValue: _selectedFeeId,
                          items: fees
                              .map(
                                (fee) => DropdownMenuItem<int>(
                                  value: fee.id,
                                  child: Text(_feeLabel(fee)),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _selectedFeeId = value),
                          decoration: const InputDecoration(
                            labelText: 'Frais élève',
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _amountController,
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
                      controller: _methodController,
                      decoration: const InputDecoration(
                        labelText: 'Méthode (Espèces, Mobile Money...)',
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'Champ requis'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _referenceController,
                      decoration: const InputDecoration(labelText: 'Référence'),
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: mutationState.isLoading
                          ? null
                          : () async {
                              if (!_formKey.currentState!.validate()) {
                                return;
                              }
                              final feeId = _selectedFeeId;
                              if (feeId == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Sélectionnez un frais'),
                                  ),
                                );
                                return;
                              }

                              await ref
                                  .read(paymentMutationProvider.notifier)
                                  .createPayment(
                                    feeId: feeId,
                                    amount: double.parse(
                                      _amountController.text.trim(),
                                    ),
                                    method: _methodController.text.trim(),
                                    reference: _referenceController.text.trim(),
                                  );
                            },
                      child: mutationState.isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Enregistrer le paiement'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Historique des paiements',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  paymentsAsync.when(
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (error, _) => Text('Erreur paiements: $error'),
                    data: (payments) {
                      if (payments.isEmpty) {
                        return const Text('Aucun paiement trouvé');
                      }
                      return Column(
                        children: payments
                            .map(
                              (payment) => Card(
                                child: ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.receipt_long_outlined),
                                  ),
                                  title: Text(
                                    '${payment.studentFullName} (${payment.studentMatricule})',
                                  ),
                                  subtitle: Text(
                                    '${payment.feeType} • ${payment.amount.toStringAsFixed(0)} FCFA • ${payment.method}',
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Imprimer reçu PDF',
                                    icon: const Icon(Icons.picture_as_pdf),
                                    onPressed: () async {
                                      try {
                                        await _printReceipt(payment.id);
                                      } catch (error) {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text('Erreur PDF: $error'),
                                          ),
                                        );
                                      }
                                    },
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
            ),
          ),
        ],
      ),
    );
  }

  String _feeLabel(StudentFeeItem fee) {
    return '#${fee.id} • ${fee.studentFullName} (${fee.studentMatricule}) • ${fee.feeType} • Solde ${fee.balance.toStringAsFixed(0)}';
  }
}

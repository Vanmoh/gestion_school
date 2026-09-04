part of 'payments_page.dart';

/// L'onglet des dépenses: ce qui sort de la caisse, et la trésorerie qui en
/// résulte.
///
/// Il vivait dans le `build`, qui atteignait mille neuf cents lignes depuis
/// que les quatre onglets y étaient construits en ligne. Contrairement aux
/// dialogues déplacés ailleurs, un onglet lit des chiffres calculés par le
/// `build`: ils lui sont passés explicitement, ce qui dit noir sur blanc ce
/// dont il dépend.
extension _OngletDesDepenses on _PaymentsPageState {
  List<Widget> ongletDesDepenses({
    required AuthUser? authUser,
    required ColorScheme colorScheme,
    required List<Map<String, dynamic>> periodExpenses,
    required int expenseDraftCount,
    required int expensePendingLevelTwoCount,
    required int expenseValidatedCount,
    required double totalExpensesAmount,
    required double periodValidatedExpensesAmount,
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
                      majEtat(() => _financePeriod = value);
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
                    if (_peutExporter) ...[
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
                    ],
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
              TableauOuFiches(
                colonnesSansLibelle: const {6},
                colonnes: const [
                  DataColumn(label: Text('Libellé')),
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Catégorie')),
                  DataColumn(label: Text('Montant')),
                  DataColumn(label: Text('Validation')),
                  DataColumn(label: Text('Paiement')),
                  DataColumn(label: Text('Actions')),
                ],
                lignes: periodExpenses.map((row) {
                  final expenseId = (row['id'] as num?)?.toInt();
                  final stage = (row['validation_stage'] ?? '').toString();
                  // Qui signe a quel niveau vient de la matrice, pas d'une
                  // liste de roles recopiee ici: elle disait la meme chose
                  // que le serveur, et rien ne garantissait qu'elle continue.
                  final canL1 = _peutValiderNiveau1 &&
                      stage != 'level_two' &&
                      expenseId != null;
                  final canL2 = _peutValiderNiveau2 &&
                      stage == 'level_one' &&
                      expenseId != null;
                  final canReset = _peutAnnulerValidationDepense && expenseId != null;
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
          ],
        ),
      ),
    ];
  }
}

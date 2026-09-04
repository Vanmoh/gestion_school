part of 'payments_page.dart';

/// L'onglet des encaissements: le journal des règlements, ses filtres, ses
/// exports, et le détail du reçu choisi.
///
/// C'est l'onglet d'accueil du module, celui qu'ouvre le comptable pour
/// encaisser. Il est sorti du `build` comme les autres, et les chiffres que la
/// page calcule lui sont passés explicitement.
extension _OngletDesEncaissements on _PaymentsPageState {
  List<Widget> ongletDesEncaissements({
    required ColorScheme colorScheme,
    required List<PaymentItem> payments,
    required List<PaymentItem> visiblePayments,
    required List<PaymentItem> periodPayments,
    required PaymentItem? selectedPayment,
    required List<StudentFeeItem> outstandingFees,
    required List<StudentFeeItem> fees,
    required double totalPaid,
    required String dominantMethodLabel,
    required bool isMutating,
    required PaginatedResult<PaymentItem> pageData,
  }) {
    return <Widget>[
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
                                majEtat(() {
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
                              majEtat(() => _selectedPaymentId = payment.id);
                            },
                            cells: [
                              DataCell(
                                Checkbox(
                                  value: _selectedPaymentIds.contains(payment.id),
                                  onChanged: (value) {
                                    majEtat(() {
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
                        items: _PaymentsPageState._pageSizeOptions
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
                          majEtat(() {
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
                            ? () => majEtat(() => _currentPage -= 1)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        tooltip: 'Page suivante',
                        onPressed: pageData.hasNext
                            ? () => majEtat(() => _currentPage += 1)
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
    ];
  }
}

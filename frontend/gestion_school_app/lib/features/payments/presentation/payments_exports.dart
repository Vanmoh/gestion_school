part of 'payments_page.dart';

/// Sortir les écritures de l'application: journal des encaissements et des
/// dépenses, en tableur ou en PDF.
///
/// Quatre cents lignes qui ne décident rien — elles mettent en forme ce que
/// la page a déjà chargé — mais qui portent tout ce qui se retrouve entre les
/// mains d'un contrôleur ou d'un commissaire aux comptes. Les tenir à part
/// permet de relire le format d'un export sans traverser la caisse.
extension _Exports on _PaymentsPageState {
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
}

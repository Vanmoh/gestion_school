import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

/// Le document tel qu'il sortira de l'imprimante.
///
/// La fenetre precedente montre les donnees; celle-ci montre la mise en page:
/// en-tete de l'etablissement, effectifs, et la colonne d'emargement qui
/// n'existe que sur le papier. Verifier avant d'engager une rame.
class RosterPdfPreviewDialog extends StatefulWidget {
  final String titre;
  final String nomFichier;
  final Future<Uint8List> Function() charger;

  const RosterPdfPreviewDialog({
    super.key,
    required this.titre,
    required this.nomFichier,
    required this.charger,
  });

  @override
  State<RosterPdfPreviewDialog> createState() => _RosterPdfPreviewDialogState();
}

class _RosterPdfPreviewDialogState extends State<RosterPdfPreviewDialog> {
  Uint8List? _bytes;
  bool _busy = false;

  /// Le document est monte par le serveur: le redemander a chaque changement
  /// de format d'apercu ferait autant d'allers-retours pour un resultat
  /// identique.
  Future<Uint8List> _document(PdfPageFormat _) async {
    final cache = _bytes;
    if (cache != null) return cache;
    final bytes = await widget.charger();
    _bytes = bytes;
    return bytes;
  }

  Future<void> _withBusy(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        final scheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : $error'),
            backgroundColor: scheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _telecharger() => _withBusy(() async {
    final bytes = _bytes ?? await widget.charger();
    await Printing.sharePdf(bytes: bytes, filename: widget.nomFichier);
  });

  Future<void> _imprimer() => _withBusy(() async {
    final bytes = _bytes ?? await widget.charger();
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 820),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Icon(Icons.description_outlined, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.titre,
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: PdfPreview(
                build: _document,
                // Barre d'actions integree remplacee par des boutons libelles:
                // ses icones seules laissent deviner ce qu'elles font.
                useActions: false,
                canChangePageFormat: false,
                canChangeOrientation: false,
                canDebug: false,
                loadingWidget: const Center(child: CircularProgressIndicator()),
                pdfFileName: widget.nomFichier,
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Fermer'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _telecharger,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Télécharger en PDF'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _imprimer,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print_outlined, size: 18),
                    label: const Text('Imprimer'),
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

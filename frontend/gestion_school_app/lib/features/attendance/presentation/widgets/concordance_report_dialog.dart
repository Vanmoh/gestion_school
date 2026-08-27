import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/timesheet_repository.dart';
import '../../domain/timesheet_concordance.dart';
import 'concordance_panel.dart';

/// Le rapprochement sur une periode: la semaine, le mois, ou ce qu'on veut.
///
/// L'ecran de pointage ne montre qu'une journee. La direction, elle, a
/// besoin du cumul: c'est lui qui documente une discussion de paie ou la
/// decision de remplacer quelqu'un, et il se faisait jusqu'ici de tete.
class ConcordanceReportDialog extends ConsumerStatefulWidget {
  /// Enseignant vise, ou null pour tout l'etablissement.
  final int? teacherId;
  final String titre;

  const ConcordanceReportDialog({super.key, this.teacherId, this.titre = 'Rapprochement'});

  @override
  ConsumerState<ConcordanceReportDialog> createState() =>
      _ConcordanceReportDialogState();
}

class _ConcordanceReportDialogState extends ConsumerState<ConcordanceReportDialog> {
  late DateTime _debut;
  late DateTime _fin;
  TimesheetConcordance _concordance = TimesheetConcordance.vide;
  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    // Le mois courant par defaut: c'est la maille de la paie, donc celle
    // sur laquelle l'ecart se discute.
    final maintenant = DateTime.now();
    _debut = DateTime(maintenant.year, maintenant.month, 1);
    _fin = maintenant;
    WidgetsBinding.instance.addPostFrameCallback((_) => _charger());
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final concordance = await ref
          .read(timesheetRepositoryProvider)
          .fetchConcordance(
            from: _debut,
            to: _fin,
            teacherId: widget.teacherId,
          );
      if (!mounted) return;
      setState(() => _concordance = concordance);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _concordance = TimesheetConcordance.vide;
        // Le serveur borne la periode a soixante-deux jours: son refus est
        // la bonne reponse, et il se lit tel quel.
        _erreur = _message(error);
      });
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  String _message(Object error) {
    final texte = error.toString();
    if (texte.contains('62')) {
      return 'Période trop large : 62 jours au maximum.';
    }
    return 'Rapprochement indisponible pour le moment.';
  }

  Future<void> _choisirLaPeriode() async {
    final choix = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _debut, end: _fin),
    );
    if (choix == null) return;
    setState(() {
      _debut = choix.start;
      _fin = choix.end;
    });
    await _charger();
  }

  void _moisPrecedent() {
    final mois = DateTime(_debut.year, _debut.month - 1, 1);
    setState(() {
      _debut = mois;
      // Dernier jour du mois: le zero du mois suivant le donne sans
      // avoir a connaitre les annees bissextiles.
      _fin = DateTime(mois.year, mois.month + 1, 0);
    });
    _charger();
  }

  String _jourLisible(DateTime valeur) {
    final j = valeur.day.toString().padLeft(2, '0');
    final m = valeur.month.toString().padLeft(2, '0');
    return '$j/$m/${valeur.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 900,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.titre,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Du ${_jourLisible(_debut)} au ${_jourLisible(_fin)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Mois précédent',
                    onPressed: _chargement ? null : _moisPrecedent,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  TextButton.icon(
                    onPressed: _chargement ? null : _choisirLaPeriode,
                    icon: const Icon(Icons.date_range),
                    label: const Text('Période'),
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
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_erreur != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _erreur!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ConcordancePanel(
                      concordance: _concordance,
                      chargement: _chargement,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

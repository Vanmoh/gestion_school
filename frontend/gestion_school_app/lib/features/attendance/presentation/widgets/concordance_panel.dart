import 'package:flutter/material.dart';

import '../../domain/timesheet_concordance.dart';

/// Ce qui devait etre assure, ce qui l'a ete, et l'ecart.
///
/// L'onglet « Enseignants » affichait des heures pointees sans jamais dire a
/// quels cours elles correspondaient, ni quels cours n'avaient ete assures
/// par personne. Le rapprochement se faisait de tete, ou pas du tout.
///
/// Widget sans etat ni reseau: il recoit ce qu'il affiche, ce qui le rend
/// verifiable sans monter la page ni son transport.
class ConcordancePanel extends StatelessWidget {
  final TimesheetConcordance concordance;
  final bool chargement;

  /// Vrai pour l'ecran d'un enseignant qui consulte son propre suivi: son
  /// nom en tete de chaque bloc n'apprendrait rien.
  final bool masquerEnseignant;

  const ConcordancePanel({
    super.key,
    required this.concordance,
    this.chargement = false,
    this.masquerEnseignant = false,
  });

  @override
  Widget build(BuildContext context) {
    final totaux = concordance.totals;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (chargement) const LinearProgressIndicator(),
        const SizedBox(height: 8),
        _bandeau(context, totaux),
        const SizedBox(height: 12),
        if (concordance.teachers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text('Aucun cours planifié ni pointage sur cette période.'),
          )
        else
          for (final enseignant in concordance.teachers)
            _blocEnseignant(context, enseignant),
      ],
    );
  }

  Widget _bandeau(BuildContext context, ConcordanceTotals totaux) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _pastille(context, 'Planifié', totaux.heuresPlanifiees),
        _pastille(context, 'Assuré', totaux.heuresAssurees),
        _pastille(
          context,
          'Écart',
          totaux.heuresManquantes,
          alerte: totaux.gapMinutes > 0,
        ),
        _pastille(
          context,
          'Séances non assurées',
          '${totaux.sessionsMissed}',
          alerte: totaux.sessionsMissed > 0,
        ),
        _pastille(context, 'Partielles', '${totaux.sessionsPartial}'),
        if (totaux.offScheduleEntries > 0)
          _pastille(
            context,
            'Hors planning',
            '${totaux.offScheduleEntries}',
          ),
      ],
    );
  }

  Widget _pastille(
    BuildContext context,
    String libelle,
    String valeur, {
    bool alerte = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: alerte ? scheme.error : scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(libelle, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            valeur,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: alerte ? scheme.error : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _blocEnseignant(BuildContext context, ConcordanceTeacher enseignant) {
    final totaux = enseignant.totals;
    final sousTitre = [
      '${totaux.sessionsAssured}/${totaux.sessionsPlanned} séance(s) assurée(s)',
      if (totaux.sessionsMissed > 0) '${totaux.sessionsMissed} non assurée(s)',
      if (totaux.offScheduleEntries > 0)
        '${totaux.offScheduleEntries} pointage(s) hors planning',
    ].join(' • ');

    final corps = [
      for (final jour in enseignant.days) _blocJour(context, jour),
    ];

    if (masquerEnseignant) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: corps);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        // Ouvert d'office quand il y a un manquement: c'est ce qu'on vient
        // chercher, et le replier demanderait un clic de plus a chaque fois.
        initiallyExpanded: totaux.sessionsMissed > 0,
        leading: _jauge(context, totaux),
        title: Text(enseignant.fullName),
        subtitle: Text(sousTitre),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: corps.isEmpty
            ? const [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Aucun cours planifié sur cette période.'),
                ),
              ]
            : corps,
      ),
    );
  }

  /// La part assuree, en un coup d'oeil.
  Widget _jauge(BuildContext context, ConcordanceTotals totaux) {
    final scheme = Theme.of(context).colorScheme;
    final taux = totaux.tauxAssure;
    return SizedBox(
      width: 38,
      height: 38,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: taux ?? 0,
            strokeWidth: 4,
            backgroundColor: scheme.surfaceContainerHighest,
            color: totaux.sessionsMissed > 0 ? scheme.error : scheme.primary,
          ),
          Text(
            taux == null ? '—' : '${(taux * 100).round()}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  Widget _blocJour(BuildContext context, ConcordanceDay jour) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            _dateLisible(jour),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        for (final seance in jour.sessions) _ligneSeance(context, seance),
        for (final entree in jour.entries)
          if (entree.isOffSchedule) _ligneHorsPlanning(context, entree),
      ],
    );
  }

  Widget _ligneSeance(BuildContext context, ConcordanceSession seance) {
    final scheme = Theme.of(context).colorScheme;
    final (couleur, icone, libelle) = switch (seance.status) {
      ConcordanceStatus.assured => (scheme.primary, Icons.check_circle_outline, 'Assurée'),
      ConcordanceStatus.partial => (
        scheme.tertiary,
        Icons.adjust_outlined,
        'Partielle',
      ),
      ConcordanceStatus.missed => (
        scheme.error,
        Icons.cancel_outlined,
        'Non assurée',
      ),
    };

    final details = <String>[
      seance.creneau,
      if (seance.room.isNotEmpty) 'salle ${seance.room}',
      if (seance.status == ConcordanceStatus.partial)
        '${seance.coveredMinutes} min sur ${seance.plannedMinutes}',
      if (seance.lateMinutes > 0) '${seance.lateMinutes} min de retard',
    ];

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icone, color: couleur),
      title: Text(seance.intitule),
      subtitle: Text(details.join('  ·  ')),
      trailing: Text(
        libelle,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: couleur),
      ),
    );
  }

  Widget _ligneHorsPlanning(BuildContext context, ConcordanceEntry entree) {
    final scheme = Theme.of(context).colorScheme;
    final fin = entree.checkOutTime ?? '—';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.event_busy_outlined, color: scheme.tertiary),
      title: Text('Hors planning : ${entree.checkInTime} – $fin'),
      subtitle: Text(
        entree.offScheduleReason.isEmpty
            ? 'Motif non renseigné'
            : entree.offScheduleReason,
      ),
      trailing: Text(
        '${entree.workedHours} h',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }

  String _dateLisible(ConcordanceDay jour) {
    final date = jour.date;
    if (date == null) return jour.weekday;
    const jours = {
      'MON': 'Lundi',
      'TUE': 'Mardi',
      'WED': 'Mercredi',
      'THU': 'Jeudi',
      'FRI': 'Vendredi',
      'SAT': 'Samedi',
      'SUN': 'Dimanche',
    };
    final nom = jours[jour.weekday] ?? '';
    final j = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$nom $j/$m/${date.year}';
  }
}

/// Le detail derriere les indicateurs de la palette enseignant.
///
/// Les trois tuiles -- affectations, emploi du temps, emargement -- annoncaient
/// des nombres sans jamais dire de quoi ils etaient faits: « 8 creneaux » sans
/// un jour ni une heure, « 2 retards » sans une date. Tout ce qu'il faut pour
/// repondre est pourtant deja charge par la page, filtre sur cet enseignant.
/// Aucune de ces vues ne demande quoi que ce soit de plus au serveur.
library;

import 'package:flutter/material.dart';

/// Ce que le serveur rend par page. Au-dela, la vue le dit plutot que de
/// laisser croire a un historique complet.
const int plafondPageServeur = 100;

/// Les jours dans l'ordre de la semaine, pas dans celui de la base.
const Map<String, String> _joursSemaine = {
  'MON': 'Lundi',
  'TUE': 'Mardi',
  'WED': 'Mercredi',
  'THU': 'Jeudi',
  'FRI': 'Vendredi',
  'SAT': 'Samedi',
  'SUN': 'Dimanche',
};

String _texte(dynamic valeur) => (valeur ?? '').toString().trim();

int _entier(dynamic valeur) {
  if (valeur is int) return valeur;
  if (valeur is double) return valeur.round();
  return int.tryParse(_texte(valeur)) ?? 0;
}

/// Minutes depuis minuit, a partir d'un « HH:MM » ou « HH:MM:SS ».
int? minutesDepuisMinuit(dynamic brut) {
  final texte = _texte(brut);
  if (texte.isEmpty) return null;
  final morceaux = texte.split(':');
  if (morceaux.length < 2) return null;
  final heures = int.tryParse(morceaux[0]);
  final minutes = int.tryParse(morceaux[1]);
  if (heures == null || minutes == null) return null;
  return heures * 60 + minutes;
}

/// « 8h30 » plutot que « 8:30:00 »: c'est un horaire, pas un timestamp.
String heureLisible(dynamic brut) {
  final texte = _texte(brut);
  if (texte.isEmpty) return '';
  final morceaux = texte.split(':');
  if (morceaux.length < 2) return texte;
  return '${morceaux[0]}:${morceaux[1]}';
}

String dureeLisible(int minutes) {
  if (minutes <= 0) return '';
  final heures = minutes ~/ 60;
  final reste = minutes % 60;
  if (heures == 0) return '$reste min';
  if (reste == 0) return '${heures}h';
  return '${heures}h$reste';
}

String dateLisible(dynamic brut) {
  final texte = _texte(brut);
  final date = DateTime.tryParse(texte);
  if (date == null) return texte;
  final jour = date.day.toString().padLeft(2, '0');
  final mois = date.month.toString().padLeft(2, '0');
  return '$jour/$mois/${date.year}';
}

/// Le cadre commun aux trois vues: titre, corps defilant, pied.
class DetailIndicateurDialog extends StatelessWidget {
  final IconData icone;
  final String titre;

  /// Ce que la tuile annoncait, rappele sous le titre: on doit retrouver le
  /// nombre sur lequel on a clique.
  final String resume;

  final Widget corps;

  /// Renvoie vers le module concerne, pour qui veut ecrire et pas seulement
  /// regarder. Absent quand aucun module ne correspond.
  final String? libelleModule;
  final VoidCallback? onOuvrirModule;

  const DetailIndicateurDialog({
    super.key,
    required this.icone,
    required this.titre,
    required this.resume,
    required this.corps,
    this.libelleModule,
    this.onOuvrirModule,
  });

  static Future<void> ouvrir(
    BuildContext context, {
    required IconData icone,
    required String titre,
    required String resume,
    required Widget corps,
    String? libelleModule,
    VoidCallback? onOuvrirModule,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => DetailIndicateurDialog(
        icone: icone,
        titre: titre,
        resume: resume,
        corps: corps,
        libelleModule: libelleModule,
        onOuvrirModule: onOuvrirModule,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icone, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titre,
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (resume.isNotEmpty)
                          Text(
                            resume,
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
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
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                child: corps,
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onOuvrirModule != null && libelleModule != null) ...[
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onOuvrirModule!();
                      },
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(libelleModule!),
                    ),
                    const SizedBox(width: 10),
                  ],
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Fermer'),
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

/// Ce que l'enseignant enseigne, et dans quelles classes.
///
/// Groupe par classe: c'est ainsi qu'on se pose la question devant un emploi
/// du temps, et la meme matiere peut revenir dans plusieurs classes.
class DetailAffectations extends StatelessWidget {
  final List<Map<String, dynamic>> affectations;

  const DetailAffectations({super.key, required this.affectations});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (affectations.isEmpty) {
      return _Vide(
        message: 'Aucune matière affectée à cet enseignant.',
        scheme: scheme,
        textTheme: textTheme,
      );
    }

    final parClasse = <String, List<Map<String, dynamic>>>{};
    for (final ligne in affectations) {
      final classe = _texte(ligne['classroom_name']);
      parClasse.putIfAbsent(classe.isEmpty ? 'Classe inconnue' : classe, () => []).add(ligne);
    }
    final classes = parClasse.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final classe in classes) ...[
          _TitreGroupe(libelle: classe, scheme: scheme, textTheme: textTheme),
          const SizedBox(height: 6),
          for (final ligne in parClasse[classe]!)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.menu_book_outlined,
                color: scheme.primary,
                size: 20,
              ),
              title: Text(
                _texte(ligne['subject_name']).isEmpty
                    ? 'Matière sans intitulé'
                    : _texte(ligne['subject_name']),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: _texte(ligne['subject_code']).isEmpty
                  ? null
                  : Text('Code ${_texte(ligne['subject_code'])}'),
            ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// Les creneaux de la semaine, jour par jour.
class DetailEmploiDuTemps extends StatelessWidget {
  final List<Map<String, dynamic>> creneaux;

  /// Les affectations, pour retrouver l'intitule de la matiere: le creneau ne
  /// porte que son code.
  final List<Map<String, dynamic>> affectations;

  const DetailEmploiDuTemps({
    super.key,
    required this.creneaux,
    this.affectations = const [],
  });

  /// Total hebdomadaire en minutes, creneaux incoherents ecartes.
  static int minutesTotales(List<Map<String, dynamic>> creneaux) {
    var total = 0;
    for (final creneau in creneaux) {
      final debut = minutesDepuisMinuit(creneau['start_time']);
      final fin = minutesDepuisMinuit(creneau['end_time']);
      if (debut != null && fin != null && fin > debut) total += fin - debut;
    }
    return total;
  }

  String _matiereDe(Map<String, dynamic> creneau) {
    final affectationId = _entier(creneau['assignment']);
    for (final affectation in affectations) {
      if (_entier(affectation['id']) == affectationId) {
        final nom = _texte(affectation['subject_name']);
        if (nom.isNotEmpty) return nom;
      }
    }
    // Le code seul reste plus parlant qu'un blanc.
    return _texte(creneau['subject_code']);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (creneaux.isEmpty) {
      return _Vide(
        message: 'Aucun créneau au planning de cet enseignant.',
        scheme: scheme,
        textTheme: textTheme,
      );
    }

    final parJour = <String, List<Map<String, dynamic>>>{};
    for (final creneau in creneaux) {
      parJour.putIfAbsent(_texte(creneau['day_of_week']), () => []).add(creneau);
    }
    // L'ordre de la semaine, pas celui d'arrivee. Un jour inconnu passe en
    // fin de liste plutot que de disparaitre.
    final jours = parJour.keys.toList()
      ..sort((a, b) {
        final rangA = _joursSemaine.keys.toList().indexOf(a);
        final rangB = _joursSemaine.keys.toList().indexOf(b);
        return (rangA < 0 ? 99 : rangA).compareTo(rangB < 0 ? 99 : rangB);
      });

    final total = minutesTotales(creneaux);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final jour in jours) ...[
          _TitreGroupe(
            libelle: _joursSemaine[jour] ?? (jour.isEmpty ? 'Jour non précisé' : jour),
            scheme: scheme,
            textTheme: textTheme,
          ),
          const SizedBox(height: 6),
          for (final creneau in _triesParHeure(parJour[jour]!))
            _LigneCreneau(
              creneau: creneau,
              matiere: _matiereDe(creneau),
              scheme: scheme,
              textTheme: textTheme,
            ),
          const SizedBox(height: 10),
        ],
        if (total > 0) ...[
          const Divider(),
          Text(
            'Total : ${dureeLisible(total)} par semaine',
            textAlign: TextAlign.right,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ],
    );
  }

  static List<Map<String, dynamic>> _triesParHeure(
    List<Map<String, dynamic>> creneaux,
  ) {
    final copie = [...creneaux];
    copie.sort((a, b) {
      final debutA = minutesDepuisMinuit(a['start_time']) ?? 0;
      final debutB = minutesDepuisMinuit(b['start_time']) ?? 0;
      return debutA.compareTo(debutB);
    });
    return copie;
  }
}

class _LigneCreneau extends StatelessWidget {
  final Map<String, dynamic> creneau;
  final String matiere;
  final ColorScheme scheme;
  final TextTheme textTheme;

  const _LigneCreneau({
    required this.creneau,
    required this.matiere,
    required this.scheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    final debut = minutesDepuisMinuit(creneau['start_time']);
    final fin = minutesDepuisMinuit(creneau['end_time']);
    final duree = (debut != null && fin != null && fin > debut)
        ? dureeLisible(fin - debut)
        : '';
    final horsDispo = _texte(creneau['off_availability_reason']);
    final salle = _texte(creneau['room']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '${heureLisible(creneau['start_time'])} – ${heureLisible(creneau['end_time'])}',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  matiere.isEmpty ? 'Matière non précisée' : matiere,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  [
                    if (_texte(creneau['classroom_name']).isNotEmpty)
                      _texte(creneau['classroom_name']),
                    if (salle.isNotEmpty) 'Salle $salle',
                    if (duree.isNotEmpty) duree,
                  ].join(' · '),
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                // Un creneau pose hors des disponibilites declarees se
                // signale: il tient rarement jusqu'a la fin du trimestre.
                if (horsDispo.isNotEmpty)
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_outlined,
                        size: 14,
                        color: scheme.tertiary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Hors disponibilité : $horsDispo',
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.tertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Les pointages, du plus recent au plus ancien.
class DetailEmargement extends StatelessWidget {
  final List<Map<String, dynamic>> pointages;

  const DetailEmargement({super.key, required this.pointages});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (pointages.isEmpty) {
      return _Vide(
        message: 'Aucun pointage enregistré pour cet enseignant.',
        scheme: scheme,
        textTheme: textTheme,
      );
    }

    final tries = [...pointages]
      ..sort((a, b) {
        final dateA = _texte(a['entry_date']);
        final dateB = _texte(b['entry_date']);
        return dateB.compareTo(dateA);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Le serveur rend une page a la fois: sans ce mot, la liste passerait
        // pour l'historique entier.
        if (pointages.length >= plafondPageServeur)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: scheme.tertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Les $plafondPageServeur pointages les plus récents. '
                    'L\'historique complet est dans le module Émargements.',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.tertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        for (final pointage in tries)
          _LignePointage(
            pointage: pointage,
            scheme: scheme,
            textTheme: textTheme,
          ),
      ],
    );
  }
}

class _LignePointage extends StatelessWidget {
  final Map<String, dynamic> pointage;
  final ColorScheme scheme;
  final TextTheme textTheme;

  const _LignePointage({
    required this.pointage,
    required this.scheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    final retard = _entier(pointage['late_minutes']);
    final sortie = heureLisible(pointage['check_out_time']);
    final autoFerme = pointage['is_auto_closed'] == true;
    final motifAuto = _texte(pointage['auto_closed_reason']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              dateLisible(pointage['entry_date']),
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${heureLisible(pointage['check_in_time'])} – '
                  // Une sortie vide n'est pas une sortie a minuit: le dire
                  // evite de lire une journee de travail nulle.
                  '${sortie.isEmpty ? 'sortie non pointée' : sortie}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (retard > 0)
                  Text(
                    'Retard de $retard min',
                    style: textTheme.bodySmall?.copyWith(color: scheme.error),
                  ),
                if (autoFerme)
                  Text(
                    motifAuto.isEmpty
                        ? 'Sortie fermée automatiquement'
                        : 'Fermeture automatique : $motifAuto',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.tertiary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TitreGroupe extends StatelessWidget {
  final String libelle;
  final ColorScheme scheme;
  final TextTheme textTheme;

  const _TitreGroupe({
    required this.libelle,
    required this.scheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      libelle.toUpperCase(),
      style: textTheme.labelSmall?.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _Vide extends StatelessWidget {
  final String message;
  final ColorScheme scheme;
  final TextTheme textTheme;

  const _Vide({
    required this.message,
    required this.scheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

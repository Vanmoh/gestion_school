import 'package:flutter/material.dart';

import '../../domain/availability.dart';

/// La semaine type: les jours en colonnes, les créneaux en lignes.
///
/// Deux lectures d'une même grille, parce que deux métiers la consultent.
/// L'enseignant y peint ce qu'il peut assurer ; l'administration y lit
/// combien de professeurs sont prenables sur chaque case — c'est-à-dire la
/// marge dont elle dispose pour placer un cours.
///
/// Widget sans état ni réseau: il reçoit ce qu'il affiche, ce qui le rend
/// vérifiable sans monter la page ni son transport.
class AvailabilityGridView extends StatelessWidget {
  final AvailabilityGrid grid;

  /// Vrai pour la vue « je déclare », faux pour la vue « j'arbitre ».
  final bool modeDeclaration;

  /// Nul quand la collecte est close ou le profil en lecture: les cases
  /// cessent alors d'être cliquables plutôt que de rendre un refus.
  final void Function(AvailabilityCell cellule)? onBasculer;

  /// Ouvre le détail d'une case côté administration: qui a déclaré quoi.
  final void Function(AvailabilityCell cellule)? onDetail;

  const AvailabilityGridView({
    super.key,
    required this.grid,
    required this.modeDeclaration,
    this.onBasculer,
    this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    if (grid.days.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: Text('Aucune plage horaire à afficher.')),
      );
    }

    final creneaux = grid.creneaux;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Les cases sont isolees de la legende, qui reprend forcement leurs
          // mots -- « Préférée », « disponible ». Sans cette separation, on ne
          // peut plus designer une case sans attraper sa legende.
          Column(
            key: const Key('availability-cells'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _enTete(context),
              for (var ligne = 0; ligne < creneaux.length; ligne++)
                _ligne(context, ligne, creneaux[ligne]),
            ],
          ),
          const SizedBox(height: 10),
          _legende(context),
        ],
      ),
    );
  }

  Widget _enTete(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 96),
        for (final jour in grid.days)
          SizedBox(
            width: 132,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                jour.dayLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
      ],
    );
  }

  Widget _ligne(BuildContext context, int index, String creneau) {
    return Row(
      // `stretch` etirerait les cases sur une hauteur non bornee -- la
      // colonne parente n'en impose aucune. Leur hauteur vient de la case
      // elle-meme, et l'heure s'aligne sur leur haut.
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Text(
              creneau,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
        for (final jour in grid.days)
          SizedBox(
            width: 132,
            child: index < jour.cells.length
                ? _case(context, jour.cells[index])
                : const SizedBox.shrink(),
          ),
      ],
    );
  }

  Widget _case(BuildContext context, AvailabilityCell cellule) {
    final scheme = Theme.of(context).colorScheme;
    final (fond, bord, contenu) = modeDeclaration
        ? _apparenceDeclaration(context, cellule)
        : _apparenceArbitrage(context, cellule);

    final actionnable = modeDeclaration
        ? onBasculer != null
        : onDetail != null && cellule.teachers.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: fond,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: actionnable
              ? () => modeDeclaration
                    ? onBasculer!(cellule)
                    : onDetail!(cellule)
              : null,
          child: Container(
            // Une case pleine porte trois lignes -- le compte, son libelle,
            // et la mention des volontaires ou de la plage plus large --,
            // dont la hauteur suit la taille de police du systeme. La marge
            // est deliberee: a 68 px la troisieme ligne debordait deja de
            // trois pixels au reglage par defaut.
            height: 76,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: bord ?? scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: contenu,
          ),
        ),
      ),
    );
  }

  /// Vue enseignant: la case porte ce que j'ai déclaré, et rien d'autre.
  (Color, Color?, Widget) _apparenceDeclaration(
    BuildContext context,
    AvailabilityCell cellule,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final etat = cellule.mine;

    if (etat == null) {
      return (
        Colors.transparent,
        null,
        Text(
          '—',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.outline,
          ),
        ),
      );
    }

    final (couleur, icone) = switch (etat) {
      AvailabilityKind.preferred => (scheme.primary, Icons.star_rounded),
      AvailabilityKind.possible => (scheme.tertiary, Icons.check_rounded),
      AvailabilityKind.unavailable => (scheme.error, Icons.block_rounded),
    };

    return (
      couleur.withValues(alpha: 0.12),
      couleur,
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icone, size: 18, color: couleur),
          const SizedBox(height: 2),
          Text(
            etat.libelle,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: couleur),
          ),
          // Une plage plus large couvre cette case sans lui appartenir: la
          // modifier d'ici découperait la déclaration d'origine.
          if (!cellule.mineExact)
            Text(
              'plage plus large',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.outline,
                fontSize: 9,
              ),
            ),
        ],
      ),
    );
  }

  /// Vue administration: la case porte la marge disponible pour placer un cours.
  (Color, Color?, Widget) _apparenceArbitrage(
    BuildContext context,
    AvailabilityCell cellule,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final ouverts = cellule.ouverts;

    if (ouverts == 0 && cellule.unavailableCount == 0) {
      return (
        Colors.transparent,
        null,
        Text(
          '—',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.outline,
          ),
        ),
      );
    }

    // L'intensité suit le nombre de professeurs prenables: une case pâle
    // est une case où l'on n'aura pas le choix.
    final intensite = ouverts == 0 ? 0.0 : (0.10 + (ouverts.clamp(0, 6) * 0.045));

    return (
      scheme.primary.withValues(alpha: intensite),
      ouverts == 0 ? scheme.error.withValues(alpha: 0.5) : null,
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$ouverts',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: ouverts == 0 ? scheme.error : scheme.onSurface,
            ),
          ),
          Text(
            ouverts > 1 ? 'disponibles' : 'disponible',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          if (cellule.preferredCount > 0)
            Text(
              '${cellule.preferredCount} volontaire'
              '${cellule.preferredCount > 1 ? 's' : ''}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontSize: 9,
              ),
            ),
        ],
      ),
    );
  }

  Widget _legende(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entrees = modeDeclaration
        ? [
            (scheme.primary, Icons.star_rounded, 'Préférée'),
            (scheme.tertiary, Icons.check_rounded, 'Possible'),
            (scheme.error, Icons.block_rounded, 'Indisponible'),
          ]
        : [
            (scheme.primary, Icons.groups_outlined, 'Nombre d’enseignants prenables'),
            (scheme.error, Icons.warning_amber_rounded, 'Aucun disponible sur la case'),
          ];

    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        for (final (couleur, icone, libelle) in entrees)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 15, color: couleur),
              const SizedBox(width: 5),
              Text(libelle, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        if (modeDeclaration)
          Text(
            'Touchez une case pour changer son état.',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    );
  }
}

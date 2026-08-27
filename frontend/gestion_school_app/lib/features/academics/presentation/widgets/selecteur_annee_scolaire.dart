import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/annee_scolaire.dart';
import '../annee_scolaire_controller.dart';

/// Le choix de l'annee de travail, dans la barre de l'application.
///
/// Place a cote de l'etablissement, et pour la meme raison: ce sont les
/// deux dimensions qui decident de ce que chaque ecran montre. Les avoir
/// separees -- une dans la coquille, l'autre dans chaque page -- laissait
/// consulter une annee tout en saisissant dans une autre.
class SelecteurAnneeScolaire extends ConsumerWidget {
  const SelecteurAnneeScolaire({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controleur = ref.watch(anneeScolaireProvider);
    final annees = controleur.annees;
    final selectionnee = controleur.selectionnee;

    // Une seule annee ne se choisit pas: l'afficher en menu deroulant
    // promettrait une bascule qui n'existe pas encore.
    if (annees.length <= 1) {
      if (selectionnee == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Center(
          child: Text(
            selectionnee.nom,
            key: const Key('annee-unique'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      );
    }

    return PopupMenuButton<int>(
      key: const Key('selecteur-annee'),
      tooltip: 'Année scolaire',
      onSelected: (id) {
        final choisie = annees.firstWhere((annee) => annee.id == id);
        controleur.selectionner(choisie);
      },
      itemBuilder: (context) => [
        for (final annee in annees)
          PopupMenuItem<int>(
            value: annee.id,
            // `min` et `Flexible`: sans eux, « 2024-2025 (cloturee) »
            // deborde de la largeur que le menu accorde a sa ligne.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (annee.id == selectionnee?.id)
                  const Icon(Icons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(annee.libelle, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_note_outlined, size: 18),
            const SizedBox(width: 6),
            Text(
              selectionnee?.nom ?? 'Année',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

/// Rappel permanent qu'on ne regarde pas l'annee en cours.
///
/// Sans lui, rien ne distinguerait a l'ecran la consultation d'une annee
/// close de la saisie courante -- et une note saisie « par erreur » sur
/// l'an dernier ne se voit qu'au moment ou le serveur la refuse.
class BandeauAnneeCloturee extends ConsumerWidget {
  const BandeauAnneeCloturee({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final annee = ref.watch(anneeScolaireProvider).selectionnee;
    if (annee == null || !annee.estCloturee) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const Key('bandeau-annee-cloturee'),
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.lock_clock_outlined, size: 18,
                color: scheme.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Année ${annee.nom} clôturée — consultation. '
                'Seule la direction peut y apporter une correction, et '
                'chacune est enregistrée.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etiquette courte d'une annee, pour les entetes d'ecran.
String libelleAnnee(AnneeScolaire? annee) =>
    annee == null ? '' : annee.libelle;

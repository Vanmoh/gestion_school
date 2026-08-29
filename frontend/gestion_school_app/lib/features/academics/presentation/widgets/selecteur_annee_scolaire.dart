import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/saisie_en_cours.dart';
import '../../../../core/widgets/cartouche_contexte.dart';
import '../../domain/annee_scolaire.dart';
import '../annee_scolaire_controller.dart';

/// Les couleurs d'un état d'année, prises dans le thème.
///
/// Rassemblées ici parce que trois widgets les emploient — la pastille, le
/// sélecteur et le bandeau — et qu'un état qui change de teinte d'un endroit
/// à l'autre ne se lit plus comme un état.
({Color trait, Color fond, Color texte, IconData icone}) _tons(
  BuildContext context,
  EtatAnnee etat,
) {
  final scheme = Theme.of(context).colorScheme;
  return switch (etat) {
    EtatAnnee.active => (
      trait: scheme.primary,
      fond: scheme.primaryContainer,
      texte: scheme.onPrimaryContainer,
      icone: Icons.play_circle_outline_rounded,
    ),
    EtatAnnee.consultee => (
      trait: scheme.tertiary,
      fond: scheme.tertiaryContainer,
      texte: scheme.onTertiaryContainer,
      icone: Icons.history_rounded,
    ),
    EtatAnnee.cloturee => (
      trait: scheme.outline,
      fond: scheme.surfaceContainerHighest,
      texte: scheme.onSurfaceVariant,
      icone: Icons.lock_outline_rounded,
    ),
  };
}

/// La pastille d'état: active, consultée, clôturée.
class PastilleEtatAnnee extends StatelessWidget {
  final EtatAnnee etat;
  final bool compacte;

  const PastilleEtatAnnee({super.key, required this.etat, this.compacte = false});

  @override
  Widget build(BuildContext context) {
    final tons = _tons(context, etat);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compacte ? 6 : 8, vertical: 2),
      decoration: BoxDecoration(
        color: tons.fond,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tons.icone, size: compacte ? 11 : 13, color: tons.texte),
          SizedBox(width: compacte ? 3 : 5),
          Text(
            etat.libelle,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tons.texte,
              fontWeight: FontWeight.w600,
              fontSize: compacte ? 10 : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Le choix de l'annee de travail, dans la barre de l'application.
///
/// Place a cote de l'etablissement, et pour la meme raison: ce sont les
/// deux dimensions qui decident de ce que chaque ecran montre. Elles
/// etaient separees -- une dans la coquille, l'autre dans chaque page --,
/// ce qui laissait consulter une annee tout en saisissant dans une autre.
///
/// Et le selecteur n'existait que sur mobile: sur grand ecran, l'ecran de
/// travail principal d'une administration, rien ne disait sur quelle annee
/// on travaillait ni ne permettait d'en changer.
class SelecteurAnneeScolaire extends ConsumerWidget {
  /// Vrai dans l'en-tete de bureau, ou la place ne manque pas: le libelle
  /// s'accompagne alors de sa periode. La barre du mobile, elle, se contente
  /// du nom et de la pastille.
  final bool etendu;

  /// Vrai dans l'en-tete de bureau, dont le fond sombre et translucide a son
  /// propre vocabulaire: les teintes du theme y perdraient leur contraste, et
  /// un cartouche aux couleurs claires y ferait une tache.
  final bool surFondSombre;

  const SelecteurAnneeScolaire({
    super.key,
    this.etendu = false,
    this.surFondSombre = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controleur = ref.watch(anneeScolaireProvider);
    final annees = controleur.annees;
    final selectionnee = controleur.selectionnee;

    // Aucune annee: l'ecran ne doit pas rester muet. Il l'etait -- un
    // `SizedBox.shrink()` -- et l'utilisateur ne savait alors pas s'il
    // travaillait sur une annee, ni laquelle.
    if (selectionnee == null) {
      return CartoucheContexte(
        key: const Key('annee-absente'),
        icone: Icons.event_note_outlined,
        titre: 'Aucune année',
        sousTitre: etendu ? 'Ouvrez une année scolaire' : null,
        etendu: etendu,
        surFondSombre: surFondSombre,
        teinte: Theme.of(context).colorScheme.error,
      );
    }

    // Une seule annee ne se choisit pas: un menu deroulant promettrait une
    // bascule qui n'existe pas. Elle reste affichee, avec son etat.
    if (annees.length <= 1) {
      return CartoucheContexte(
        key: const Key('annee-unique'),
        icone: Icons.event_note_outlined,
        titre: selectionnee.nom,
        sousTitre: etendu ? selectionnee.periode : null,
        marque: PastilleEtatAnnee(etat: selectionnee.etat, compacte: !etendu),
        etendu: etendu,
        surFondSombre: surFondSombre,
        teinte: _tons(context, selectionnee.etat).trait,
      );
    }

    return PopupMenuButton<int>(
      key: const Key('selecteur-annee'),
      tooltip: 'Année scolaire',
      position: PopupMenuPosition.under,
      onSelected: (id) async {
        final choisie = annees.firstWhere((annee) => annee.id == id);
        if (choisie.id == selectionnee.id) return;

        // Changer d'annee recharge l'ecran: une saisie en cours partirait
        // sur une annee qui n'est plus celle affichee.
        final feuVert = await confirmerChangementDeContexte(
          context,
          ref,
          quoi: 'd’année scolaire',
        );
        if (!feuVert) return;
        controleur.selectionner(choisie);
      },
      itemBuilder: (context) => [
        for (final annee in annees)
          PopupMenuItem<int>(
            value: annee.id,
            child: _LigneMenu(
              annee: annee,
              choisie: annee.id == selectionnee.id,
            ),
          ),
      ],
      child: CartoucheContexte(
        icone: Icons.event_note_outlined,
        titre: selectionnee.nom,
        sousTitre: etendu ? selectionnee.periode : null,
        marque: PastilleEtatAnnee(etat: selectionnee.etat, compacte: !etendu),
        etendu: etendu,
        surFondSombre: surFondSombre,
        deroulant: true,
        teinte: _tons(context, selectionnee.etat).trait,
        infobulle: 'Changer d’année scolaire',
      ),
    );
  }
}

/// Une ligne du menu déroulant: l'année, sa période, son état.
class _LigneMenu extends StatelessWidget {
  final AnneeScolaire annee;
  final bool choisie;

  const _LigneMenu({required this.annee, required this.choisie});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 22,
          child: choisie ? const Icon(Icons.check, size: 18) : null,
        ),
        // `Flexible`: sans lui, « 2024-2025 (clôturée) » déborde de la
        // largeur que le menu accorde à sa ligne.
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(annee.nom, overflow: TextOverflow.ellipsis),
              if (annee.periode.isNotEmpty)
                Text(
                  annee.periode,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        PastilleEtatAnnee(etat: annee.etat, compacte: true),
      ],
    );
  }
}

/// Rappel permanent qu'on ne saisit pas dans l'annee en cours.
///
/// Il ne se levait que sur une annee cloturee. Consulter une annee passee
/// mais encore ouverte ne declenchait rien: on y saisissait sans que rien ne
/// le signale, et l'erreur ne se voyait qu'a la relecture des bulletins.
class BandeauAnneeCloturee extends ConsumerWidget {
  const BandeauAnneeCloturee({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controleur = ref.watch(anneeScolaireProvider);
    final annee = controleur.selectionnee;
    if (annee == null || annee.etat == EtatAnnee.active) {
      return const SizedBox.shrink();
    }

    final tons = _tons(context, annee.etat);
    final courante = controleur.annees
        .where((autre) => autre.estCourante && !autre.estCloturee)
        .firstOrNull;

    final message = annee.estCloturee
        ? 'Année ${annee.nom} clôturée — consultation. Seule la direction '
              'peut y apporter une correction, et chacune est enregistrée.'
        : 'Vous travaillez sur ${annee.nom}, qui n’est pas l’année en cours. '
              'Toute saisie sera enregistrée sur cette année-là.';

    return Material(
      key: const Key('bandeau-annee-cloturee'),
      color: tons.fond,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(tons.icone, size: 18, color: tons.texte),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tons.texte,
                ),
              ),
            ),
            // Le retour d'un clic: sans lui, revenir a l'annee en cours
            // demandait de rouvrir le menu et de la retrouver dans la liste.
            if (courante != null && courante.id != annee.id) ...[
              const SizedBox(width: 12),
              TextButton(
                key: const Key('retour-annee-courante'),
                onPressed: () => controleur.selectionner(courante),
                child: Text(
                  'Revenir à ${courante.nom}',
                  style: TextStyle(color: tons.texte),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Etiquette courte d'une annee, pour les entetes d'ecran.
String libelleAnnee(AnneeScolaire? annee) =>
    annee == null ? '' : annee.libelle;

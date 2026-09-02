import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/annee_scolaire.dart';
import '../annee_scolaire_controller.dart';
import 'selecteur_annee_scolaire.dart';

/// L'année de travail, en tête de l'écran Académique.
///
/// L'écran affichait « Année active : 2025-2026 » au milieu d'un bandeau
/// d'informations, sans ses dates ni où l'on en était dedans. Or c'est cette
/// page qui ouvre, ferme et bascule les années : le repère y a sa place au
/// premier regard.
///
/// Widget sans réseau : il lit le contrôleur partagé et rend ce qu'il y
/// trouve, ce qui le rend vérifiable sans monter la page entière.
class CarteAnneeActive extends ConsumerWidget {
  /// Nombre de classes et d'élèves rattachés à l'année affichée. Passés par
  /// l'écran, qui les a déjà chargés : les redemander ici ferait deux appels
  /// pour une seule information.
  final int classes;
  final int eleves;

  /// Ouvre l'assistant d'ouverture d'année. Nul quand le profil ne peut pas
  /// écrire : proposer le bouton mènerait à un refus.
  final VoidCallback? onOuvrirAnnee;

  /// Changer l'état de l'année affichée. Le back-office sait le faire depuis
  /// toujours (`activer`, `cloturer`, `rouvrir`) mais aucun écran ne l'offrait :
  /// basculer l'année de saisie ou fermer une année demandait de passer par
  /// l'admin Django. Nuls quand le profil ne peut pas écrire.
  final VoidCallback? onActiver;
  final VoidCallback? onCloturer;
  final VoidCallback? onRouvrir;

  const CarteAnneeActive({
    super.key,
    required this.classes,
    required this.eleves,
    this.onOuvrirAnnee,
    this.onActiver,
    this.onCloturer,
    this.onRouvrir,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controleur = ref.watch(anneeScolaireProvider);
    final annee = controleur.selectionnee;
    final scheme = Theme.of(context).colorScheme;

    if (annee == null) {
      return _cadre(
        context,
        teinte: scheme.error,
        enfants: [
          Text(
            'Aucune année scolaire',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            'Ouvrez une année pour inscrire des élèves, saisir des notes et '
            'construire l’emploi du temps.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (onOuvrirAnnee != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const Key('ouvrir-premiere-annee'),
                onPressed: onOuvrirAnnee,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ouvrir une année'),
              ),
            ),
          ],
        ],
      );
    }

    final avancement = annee.avancement;
    final teinte = switch (annee.etat) {
      EtatAnnee.active => scheme.primary,
      EtatAnnee.consultee => scheme.tertiary,
      EtatAnnee.cloturee => scheme.outline,
    };

    return _cadre(
      context,
      teinte: teinte,
      enfants: [
        Row(
          children: [
            Expanded(
              child: Text(
                annee.nom,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            PastilleEtatAnnee(etat: annee.etat),
          ],
        ),
        if (annee.periode.isNotEmpty)
          Text(
            annee.periode,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        if (avancement != null) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              key: const Key('avancement-annee'),
              value: avancement,
              minHeight: 7,
              backgroundColor: scheme.surfaceContainerHighest,
              color: teinte,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            annee.moisEcoules,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _compteur(context, Icons.meeting_room_outlined, classes, 'classe'),
            _compteur(context, Icons.groups_2_outlined, eleves, 'élève'),
          ],
        ),
        const SizedBox(height: 4),
        // Les gestes de vie de l'année, la ou on la regarde. Chacun n'a de
        // sens que dans un etat: une annee active n'a pas a etre activee, une
        // annee cloturee ne redevient l'année de saisie qu'apres reouverture
        // -- le serveur refuse d'ailleurs le raccourci.
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (annee.etat == EtatAnnee.consultee && onActiver != null)
              FilledButton.tonalIcon(
                key: const Key('annee-rendre-active'),
                onPressed: onActiver,
                icon: const Icon(Icons.play_circle_outline, size: 18),
                label: const Text('Rendre active'),
              ),
            if (annee.etat != EtatAnnee.cloturee && onCloturer != null)
              TextButton.icon(
                key: const Key('annee-cloturer'),
                onPressed: onCloturer,
                icon: const Icon(Icons.lock_outline, size: 18),
                label: const Text('Clôturer'),
              ),
            if (annee.etat == EtatAnnee.cloturee && onRouvrir != null)
              TextButton.icon(
                key: const Key('annee-rouvrir'),
                onPressed: onRouvrir,
                icon: const Icon(Icons.lock_open_outlined, size: 18),
                label: const Text('Rouvrir'),
              ),
            if (onOuvrirAnnee != null)
              TextButton.icon(
                key: const Key('ouvrir-annee-suivante'),
                onPressed: onOuvrirAnnee,
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: const Text('Ouvrir une nouvelle année'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _compteur(
    BuildContext context,
    IconData icone,
    int valeur,
    String nom,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 17, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            '$valeur',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            valeur > 1 ? '${nom}s' : nom,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _cadre(
    BuildContext context, {
    required Color teinte,
    required List<Widget> enfants,
  }) {
    final scheme = Theme.of(context).colorScheme;
    // La bande de couleur est un enfant et non un cote de la bordure:
    // Flutter refuse de peindre un `Border` aux cotes de couleurs
    // differentes des qu'un rayon lui est donne.
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: teinte),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: enfants,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Les briques communes aux sept tableaux de bord.
///
/// Elles vivaient dans `dashboard_page.dart`, écrites pour l'écran de la
/// direction. Les dashboards de rôle, eux, avaient leur propre langage —
/// `_RoleMetric` avec ses couleurs écrites en dur (`Color(0xFF2CC2FF)`), qui
/// ignorent l'accent choisi par l'école et tiennent mal en thème clair.
///
/// Deux langages visuels dans la même application, c'est deux fois le travail
/// et deux fois les défauts: la discipline du « une phrase par chiffre »
/// n'existait que d'un côté, et l'année n'était nommée que d'un côté.
///
/// D'où ce fichier. Les six écrans de rôle parlent désormais la langue de
/// celui de la direction, et une correction profite à tous.
library;

import 'package:flutter/material.dart';

import '../domain/dashboard_stats.dart';

class Panne extends StatelessWidget {
  const Panne({super.key, required this.erreur, required this.onReessayer});

  final Object erreur;
  final Future<void> Function() onReessayer;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.cloud_off_outlined, color: couleurs.error),
                    const SizedBox(width: 10),
                    Text(
                      'Erreur de chargement',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Les compteurs ne sont pas arrivés. $erreur',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onReessayer,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class EnTete extends StatelessWidget {
  const EnTete({super.key, required this.stats, required this.onActualiser});

  final DashboardStats stats;
  final Future<void> Function() onActualiser;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final couleurs = Theme.of(context).colorScheme;
    final annee = stats.academicYearName;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stats.activeEtablissementName?.trim().isNotEmpty == true
                    ? stats.activeEtablissementName!
                    : 'Tableau de bord',
                style: textes.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (annee != null && annee.isNotEmpty)
                    Etiquette(
                      texte: 'Année $annee',
                      icone: Icons.event_outlined,
                      accentuee: true,
                    )
                  else
                    const Etiquette(
                      texte: 'Aucune année active',
                      icone: Icons.event_busy_outlined,
                    ),
                  if (stats.academicYearClosed)
                    const Etiquette(
                      texte: 'Année clôturée',
                      icone: Icons.lock_outline,
                    ),
                  if (stats.academicYearStart != null &&
                      stats.academicYearEnd != null)
                    Text(
                      'du ${_jour(stats.academicYearStart!)} '
                      'au ${_jour(stats.academicYearEnd!)}',
                      style: textes.bodySmall?.copyWith(
                        color: couleurs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        IconButton.filledTonal(
          onPressed: onActualiser,
          icon: const Icon(Icons.refresh),
          tooltip: 'Actualiser',
        ),
      ],
    );
  }

  /// « 2025-09-01 » devient « 01/09/2025 ».
  static String _jour(String iso) {
    final parts = iso.split('-');
    if (parts.length < 3) return iso;
    final jour = parts[2].split('T').first;
    return '$jour/${parts[1]}/${parts[0]}';
  }
}

class Etiquette extends StatelessWidget {
  const Etiquette({super.key, 
    required this.texte,
    required this.icone,
    this.accentuee = false,
  });

  final String texte;
  final IconData icone;
  final bool accentuee;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    final fond = accentuee
        ? couleurs.primary.withValues(alpha: 0.12)
        : couleurs.surfaceContainerHighest;
    final encre = accentuee ? couleurs.primary : couleurs.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: encre),
          const SizedBox(width: 6),
          Text(
            texte,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: encre,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Quatre chiffres, et une phrase par chiffre.
///
/// Quatre et non neuf: au-delà, on ne lit plus, on balaie. Et une phrase
/// plutôt qu'un pourcentage nu, parce qu'un nombre sans son sens oblige
/// chacun à l'interpréter — souvent de travers.
/// Qui est en ligne, maintenant.
///
/// Un bandeau et non une cinquième carte: c'est un état instantané, pas une
/// mesure de l'année, et le mêler aux chiffres de pilotage inviterait à le
/// comparer à eux.
///
/// **Quinze secondes**, et c'est ce qui rend le mot « temps réel » honnête:
/// sans ce minuteur, le chiffre resterait figé jusqu'au prochain tirage vers le
/// bas. Seul ce bandeau se rafraîchit — relancer les quinze agrégations du
/// tableau de bord toutes les quinze secondes serait absurde, et le serveur les
/// garde de toute façon en cache soixante secondes.
///
/// Un rôle sans droit sur le module `users` reçoit 403: le bandeau disparaît
/// alors, sans message d'erreur. Savoir qui est connecté est une information
/// d'administration, et son absence n'est pas une panne.

class Rangee extends StatelessWidget {
  const Rangee({super.key, required this.titre, required this.cartes});

  final String titre;
  final List<Widget> cartes;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final couleurs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titre.toUpperCase(),
          style: textes.labelSmall?.copyWith(
            color: couleurs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, contraintes) {
            // Quatre de front sur un bureau, deux sur une tablette, une seule
            // sur un téléphone. Le seuil vient de la largeur qu'un montant en
            // francs demande sans se couper: « 5 040 000 FCFA » ne tient pas
            // sous 240 px.
            final parLigne = contraintes.maxWidth >= 1000
                ? 4
                : contraintes.maxWidth >= 620
                ? 2
                : 1;
            const ecart = 14.0;
            final largeur =
                (contraintes.maxWidth - ecart * (parLigne - 1)) / parLigne;

            return Wrap(
              spacing: ecart,
              runSpacing: ecart,
              children: [
                for (final carte in cartes)
                  SizedBox(width: largeur, child: carte),
              ],
            );
          },
        ),
      ],
    );
  }
}

class CarteChiffre extends StatelessWidget {
  const CarteChiffre({
    super.key,
    required this.libelle,
    required this.valeur,
    required this.phrase,
    required this.icone,
    this.unite,
    this.jauge,
    this.alerte = false,
  });

  final String libelle;
  final String valeur;
  final String? unite;
  final String phrase;
  final IconData icone;

  /// La part réalisée, entre 0 et 1, quand le chiffre est un ratio.
  ///
  /// Une jauge sur piste de même teinte, et non un camembert de deux parts:
  /// « 93 % d'un total » se lit d'un coup sur une barre, et la part manquante
  /// occupe visuellement la place qu'elle représente.
  final double? jauge;

  final bool alerte;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final couleurs = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, size: 18, color: couleurs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    libelle,
                    style: textes.labelLarge?.copyWith(
                      color: couleurs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  valeur,
                  style: textes.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                if (unite != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    unite!,
                    style: textes.bodyMedium?.copyWith(
                      color: couleurs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            if (jauge != null) ...[
              const SizedBox(height: 12),
              Jauge(part: jauge!),
            ],
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (alerte) ...[
                  Icon(
                    Icons.pending_actions_outlined,
                    size: 15,
                    color: couleurs.error,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    phrase,
                    style: textes.bodySmall?.copyWith(
                      color: alerte ? couleurs.error : couleurs.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// La part réalisée, sur une piste de la même teinte.

class Jauge extends StatelessWidget {
  const Jauge({super.key, required this.part});

  final double part;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    final borne = part.clamp(0.0, 1.0);

    return Semantics(
      label: 'Réalisé ${(borne * 100).round()} pour cent',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: borne,
          minHeight: 8,
          backgroundColor: couleurs.primary.withValues(alpha: 0.16),
          valueColor: AlwaysStoppedAnimation(couleurs.primary),
        ),
      ),
    );
  }
}

/// Une seule courbe: ce qui était dû chaque mois, et ce qui est rentré.
///
/// Une seule, parce que l'écran en portait quatre — un radar, des barres, un
/// anneau, des sparklines — et qu'aucune ne disait quoi faire.
///
/// Le mois vient de l'échéance du barème et non de l'heure de saisie du
/// paiement: `Payment` ne porte aucune date de paiement, donc un reçu écrit le
/// 30 et saisi le 2 tombait dans le mois suivant, et un import en masse faisait
/// tenir une année dans un seul mois.

/// Ce qui demande une décision, et l'écran qui la règle.
///
/// C'est ce qui sépare un tableau de bord d'un outil: chaque ligne mène là où
/// on agit, au lieu de laisser son lecteur chercher le module lui-même.
///
/// Elle reçoit ses lignes au lieu de les calculer. La première version lisait
/// `DashboardStats`, `Echeancier` et `PresenceParRole` — les trois sources de
/// l'écran de la direction — ce qui la rendait inutilisable pour les autres
/// rôles. Or « ce qui demande une décision » dépend justement du rôle: un
/// surveillant voit des feuilles d'appel, un comptable des charges à valider.
class ATraiter extends StatelessWidget {
  const ATraiter({super.key, required this.lignes, required this.onOuvrirModule});

  final List<ActionATraiter> lignes;
  final void Function(String) onOuvrirModule;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final couleurs = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'À traiter',
              style: textes.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            if (lignes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: couleurs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Rien n\'attend de décision.',
                        style: textes.bodyMedium?.copyWith(
                          color: couleurs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final ligne in lignes)
                LigneAction(
                  ligne: ligne,
                  onOuvrir: () => onOuvrirModule(ligne.module),
                ),
          ],
        ),
      ),
    );
  }
}

class ActionATraiter {
  const ActionATraiter({
    required this.titre,
    required this.detail,
    required this.icone,
    required this.module,
    this.urgent = false,
  });

  final String titre;
  final String detail;
  final IconData icone;
  final String module;
  final bool urgent;
}

class LigneAction extends StatelessWidget {
  const LigneAction({super.key, required this.ligne, required this.onOuvrir});

  final ActionATraiter ligne;
  final VoidCallback onOuvrir;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final couleurs = Theme.of(context).colorScheme;
    final encre = ligne.urgent ? couleurs.error : couleurs.onSurfaceVariant;

    return InkWell(
      onTap: onOuvrir,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        // 48 px de haut au minimum: une ligne cliquable doit pouvoir être
        // touchée au doigt.
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Icon(ligne.icone, size: 19, color: encre),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ligne.titre,
                    style: textes.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ligne.detail,
                    style: textes.bodySmall?.copyWith(
                      color: couleurs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: couleurs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

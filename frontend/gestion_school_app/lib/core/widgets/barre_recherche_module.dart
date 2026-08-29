import 'package:flutter/material.dart';

/// La grande barre de recherche qui ouvre un module.
///
/// Reprise du motif des modules « Gestion des eleves » et « Enseignants »: on
/// tape un nom, un code, un telephone, et la palette de ce qu'on cherche
/// s'ouvre. Ces deux ecrans-la portent chacun leur propre copie de cette
/// barre; ce widget existe pour que les modules suivants n'en fassent pas une
/// troisieme et une quatrieme, qui divergeraient au premier ajustement.
///
/// Volontairement sans etat: la recherche, son minuteur d'attente et ses
/// resultats appartiennent a la page, qui seule sait ce qu'elle cherche.
class BarreRechercheModule extends StatelessWidget {
  final TextEditingController controller;

  /// Ce qu'on peut taper, enumere: une barre qui annonce « Rechercher » ne
  /// dit pas qu'un numero de telephone ou un code suffisent aussi.
  final String indication;

  final ValueChanged<String> onChanged;

  /// Efface le champ et remet la page a son etat d'accueil. Le bouton
  /// n'apparait que lorsqu'il y a quelque chose a effacer.
  final VoidCallback onEffacer;

  /// Boutons places sous la barre: on agit la ou on cherche.
  final List<Widget> actions;

  /// Affiche une pastille « Recherche... » pendant l'attente du serveur.
  final bool rechercheEnCours;

  /// Resserre les marges et coupe la prise de focus automatique: sur un
  /// telephone, ouvrir le clavier des l'arrivee masque la moitie de l'ecran.
  final bool compact;

  const BarreRechercheModule({
    super.key,
    required this.controller,
    required this.indication,
    required this.onChanged,
    required this.onEffacer,
    this.actions = const [],
    this.rechercheEnCours = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              onChanged: onChanged,
              autofocus: !compact,
              // Plus grand que le corps de texte: c'est le point d'entree du
              // module, pas un filtre parmi d'autres.
              style: textTheme.titleMedium,
              decoration: InputDecoration(
                hintText: indication,
                prefixIcon: const Icon(Icons.search, size: 24),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer',
                        icon: const Icon(Icons.clear),
                        onPressed: onEffacer,
                      ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
              ),
            ),
            if (rechercheEnCours || actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (rechercheEnCours)
                    const Chip(
                      avatar: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      label: Text('Recherche...'),
                    ),
                  ...actions,
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ce que la page montre tant qu'aucune entite n'est choisie.
///
/// Trois etats se ressemblent a l'ecran et ne veulent pas dire la meme chose:
/// on n'a rien demande, on cherche, ou on a cherche sans rien trouver. Les
/// confondre fait conclure a une base vide.
class EtatVideRecherche extends StatelessWidget {
  /// Vide tant que l'utilisateur n'a rien tape.
  final String recherche;

  /// « Recherchez un eleve pour ouvrir sa palette. »
  final String invitation;

  /// Les criteres acceptes, rappeles sous l'invitation.
  final String precision;

  /// « Aucun eleve ne correspond a ... » -- le mot varie avec le module.
  final String motAucun;

  const EtatVideRecherche({
    super.key,
    required this.recherche,
    required this.invitation,
    required this.precision,
    required this.motAucun,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final vide = recherche.trim().isEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
        child: Column(
          children: [
            Icon(
              vide ? Icons.search : Icons.search_off_outlined,
              size: 44,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              vide ? invitation : '$motAucun « ${recherche.trim()} ».',
              textAlign: TextAlign.center,
              style: textTheme.titleSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (vide) ...[
              const SizedBox(height: 6),
              Text(
                precision,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

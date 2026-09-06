/// La carte de connexion: deux champs, un bouton, et rien d'autre.
///
/// Elle portait aussi l'URL de l'API, un bouton « Tester connexion API » et
/// « Changer d'etablissement »: trois lignes techniques sous le bouton, qui
/// donnaient a la premiere page de l'application l'allure d'un outil de
/// diagnostic. Elles vivent desormais derriere l'icone de reglages -- sauf
/// quand le serveur est injoignable, seul moment ou elles aident vraiment.
library;

import 'package:flutter/material.dart';

import '../../../../models/etablissement.dart';
import '../../../../widgets/etablissement_identity.dart';

/// Cles stables pour les tests: elles designent le champ, pas sa position.
const Key kChampIdentifiant = Key('champ-identifiant');
const Key kChampMotDePasse = Key('champ-mot-de-passe');

class LoginFormCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final Etablissement etablissement;
  final TextEditingController identifiantController;
  final TextEditingController motDePasseController;
  final FocusNode identifiantFocus;
  final FocusNode motDePasseFocus;

  final bool motDePasseMasque;
  final VoidCallback onBasculerVisibilite;

  final bool enCours;
  final VoidCallback onSoumettre;
  final VoidCallback onMotDePasseOublie;

  /// Messages du serveur, deja traduits, poses sous le champ concerne.
  ///
  /// Des fonctions et non des valeurs: le validator est appele apres coup, y
  /// compris pendant la soumission qui vient d'effacer ces messages. Une
  /// valeur capturee a la construction serait alors deja perimee, le validator
  /// retournerait l'ancienne erreur et la requete ne partirait jamais.
  final String? Function() erreurIdentifiant;
  final String? Function() erreurMotDePasse;

  /// Ce qui ne releve d'aucun champ (compte refuse, serveur en panne).
  final String? erreurGenerale;

  /// Serveur injoignable: l'URL de l'API redevient pertinente, on la montre.
  final bool erreurReseau;
  final String urlApi;
  final VoidCallback onOuvrirReglages;

  /// Le clavier ne s'ouvre de lui-meme que sur grand ecran: sur telephone, il
  /// masquerait la carte avant meme qu'on l'ait vue.
  final bool autofocus;

  /// Repeter la pastille et le nom de l'ecole en tete de carte.
  ///
  /// Vrai sur grand ecran, ou la marque vit dans l'autre colonne, loin de
  /// l'oeil. Faux en colonne unique: l'en-tete de marque est alors juste
  /// au-dessus, et les deux pastilles se retrouvaient a cinquante pixels
  /// l'une de l'autre, a dire la meme chose.
  final bool avecIdentite;

  /// Efface le message serveur des que l'utilisateur retape.
  final ValueChanged<String> onIdentifiantModifie;
  final ValueChanged<String> onMotDePasseModifie;

  const LoginFormCard({
    super.key,
    required this.formKey,
    required this.etablissement,
    required this.identifiantController,
    required this.motDePasseController,
    required this.identifiantFocus,
    required this.motDePasseFocus,
    required this.motDePasseMasque,
    required this.onBasculerVisibilite,
    required this.enCours,
    required this.onSoumettre,
    required this.onMotDePasseOublie,
    required this.erreurIdentifiant,
    required this.erreurMotDePasse,
    required this.erreurGenerale,
    required this.erreurReseau,
    required this.urlApi,
    required this.onOuvrirReglages,
    required this.autofocus,
    required this.avecIdentite,
    required this.onIdentifiantModifie,
    required this.onMotDePasseModifie,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return _CarteVivante(
      accent: scheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AutofillGroup(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (avecIdentite)
                  Row(
                    children: [
                      EtabIdentityBadge(etab: etablissement, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Connexion',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            ),
                            Text(
                              etabDisplayName(etablissement),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    'Connexion',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                const SizedBox(height: 20),
                TextFormField(
                  key: kChampIdentifiant,
                  controller: identifiantController,
                  focusNode: identifiantFocus,
                  autofocus: autofocus,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  onChanged: onIdentifiantModifie,
                  onFieldSubmitted: (_) => motDePasseFocus.requestFocus(),
                  // Le message du serveur remonte par le validator et non par
                  // `decoration.errorText`: `Form.validate()` ne consulte que
                  // le validator, et c'est lui qu'on rejoue a l'arrivee d'une
                  // erreur pour l'afficher sur-le-champ.
                  validator: (valeur) {
                    if ((valeur ?? '').trim().isEmpty) {
                      return 'Saisissez votre nom d\'utilisateur.';
                    }
                    return erreurIdentifiant();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Nom utilisateur',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: kChampMotDePasse,
                  controller: motDePasseController,
                  focusNode: motDePasseFocus,
                  obscureText: motDePasseMasque,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  onChanged: onMotDePasseModifie,
                  onFieldSubmitted: (_) => onSoumettre(),
                  validator: (valeur) {
                    if ((valeur ?? '').isEmpty) {
                      return 'Saisissez votre mot de passe.';
                    }
                    return erreurMotDePasse();
                  },
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      // Sans ce libelle, un lecteur d'ecran n'annoncait rien.
                      tooltip: motDePasseMasque
                          ? 'Afficher le mot de passe'
                          : 'Masquer le mot de passe',
                      onPressed: onBasculerVisibilite,
                      icon: Icon(
                        motDePasseMasque
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onMotDePasseOublie,
                    child: const Text('Mot de passe oublié ?'),
                  ),
                ),
                if (erreurGenerale != null) ...[
                  const SizedBox(height: 4),
                  _BandeauErreur(
                    message: erreurGenerale!,
                    urlApi: erreurReseau ? urlApi : null,
                    onOuvrirReglages: onOuvrirReglages,
                  ),
                ],
                const SizedBox(height: 16),
                _BoutonPrincipal(
                  enCours: enCours,
                  onSoumettre: onSoumettre,
                  accent: scheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  'Accès réservé aux utilisateurs autorisés',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ce qui ne se rattache a aucun champ.
///
/// La SnackBar ne convenait pas: un compte refuse n'est pas une information
/// transitoire, et elle s'evaporait au bout de quatre secondes. Sur un
/// serveur injoignable, c'est de plus la seule occasion ou l'URL de l'API
/// redevient utile -- ce qui rend acceptable de l'avoir rangee le reste du
/// temps.
class _BandeauErreur extends StatelessWidget {
  final String message;
  final String? urlApi;
  final VoidCallback onOuvrirReglages;

  const _BandeauErreur({
    required this.message,
    required this.urlApi,
    required this.onOuvrirReglages,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline,
                size: 18,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
          if (urlApi != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onOuvrirReglages,
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('Réglages'),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onErrorContainer,
                  minimumSize: const Size(0, 36),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// La carte, posee sur une lueur qui s'intensifie au survol.
///
/// Sans elle, la carte se confondait avec le fond: meme famille de sombres,
/// une bordure fine, et rien qui la designe comme l'endroit ou agir. La lueur
/// la detache; le survol la souleve juste assez pour qu'on la sente cliquable
/// sans qu'elle bouge sous le curseur.
///
/// L'animation ne touche que l'ombre et l'echelle -- jamais la taille. Le test
/// de mise en page mesure l'ecran a cent millisecondes, donc en pleine
/// animation: une hauteur animee y serait mesuree a mi-course et pourrait
/// deborder.
class _CarteVivante extends StatefulWidget {
  final Widget child;
  final Color accent;

  const _CarteVivante({required this.child, required this.accent});

  @override
  State<_CarteVivante> createState() => _CarteVivanteState();
}

class _CarteVivanteState extends State<_CarteVivante> {
  bool _survol = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final immobile = etabReduceMotion(context);
    final duree = immobile ? Duration.zero : const Duration(milliseconds: 180);

    return MouseRegion(
      onEnter: (_) => setState(() => _survol = true),
      onExit: (_) => setState(() => _survol = false),
      child: AnimatedScale(
        scale: _survol && !immobile ? 1.006 : 1,
        duration: duree,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: duree,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _survol
                  ? widget.accent.withValues(alpha: 0.45)
                  : scheme.outlineVariant.withValues(alpha: 0.8),
              width: _survol ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.accent.withValues(alpha: _survol ? 0.26 : 0.16),
                blurRadius: _survol ? 40 : 30,
                spreadRadius: -8,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.30),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          // `clipBehavior`: sans lui, le lisere deborderait des coins arrondis.
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              widget.child,
              // Une arete eclairee sur le bord superieur, comme sur un objet
              // pose sous une lumiere. Un pixel suffit: au-dela, cela devient
              // une bordure, et l'effet se perd.
              Positioned(
                top: 0,
                left: 18,
                right: 18,
                child: IgnorePointer(
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.white.withValues(alpha: _survol ? 0.45 : 0.22),
                          Colors.transparent,
                        ],
                      ),
                    ),
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

/// Le bouton d'action, entoure d'une lueur qui repond au survol.
///
/// C'est le seul geste que la page attend: il doit se voir comme tel, et
/// reagir quand la souris l'approche. L'animation ne touche que l'ombre --
/// aucune taille, pour la raison expliquee sur [_CarteVivante].
class _BoutonPrincipal extends StatefulWidget {
  final bool enCours;
  final VoidCallback onSoumettre;
  final Color accent;

  const _BoutonPrincipal({
    required this.enCours,
    required this.onSoumettre,
    required this.accent,
  });

  @override
  State<_BoutonPrincipal> createState() => _BoutonPrincipalState();
}

class _BoutonPrincipalState extends State<_BoutonPrincipal> {
  bool _survol = false;

  @override
  Widget build(BuildContext context) {
    final immobile = etabReduceMotion(context);
    final duree = immobile ? Duration.zero : const Duration(milliseconds: 180);
    final actif = _survol && !widget.enCours;

    return MouseRegion(
      onEnter: (_) => setState(() => _survol = true),
      onExit: (_) => setState(() => _survol = false),
      child: AnimatedContainer(
        duration: duree,
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: widget.accent.withValues(alpha: actif ? 0.48 : 0.28),
              blurRadius: actif ? 26 : 16,
              spreadRadius: actif ? -2 : -4,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: FilledButton.icon(
          onPressed: widget.enCours ? null : widget.onSoumettre,
          icon: widget.enCours
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.login_rounded),
          label: Text(
            widget.enCours ? 'Connexion en cours...' : 'Se connecter',
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

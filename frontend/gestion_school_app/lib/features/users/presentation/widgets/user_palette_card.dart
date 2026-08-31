import 'package:flutter/material.dart';

import '../../domain/user_account.dart';

/// Ce qu'il faut savoir d'un compte pour agir dessus.
///
/// Meme grammaire que les palettes eleve et enseignant: en-tete identifiant,
/// blocs de champs, puis l'etat du compte. La fiche qu'elle remplace tenait
/// en six pastilles grises ou l'essentiel -- un compte encore ouvert apres un
/// depart, un compte cree puis jamais utilise -- ne se voyait pas.
class UserPaletteCard extends StatelessWidget {
  final UserAccount compte;

  /// Boutons d'ecriture, places sous le nom: on agit la ou on regarde.
  final List<Widget> actions;

  /// Presente seulement quand la recherche avait plusieurs reponses: sinon le
  /// bouton proposerait de revenir a une liste qui n'existe pas.
  final VoidCallback? onClear;

  const UserPaletteCard({
    super.key,
    required this.compte,
    this.actions = const [],
    this.onClear,
  });

  static const nonRenseigne = 'Non renseigné';
  static const jamaisConnecte = 'Jamais connecté';

  /// Le meme vert que la pastille de la messagerie: « en ligne » doit se
  /// reconnaitre d'un ecran a l'autre.
  static const couleurEnLigne = Color(0xFF12B76A);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _enTete(scheme, textTheme),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final colonnes = constraints.maxWidth > 900
                    ? 3
                    : (constraints.maxWidth > 560 ? 2 : 1);
                final largeur =
                    (constraints.maxWidth - (colonnes - 1) * 16) / colonnes;

                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: largeur,
                      child: _bloc(scheme, textTheme, 'Identité', [
                        ('Nom et prénom', compte.fullName),
                        ('Identifiant', compte.username),
                      ]),
                    ),
                    SizedBox(
                      width: largeur,
                      child: _bloc(scheme, textTheme, 'Accès', [
                        ('Rôle', _libelleRole()),
                        ('Établissement', compte.etablissementName),
                      ]),
                    ),
                    SizedBox(
                      width: largeur,
                      child: _bloc(scheme, textTheme, 'Contacts', [
                        ('Email', compte.email),
                        ('Téléphone', compte.phone),
                      ]),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            _etatDuCompte(scheme, textTheme),
          ],
        ),
      ),
    );
  }

  String _libelleRole() =>
      compte.roleLabel.trim().isEmpty ? compte.role : compte.roleLabel;

  Widget _enTete(ColorScheme scheme, TextTheme textTheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Initiales(
          initiales: _initiales(compte.fullName, compte.username),
          scheme: scheme,
          textTheme: textTheme,
          actif: compte.isActive,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                compte.fullName.trim().isEmpty
                    ? compte.username
                    : compte.fullName,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _pastille(scheme, textTheme, _libelleRole()),
                  // Un compte coupe n'ouvre plus de session: c'est la premiere
                  // chose a voir, avant meme le role.
                  if (!compte.isActive)
                    _pastille(
                      scheme,
                      textTheme,
                      'Désactivé',
                      couleur: scheme.errorContainer,
                      texteCouleur: scheme.onErrorContainer,
                    ),
                  if (compte.isActive && compte.enLigne)
                    _pastille(
                      scheme,
                      textTheme,
                      'En ligne',
                      couleur: couleurEnLigne.withValues(alpha: 0.18),
                      texteCouleur: couleurEnLigne,
                    ),
                  if (compte.etablissementName.trim().isNotEmpty)
                    _pastille(scheme, textTheme, compte.etablissementName),
                ],
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ],
          ),
        ),
        if (onClear != null)
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Résultats'),
          ),
      ],
    );
  }

  /// L'usage reel du compte: ouvert ou coupe, cree quand, utilise quand.
  ///
  /// Un compte cree puis jamais utilise et un compte actif quotidiennement se
  /// ressemblaient trait pour trait dans l'ancienne fiche.
  Widget _etatDuCompte(ColorScheme scheme, TextTheme textTheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Wrap(
        spacing: 22,
        runSpacing: 12,
        children: [
          _indicateur(
            scheme,
            textTheme,
            'État',
            compte.isActive ? 'Actif' : 'Désactivé',
            couleur: compte.isActive ? null : scheme.error,
          ),
          _indicateur(
            scheme,
            textTheme,
            // La date seule ne repondait pas a la question qu'on se pose en
            // regardant cette fiche: est-il devant son ecran la, maintenant?
            compte.enLigne ? 'Connexion' : 'Dernière connexion',
            compte.etatDeConnexion,
            // Vert quand la personne est la; l'accent tertiaire signale au
            // contraire un compte qui n'a jamais servi -- soit il ne sert a
            // personne, soit son titulaire n'a jamais recu ses acces.
            couleur: compte.enLigne
                ? couleurEnLigne
                : (compte.jamaisConnecte ? scheme.tertiary : null),
            puce: compte.enLigne,
          ),
          _indicateur(
            scheme,
            textTheme,
            'Créé le',
            _date(compte.dateJoined, repli: nonRenseigne),
          ),
        ],
      ),
    );
  }

  Widget _indicateur(
    ColorScheme scheme,
    TextTheme textTheme,
    String libelle,
    String valeur, {
    Color? couleur,
    bool puce = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          libelle,
          style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Le point vert se lit avant le mot: c'est la convention de toutes
            // les messageries, et elle survit a un coup d'oeil rapide.
            if (puce) ...[
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: couleurEnLigne,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              valeur,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: couleur,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _bloc(
    ColorScheme scheme,
    TextTheme textTheme,
    String titre,
    List<(String, String)> champs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titre.toUpperCase(),
          style: textTheme.labelSmall?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        for (final (label, valeur) in champs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  valeur.trim().isEmpty ? nonRenseigne : valeur,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: valeur.trim().isEmpty
                        ? FontWeight.w400
                        : FontWeight.w600,
                    fontStyle: valeur.trim().isEmpty
                        ? FontStyle.italic
                        : FontStyle.normal,
                    color: valeur.trim().isEmpty
                        ? scheme.onSurfaceVariant
                        : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _pastille(
    ColorScheme scheme,
    TextTheme textTheme,
    String texte, {
    Color? couleur,
    Color? texteCouleur,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: couleur ?? scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texte,
        style: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: texteCouleur ?? scheme.onSecondaryContainer,
        ),
      ),
    );
  }

  static String _date(DateTime? valeur, {required String repli}) {
    if (valeur == null) return repli;
    final jour = valeur.day.toString().padLeft(2, '0');
    final mois = valeur.month.toString().padLeft(2, '0');
    return '$jour/$mois/${valeur.year}';
  }

  /// Deux lettres tirees du nom, ou de l'identifiant quand le nom manque:
  /// un rond vide se lit comme un defaut d'affichage.
  static String _initiales(String nomComplet, String identifiant) {
    final source = nomComplet.trim().isEmpty ? identifiant : nomComplet;
    final mots = source
        .trim()
        .split(RegExp(r'\s+'))
        .where((mot) => mot.isNotEmpty)
        .toList();
    if (mots.isEmpty) return '?';
    if (mots.length == 1) {
      final mot = mots.first;
      return (mot.length == 1 ? mot : mot.substring(0, 2)).toUpperCase();
    }
    return '${mots.first[0]}${mots[1][0]}'.toUpperCase();
  }
}

class _Initiales extends StatelessWidget {
  final String initiales;
  final ColorScheme scheme;
  final TextTheme textTheme;
  final bool actif;

  static const taille = 76.0;

  const _Initiales({
    required this.initiales,
    required this.scheme,
    required this.textTheme,
    required this.actif,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: taille,
      height: taille,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // Un compte coupe se reconnait des le rond, sans lire la pastille.
        color: actif ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Text(
        initiales,
        style: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: actif ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

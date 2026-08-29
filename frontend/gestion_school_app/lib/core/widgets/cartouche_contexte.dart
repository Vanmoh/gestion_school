import 'package:flutter/material.dart';

/// Le bloc qui porte une dimension de travail dans le bandeau.
///
/// Établissement et année scolaire sont les deux dimensions qui décident de
/// ce que chaque écran montre. Elles doivent donc se lire comme une paire —
/// même hauteur, même rayon, même fond — et non comme deux éléments
/// empruntés à des écrans différents.
///
/// Partagé plutôt que recopié: les deux sélecteurs en dépendent, et deux
/// copies finiraient par diverger, comme cela s'est déjà produit ailleurs
/// dans ce projet.
class CartoucheContexte extends StatelessWidget {
  /// L'icône qui identifie la dimension: un bâtiment, un calendrier.
  final IconData icone;

  /// La valeur courante — le nom de l'école, celui de l'année.
  final String titre;

  /// La ligne du dessous, affichée seulement en version étendue.
  final String? sousTitre;

  /// La pastille d'état, à droite du titre. Facultative.
  final Widget? marque;

  /// Vrai dans l'en-tête de bureau, où la place ne manque pas.
  final bool etendu;

  /// Affiche la flèche: le cartouche promet alors une bascule.
  final bool deroulant;

  /// Vrai sur le fond sombre du bandeau, qui a son propre vocabulaire —
  /// blanc translucide. Les teintes du thème y perdraient leur contraste.
  final bool surFondSombre;

  /// Teinte de la bordure hors fond sombre. Le thème sinon.
  final Color? teinte;

  /// Ce que dit l'infobulle. Sert à expliquer pourquoi un cartouche ne se
  /// déroule pas — « ce compte est rattaché à cet établissement ».
  final String? infobulle;

  const CartoucheContexte({
    super.key,
    required this.icone,
    required this.titre,
    this.sousTitre,
    this.marque,
    this.etendu = false,
    this.deroulant = false,
    this.surFondSombre = false,
    this.teinte,
    this.infobulle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trait = teinte ?? scheme.primary;

    final bordure = surFondSombre
        ? Colors.white.withValues(alpha: 0.16)
        : trait.withValues(alpha: 0.35);
    final fond = surFondSombre
        ? Colors.white.withValues(alpha: 0.1)
        : trait.withValues(alpha: 0.06);
    final encre = surFondSombre ? Colors.white : null;
    final encreDouce = surFondSombre
        ? Colors.white.withValues(alpha: 0.72)
        : scheme.onSurfaceVariant;

    final contenu = Container(
      padding: EdgeInsets.fromLTRB(etendu ? 12 : 10, 6, deroulant ? 4 : 10, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(surFondSombre ? 999 : 10),
        border: Border.all(color: bordure),
        color: fond,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: etendu ? 18 : 16, color: encre ?? trait),
          SizedBox(width: etendu ? 10 : 6),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        titre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: encre,
                        ),
                      ),
                    ),
                    if (marque != null) ...[const SizedBox(width: 8), marque!],
                  ],
                ),
                if (sousTitre != null && sousTitre!.isNotEmpty)
                  Text(
                    sousTitre!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: encreDouce,
                    ),
                  ),
              ],
            ),
          ),
          if (deroulant) Icon(Icons.arrow_drop_down, color: encre ?? trait),
        ],
      ),
    );

    final message = infobulle;
    if (message == null || message.isEmpty) return contenu;
    return Tooltip(message: message, child: contenu);
  }
}

import 'package:flutter/material.dart';

/// Un chiffre et ce qu'il désigne, tels que l'application les affiche partout.
///
/// Douze écrans portaient chacun leur copie de cette pastille — neuf d'entre
/// elles rigoureusement identiques, recopiées d'un module à l'autre. Elles
/// partageaient donc aussi le même défaut : une bordure figée en noir
/// translucide, qui disparaît sur fond sombre.
///
/// La forme retenue est celle de la majorité : le libellé en petit au-dessus,
/// la valeur en gras dessous. Elle se lit mieux qu'un « libellé : valeur » sur
/// une ligne quand les chiffres s'alignent côte à côte, et c'est déjà la
/// grammaire des indicateurs de la fiche d'un compte.
class Indicateur extends StatelessWidget {
  final String libelle;
  final String valeur;

  /// Colore la valeur quand elle appelle une réaction — une trésorerie
  /// négative, un retard critique. Nul, elle prend l'encre courante.
  final Color? couleur;

  /// Impose une largeur minimale, pour que plusieurs indicateurs s'alignent
  /// en colonnes régulières plutôt que de se serrer sur leur contenu.
  final double? largeurMinimale;

  const Indicateur({
    super.key,
    required this.libelle,
    required this.valeur,
    this.couleur,
    this.largeurMinimale,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      constraints: largeurMinimale == null
          ? null
          : BoxConstraints(minWidth: largeurMinimale!),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            libelle,
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            valeur,
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: couleur,
            ),
          ),
        ],
      ),
    );
  }
}

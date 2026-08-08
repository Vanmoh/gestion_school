import 'package:flutter/material.dart';

/// Reference tokens for the academic imports UI.
/// Keep page-level colors and shapes centralized to avoid visual drift.
class AcademicImportsUiReference {
  static const BorderRadius panelRadius = BorderRadius.all(Radius.circular(18));
  static const EdgeInsets pagePadding = EdgeInsets.all(16);

  static Color panelBackground(ColorScheme scheme) => scheme.surfaceContainerLow;

  static Color panelBorder(ColorScheme scheme) => scheme.outlineVariant;

  static Color subtleText(ColorScheme scheme) => scheme.onSurfaceVariant;

  static const Color successBackground = Color(0xFFDFF5E6);
  static const Color infoBackground = Color(0xFFE3F0FF);
  static const Color warningBackground = Color(0xFFFFE9C2);
  static const Color errorBackground = Color(0xFFFCE7E4);

  static Color metricBackground(ColorScheme scheme, String key) {
    switch (key) {
      case 'errors':
      case 'blocking_conflicts':
        return errorBackground;
      case 'conflicts':
        return warningBackground;
      case 'to_create':
        return successBackground;
      case 'to_update':
        return infoBackground;
      default:
        return scheme.surfaceContainerHighest;
    }
  }

  static RoundedRectangleBorder panelShape(ColorScheme scheme) {
    return RoundedRectangleBorder(
      borderRadius: panelRadius,
      side: BorderSide(color: panelBorder(scheme)),
    );
  }

  /// Bouton d'acces aux imports academiques.
  ///
  /// Les couleurs viennent du schema, pas des constantes pastel ci-dessus:
  /// `infoBackground` est un bleu pale fige, et l'associer a
  /// `scheme.onSurface` -- quasi blanc en theme sombre -- rendait le bouton
  /// illisible, donc invisible. Le defaut touchait les trois pages qui
  /// utilisent ce style: eleves, emploi du temps et notes.
  static ButtonStyle importActionStyle(ColorScheme scheme) {
    return FilledButton.styleFrom(
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      disabledBackgroundColor: scheme.surfaceContainerHighest,
      disabledForegroundColor: scheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: panelBorder(scheme)),
    );
  }
}

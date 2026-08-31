import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Secoue son enfant pendant deux secondes et demie, puis s'arrête.
///
/// Un appel d'attention fait surgir la fenêtre de discussion par-dessus ce
/// que la personne était en train de faire. Surgir ne suffit pas : sur un
/// écran chargé, une fenêtre de plus passe inaperçue. La secousse dit que
/// c'est cette fenêtre-là, et maintenant.
///
/// Elle s'arrête d'elle-même. Une fenêtre qui tremble sans fin empêcherait de
/// lire ce qu'elle contient et de répondre — l'inverse du but recherché.
class SecousseAttention extends StatefulWidget {
  final Widget child;

  /// Change de valeur à chaque nouvel appel. Un simple booléen ne suffirait
  /// pas : deux appels d'affilée doivent secouer deux fois, or « vrai » suivi
  /// de « vrai » ne se distingue pas d'une reconstruction quelconque.
  final int declencheur;

  const SecousseAttention({
    super.key,
    required this.child,
    required this.declencheur,
  });

  /// Deux secondes et demie : assez pour être vu de l'autre bout de la pièce,
  /// assez court pour ne pas gêner la lecture du premier message.
  static const Duration duree = Duration(milliseconds: 2500);

  @override
  State<SecousseAttention> createState() => _SecousseAttentionState();
}

class _SecousseAttentionState extends State<SecousseAttention>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controleur = AnimationController(
    vsync: this,
    duration: SecousseAttention.duree,
  );

  @override
  void initState() {
    super.initState();
    if (widget.declencheur > 0) {
      _controleur.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(SecousseAttention ancien) {
    super.didUpdateWidget(ancien);
    // Reprendre depuis zéro, et non enchaîner: un second appel pendant le
    // premier doit relancer la secousse entière, pas la prolonger d'un cran.
    if (widget.declencheur != ancien.declencheur) {
      _controleur.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controleur,
      // L'enfant est construit une fois et réutilisé à chaque image: la
      // fenêtre de discussion est un arbre lourd, la reconstruire soixante
      // fois par seconde pendant la secousse ferait saccader l'animation.
      child: widget.child,
      builder: (context, enfant) {
        final t = _controleur.value;
        if (t == 0 || t == 1) return enfant!;

        // L'amplitude décroît avec le temps: la secousse s'épuise au lieu de
        // s'interrompre net, ce qui se lit comme un arrêt et non un bug.
        final amplitude = 12 * (1 - t);
        final decalage = math.sin(t * math.pi * 2 * 9) * amplitude;
        return Transform.translate(
          offset: Offset(decalage, 0),
          child: enfant,
        );
      },
    );
  }
}

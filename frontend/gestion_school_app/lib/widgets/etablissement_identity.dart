import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/etablissement.dart';

/// Langage visuel partage par le portail de selection et la fiche d'un
/// etablissement.
///
/// Les deux ecrans montrent le meme objet a deux profondeurs differentes: ils
/// doivent donc parler la meme langue (teinte d'identite, pastille, etiquette
/// de nature, fond ambiant, cascade d'apparition). Ce fichier est la source
/// unique de cette langue; sans lui, chaque ecran redefinissait ses couleurs et
/// la fiche paraissait venir d'une autre application.

/// Largeur maximale de la bande de contenu.
///
/// Sans plafond, les lignes s'etiraient d'un bord a l'autre sur grand ecran:
/// l'oeil perdait le lien entre la pastille a gauche et le chevron a droite.
const double kEtabContentMaxWidth = 980;

/// Vrai quand le systeme demande de limiter les animations.
///
/// Toutes les animations de ces ecrans passent par ce drapeau: le mouvement est
/// une decoration, jamais une condition pour comprendre la page.
bool etabReduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Contraint le contenu a une bande centree, alignee en haut.
class EtabContentBand extends StatelessWidget {
  final Widget child;

  const EtabContentBand({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kEtabContentMaxWidth),
        child: child,
      ),
    );
  }
}

/// Fond ambiant: deux halos qui derivent lentement derriere le contenu.
///
/// Volontairement tres peu contraste et tres lent: l'ecran doit paraitre vivant
/// sans jamais tirer l'oeil loin du contenu.
class EtabAmbientBackdrop extends StatefulWidget {
  /// Teintes des halos. Par defaut celles du theme; la fiche d'un
  /// etablissement passe sa teinte d'identite pour que le fond prolonge la
  /// couleur de son en-tete.
  final List<Color>? tints;

  const EtabAmbientBackdrop({super.key, this.tints});

  @override
  State<EtabAmbientBackdrop> createState() => _EtabAmbientBackdropState();
}

class _EtabAmbientBackdropState extends State<EtabAmbientBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 26),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final still = etabReduceMotion(context);
    final tints =
        widget.tints ?? [scheme.primary, scheme.tertiary, scheme.secondary];

    Widget halo({
      required Color color,
      required double diameter,
      required Alignment base,
      required double phase,
      required double drift,
    }) {
      return AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // Lissajous lent: la trajectoire ne se repete pas visiblement.
          final t = still ? 0.0 : (_controller.value + phase) * 2 * math.pi;
          final dx = math.sin(t) * drift;
          final dy = math.cos(t * 0.75) * drift * 0.6;
          return Align(
            alignment: base,
            child: Transform.translate(
              offset: Offset(dx, dy),
              child: Container(
                width: diameter,
                height: diameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [color, color.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    return IgnorePointer(
      child: ClipRect(
        child: Stack(
          children: [
            halo(
              color: tints[0].withValues(alpha: 0.16),
              diameter: 460,
              base: const Alignment(-1.05, -0.95),
              phase: 0,
              drift: 42,
            ),
            halo(
              color: tints[1 % tints.length].withValues(alpha: 0.13),
              diameter: 520,
              base: const Alignment(1.1, 0.9),
              phase: 0.42,
              drift: 52,
            ),
            halo(
              color: tints[2 % tints.length].withValues(alpha: 0.09),
              diameter: 380,
              base: const Alignment(0.85, -1.05),
              phase: 0.71,
              drift: 34,
            ),
          ],
        ),
      ),
    );
  }
}

/// Apparition en cascade: fondu + montee de quelques pixels, decalee selon la
/// position dans la liste.
///
/// Joue une seule fois par element. Un element conserve son State tant que sa
/// cle ne change pas, donc filtrer la liste ne rejoue pas l'animation des
/// lignes deja affichees, seulement celle des nouvelles.
class EtabStaggeredReveal extends StatefulWidget {
  final int index;
  final Widget child;

  const EtabStaggeredReveal({
    super.key,
    required this.index,
    required this.child,
  });

  @override
  State<EtabStaggeredReveal> createState() => _EtabStaggeredRevealState();
}

class _EtabStaggeredRevealState extends State<EtabStaggeredReveal>
    with SingleTickerProviderStateMixin {
  static const _revealMs = 420;

  late final int _delayMs;
  late final AnimationController _controller;
  late final Animation<double> _reveal;

  @override
  void initState() {
    super.initState();
    // Cascade plafonnee: au-dela d'une dizaine de lignes, attendre plus
    // longtemps ne se lit plus comme un rythme mais comme une latence.
    _delayMs = math.min(widget.index, 10) * 45;
    final totalMs = _delayMs + _revealMs;

    // Le decalage passe par un Interval, pas par un Timer: un seul controleur
    // demarre des initState, donc l'animation se termine avec le pipeline de
    // frames normal. Avec un Timer, un arbre rendu sans frame suivante restait
    // bloque a l'opacite 0, c'est-a-dire une liste vide.
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );
    _reveal = CurvedAnimation(
      parent: _controller,
      curve: Interval(_delayMs / totalMs, 1, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (etabReduceMotion(context)) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _reveal,
      builder: (context, child) {
        return Opacity(
          opacity: _reveal.value,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - _reveal.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Intitule de section: petites capitales suivies d'un filet.
class EtabSectionLabel extends StatelessWidget {
  final String label;

  const EtabSectionLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: scheme.outlineVariant, height: 1)),
        ],
      ),
    );
  }
}

/// Teintes d'identite: deux ecoles au logo generique restent distinguables.
const List<List<Color>> _identityRamps = <List<Color>>[
  [Color(0xFF8B5CF6), Color(0xFF6366F1)],
  [Color(0xFF38BDF8), Color(0xFF0EA5E9)],
  [Color(0xFF10B981), Color(0xFF059669)],
  [Color(0xFFF59E0B), Color(0xFFD97706)],
];

List<Color> etabRamp(Etablissement etab) =>
    _identityRamps[etab.id.abs() % _identityRamps.length];

/// Le code court se range entre parentheses en base ("... Omar Bah (CSOB)").
final RegExp _trailingCode = RegExp(r'\s*\(([^()]{1,12})\)\s*$');

/// Nom sans son code: le sigle encombre le titre alors qu'il tient mieux en
/// sous-titre, ou il distingue deux etablissements homonymes.
String etabDisplayName(Etablissement etab) {
  final name = etab.name.trim();
  final stripped = name.replaceFirst(_trailingCode, '').trim();
  // Un nom reduit a son seul sigle ne doit pas disparaitre du titre.
  return stripped.isEmpty ? name : stripped;
}

String? etabCode(Etablissement etab) {
  final match = _trailingCode.firstMatch(etab.name.trim());
  return match?.group(1)?.trim();
}

/// Sous-titre: le sigle d'abord s'il existe, puis l'adresse, ou a defaut la
/// nature de l'etablissement. Deux "Lycee Technique Oumar Bah" sans adresse
/// ne se distinguent que par leur sigle.
String etabSubtitle(Etablissement etab) {
  final code = etabCode(etab);
  final address = (etab.address ?? '').trim();
  final tail = address.isEmpty ? 'Établissement scolaire' : address;
  return code == null || code.isEmpty ? tail : '$code · $tail';
}

String etabFoldAccents(String value) {
  const from = 'àâäáãçéèêëíìîïñóòôöõúùûüýÿ';
  const to = 'aaaaaceeeeiiiinooooouuuuyy';
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final index = from.indexOf(char);
    buffer.write(index == -1 ? char : to[index]);
  }
  return buffer.toString();
}

/// Etiquette de nature, deduite du nom: le modele n'expose aucun type et le
/// backend n'en stocke pas.
String etabTag(Etablissement etab) {
  final name = etabFoldAccents(etab.name);

  // "Etablissement Demo" contient aussi "etablissement": le cas demo passe en
  // premier, sinon il tomberait dans le libelle generique.
  if (name.contains('demo')) {
    return 'DEMO';
  }
  if (name.contains('complexe')) {
    return 'COMPLEXE';
  }
  if (name.contains('lycee')) {
    return 'LYCEE';
  }
  if (name.contains('college')) {
    return 'COLLEGE';
  }
  if (name.contains('institut') || name.contains('ifp')) {
    return 'INSTITUT';
  }
  if (name.contains('universite') || name.contains('faculte')) {
    return 'UNIVERSITE';
  }
  if (name.contains('ecole') || name.contains('groupe scolaire')) {
    return 'ECOLE';
  }
  return 'ÉTABLISSEMENT';
}

String etabInitials(Etablissement etab) {
  final words = etab.name
      .trim()
      .split(RegExp(r'[\s-]+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) {
    return '?';
  }
  if (words.length == 1) {
    final word = words.first;
    return (word.length == 1 ? word : word.substring(0, 2)).toUpperCase();
  }
  return (words[0][0] + words[1][0]).toUpperCase();
}

/// Tag de la pastille d'identite pour la transition portail -> fiche.
///
/// Un seul element vole: la pastille. Faire voler aussi le titre donnait un
/// texte blanc de 30px au-dessus d'une tuile claire pendant le trajet, donc
/// illisible a mi-course.
///
/// Un tag doit etre unique par ecran: le portail ne montre jamais deux fois le
/// meme etablissement (la carte "Reprendre" est retiree de la grille), la
/// condition tient.
String etabIdentityHeroTag(Etablissement etab) => 'etab-identity-${etab.id}';

/// Pastille d'identite: le logo s'il existe, sinon les initiales sur la
/// teinte de l'etablissement.
class EtabIdentityBadge extends StatelessWidget {
  final Etablissement etab;
  final double size;

  const EtabIdentityBadge({super.key, required this.etab, this.size = 42});

  @override
  Widget build(BuildContext context) {
    final ramp = etabRamp(etab);
    final logo = etab.logoUrlForDisplay;
    final radius = BorderRadius.circular(size * 0.28);

    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: ramp,
        ),
      ),
      child: Text(
        etabInitials(etab),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.33,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
    );

    if (logo == null || logo.isEmpty) {
      return fallback;
    }

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          logo,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => fallback,
        ),
      ),
    );
  }
}

/// Etiquette de nature, posee sur une surface neutre (tuile du portail).
class EtabTypeTag extends StatelessWidget {
  final String label;
  final List<Color> ramp;

  const EtabTypeTag({super.key, required this.label, required this.ramp});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ramp.first.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ramp.first.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Color.alphaBlend(
            ramp.first.withValues(alpha: 0.55),
            scheme.onSurface,
          ),
          fontWeight: FontWeight.w800,
          fontSize: 9,
          letterSpacing: 0.9,
          height: 1.2,
        ),
      ),
    );
  }
}

/// Bandeau de bas de page: meme promesse sur le portail et sur la fiche.
class EtabSecureFooter extends StatelessWidget {
  const EtabSecureFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        // Translucide: le fond ambiant continue derriere la barre au lieu de
        // s'arreter net sur une bande opaque.
        color: scheme.surfaceContainerLow.withValues(alpha: 0.72),
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 13,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Connexion chiffrée — vos données sont protégées',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Le fond des ecrans publics: le portail de selection et la connexion.
///
/// Les deux se suivent dans le parcours -- on choisit son ecole, puis on s'y
/// connecte -- et se ressemblaient pourtant a peine: halos nus d'un cote,
/// fond compose de l'autre. Un seul widget les habille desormais.
///
/// Les halos du portail seuls ne suffisaient pas ici: ils mesurent 460 a 520
/// px et se diluent sur un ecran de 1920, ou la page paraissait alors d'un
/// noir uni. Trois couches s'y ajoutent, toutes dessinees -- donc sans un
/// octet d'image a telecharger:
///
/// 1. un degrade de base qui donne de la profondeur du coin haut-gauche au
///    coin bas-droit;
/// 2. une lueur d'accent derriere l'endroit ou vit la carte, pour que l'oeil
///    y aille en premier;
/// 3. une vignette qui assombrit les bords et ramene le regard au centre.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'etablissement_identity.dart';

class FondEcranPublic extends StatelessWidget {
  /// Teintes des halos animes.
  ///
  /// Nulles au portail: il s'affiche avant qu'une ecole soit choisie, et n'a
  /// donc pas de teinte propre a porter. Les halos gardent alors celles du
  /// theme.
  final List<Color>? tints;

  /// Photo de fond, si l'on en a depose une.
  ///
  /// Elle occupe la moitie gauche sur grand ecran -- celle de la marque -- et
  /// toute la page en colonne unique. Toujours sous un voile: une photo nue
  /// rendrait illisible le texte pose dessus, et les photos d'ecole sont
  /// prises a toute heure, donc de luminosite imprevisible.
  final String? photoUrl;

  /// Ou poser la lueur principale: a droite quand la carte y vit, au centre
  /// en colonne unique.
  final Alignment ancrageLueur;

  /// Fraction de la largeur occupee par la photo (1 = toute la page).
  final double largeurPhoto;

  /// Position du curseur, en coordonnees d'alignement (-1 a 1).
  ///
  /// Nulle au doigt et au clavier: la lueur reste alors a son ancrage plutot
  /// que de sauter au dernier endroit touche.
  final Alignment? curseur;

  const FondEcranPublic({
    super.key,
    this.tints,
    this.photoUrl,
    this.largeurPhoto = 1,
    this.curseur,
    this.ancrageLueur = Alignment.centerRight,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.surface,
                  Color.alphaBlend(
                    scheme.primary.withValues(alpha: 0.06),
                    scheme.surfaceContainer,
                  ),
                  scheme.surface,
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
          if (photoUrl != null && photoUrl!.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: largeurPhoto,
                heightFactor: 1,
                child: _PhotoVoilee(url: photoUrl!),
              ),
            ),
          EtabAmbientBackdrop(tints: tints),
          // La lueur qui designe la carte, et qui suit le curseur. Large et
          // tres diffuse: une tache franche se lirait comme un defaut
          // d'affichage. Au doigt, aucun curseur n'existe et elle reste a son
          // ancrage.
          IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: curseur ?? ancrageLueur,
                  radius: 0.9,
                  colors: [
                    scheme.primary.withValues(alpha: 0.16),
                    scheme.primary.withValues(alpha: 0.04),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
          ),

          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.1,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.28),
                  ],
                  stops: const [0.55, 1],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// La photo de l'ecole, assombrie et fondue dans la page.
///
/// Trois precautions, toutes necessaires: un voile sombre pour que le texte
/// reste lisible quelle que soit la photo, un degrade vers la droite pour que
/// l'image se fonde dans le fond au lieu de s'arreter net, et un repli
/// silencieux -- une photo introuvable ne doit pas barrer l'ecran de
/// connexion.
class _PhotoVoilee extends StatelessWidget {
  final String url;

  const _PhotoVoilee({required this.url});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0, 0.55, 1],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Un flou leger, dans sa propre couche: le texte pose par-dessus
          // reste net quelle que soit la photo, et les details de l'image ne
          // se disputent plus l'oeil avec les libelles. `RepaintBoundary`
          // n'est pas decoratif ici -- sans lui, les halos animes du parent
          // feraient recalculer ce flou a chaque image.
          RepaintBoundary(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
                // Pas de fondu d'apparition par defaut: la photo surgirait
                // apres le reste de la page, ce qui se remarque plus que son
                // absence.
                frameBuilder: (context, child, frame, charge) {
                  return AnimatedOpacity(
                    opacity: frame == null && !charge ? 0 : 1,
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutCubic,
                    child: child,
                  );
                },
              ),
            ),
          ),
          // Le voile protege la lisibilite du texte, il ne doit pas effacer la
          // photo. Il montait a 0,92 d'opacite: une image deposee ne se voyait
          // pas du tout, et l'ecole croyait son envoi perdu. Il s'arrete
          // desormais a 0,74 la ou le texte se pose -- en bas a gauche -- et
          // descend a 0,42 ailleurs, ou rien n'est ecrit.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
                colors: [
                  scheme.surface.withValues(alpha: 0.74),
                  scheme.surface.withValues(alpha: 0.52),
                  scheme.surface.withValues(alpha: 0.42),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

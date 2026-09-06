/// L'identite de l'ecole sur l'ecran de connexion.
///
/// Elle n'existait qu'au-dela de 980 px de large: sous ce seuil, la colonne
/// entiere disparaissait et il ne restait qu'une carte nue sur fond sombre --
/// or c'est l'ecran que voient la plupart des parents, sur telephone. La
/// marque ne disparait plus, elle se replie: le panneau devient un en-tete
/// d'une ligne, qui garde le logo, le nom et le sigle.
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/branding.dart';
import '../../../../models/etablissement.dart';
import '../../../../widgets/etablissement_identity.dart';

/// Le panneau large, a gauche du formulaire.
class LoginBrandPanel extends StatelessWidget {
  final Etablissement etablissement;

  /// Logo de secours quand l'etablissement n'en publie pas.
  final String? logoDeMarque;

  /// Ce que l'ecole ecrit d'elle-meme (facultatif).
  final String titre;
  final String sousTitre;

  /// Coordonnee affichee en pastille, deja mise en forme.
  final String? contact;

  /// Fenetre courte: le logo cede la place au texte plutot que l'inverse.
  final bool dense;

  const LoginBrandPanel({
    super.key,
    required this.etablissement,
    this.logoDeMarque,
    this.titre = '',
    this.sousTitre = '',
    this.contact,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // L'accent de l'ecole, et non la teinte tiree de son identifiant: cette
    // derniere sortait un orange sur une page entierement violette, et deux
    // couleurs franches sans rapport donnent l'impression d'un assemblage.
    final accent = scheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        EtabStaggeredReveal(index: 0, child: const SalutationDuJour()),
        const SizedBox(height: 14),
        EtabStaggeredReveal(
          index: 1,
          child: LoginLogoEtablissement(
            etablissement: etablissement,
            logoDeMarque: logoDeMarque,
            hauteur: dense ? 96 : 138,
          ),
        ),
        const SizedBox(height: 22),
        EtabStaggeredReveal(
          index: 2,
          child: _TitreEnDegrade(
            texte: etabDisplayName(etablissement),
            dense: dense,
          ),
        ),
        const SizedBox(height: 10),
        EtabStaggeredReveal(
          index: 3,
          child: Text(
            etabSubtitle(etablissement),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 16),
        EtabStaggeredReveal(
          index: 4,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              // Une page de connexion qui ne dit que « connexion » n'annonce
              // rien. L'ecole peut ecrire sa propre phrase; a defaut, celle-ci
              // dit au moins a quoi l'on accede.
              sousTitre.isNotEmpty
                  ? sousTitre
                  : 'Notes, emplois du temps, paiements et bulletins : tout '
                        'l\'établissement dans un seul espace.',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
        ),
        if (titre.isNotEmpty) ...[
          const SizedBox(height: 12),
          EtabStaggeredReveal(
            index: 5,
            child: Text(
              titre,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        EtabStaggeredReveal(
          index: 6,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Atout(
                icon: Icons.verified_user_outlined,
                label: 'Connexion sécurisée',
                accent: accent,
              ),
              _Atout(
                icon: Icons.devices_rounded,
                label: 'Ordinateur, tablette et mobile',
                accent: accent,
              ),
              if (contact != null && contact!.isNotEmpty)
                _Atout(
                  icon: Icons.call_outlined,
                  label: contact!,
                  accent: accent,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Le nom de l'ecole, en grand, moitie accent moitie clair.
///
/// Le degrade reprend celui du portail: le titre y est le seul element qui
/// porte la couleur, ce qui le designe comme le sujet de la page.
class _TitreEnDegrade extends StatelessWidget {
  final String texte;
  final bool dense;

  const _TitreEnDegrade({required this.texte, required this.dense});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final style = theme.textTheme.displaySmall?.copyWith(
      // Sora ici, Inter partout ailleurs: c'est le contraste entre les deux
      // qui donne au nom de l'ecole son statut de titre, plutot qu'une
      // graisse de plus sur la meme police.
      fontFamily: 'Sora',
      fontSize: dense ? 32 : 42,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.8,
      height: 1.08,
      color: Colors.white,
    );

    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [scheme.onSurface, scheme.primary],
      ).createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Text(
        texte,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

/// La meme identite, repliee sur une ligne, au-dessus du formulaire.
///
/// [action] se pose en fin de ligne: c'est la ou vit le bouton des reglages
/// en colonne unique, un coin d'ecran l'y ferait chevaucher la carte.
class LoginBrandHeader extends StatelessWidget {
  final Etablissement etablissement;
  final Widget? action;

  const LoginBrandHeader({super.key, required this.etablissement, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        EtabIdentityBadge(etab: etablissement, size: 46),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                etabDisplayName(etablissement),
                // Deux lignes: sur un telephone, « Complexe Scolaire Omar
                // Bah » se coupait apres le troisieme mot, et l'ecole ne
                // lisait plus son propre nom sur sa page d'accueil.
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  height: 1.15,
                ),
              ),
              Text(
                etabSubtitle(etablissement),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 8), action!],
      ],
    );
  }
}

/// Le logo de l'ecole, pose sur une plaque claire.
///
/// La plaque n'est pas un ornement: la plupart des logos d'ecole sont dessines
/// en noir sur fond blanc, et le PNG livre garde ce fond. Pose a nu sur une
/// page sombre, il formait un rectangle blanc franc -- une tache, pas une
/// marque. La fiche etablissement resout deja le probleme de cette facon.
///
/// `EtabIdentityBadge` ne convient pas ici: il cadre en `cover` dans un
/// carre, ce qui rognerait un logo large. Il reste le bon choix aux petites
/// tailles, ou le carre et les initiales de repli sont ce qu'on veut.
class LoginLogoEtablissement extends StatelessWidget {
  final Etablissement etablissement;
  final String? logoDeMarque;
  final double hauteur;

  const LoginLogoEtablissement({
    super.key,
    required this.etablissement,
    this.logoDeMarque,
    required this.hauteur,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.22),
            blurRadius: 28,
            offset: const Offset(0, 12),
            spreadRadius: -6,
          ),
        ],
      ),
      // La plaque epouse le logo, avec un carre pour plancher: le temps qu'un
      // logo distant arrive, l'image ne mesure rien et la plaque se reduisait
      // a une barre verticale. Pas de `Center` ici -- il s'etendrait a toute
      // la largeur offerte par la colonne, et la plaque traversait l'ecran.
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: hauteur),
        child: SizedBox(height: hauteur, child: _image()),
      ),
    );
  }

  Widget _image() {
    final distant = etablissement.logoUrlForDisplay;
    if (distant != null && distant.isNotEmpty) {
      return _reseau(distant);
    }
    final marque = logoDeMarque ?? '';
    if (marque.isNotEmpty) {
      return _reseau(marque);
    }
    return _asset();
  }

  Widget _reseau(String url) => Image.network(
    url,
    height: hauteur,
    fit: BoxFit.contain,
    alignment: Alignment.center,
    // Les memes reglages que la branche asset: sans eux, un logo de 2000 px
    // etait decode en pleine resolution pour etre affiche a 138.
    cacheHeight: (hauteur * 3).round(),
    filterQuality: FilterQuality.medium,
    errorBuilder: (_, _, _) => _asset(),
  );

  Widget _asset() => Image.asset(
    SchoolBranding.logoAsset,
    height: hauteur,
    fit: BoxFit.contain,
    alignment: Alignment.center,
    cacheWidth: 640,
    filterQuality: FilterQuality.medium,
  );
}

/// Pastille de reassurance.
class _Atout extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _Atout({required this.icon, required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 6),
          // Flexible: le numero de telephone depassait la largeur offerte par
          // le Wrap parent.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

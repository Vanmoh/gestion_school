import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/etablissement.dart';
import '../widgets/etablissement_identity.dart';

/// Fiche d'un etablissement.
///
/// Prolongement du portail de selection: meme bande de contenu, meme fond
/// ambiant, meme teinte d'identite, meme cascade d'apparition. La page ne
/// redefinit aucune couleur en dur, tout vient du ColorScheme actif ou de la
/// teinte de l'etablissement, sinon la fiche changeait d'apparence en theme
/// sombre alors que le portail suivait le theme.
class EtablissementDetailsScreen extends StatelessWidget {
  final Etablissement etablissement;

  /// Entree dans l'etablissement depuis la fiche.
  ///
  /// Optionnel: la fiche s'ouvre depuis des contextes qui n'ont pas tous le
  /// droit de changer d'etablissement. Sans ce rappel, la page reste une
  /// consultation et n'affiche aucun bouton d'action.
  final FutureOr<void> Function(Etablissement)? onSelect;

  const EtablissementDetailsScreen({
    super.key,
    required this.etablissement,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 760;
    final ramp = etabRamp(etablissement);

    final address = (etablissement.address ?? '').trim();
    final phone = (etablissement.phone ?? '').trim();
    final email = (etablissement.email ?? '').trim();

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Stack(
        children: [
          // Le fond reprend la teinte de l'etablissement: la fiche prolonge la
          // couleur de la tuile sur laquelle l'utilisateur vient de cliquer.
          Positioned.fill(
            child: EtabAmbientBackdrop(
              tints: [ramp.first, ramp.last, scheme.primary],
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EtabContentBand(
                  child: _DetailsTopBar(etab: etablissement, compact: compact),
                ),
                Expanded(
                  child: EtabContentBand(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 16 : 28,
                        4,
                        compact ? 16 : 28,
                        24,
                      ),
                      children: [
                        EtabStaggeredReveal(
                          index: 0,
                          child: _IdentityHeader(
                            etab: etablissement,
                            compact: compact,
                          ),
                        ),
                        const EtabSectionLabel('Coordonnées'),
                        EtabStaggeredReveal(
                          index: 1,
                          child: _DetailsCard(
                            child: Column(
                              children: [
                                _ContactRow(
                                  icon: Icons.location_on_outlined,
                                  label: 'Adresse',
                                  value: address,
                                  ramp: ramp,
                                ),
                                _ContactRow(
                                  icon: Icons.call_outlined,
                                  label: 'Téléphone',
                                  value: phone,
                                  ramp: ramp,
                                ),
                                _ContactRow(
                                  icon: Icons.mail_outline_rounded,
                                  label: 'E-mail',
                                  value: email,
                                  ramp: ramp,
                                  last: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const EtabSectionLabel('Identité visuelle'),
                        EtabStaggeredReveal(
                          index: 2,
                          child: _DetailsCard(
                            padding: EdgeInsets.all(compact ? 12 : 14),
                            child: _LogoPanel(
                              etab: etablissement,
                              compact: compact,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (onSelect != null)
                  EtabContentBand(
                    child: _SelectBar(
                      etab: etablissement,
                      compact: compact,
                      onSelect: onSelect!,
                    ),
                  ),
                const EtabSecureFooter(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Barre haute: retour et titre, sans AppBar opaque.
///
/// Une AppBar pleine aurait coupe le fond ambiant par une bande de couleur,
/// alors que le portail laisse le fond courir jusqu'en haut.
class _DetailsTopBar extends StatelessWidget {
  final Etablissement etab;
  final bool compact;

  const _DetailsTopBar({required this.etab, required this.compact});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 8 : 20, 8, compact ? 16 : 28, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Retour',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: scheme.onSurface,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Fiche établissement',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                Text(
                  etabDisplayName(etab),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// En-tete: la carte du portail, agrandie.
///
/// Le degrade est celui de la pastille d'identite, pas une couleur maison: la
/// fiche se lit comme la suite de la tuile cliquee.
class _IdentityHeader extends StatelessWidget {
  final Etablissement etab;
  final bool compact;

  const _IdentityHeader({required this.etab, required this.compact});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final ramp = etabRamp(etab);
    final code = etabCode(etab);
    final address = (etab.address ?? '').trim();

    return Container(
      padding: EdgeInsets.all(compact ? 16 : 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: ramp,
        ),
        boxShadow: [
          BoxShadow(
            color: ramp.first.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cadre clair derriere le logo: la plupart des logos sont dessines
              // en noir sur fond blanc et disparaissaient sur le degrade.
              Hero(
                tag: etabIdentityHeroTag(etab),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(compact ? 16 : 18),
                    ),
                    child: EtabIdentityBadge(
                      etab: etab,
                      size: compact ? 44 : 52,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeaderPill(label: etabTag(etab)),
                    const SizedBox(height: 8),
                    Text(
                      etabDisplayName(etab),
                      style: textTheme.headlineSmall?.copyWith(
                        fontSize: compact ? 22 : 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                    if (code != null && code.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        code,
                        style: textTheme.labelMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.86),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            address.isEmpty ? 'Établissement scolaire' : address,
            style: textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pastille claire sur l'en-tete colore.
class _HeaderPill extends StatelessWidget {
  final String label;

  const _HeaderPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.34)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 9.5,
          letterSpacing: 0.9,
          height: 1.2,
        ),
      ),
    );
  }
}

/// Surface des sections: exactement celle des tuiles du portail.
class _DetailsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const _DetailsCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.06),
            blurRadius: 9,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Une coordonnee. Toujours affichee, meme absente: une ligne "Non renseigne"
/// dit que l'information manque, la masquer laisserait croire qu'elle n'existe
/// pas dans la fiche.
class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final List<Color> ramp;
  final bool last;

  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.ramp,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final filled = value.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ramp.first.withValues(alpha: filled ? 0.14 : 0.07),
            ),
            child: Icon(
              icon,
              size: 16,
              color: filled ? ramp.first : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    fontSize: 9.5,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  filled ? value : 'Non renseigné',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: filled ? FontWeight.w600 : FontWeight.w400,
                    color: filled
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          if (filled)
            IconButton(
              tooltip: 'Copier',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$label copié'),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              visualDensity: VisualDensity.compact,
              iconSize: 17,
              color: scheme.onSurfaceVariant,
              icon: const Icon(Icons.copy_rounded),
            ),
        ],
      ),
    );
  }
}

/// Barre d'action: la fiche menait a une impasse, il fallait revenir en
/// arriere pour entrer dans l'etablissement qu'on venait de consulter.
///
/// Elle reste collee au bas de l'ecran plutot que de suivre le defilement: la
/// fiche est longue, et l'action ne doit pas dependre de la position dans la
/// page.
class _SelectBar extends StatefulWidget {
  final Etablissement etab;
  final bool compact;
  final FutureOr<void> Function(Etablissement) onSelect;

  const _SelectBar({
    required this.etab,
    required this.compact,
    required this.onSelect,
  });

  @override
  State<_SelectBar> createState() => _SelectBarState();
}

class _SelectBarState extends State<_SelectBar> {
  bool _busy = false;

  Future<void> _enter() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);

    // La fiche se retire avant l'action: l'appelant redirige souvent vers la
    // connexion, et la fiche resterait empilee derriere cette redirection.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }

    try {
      await widget.onSelect(widget.etab);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text("Impossible d'ouvrir l'établissement : $error"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ramp = etabRamp(widget.etab);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.compact ? 16 : 28,
        4,
        widget.compact ? 16 : 28,
        10,
      ),
      child: FilledButton.icon(
        onPressed: _busy ? null : _enter,
        icon: _busy
            ? SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onPrimary,
                ),
              )
            : const Icon(Icons.login_rounded, size: 17),
        label: Text(
          'Accéder à ${etabDisplayName(widget.etab)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: FilledButton.styleFrom(
          backgroundColor: ramp.first,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(46),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

/// Panneau du logo: fond neutre, image contenue.
class _LogoPanel extends StatelessWidget {
  final Etablissement etab;
  final bool compact;

  const _LogoPanel({required this.etab, required this.compact});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final logo = etab.logoUrlForDisplay;

    final placeholder = Image.asset(
      'assets/images/ecole_photo.png',
      fit: BoxFit.contain,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          minHeight: compact ? 180 : 240,
          maxHeight: compact ? 260 : 330,
        ),
        padding: const EdgeInsets.all(12),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        child: logo == null || logo.isEmpty
            ? placeholder
            : Image.network(
                logo,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

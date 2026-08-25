import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/etablissement_api.dart';
import '../core/network/api_client.dart';
import '../core/network/paged_response.dart';
import '../models/etablissement.dart';
import '../widgets/etablissement_identity.dart';
import 'etablissement_details_screen.dart';

class PublicEtablissementEntryPage extends ConsumerStatefulWidget {
  const PublicEtablissementEntryPage({super.key});

  @override
  ConsumerState<PublicEtablissementEntryPage> createState() =>
      _PublicEtablissementEntryPageState();
}

class _PublicEtablissementEntryPageState
    extends ConsumerState<PublicEtablissementEntryPage> {
  bool _loading = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _erreur = null;
      });
    }
    try {
      final provider = ref.read(etablissementProvider);
      await provider.hydrate();

      final response = await ref
          .read(dioProvider)
          .get(EtablissementApi.etablissements);
      final etablissements = rowsOf(
        response.data,
      ).map(Etablissement.fromJson).toList();
      provider.setEtablissements(etablissements);
      if (mounted) {
        setState(() => _erreur = null);
      }
    } catch (erreur) {
      // L'echec etait avale en silence: le portail affichait « Aucun
      // etablissement disponible » aussi bien pour une base vide que pour un
      // serveur injoignable, et rien ne permettait de relancer l'appel. Un
      // simple pic de latence au demarrage du backend figeait donc l'ecran
      // jusqu'a un rechargement complet de la page -- que rien n'invitait a
      // faire, puisque l'application semblait fonctionner.
      if (mounted) {
        setState(() => _erreur = _raisonLisible(erreur));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// La raison de l'echec, avec l'adresse reellement appelee.
  ///
  /// L'adresse compte autant que la raison: le build web porte parfois une
  /// URL d'API figee a la compilation, et c'est en la lisant qu'on voit
  /// qu'elle ne correspond plus au reseau courant.
  String _raisonLisible(Object erreur) {
    if (erreur is DioException) {
      final cible = erreur.requestOptions.uri.toString();
      final raison = switch (erreur.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'Le serveur n\'a pas répondu à temps.',
        DioExceptionType.connectionError => 'Serveur injoignable.',
        DioExceptionType.badResponse =>
          'Le serveur a répondu ${erreur.response?.statusCode}.',
        DioExceptionType.badCertificate => 'Certificat refusé.',
        DioExceptionType.cancel => 'Appel interrompu.',
        _ => 'Appel impossible.',
      };
      return '$raison\n$cible';
    }
    return erreur.toString();
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(etablissementProvider);

    if (_loading && provider.etablissements.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return EtablissementSelectionScreen(
      loadError: _erreur,
      onRetry: _bootstrap,
      onSelected: (etab) async {
        await ref.read(etablissementProvider).selectEtablissement(etab);
        if (!context.mounted) {
          return;
        }
        Navigator.of(context).pushReplacementNamed('/login');
      },
    );
  }
}

class RequireEtablissementSelection extends ConsumerStatefulWidget {
  final Widget child;
  const RequireEtablissementSelection({required this.child, super.key});

  @override
  ConsumerState<RequireEtablissementSelection> createState() =>
      _RequireEtablissementSelectionState();
}

class _RequireEtablissementSelectionState
    extends ConsumerState<RequireEtablissementSelection> {
  bool _loadingEtablissements = false;
  bool _didTryLoad = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkEtab();
    });
  }

  Future<void> _loadEtablissementsIfNeeded() async {
    final etabProvider = ref.read(etablissementProvider);
    if (_loadingEtablissements ||
        _didTryLoad ||
        etabProvider.etablissements.isNotEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        _didTryLoad = true;
        _loadingEtablissements = true;
      });
    } else {
      _didTryLoad = true;
      _loadingEtablissements = true;
    }
    try {
      final response = await ref
          .read(dioProvider)
          .get(EtablissementApi.etablissements);
      final data = rowsOf(response.data).map(Etablissement.fromJson).toList();
      etabProvider.setEtablissements(data);
    } catch (_) {
      // Keep navigation usable even if API is temporarily unavailable.
    } finally {
      if (mounted) {
        setState(() {
          _loadingEtablissements = false;
        });
      } else {
        _loadingEtablissements = false;
      }
    }
  }

  Future<void> _checkEtab() async {
    if (!mounted || _checking) {
      return;
    }
    _checking = true;

    try {
      await ref.read(etablissementProvider).hydrate();
      await _loadEtablissementsIfNeeded();

      if (!mounted) {
        return;
      }

      final etabProvider = ref.read(etablissementProvider);
      if (etabProvider.selected == null &&
          etabProvider.etablissements.isEmpty &&
          !_loadingEtablissements &&
          !_didTryLoad) {
        _didTryLoad = true;
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final etabProvider = ref.watch(etablissementProvider);

    if (!etabProvider.hydrated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (etabProvider.selected == null) {
      if (_loadingEtablissements && etabProvider.etablissements.isEmpty) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }

      if (etabProvider.etablissements.isNotEmpty) {
        return EtablissementSelectionScreen(
          onSelected: (etab) async {
            await ref.read(etablissementProvider).selectEtablissement(etab);
          },
        );
      }
    }

    return widget.child;
  }
}

/// Surface interactive: se souleve au survol, s'enfonce a l'appui.
///
/// Le builder recoit l'etat de survol pour que le contenu puisse suivre le
/// mouvement (le chevron glisse vers la droite, par exemple).
class _HoverLift extends StatefulWidget {
  final BorderRadius borderRadius;
  final Color surfaceColor;
  final Color borderColor;
  final Color hoverBorderColor;
  final Color glowColor;
  final VoidCallback onTap;
  /// Chemin de secours vers les details au doigt: le bouton dedie n'apparait
  /// qu'au survol, geste dont un ecran tactile ne dispose pas.
  final VoidCallback? onLongPress;
  final Widget Function(BuildContext context, bool hovered) builder;

  const _HoverLift({
    required this.borderRadius,
    required this.surfaceColor,
    required this.borderColor,
    required this.hoverBorderColor,
    required this.glowColor,
    required this.onTap,
    this.onLongPress,
    required this.builder,
  });

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final still = etabReduceMotion(context);
    final duration = still ? Duration.zero : const Duration(milliseconds: 170);

    final scale = still
        ? 1.0
        : _pressed
        ? 0.985
        : _hovered
        ? 1.012
        : 1.0;

    return AnimatedScale(
      scale: scale,
      duration: duration,
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: [
            BoxShadow(
              color: widget.glowColor.withValues(alpha: _hovered ? 0.20 : 0.06),
              blurRadius: _hovered ? 22 : 9,
              offset: Offset(0, _hovered ? 9 : 3),
            ),
          ],
        ),
        child: Material(
          color: widget.surfaceColor,
          borderRadius: widget.borderRadius,
          child: InkWell(
            borderRadius: widget.borderRadius,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onHover: (value) => setState(() => _hovered = value),
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                borderRadius: widget.borderRadius,
                border: Border.all(
                  color: _hovered
                      ? widget.hoverBorderColor
                      : widget.borderColor,
                  width: _hovered ? 1.4 : 1,
                ),
              ),
              child: widget.builder(context, _hovered),
            ),
          ),
        ),
      ),
    );
  }
}

/// Portail de selection: la page a une seule mission, amener l'utilisateur
/// dans son etablissement en un geste. Toutes les couleurs viennent du
/// ColorScheme actif, pour rester coherent avec la connexion et le tableau
/// de bord.
class EtablissementSelectionScreen extends ConsumerStatefulWidget {
  final FutureOr<void> Function(Etablissement) onSelected;

  /// Pourquoi la liste est vide, quand elle l'est faute d'avoir pu la charger.
  final String? loadError;

  /// De quoi relancer l'appel sans recharger la page.
  final Future<void> Function()? onRetry;

  const EtablissementSelectionScreen({
    super.key,
    required this.onSelected,
    this.loadError,
    this.onRetry,
  });

  @override
  ConsumerState<EtablissementSelectionScreen> createState() =>
      _EtablissementSelectionScreenState();
}

class _EtablissementSelectionScreenState
    extends ConsumerState<EtablissementSelectionScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  bool _matches(Etablissement etab, String query) {
    if (query.isEmpty) {
      return true;
    }
    final needle = query.toLowerCase();
    return etab.name.toLowerCase().contains(needle) ||
        (etab.address ?? '').toLowerCase().contains(needle) ||
        (etab.email ?? '').toLowerCase().contains(needle);
  }

  Future<void> _select(Etablissement etab) async {
    await widget.onSelected(etab);
  }

  void _openDetails(Etablissement etab) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EtablissementDetailsScreen(
          etablissement: etab,
          onSelect: _select,
        ),
      ),
    );
  }

  /// Demande d'acces: aucune API ne couvre l'inscription a un etablissement,
  /// la carte explique donc la marche a suivre plutot que de promettre une
  /// action qui n'existe pas.
  void _requestAccess(List<Etablissement> known) {
    // Un etablissement deja visible sert de point de contact: c'est la seule
    // coordonnee que le portail connaisse avant l'authentification.
    Etablissement? contact;
    for (final etab in known) {
      if ((etab.phone ?? '').trim().isNotEmpty ||
          (etab.email ?? '').trim().isNotEmpty) {
        contact = etab;
        break;
      }
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        final textTheme = Theme.of(dialogContext).textTheme;

        return AlertDialog(
          icon: Icon(Icons.person_add_alt_1_outlined, color: scheme.primary),
          title: const Text('Demander un accès'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'La liste ci-dessus ne contient que les établissements ouverts '
                'à votre compte. Pour en rejoindre un autre, contactez son '
                'administrateur : lui seul peut créer votre accès.',
                style: textTheme.bodyMedium,
              ),
              if (contact != null) ...[
                const SizedBox(height: 14),
                Text(
                  'Contact disponible',
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                _ContactLine(
                  icon: Icons.apartment_rounded,
                  value: etabDisplayName(contact),
                ),
                if ((contact.phone ?? '').trim().isNotEmpty)
                  _ContactLine(
                    icon: Icons.call_outlined,
                    value: contact.phone!.trim(),
                  ),
                if ((contact.email ?? '').trim().isNotEmpty)
                  _ContactLine(
                    icon: Icons.mail_outline_rounded,
                    value: contact.email!.trim(),
                  ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = ref.watch(etablissementProvider);
    final all = provider.etablissements;
    final resume = provider.selected;

    // La maquette presente les etablissements par ordre alphabetique: sans
    // tri, l'ordre depend de l'API et deux chargements ne donnent pas la meme
    // grille.
    //
    // Le tri se fait sur le nom sans accents: compare tel quel, "Établissement"
    // (E accentue) passe apres "Lycee", parce que la comparaison porte sur les
    // codes UTF-16 et non sur l'alphabet.
    final sorted = [...all]
      ..sort(
        (a, b) => etabFoldAccents(
          etabDisplayName(a),
        ).compareTo(etabFoldAccents(etabDisplayName(b))),
      );

    final filtered = sorted
        .where((etab) => _matches(etab, _searchQuery))
        .toList(growable: false);
    // Le bloc "Reprendre" ne doit pas dupliquer une carte de la grille.
    final others = filtered
        .where((etab) => resume == null || etab.id != resume.id)
        .toList(growable: false);
    final showResume =
        resume != null &&
        _searchQuery.isEmpty &&
        all.any((e) => e.id == resume.id);

    return Scaffold(
      backgroundColor: scheme.surface,
      body: CallbackShortcuts(
        // "/" met le curseur dans la recherche, comme l'indique la touche
        // affichee dans le champ.
        bindings: {
          const SingleActivator(LogicalKeyboardKey.slash): () =>
              _searchFocusNode.requestFocus(),
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              const Positioned.fill(child: EtabAmbientBackdrop()),
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EtabContentBand(
                      child: _PortalHeader(
                        total: all.length,
                        searchController: _searchController,
                        searchFocusNode: _searchFocusNode,
                        searchQuery: _searchQuery,
                        onSearchChanged: (value) =>
                            setState(() => _searchQuery = value.trim()),
                        onClearSearch: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? _EmptyResults(
                              query: _searchQuery,
                              erreur: widget.loadError,
                              onRetry: widget.onRetry,
                            )
                          : EtabContentBand(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final wide = constraints.maxWidth >= 720;
                                  final horizontal = wide ? 28.0 : 16.0;

                                  return ListView(
                                    padding: EdgeInsets.fromLTRB(
                                      horizontal,
                                      4,
                                      horizontal,
                                      24,
                                    ),
                                    children: [
                                      if (showResume) ...[
                                        const EtabSectionLabel('Reprendre'),
                                        EtabStaggeredReveal(
                                          key: ValueKey('resume-${resume.id}'),
                                          index: 0,
                                          child: _ResumeCard(
                                            etab: resume,
                                            onTap: () => _select(resume),
                                            onDetails: () =>
                                                _openDetails(resume),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                      ],
                                      EtabSectionLabel(
                                        showResume
                                            ? 'Autres établissements'
                                            : 'Tous les établissements',
                                      ),
                                      _EtablissementGrid(
                                        etablissements: others,
                                        maxWidth:
                                            constraints.maxWidth -
                                            horizontal * 2,
                                        onSelected: _select,
                                        onDetails: _openDetails,
                                        onRequestAccess: () =>
                                            _requestAccess(all),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                    ),
                    const EtabSecureFooter(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une coordonnee dans la boite "Demander un acces".
class _ContactLine extends StatelessWidget {
  final IconData icon;
  final String value;

  const _ContactLine({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// En-tete: enonce la tache, puis donne l'outil pour l'accomplir.
class _PortalHeader extends StatelessWidget {
  final int total;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;

  const _PortalHeader({
    required this.total,
    required this.searchController,
    required this.searchFocusNode,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final horizontal = wide ? 28.0 : 16.0;

        return Padding(
          padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [scheme.primary, scheme.secondary],
                      ),
                    ),
                    child: const Text(
                      'GS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Gestion Scolaire',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                        ),
                        Text(
                          'Espace multi-établissements',
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
                  const SizedBox(width: 8),
                  _SecureBadge(scheme: scheme, textTheme: textTheme),
                ],
              ),
              const SizedBox(height: 18),
              // Seul "votre établissement" porte le degrade: le contraste entre
              // la partie neutre et la partie accentuee fait lire le titre en
              // deux temps, comme dans la maquette.
              _PortalTitle(fontSize: wide ? 32 : 23),
              const SizedBox(height: 6),
              Text(
                total <= 1
                    ? '$total établissement accessible avec ce compte — '
                          'sélectionnez-le pour continuer.'
                    : '$total établissements accessibles avec ce compte — '
                          'sélectionnez-en un pour continuer.',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: searchController,
                focusNode: searchFocusNode,
                onChanged: onSearchChanged,
                style: textTheme.bodyMedium,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Rechercher un établissement...',
                  hintStyle: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  filled: true,
                  fillColor: scheme.surfaceContainer,
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 19,
                    color: scheme.onSurfaceVariant,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  suffixIcon: searchQuery.isEmpty
                      ? _SlashHint(scheme: scheme, textTheme: textTheme)
                      : IconButton(
                          tooltip: 'Effacer',
                          onPressed: onClearSearch,
                          icon: const Icon(Icons.close_rounded, size: 17),
                        ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 13,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: scheme.primary, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Badge "Sécurisé" de l'en-tete, avec un point qui respire lentement.
class _SecureBadge extends StatefulWidget {
  final ColorScheme scheme;
  final TextTheme textTheme;

  const _SecureBadge({required this.scheme, required this.textTheme});

  @override
  State<_SecureBadge> createState() => _SecureBadgeState();
}

class _SecureBadgeState extends State<_SecureBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = widget.scheme;
    final still = etabReduceMotion(context);
    const live = Color(0xFF22C55E);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = still ? 1.0 : 0.45 + _controller.value * 0.55;
              return Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: live.withValues(alpha: t),
                  boxShadow: [
                    BoxShadow(
                      color: live.withValues(alpha: t * 0.6),
                      blurRadius: 5,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 6),
          Text(
            'Connexion sécurisée',
            style: widget.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Titre en deux temps: une partie neutre, une partie degradee.
///
/// Le degrade ne couvre que le second fragment, donc un ShaderMask sur tout le
/// texte ne suffit pas: les deux fragments sont peints separement et remis
/// bout a bout, avec un retour a la ligne propre en largeur mobile.
class _PortalTitle extends StatelessWidget {
  final double fontSize;

  const _PortalTitle({required this.fontSize});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.headlineSmall?.copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.7,
      height: 1.12,
    );

    return Semantics(
      header: true,
      label: 'Choisissez votre établissement',
      child: ExcludeSemantics(
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Choisissez ', style: style?.copyWith(color: scheme.onSurface)),
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [scheme.primary, scheme.tertiary],
              ).createShader(bounds),
              child: Text('votre établissement', style: style),
            ),
          ],
        ),
      ),
    );
  }
}

/// Touche "/" affichee dans le champ de recherche.
class _SlashHint extends StatelessWidget {
  final ColorScheme scheme;
  final TextTheme textTheme;

  const _SlashHint({required this.scheme, required this.textTheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Tooltip(
        message: 'Appuyez sur / pour rechercher',
        child: Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Text(
            '/',
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Carte "Reprendre": meme langage visuel que les tuiles, mais sur toute la
/// largeur de la bande, parce qu'elle designe un choix unique et non un
/// element parmi d'autres.
class _ResumeCard extends StatelessWidget {
  final Etablissement etab;
  final VoidCallback onTap;
  final VoidCallback onDetails;

  const _ResumeCard({
    required this.etab,
    required this.onTap,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final still = etabReduceMotion(context);
    final radius = BorderRadius.circular(16);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: _HoverLift(
        borderRadius: radius,
        onTap: onTap,
        onLongPress: onDetails,
        surfaceColor: Color.alphaBlend(
          scheme.primary.withValues(alpha: 0.12),
          scheme.surfaceContainerLow,
        ),
        borderColor: scheme.primary.withValues(alpha: 0.55),
        hoverBorderColor: scheme.primary,
        glowColor: scheme.primary,
        builder: (context, hovered) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Hero(
                  tag: etabIdentityHeroTag(etab),
                  child: Material(
                    color: Colors.transparent,
                    child: EtabIdentityBadge(etab: etab, size: 46),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              etabDisplayName(etab),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _ResumePill(scheme: scheme, textTheme: textTheme),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Dernier établissement utilisé',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Détails de ${etabDisplayName(etab)}',
                  onPressed: onDetails,
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  color: scheme.onSurfaceVariant,
                  icon: const Icon(Icons.info_outline_rounded),
                ),
                // Le chevron avance au survol: la carte annonce ou elle mene.
                AnimatedSlide(
                  offset: Offset(hovered && !still ? 0.28 : 0, 0),
                  duration: still
                      ? Duration.zero
                      : const Duration(milliseconds: 170),
                  curve: Curves.easeOut,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: hovered ? scheme.primary : scheme.onSurfaceVariant,
                    size: 21,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Pastille "Reprendre" sur la ligne du dernier etablissement utilise.
class _ResumePill extends StatelessWidget {
  final ColorScheme scheme;
  final TextTheme textTheme;

  const _ResumePill({required this.scheme, required this.textTheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_rounded, size: 11, color: scheme.primary),
          const SizedBox(width: 4),
          Text(
            'Reprendre',
            style: textTheme.labelSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _EtablissementGrid extends StatelessWidget {
  final List<Etablissement> etablissements;
  final double maxWidth;
  final ValueChanged<Etablissement> onSelected;
  final ValueChanged<Etablissement> onDetails;
  final VoidCallback onRequestAccess;

  const _EtablissementGrid({
    required this.etablissements,
    required this.maxWidth,
    required this.onSelected,
    required this.onDetails,
    required this.onRequestAccess,
  });

  @override
  Widget build(BuildContext context) {
    final columns = maxWidth >= 1080
        ? 4
        : maxWidth >= 760
        ? 3
        : maxWidth >= 520
        ? 2
        : 1;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    // Hauteur de tuile: chrome constant + bloc de texte qui suit le reglage
    // de police du systeme.
    final extent = 126.0 + 58.0 * scale;

    // La carte de demande d'acces ferme la grille: elle occupe la case qui
    // suit le dernier etablissement.
    final itemCount = etablissements.length + 1;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: itemCount,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: extent,
      ),
      itemBuilder: (context, index) {
        if (index == etablissements.length) {
          return EtabStaggeredReveal(
            key: const ValueKey('tile-request-access'),
            index: index,
            child: _RequestAccessTile(onTap: onRequestAccess),
          );
        }

        final etab = etablissements[index];
        return EtabStaggeredReveal(
          key: ValueKey('tile-${etab.id}'),
          index: index,
          child: _EtablissementTile(
            etab: etab,
            onTap: () => onSelected(etab),
            onDetails: () => onDetails(etab),
          ),
        );
      },
    );
  }
}

/// Derniere case: la demande d'acces, en pointilles pour se lire comme une
/// case a remplir et non comme un etablissement de plus.
class _RequestAccessTile extends StatefulWidget {
  final VoidCallback onTap;

  const _RequestAccessTile({required this.onTap});

  @override
  State<_RequestAccessTile> createState() => _RequestAccessTileState();
}

class _RequestAccessTileState extends State<_RequestAccessTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final still = etabReduceMotion(context);
    final radius = BorderRadius.circular(16);
    final duration = still ? Duration.zero : const Duration(milliseconds: 170);

    return Material(
      color: scheme.surfaceContainerLow.withValues(alpha: 0.35),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: widget.onTap,
        onHover: (value) => setState(() => _hovered = value),
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: _hovered
                ? scheme.primary.withValues(alpha: 0.7)
                : scheme.outlineVariant,
            radius: 16,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOut,
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _hovered
                        ? scheme.primary.withValues(alpha: 0.18)
                        : scheme.surfaceContainerHighest.withValues(
                            alpha: 0.55,
                          ),
                    border: Border.all(
                      color: _hovered
                          ? scheme.primary.withValues(alpha: 0.6)
                          : scheme.outlineVariant,
                    ),
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    size: 19,
                    color: _hovered ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "Demander l'accès à un autre établissement",
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    color: _hovered ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
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

/// Contour en pointilles suivant un rectangle arrondi.
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ),
      );

    const dash = 5.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _EtablissementTile extends StatelessWidget {
  final Etablissement etab;
  final VoidCallback onTap;
  final VoidCallback onDetails;

  const _EtablissementTile({
    required this.etab,
    required this.onTap,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final radius = BorderRadius.circular(16);
    final ramp = etabRamp(etab);
    final still = etabReduceMotion(context);
    final duration = still ? Duration.zero : const Duration(milliseconds: 180);

    return _HoverLift(
      borderRadius: radius,
      onTap: onTap,
      // Au doigt, le survol n'existe pas: l'appui long remplace le bouton de
      // details qui n'apparait qu'a la souris.
      onLongPress: onDetails,
      surfaceColor: scheme.surfaceContainerLow,
      borderColor: scheme.outlineVariant,
      hoverBorderColor: ramp.first.withValues(alpha: 0.75),
      // Le halo reprend la teinte d'identite de l'etablissement: chaque tuile
      // se souleve avec sa propre couleur.
      glowColor: ramp.first,
      builder: (context, hovered) {
        return ClipRRect(
          borderRadius: radius,
          child: Stack(
            children: [
              // Nappe de couleur derriere la pastille: elle rattache la tuile
              // a l'identite de l'etablissement sans colorer tout le fond.
              Positioned(
                left: -60,
                top: -70,
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: duration,
                    curve: Curves.easeOut,
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          ramp.first.withValues(alpha: hovered ? 0.30 : 0.18),
                          ramp.first.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // La pastille vole jusqu'a l'en-tete de la fiche:
                        // l'utilisateur garde des yeux l'etablissement ouvert.
                        Hero(
                          tag: etabIdentityHeroTag(etab),
                          child: Material(
                            color: Colors.transparent,
                            child: EtabIdentityBadge(etab: etab, size: 40),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topRight,
                            child: EtabTypeTag(label: etabTag(etab), ramp: ramp),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 13),
                    Text(
                      etabDisplayName(etab),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.22,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      etabSubtitle(etab),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        // Les details restent joignables sans encombrer l'etat
                        // au repos, que la maquette laisse vide a gauche.
                        AnimatedOpacity(
                          opacity: hovered ? 1 : 0,
                          duration: duration,
                          child: IgnorePointer(
                            ignoring: !hovered,
                            child: Tooltip(
                              message: 'Détails de ${etabDisplayName(etab)}',
                              child: InkResponse(
                                onTap: onDetails,
                                radius: 18,
                                child: Padding(
                                  padding: const EdgeInsets.all(3),
                                  child: Icon(
                                    Icons.info_outline_rounded,
                                    size: 16,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Accéder',
                          style: textTheme.labelMedium?.copyWith(
                            color: hovered ? ramp.first : scheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        AnimatedSlide(
                          offset: Offset(hovered && !still ? 0.3 : 0, 0),
                          duration: duration,
                          curve: Curves.easeOut,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 5),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: hovered ? ramp.first : scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyResults extends StatelessWidget {
  final String query;

  /// La raison de l'echec, quand la liste est vide faute d'avoir pu la charger.
  final String? erreur;

  /// Relance l'appel: sans lui, seul un rechargement de page sortait de la.
  final Future<void> Function()? onRetry;

  const _EmptyResults({required this.query, this.erreur, this.onRetry});

  /// Trois cas et non deux: la recherche infructueuse, la base sans
  /// etablissement, et le serveur qu'on n'a pas pu joindre. Les deux derniers
  /// portaient le meme texte, ce qui envoyait chercher une panne de reseau
  /// quand la base etait simplement vide -- et l'inverse.
  String get _titre {
    if (query.isNotEmpty) {
      return 'Aucun résultat pour "$query"';
    }
    return erreur == null
        ? 'Aucun établissement disponible'
        : 'Impossible de joindre le serveur';
  }

  String get _explication {
    if (query.isNotEmpty) {
      return 'Essayez un autre nom, une ville ou une adresse e-mail.';
    }
    return erreur ?? 'Aucun établissement n\'est enregistré pour le moment.';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: EtabStaggeredReveal(
        index: 0,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      scheme.primary.withValues(alpha: 0.18),
                      scheme.primary.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: Icon(
                  Icons.travel_explore_outlined,
                  size: 34,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _titre,
                textAlign: TextAlign.center,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _explication,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              // Le bouton n'apparait que sur l'echec de chargement: une
              // recherche sans resultat n'a rien a reessayer.
              if (query.isEmpty && onRetry != null) ...[
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: () => onRetry!(),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Réessayer'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


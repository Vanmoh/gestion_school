import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/etablissement.dart';

import '../screens/etablissement_details_screen.dart';

enum EtablissementLayoutMode { grid, list }

enum EtablissementSearchField { all, name, address, email }

enum EtablissementSortMode { relevance, alphaAsc, alphaDesc }

class EtablissementSelector extends ConsumerWidget {
  final FutureOr<void> Function(Etablissement) onSelected;
  final String searchQuery;
  final EtablissementLayoutMode layoutMode;
  final EtablissementSearchField searchField;
  final EtablissementSortMode sortMode;

  const EtablissementSelector({
    super.key,
    required this.onSelected,
    this.searchQuery = '',
    this.layoutMode = EtablissementLayoutMode.grid,
    this.searchField = EtablissementSearchField.all,
    this.sortMode = EtablissementSortMode.relevance,
  });

  static String titleHeroTag(Etablissement etab) => 'etab-title-${etab.id}';

  static String logoHeroTag(Etablissement etab) => 'etab-logo-${etab.id}';

  static String badgeHeroTag(Etablissement etab) => 'etab-badge-${etab.id}';

  String _subtitle(Etablissement etab) {
    if (etab.address != null && etab.address!.trim().isNotEmpty) {
      return etab.address!.trim();
    }
    if (etab.email != null && etab.email!.trim().isNotEmpty) {
      return etab.email!.trim();
    }
    return 'Établissement scolaire';
  }

  List<Etablissement> _fallbackEtablissements() {
    return [
      Etablissement(id: -101, name: 'CTOB', address: 'Collège Technique OBK'),
      Etablissement(id: -102, name: 'LOBK', address: 'Lycée OBK'),
      Etablissement(
        id: -103,
        name: 'IFP-OBK',
        address: 'Institut de Formation Professionnelle',
      ),
      Etablissement(
        id: -104,
        name: 'Complexe Scolaire',
        address: 'École Maternelle & Primaire',
      ),
    ];
  }

  int _fieldScore(String value, String query) {
    if (query.isEmpty) {
      return 0;
    }
    final raw = value.toLowerCase().trim();
    if (raw.isEmpty) {
      return 0;
    }
    if (raw == query) {
      return 140;
    }
    if (raw.startsWith(query)) {
      return 96;
    }
    final index = raw.indexOf(query);
    if (index >= 0) {
      return 42 - index.clamp(0, 30);
    }
    return 0;
  }

  int _searchScore(Etablissement etab, String query) {
    final name = etab.name;
    final subtitle = _subtitle(etab);
    final email = etab.email ?? '';
    switch (searchField) {
      case EtablissementSearchField.name:
        return _fieldScore(name, query);
      case EtablissementSearchField.address:
        return _fieldScore(subtitle, query);
      case EtablissementSearchField.email:
        return _fieldScore(email, query);
      case EtablissementSearchField.all:
        return (_fieldScore(name, query) * 3) +
            (_fieldScore(subtitle, query) * 2) +
            _fieldScore(email, query);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etablissements = ref.watch(etablissementProvider).etablissements;
    final seedEtablissements =
        (etablissements.isNotEmpty ? etablissements : _fallbackEtablissements())
            .take(4)
            .toList(growable: false);
    final normalizedQuery = searchQuery.trim().toLowerCase();
    final displayEtablissements = normalizedQuery.isEmpty
        ? seedEtablissements
        : seedEtablissements.where((etab) {
            final name = etab.name.toLowerCase();
            final address = _subtitle(etab).toLowerCase();
            final email = (etab.email ?? '').toLowerCase();
            switch (searchField) {
              case EtablissementSearchField.name:
                return name.contains(normalizedQuery);
              case EtablissementSearchField.address:
                return address.contains(normalizedQuery);
              case EtablissementSearchField.email:
                return email.contains(normalizedQuery);
              case EtablissementSearchField.all:
                final haystack = '$name $address $email';
                return haystack.contains(normalizedQuery);
            }
          }).toList(growable: false);

    final sortedEtablissements = <Etablissement>[...displayEtablissements];
    switch (sortMode) {
      case EtablissementSortMode.alphaAsc:
        sortedEtablissements.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case EtablissementSortMode.alphaDesc:
        sortedEtablissements.sort(
          (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        );
        break;
      case EtablissementSortMode.relevance:
        if (normalizedQuery.isEmpty) {
          sortedEtablissements.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        } else {
          sortedEtablissements.sort((a, b) {
            final scoreA = _searchScore(a, normalizedQuery);
            final scoreB = _searchScore(b, normalizedQuery);
            if (scoreA != scoreB) {
              return scoreB.compareTo(scoreA);
            }
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
        }
        break;
    }

    if (sortedEtablissements.isEmpty) {
      return _NoSearchResultCard(query: searchQuery);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final tightLayout = height < 720;
        final crossAxisCount = layoutMode == EtablissementLayoutMode.list
            ? 1
            : (width >= 520 ? 2 : 1);
        final spacing = tightLayout ? 6.0 : 10.0;
        final rows = (sortedEtablissements.length / crossAxisCount).ceil();
        final usableWidth = width - spacing * (crossAxisCount - 1);
        final usableHeight = height - spacing * (rows - 1);
        final tileWidth = usableWidth / crossAxisCount;
        final tileHeight = usableHeight / rows;
        // Keep a safe range so cards stay readable on both short and tall screens.
        final computedAspectRatio = layoutMode == EtablissementLayoutMode.list
            ? ((tileWidth / tileHeight) * 1.85).clamp(2.1, 4.3)
            : ((tileWidth / tileHeight) * 1.18).clamp(1.35, 2.80);

        return Padding(
          padding: EdgeInsets.zero,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: GridView.builder(
              key: ValueKey<String>('${layoutMode.name}_${sortMode.name}_$normalizedQuery'),
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                childAspectRatio: computedAspectRatio,
              ),
              itemCount: sortedEtablissements.length,
              itemBuilder: (context, index) {
                final etab = sortedEtablissements[index];
                return _EtablissementTile(
                  etab: etab,
                  subtitle: _subtitle(etab),
                  tightLayout: tightLayout,
                  index: index,
                  searchActive: normalizedQuery.isNotEmpty,
                  normalizedQuery: normalizedQuery,
                  searchField: searchField,
                  onSelected: onSelected,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _NoSearchResultCard extends StatelessWidget {
  final String query;

  const _NoSearchResultCard({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 520,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFDFEFF), Color(0xFFF0F7FF)],
          ),
          border: Border.all(color: const Color(0xFFD0E1F3)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x16345C85),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFE7F2FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 28,
                color: Color(0xFF2E6294),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Aucun établissement trouvé',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1F4A74),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Aucun resultat pour "$query". Essayez un autre nom ou une autre adresse.',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF5A7592),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EtablissementTile extends StatefulWidget {
  final Etablissement etab;
  final String subtitle;
  final bool tightLayout;
  final int index;
  final bool searchActive;
  final String normalizedQuery;
  final EtablissementSearchField searchField;
  final FutureOr<void> Function(Etablissement) onSelected;

  const _EtablissementTile({
    required this.etab,
    required this.subtitle,
    required this.tightLayout,
    required this.index,
    required this.searchActive,
    required this.normalizedQuery,
    required this.searchField,
    required this.onSelected,
  });

  @override
  State<_EtablissementTile> createState() => _EtablissementTileState();
}

class _EtablissementTileState extends State<_EtablissementTile> {
  bool _hovered = false;
  bool _hoverAccess = false;
  bool _hoverDetails = false;
  Offset _pointer = Offset.zero;

  TextSpan _highlightedSpan({
    required String text,
    required TextStyle baseStyle,
    required bool enabled,
  }) {
    final query = widget.normalizedQuery;
    if (!enabled || query.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final index = lower.indexOf(query, start);
      if (index < 0) {
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start), style: baseStyle));
        }
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: baseStyle));
      }
      final end = (index + query.length).clamp(index, text.length);
      spans.add(
        TextSpan(
          text: text.substring(index, end),
          style: baseStyle.copyWith(
            color: const Color(0xFF0F4C86),
            backgroundColor: const Color(0x99D8EAFE),
            fontWeight: FontWeight.w900,
          ),
        ),
      );
      start = end;
    }
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final tightLayout = widget.tightLayout;
    final baseDelay = Duration(milliseconds: 120 + (widget.index * 95));

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final dx = (_pointer.dx * 12).clamp(-6.0, 6.0);
        final dy = (_pointer.dy * 12).clamp(-6.0, 6.0);

        return _ViewportCascadeReveal(
          delay: baseDelay,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onHover: (event) {
              final nx = ((event.localPosition.dx / width) - 0.5).clamp(-0.5, 0.5);
              final ny = ((event.localPosition.dy / height) - 0.5).clamp(-0.5, 0.5);
              setState(() {
                _hovered = true;
                _pointer = Offset(nx, ny);
              });
            },
            onExit: (_) => setState(() {
              _hovered = false;
              _hoverAccess = false;
              _hoverDetails = false;
              _pointer = Offset.zero;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              transform: Matrix4.identity()
                ..translate(dx * 0.55, (_hovered ? -5.0 : 0.0) + (dy * 0.40))
                ..rotateZ(dx * 0.0035),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFEFFFF), Color(0xFFF2F8FE)],
                ),
                border: Border.all(
                  color: widget.searchActive
                      ? const Color(0xFF78A7D1)
                      : (_hovered ? const Color(0xFF8EB8DF) : const Color(0xFFD1E0F0)),
                  width: widget.searchActive ? 1.4 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _hovered ? const Color(0x2A2B5884) : const Color(0x14295985),
                    blurRadius: _hovered ? 20 : 12,
                    offset: Offset(0, _hovered ? 10 : 6),
                  ),
                  if (widget.searchActive)
                    const BoxShadow(
                      color: Color(0x22598FC2),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -28 + (dx * 0.8),
                    top: -26 + (dy * 0.8),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: _hovered ? 94 : 86,
                      height: _hovered ? 94 : 86,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0x44A8D6F2), Color(0x00A8D6F2)],
                        ),
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.fromLTRB(
                            tightLayout ? 8 : 10,
                            tightLayout ? 6 : 8,
                            tightLayout ? 8 : 10,
                            tightLayout ? 4 : 6,
                          ),
                          decoration: const BoxDecoration(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [Color(0xFFEDF5FE), Color(0xFFE3F0FD)],
                            ),
                          ),
                          child: Column(
                            children: [
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Hero(
                                    tag: EtablissementSelector.badgeHeroTag(widget.etab),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDCEAF9),
                                          borderRadius: BorderRadius.circular(999),
                                          border: Border.all(
                                            color: const Color(0xFFC1D8EF),
                                          ),
                                        ),
                                        child: const Text(
                                          'ETABLISSEMENT',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.8,
                                            color: Color(0xFF2A5B89),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: tightLayout ? 2 : 4),
                              Hero(
                                tag: EtablissementSelector.titleHeroTag(widget.etab),
                                child: Material(
                                  color: Colors.transparent,
                                  child: RichText(
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    text: _highlightedSpan(
                                      text: widget.etab.name,
                                      enabled: widget.searchField == EtablissementSearchField.all ||
                                          widget.searchField == EtablissementSearchField.name,
                                      baseStyle: TextStyle(
                                        fontSize: tightLayout ? 13 : 16,
                                        fontWeight: FontWeight.w900,
                                        color: const Color(0xFF1B456D),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: tightLayout ? 1 : 2),
                              RichText(
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                text: _highlightedSpan(
                                  text: widget.subtitle,
                                  enabled: widget.searchField == EtablissementSearchField.all ||
                                      widget.searchField == EtablissementSearchField.address ||
                                      widget.searchField == EtablissementSearchField.email,
                                  baseStyle: TextStyle(
                                    fontSize: tightLayout ? 10 : 11,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF5E7692),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Transform.translate(
                            offset: Offset(dx * 0.85, dy * 0.95),
                            child: Container(
                              margin: EdgeInsets.fromLTRB(
                                tightLayout ? 7 : 9,
                                tightLayout ? 5 : 7,
                                tightLayout ? 7 : 9,
                                0,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Color(0xFFF9FCFF), Color(0xFFEAF2FC)],
                                ),
                                border: Border.all(color: const Color(0xFFD5E2F1)),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Hero(
                                  tag: EtablissementSelector.logoHeroTag(widget.etab),
                                  child: Material(
                                    color: Colors.transparent,
                                    child:
                                        widget.etab.logoUrlForDisplay != null &&
                                            widget.etab.logoUrlForDisplay!.isNotEmpty
                                        ? Image.network(
                                            widget.etab.logoUrlForDisplay!,
                                            fit: BoxFit.contain,
                                            width: double.infinity,
                                            filterQuality: FilterQuality.medium,
                                            errorBuilder: (context, error, stackTrace) => Image.asset(
                                              'assets/images/ecole_photo.png',
                                              fit: BoxFit.contain,
                                              width: double.infinity,
                                            ),
                                          )
                                        : Image.asset(
                                            'assets/images/ecole_photo.png',
                                            fit: BoxFit.contain,
                                            width: double.infinity,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            tightLayout ? 7 : 9,
                            tightLayout ? 5 : 7,
                            tightLayout ? 7 : 9,
                            tightLayout ? 6 : 8,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: MouseRegion(
                                  onEnter: (_) => setState(() => _hoverAccess = true),
                                  onExit: (_) => setState(() => _hoverAccess = false),
                                  child: AnimatedScale(
                                    scale: _hoverAccess ? 1.03 : 1,
                                    duration: const Duration(milliseconds: 150),
                                    child: Stack(
                                      children: [
                                        FilledButton.icon(
                                          icon: Icon(Icons.login_rounded, size: tightLayout ? 13 : 14),
                                          label: const Text('Accéder'),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: _hoverAccess
                                                ? const Color(0xFF1A5187)
                                                : const Color(0xFF1F5D97),
                                            foregroundColor: Colors.white,
                                            minimumSize: Size(0, tightLayout ? 30 : 34),
                                            textStyle: TextStyle(
                                              fontSize: tightLayout ? 11 : 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            elevation: _hoverAccess ? 4 : 0,
                                          ),
                                          onPressed: () async {
                                            try {
                                              await widget.onSelected(widget.etab);
                                            } catch (error) {
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Impossible d\'ouvrir l\'établissement: $error',
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                        ),
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(10),
                                              child: _ShineOverlay(active: !_hoverAccess || _hovered),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: tightLayout ? 6 : 8),
                              Expanded(
                                child: MouseRegion(
                                  onEnter: (_) => setState(() => _hoverDetails = true),
                                  onExit: (_) => setState(() => _hoverDetails = false),
                                  child: AnimatedScale(
                                    scale: _hoverDetails ? 1.03 : 1,
                                    duration: const Duration(milliseconds: 150),
                                    child: OutlinedButton.icon(
                                      icon: Icon(Icons.info_outline, size: tightLayout ? 13 : 14),
                                      label: const Text('Voir Détails'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _hoverDetails
                                            ? const Color(0xFF134D83)
                                            : const Color(0xFF225A90),
                                        minimumSize: Size(0, tightLayout ? 30 : 34),
                                        textStyle: TextStyle(
                                          fontSize: tightLayout ? 11 : 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        side: BorderSide(
                                          color: _hoverDetails
                                              ? const Color(0xFF5F95C7)
                                              : const Color(0xFF79A3CD),
                                        ),
                                        backgroundColor: _hoverDetails
                                            ? const Color(0xFFEFF6FF)
                                            : const Color(0xFFF5FAFF),
                                      ),
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          PageRouteBuilder<void>(
                                            transitionDuration: const Duration(milliseconds: 520),
                                            reverseTransitionDuration: const Duration(milliseconds: 360),
                                            pageBuilder: (context, animation, secondaryAnimation) =>
                                                EtablissementDetailsScreen(
                                              etablissement: widget.etab,
                                            ),
                                            transitionsBuilder: (
                                              context,
                                              animation,
                                              secondaryAnimation,
                                              child,
                                            ) {
                                              final curved = CurvedAnimation(
                                                parent: animation,
                                                curve: Curves.easeOutCubic,
                                              );
                                              return FadeTransition(
                                                opacity: curved,
                                                child: ScaleTransition(
                                                  scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
                                                  child: child,
                                                ),
                                              );
                                            },
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        );
      },
    );
  }
}

class _ViewportCascadeReveal extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const _ViewportCascadeReveal({required this.child, required this.delay});

  @override
  State<_ViewportCascadeReveal> createState() => _ViewportCascadeRevealState();
}

class _ViewportCascadeRevealState extends State<_ViewportCascadeReveal> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
  }

  void _checkVisibility() {
    if (!mounted || _visible) {
      return;
    }
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return;
    }
    final position = renderObject.localToGlobal(Offset.zero);
    final viewport = MediaQuery.sizeOf(context);
    final isVisible = position.dy < viewport.height &&
        position.dy + renderObject.size.height > 0;
    if (!isVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
      return;
    }
    _timer = Timer(widget.delay, () {
      if (mounted) {
        setState(() => _visible = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: _visible ? 1 : 0),
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
      child: widget.child,
      builder: (context, value, child) {
        final t = value.clamp(0.0, 1.0).toDouble();
        return Transform.translate(
          offset: Offset(0, (1 - t) * 26),
          child: Opacity(opacity: t, child: child),
        );
      },
    );
  }
}

class _ShineOverlay extends StatefulWidget {
  final bool active;

  const _ShineOverlay({required this.active});

  @override
  State<_ShineOverlay> createState() => _ShineOverlayState();
}

class _ShineOverlayState extends State<_ShineOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _ShineOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final slide = Tween<double>(begin: -1.4, end: 1.8).transform(_controller.value);
        return Transform.translate(
          offset: Offset(slide * 120, 0),
          child: Transform.rotate(
            angle: -0.28,
            child: Container(
              width: 28,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.0),
                    Colors.white.withValues(alpha: 0.18),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

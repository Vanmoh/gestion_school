import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/etablissement_api.dart';
import '../core/network/api_client.dart';
import '../models/etablissement.dart';
import '../widgets/etablissement_selector.dart';

class PublicEtablissementEntryPage extends ConsumerStatefulWidget {
  const PublicEtablissementEntryPage({super.key});

  @override
  ConsumerState<PublicEtablissementEntryPage> createState() =>
      _PublicEtablissementEntryPageState();
}

class _PublicEtablissementEntryPageState
    extends ConsumerState<PublicEtablissementEntryPage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    try {
      final provider = ref.read(etablissementProvider);
      await provider.hydrate();

      final response = await ref
          .read(dioProvider)
          .get(EtablissementApi.etablissements);
      final etablissements = (response.data as List<dynamic>)
          .map((row) => Etablissement.fromJson(row as Map<String, dynamic>))
          .toList();
      provider.setEtablissements(etablissements);
    } catch (_) {
      // Keep the screen usable; an empty state will be shown if the API is down.
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(etablissementProvider);

    if (_loading && provider.etablissements.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return EtablissementSelectionScreen(
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
      final data = (response.data as List<dynamic>)
          .map((e) => Etablissement.fromJson(e as Map<String, dynamic>))
          .toList();
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

class EtablissementSelectionScreen extends ConsumerStatefulWidget {
  final FutureOr<void> Function(Etablissement) onSelected;

  const EtablissementSelectionScreen({super.key, required this.onSelected});

  @override
  ConsumerState<EtablissementSelectionScreen> createState() =>
      _EtablissementSelectionScreenState();
}

class _EtablissementSelectionScreenState
    extends ConsumerState<EtablissementSelectionScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ambientController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  EtablissementLayoutMode _layoutMode = EtablissementLayoutMode.grid;
  Offset _spotlight = const Offset(0.52, 0.36);

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ambientController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenHeight < 820;
    final veryCompact = screenHeight < 780;
    final rawEtabCount = ref.watch(etablissementProvider).etablissements.length;
    final etabCount = rawEtabCount <= 0
        ? 4
        : (rawEtabCount > 4 ? 4 : rawEtabCount);

    return Scaffold(
      backgroundColor: const Color(0xFFEFF4FB),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(veryCompact ? 48 : (compact ? 56 : 64)),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F355D), Color(0xFF114C77), Color(0xFF156A8D)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Container(
                    width: veryCompact ? 30 : 34,
                    height: veryCompact ? 30 : 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.30),
                      ),
                    ),
                    child: const Icon(
                      Icons.school,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Gestion Scolaire',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: veryCompact ? 18 : (compact ? 21 : 24),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Text(
                      'Plateforme officielle',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: veryCompact ? 10 : 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: _LuxuryBackdropPainter(),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            left: (size.width * _spotlight.dx) - (size.width * 0.22),
            top: (size.height * _spotlight.dy) - (size.width * 0.22),
            child: IgnorePointer(
              child: Container(
                width: size.width * 0.44,
                height: size.width * 0.44,
                decoration: BoxDecoration(
                  gradient: const RadialGradient(
                    colors: [Color(0x44FFFFFF), Color(0x00FFFFFF)],
                  ),
                  borderRadius: BorderRadius.circular(1000),
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _ambientController,
            builder: (context, _) {
              final pulse = _ambientController.value;
              return Stack(
                children: [
                  Positioned(
                    left: -130 + (22 * pulse),
                    bottom: -95 + (16 * pulse),
                    child: Container(
                      width: screenWidth * 0.48,
                      height: screenWidth * 0.40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0x66BFD8F6), Color(0x00BFD8F6)],
                        ),
                        borderRadius: BorderRadius.circular(280),
                      ),
                    ),
                  ),
                  Positioned(
                    right: -70 + (18 * pulse),
                    top: 66 - (12 * pulse),
                    child: Container(
                      width: size.width * 0.36,
                      height: size.width * 0.29,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0x66D7F0EE), Color(0x00D7F0EE)],
                        ),
                        borderRadius: BorderRadius.circular(240),
                      ),
                    ),
                  ),
                  Positioned(
                    left: size.width * 0.30,
                    top: -80 + (15 * pulse),
                    child: Container(
                      width: size.width * 0.22,
                      height: size.width * 0.18,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0x44FFE1C8), Color(0x00FFE1C8)],
                        ),
                        borderRadius: BorderRadius.circular(200),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          MouseRegion(
            onHover: (event) {
              final nx = (event.localPosition.dx / size.width).clamp(0.0, 1.0);
              final ny = (event.localPosition.dy / size.height).clamp(0.0, 1.0);
              setState(() => _spotlight = Offset(nx, ny));
            },
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1060),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: veryCompact ? 10 : 14,
                      vertical: veryCompact ? 4 : 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AnimatedReveal(
                          delay: const Duration(milliseconds: 80),
                          child: Container(
                          padding: EdgeInsets.fromLTRB(
                            veryCompact ? 12 : 18,
                            veryCompact ? 11 : 16,
                            veryCompact ? 12 : 18,
                            veryCompact ? 11 : 14,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFDFEFFFE), Color(0xF0F7FEFF)],
                            ),
                            border: Border.all(color: const Color(0xFFD3E2F2)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x12324F73),
                                blurRadius: 20,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE6F1FC),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: const Color(0xFFC6DBF2)),
                                ),
                                child: const Text(
                                  'ENTREE OFFICIELLE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1,
                                    color: Color(0xFF24557F),
                                  ),
                                ),
                              ),
                              SizedBox(height: veryCompact ? 6 : 8),
                              Text(
                                'Bienvenue sur la plateforme de Gestion Scolaire OUMAR BAH',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: veryCompact ? 16 : (compact ? 21 : 27),
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF163E63),
                                  letterSpacing: 0.2,
                                  height: 1.15,
                                ),
                              ),
                              SizedBox(height: veryCompact ? 4 : 6),
                              Text(
                                'Sélectionnez un établissement pour accéder à la gestion.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: veryCompact ? 11 : (compact ? 13 : 14),
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF476584),
                                ),
                              ),
                              SizedBox(height: veryCompact ? 9 : 11),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  _StatChip(
                                    icon: Icons.domain,
                                    label: '$etabCount etablissements disponibles',
                                  ),
                                  const _StatChip(
                                    icon: Icons.verified_user,
                                    label: 'Acces securise',
                                  ),
                                  const _StatChip(
                                    icon: Icons.bolt,
                                    label: 'Acces rapide',
                                  ),
                                ],
                              ),
                              SizedBox(height: veryCompact ? 9 : 12),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 760),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final compactSearchRow = constraints.maxWidth < 660;
                                    final searchField = TextField(
                                      controller: _searchController,
                                      onChanged: (value) {
                                        setState(() => _searchQuery = value.trim());
                                      },
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1C466E),
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'Rechercher un etablissement...',
                                        hintStyle: const TextStyle(
                                          color: Color(0xFF6A84A1),
                                          fontWeight: FontWeight.w500,
                                        ),
                                        filled: true,
                                        fillColor: const Color(0xFFF3F9FF),
                                        prefixIcon: const Icon(
                                          Icons.search_rounded,
                                          color: Color(0xFF2A5F8D),
                                        ),
                                        suffixIcon: _searchQuery.isEmpty
                                            ? null
                                            : IconButton(
                                                tooltip: 'Effacer',
                                                onPressed: () {
                                                  _searchController.clear();
                                                  setState(() => _searchQuery = '');
                                                },
                                                icon: const Icon(Icons.close_rounded),
                                              ),
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(14),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFC5DCF2),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(14),
                                          borderSide: const BorderSide(
                                            color: Color(0xFF4E83B3),
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    );

                                    final layoutToggle = SegmentedButton<EtablissementLayoutMode>(
                                      segments: const [
                                        ButtonSegment<EtablissementLayoutMode>(
                                          value: EtablissementLayoutMode.grid,
                                          icon: Icon(Icons.grid_view_rounded, size: 16),
                                          label: Text('Grille'),
                                        ),
                                        ButtonSegment<EtablissementLayoutMode>(
                                          value: EtablissementLayoutMode.list,
                                          icon: Icon(Icons.view_agenda_rounded, size: 16),
                                          label: Text('Liste'),
                                        ),
                                      ],
                                      selected: <EtablissementLayoutMode>{_layoutMode},
                                      showSelectedIcon: false,
                                      onSelectionChanged: (selection) {
                                        if (selection.isEmpty) {
                                          return;
                                        }
                                        setState(() => _layoutMode = selection.first);
                                      },
                                      style: ButtonStyle(
                                        foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                                          if (states.contains(WidgetState.selected)) {
                                            return Colors.white;
                                          }
                                          return const Color(0xFF2B5F8E);
                                        }),
                                        backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                                          if (states.contains(WidgetState.selected)) {
                                            return const Color(0xFF2A5F99);
                                          }
                                          return const Color(0xFFEAF3FD);
                                        }),
                                        side: const WidgetStatePropertyAll(
                                          BorderSide(color: Color(0xFFC5D9EF)),
                                        ),
                                      ),
                                    );

                                    if (compactSearchRow) {
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          searchField,
                                          const SizedBox(height: 8),
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: layoutToggle,
                                          ),
                                        ],
                                      );
                                    }

                                    return Row(
                                      children: [
                                        Expanded(child: searchField),
                                        const SizedBox(width: 10),
                                        layoutToggle,
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        ),
                        SizedBox(height: veryCompact ? 6 : 10),
                        Expanded(
                          child: _AnimatedReveal(
                            delay: const Duration(milliseconds: 180),
                            child: EtablissementSelector(
                              searchQuery: _searchQuery,
                              layoutMode: _layoutMode,
                              onSelected: (etab) async {
                                await widget.onSelected(etab);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3FD),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFC9DDF3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF1F5788)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF2C517A),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedReveal extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const _AnimatedReveal({required this.child, required this.delay});

  @override
  State<_AnimatedReveal> createState() => _AnimatedRevealState();
}

class _AnimatedRevealState extends State<_AnimatedReveal> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Timer(widget.delay, () {
      if (mounted) {
        setState(() => _visible = true);
      }
    });
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
        return AnimatedOpacity(
          opacity: t,
          duration: const Duration(milliseconds: 220),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 24),
            child: child,
          ),
        );
      },
    );
  }
}

class _LuxuryBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0x163B6B92)
      ..strokeWidth = 1;
    const spacing = 28.0;
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final dotPaint = Paint()..color = const Color(0x1A6E9FC7);
    for (double y = 18; y < size.height; y += 56) {
      for (double x = 18; x < size.width; x += 56) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

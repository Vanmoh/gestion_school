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

class EtablissementSelectionScreen extends ConsumerWidget {
  final FutureOr<void> Function(Etablissement) onSelected;

  const EtablissementSelectionScreen({super.key, required this.onSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      backgroundColor: const Color(0xFFF2F6FB),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(veryCompact ? 48 : (compact ? 56 : 64)),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF245B95), Color(0xFF143B6B)],
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
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(9),
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
                      letterSpacing: 0.2,
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
          Positioned(
            left: -110,
            bottom: -90,
            child: Container(
              width: screenWidth * 0.45,
              height: screenWidth * 0.38,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0x55C9DBF5), Color(0x00C9DBF5)],
                ),
                borderRadius: BorderRadius.circular(260),
              ),
            ),
          ),
          Positioned(
            right: -80,
            top: 70,
            child: Container(
              width: size.width * 0.34,
              height: size.width * 0.28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x66D9E8FB), Color(0x00D9E8FB)],
                ),
                borderRadius: BorderRadius.circular(220),
              ),
            ),
          ),
          SafeArea(
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
                      Container(
                        padding: EdgeInsets.fromLTRB(
                          veryCompact ? 12 : 16,
                          veryCompact ? 10 : 14,
                          veryCompact ? 12 : 16,
                          veryCompact ? 9 : 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.90),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFD5E2F1)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x18315B89),
                              blurRadius: 16,
                              offset: Offset(0, 7),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Bienvenue sur la plateforme de Gestion Scolaire OUMAR BAH',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: veryCompact
                                    ? 16
                                    : (compact ? 20 : 25),
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF1F3F67),
                                letterSpacing: 0.15,
                              ),
                            ),
                            SizedBox(height: veryCompact ? 3 : 5),
                            Text(
                              'Sélectionnez un établissement pour accéder à la gestion.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: veryCompact
                                    ? 11
                                    : (compact ? 13 : 14),
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF4A607E),
                              ),
                            ),
                            SizedBox(height: veryCompact ? 8 : 10),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                _InfoPill(
                                  icon: Icons.domain,
                                  label:
                                      '$etabCount etablissements disponibles',
                                ),
                                const _InfoPill(
                                  icon: Icons.verified_user,
                                  label: 'Acces securise',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: veryCompact ? 6 : 10),
                      Expanded(
                        child: EtablissementSelector(
                          onSelected: (etab) async {
                            await onSelected(etab);
                          },
                        ),
                      ),
                    ],
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

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD0DEEF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF26588D)),
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

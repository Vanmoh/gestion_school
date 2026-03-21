
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/etablissement_api.dart';
import '../core/network/api_client.dart';
import '../models/etablissement.dart';
import '../widgets/etablissement_selector.dart';

class RequireEtablissementSelection extends ConsumerStatefulWidget {
  final Widget child;
  const RequireEtablissementSelection({required this.child, Key? key}) : super(key: key);

  @override
  ConsumerState<RequireEtablissementSelection> createState() =>
      _RequireEtablissementSelectionState();
}

class _RequireEtablissementSelectionState
    extends ConsumerState<RequireEtablissementSelection> {
  bool _loadingEtablissements = false;
  bool _didTryLoad = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkEtab();
    });
  }

  Future<void> _loadEtablissementsIfNeeded() async {
    final etabProvider = ref.read(etablissementProvider);
    if (_loadingEtablissements || _didTryLoad || etabProvider.etablissements.isNotEmpty) {
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
      final response = await ref.read(dioProvider).get(EtablissementApi.etablissements);
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
    if (!mounted) {
      return;
    }

    await _loadEtablissementsIfNeeded();

    if (!mounted) {
      return;
    }

    final etabProvider = ref.read(etablissementProvider);
    if (etabProvider.selected == null &&
        etabProvider.etablissements.isEmpty &&
        !_loadingEtablissements &&
        !_didTryLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkEtab();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final etabProvider = ref.watch(etablissementProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkEtab();
    });

    if (etabProvider.selected == null) {
      if (_loadingEtablissements && etabProvider.etablissements.isEmpty) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }

      if (etabProvider.etablissements.isNotEmpty) {
        return EtablissementSelectionScreen(
          onSelected: (etab) {
            ref.read(etablissementProvider).selectEtablissement(etab);
          },
        );
      }
    }

    return widget.child;
  }
}

class EtablissementSelectionScreen extends ConsumerWidget {
  final void Function(Etablissement) onSelected;

  const EtablissementSelectionScreen({Key? key, required this.onSelected}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 920;

    return Scaffold(
      backgroundColor: const Color(0xFFEAF1F8),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(72),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2E67A7), Color(0xFF1B4C86)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.school, color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  const Text(
                    'Gestion Scolaire',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (isDesktop) ...const [
                    _TopMenuItem(icon: Icons.dashboard, label: 'Tableau de Bord'),
                    SizedBox(width: 16),
                    _TopMenuItem(icon: Icons.mail, label: 'Messages'),
                    SizedBox(width: 16),
                    _TopMenuItem(icon: Icons.person, label: 'Profil'),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned(
            left: -140,
            bottom: -120,
            child: Container(
              width: 380,
              height: 260,
              decoration: BoxDecoration(
                color: const Color(0xFFDCE9F7),
                borderRadius: BorderRadius.circular(180),
              ),
            ),
          ),
          Positioned(
            right: -120,
            top: 120,
            child: Container(
              width: 320,
              height: 220,
              decoration: BoxDecoration(
                color: const Color(0xDDE3EEF9),
                borderRadius: BorderRadius.circular(160),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1060),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 6),
                      const Text(
                        'Bienvenue sur l\'Application de Gestion Scolaire',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2A446C),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Sélectionnez un établissement pour accéder à la gestion.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF4B5E78),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: EtablissementSelector(
                          onSelected: (etab) {
                            onSelected(etab);
                          },
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFD6E1EE)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x14274E7E),
                              blurRadius: 10,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Wrap(
                          alignment: WrapAlignment.spaceEvenly,
                          runAlignment: WrapAlignment.center,
                          spacing: 24,
                          runSpacing: 8,
                          children: [
                            _FooterFeature(
                              icon: Icons.bar_chart,
                              title: 'Suivi des Élèves',
                              subtitle: 'Consultez les informations des élèves.',
                            ),
                            _FooterFeature(
                              icon: Icons.assignment,
                              title: 'Gestion des Notes',
                              subtitle: 'Gérez les notes et les bulletins scolaires.',
                            ),
                            _FooterFeature(
                              icon: Icons.calendar_month,
                              title: 'Planning Scolaire',
                              subtitle: 'Organisez les emplois du temps.',
                            ),
                          ],
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

class _TopMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TopMenuItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.95)),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.95),
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _FooterFeature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FooterFeature({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 40, color: const Color(0xFF2F68A3)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2F4E75),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF5D6F87),
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

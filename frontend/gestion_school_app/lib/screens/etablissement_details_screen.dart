import 'package:flutter/material.dart';
import '../models/etablissement.dart';
import '../widgets/etablissement_selector.dart';

class EtablissementDetailsScreen extends StatelessWidget {
  final Etablissement etablissement;
  const EtablissementDetailsScreen({super.key, required this.etablissement});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 760;

    final subtitle = (etablissement.address ?? '').trim().isNotEmpty
        ? etablissement.address!.trim()
        : ((etablissement.email ?? '').trim().isNotEmpty
              ? etablissement.email!.trim()
              : 'Etablissement scolaire');

    return Scaffold(
      backgroundColor: const Color(0xFFEFF4FB),
      appBar: AppBar(
        title: const Text('Détails de l\'établissement'),
        elevation: 0,
        backgroundColor: const Color(0xFF123D68),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: _LuxuryBackdropPainter(),
            ),
          ),
          Positioned(
            left: -120,
            top: -70,
            child: Container(
              width: size.width * 0.50,
              height: size.width * 0.42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0x55D5E9FB), Color(0x00D5E9FB)],
                ),
                borderRadius: BorderRadius.circular(280),
              ),
            ),
          ),
          Positioned(
            right: -90,
            bottom: -120,
            child: Container(
              width: size.width * 0.44,
              height: size.width * 0.36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0x44CBECDC), Color(0x00CBECDC)],
                ),
                borderRadius: BorderRadius.circular(260),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DetailsReveal(
                        delayMs: 50,
                        child: Container(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 14 : 18,
                            compact ? 14 : 18,
                            compact ? 14 : 18,
                            compact ? 12 : 14,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF0F345B), Color(0xFF145379)],
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x1A1D3D62),
                                blurRadius: 18,
                                offset: Offset(0, 9),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Hero(
                                tag: EtablissementSelector.badgeHeroTag(etablissement),
                                child: Material(
                                  color: Colors.transparent,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.30),
                                      ),
                                    ),
                                    child: const Text(
                                      'FICHE ETABLISSEMENT',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Hero(
                                tag: EtablissementSelector.titleHeroTag(etablissement),
                                child: Material(
                                  color: Colors.transparent,
                                  child: Text(
                                    etablissement.name,
                                    style: TextStyle(
                                      fontSize: compact ? 22 : 30,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      height: 1.05,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  fontSize: compact ? 13 : 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.86),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _DetailChip(
                                    icon: Icons.location_on_outlined,
                                    label: (etablissement.address ?? '').trim().isNotEmpty
                                        ? 'Adresse disponible'
                                        : 'Adresse non renseignee',
                                  ),
                                  _DetailChip(
                                    icon: Icons.alternate_email,
                                    label: (etablissement.email ?? '').trim().isNotEmpty
                                        ? etablissement.email!.trim()
                                        : 'Email non renseigne',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _DetailsReveal(
                        delayMs: 140,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFFCFEFF), Color(0xFFF1F8FF)],
                            ),
                            border: Border.all(color: const Color(0xFFD4E3F3)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x13295178),
                                blurRadius: 16,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(compact ? 12 : 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Identite visuelle',
                                  style: TextStyle(
                                    fontSize: compact ? 17 : 20,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF1A466F),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Hero(
                                    tag: EtablissementSelector.logoHeroTag(etablissement),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: Container(
                                        constraints: BoxConstraints(
                                          minHeight: compact ? 180 : 260,
                                          maxHeight: compact ? 280 : 360,
                                        ),
                                        width: double.infinity,
                                        color: const Color(0xFFEAF2FC),
                                        child:
                                            etablissement.logoUrlForDisplay != null &&
                                                etablissement.logoUrlForDisplay!.isNotEmpty
                                            ? Image.network(
                                                etablissement.logoUrlForDisplay!,
                                                fit: BoxFit.contain,
                                                errorBuilder: (_, __, ___) => Image.asset(
                                                  'assets/images/ecole_photo.png',
                                                  fit: BoxFit.contain,
                                                ),
                                              )
                                            : Image.asset(
                                                'assets/images/ecole_photo.png',
                                                fit: BoxFit.contain,
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
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

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DetailChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsReveal extends StatelessWidget {
  final Widget child;
  final int delayMs;

  const _DetailsReveal({required this.child, required this.delayMs});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 520 + delayMs),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) {
        final t = value.clamp(0.0, 1.0).toDouble();
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 18),
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
      ..color = const Color(0x143B6B92)
      ..strokeWidth = 1;
    const spacing = 30.0;
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final dotPaint = Paint()..color = const Color(0x176E9FC7);
    for (double y = 20; y < size.height; y += 60) {
      for (double x = 20; x < size.width; x += 60) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

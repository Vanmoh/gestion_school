import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class SharedDashboardBackdrop extends StatelessWidget {
  final List<Color> gradientColors;
  final Color topOrbColor;
  final Color bottomOrbColor;

  const SharedDashboardBackdrop({
    super.key,
    this.gradientColors = const [
      Color(0xFF0F172A),
      Color(0xFF162338),
      Color(0xFF1E293B),
    ],
    this.topOrbColor = const Color(0xFF8B5CF6),
    this.bottomOrbColor = const Color(0xFF6366F1),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -160,
            right: -110,
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: topOrbColor.withValues(alpha: 0.18),
              ),
            ),
          ),
          Positioned(
            left: -120,
            bottom: -90,
            child: Container(
              width: 330,
              height: 330,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bottomOrbColor.withValues(alpha: 0.18),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.02),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.1),
                  ],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(child: CustomPaint(painter: _SharedStarDust())),
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardGlassCard extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final List<Color>? gradient;
  final EdgeInsetsGeometry padding;

  const DashboardGlassCard({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.gradient,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient ??
                  [
                    Colors.white.withValues(alpha: 0.12),
                    Colors.white.withValues(alpha: 0.06),
                  ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.14),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
                blurRadius: 18,
                spreadRadius: -3,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _SharedStarDust extends CustomPainter {
  const _SharedStarDust();

  @override
  void paint(Canvas canvas, Size size) {
    final starPaint = Paint()..style = PaintingStyle.fill;
    final random = math.Random(42);

    for (var i = 0; i < 95; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final r = (random.nextDouble() * 1.3) + 0.25;
      final alpha = (random.nextDouble() * 0.22) + 0.04;
      starPaint.color = Colors.white.withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), r, starPaint);
    }

    final hazePaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x2E8B5CF6), Color(0x206366F1), Color(0x0010182A)],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.66, size.height * 0.26),
          radius: size.shortestSide * 0.52,
        ),
      );

    canvas.drawRect(Offset.zero & size, hazePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class MotionPolicy {
  const MotionPolicy._();

  static bool reduce(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery.disableAnimationsOf(context) ||
        media.size.shortestSide <= 360 ||
        media.textScaler.scale(1) > 1.25;
  }

  static Duration duration(
    BuildContext context, {
    Duration normal = AppMotion.medium,
  }) {
    return reduce(context) ? Duration.zero : normal;
  }
}

class SurfacePolicy {
  const SurfacePolicy._();

  static bool cheapSurfaces(BuildContext context) {
    final media = MediaQuery.of(context);
    return MotionPolicy.reduce(context) || media.size.shortestSide <= 390;
  }

  static double blur(BuildContext context, {double normal = 14}) {
    return cheapSurfaces(context) ? 0 : normal;
  }

  static List<BoxShadow>? shadow(BuildContext context,
      {bool elevated = false}) {
    if (!elevated || cheapSurfaces(context)) return null;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.24),
        blurRadius: 20,
        offset: const Offset(0, 12),
      ),
    ];
  }
}

class CheapBackdrop extends StatelessWidget {
  final BorderRadius borderRadius;
  final double blur;
  final Widget child;

  const CheapBackdrop({
    super.key,
    required this.borderRadius,
    required this.blur,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (blur <= 0) return child;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: child,
      ),
    );
  }
}

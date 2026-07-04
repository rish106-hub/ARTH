import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_theme.dart';
import 'ui_policy.dart';

class ArthScaffold extends StatelessWidget {
  final Widget child;
  final Widget? bottomNavigationBar;
  final EdgeInsetsGeometry padding;
  final bool showAmbientGlow;

  const ArthScaffold({
    super.key,
    required this.child,
    this.bottomNavigationBar,
    this.padding = EdgeInsets.zero,
    this.showAmbientGlow = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      bottomNavigationBar: bottomNavigationBar,
      body: Stack(
        children: [
          if (showAmbientGlow) const _AmbientFinanceGlow(),
          SafeArea(
            bottom: bottomNavigationBar == null,
            child: Padding(padding: padding, child: child),
          ),
        ],
      ),
    );
  }
}

class ArthPremiumAppBar extends StatelessWidget {
  final String title;
  final String? eyebrow;
  final Widget? leading;
  final List<Widget> actions;

  const ArthPremiumAppBar({
    super.key,
    required this.title,
    this.eyebrow,
    this.leading,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!.toUpperCase(),
                    style: AppTextStyles.micro(
                      color: AppColors.gold,
                    ).copyWith(letterSpacing: 1.1, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                ],
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.h2(),
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class PremiumGlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final Color tint;
  final bool elevated;

  const PremiumGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = AppRadius.card,
    this.tint = Colors.white,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    final blur = SurfacePolicy.blur(context);

    return CheapBackdrop(
      borderRadius: borderRadius,
      blur: blur,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              tint.withValues(alpha: blur <= 0 ? 0.075 : 0.10),
              tint.withValues(alpha: blur <= 0 ? 0.025 : 0.035),
            ],
          ),
          border: Border.all(color: AppColors.glassStroke),
          boxShadow: SurfacePolicy.shadow(context, elevated: elevated),
        ),
        child: child,
      ),
    );
  }
}

class TrustBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const TrustBadge({
    super.key,
    required this.icon,
    required this.label,
    this.color = AppColors.gold,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.pill,
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.micro(color: AppColors.textPrimary)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class ArthMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? helper;
  final IconData icon;
  final Color color;

  const ArthMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.helper,
    this.color = AppColors.gold,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumGlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.micro(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.h2(color: color),
          ),
          if (helper != null) ...[
            const SizedBox(height: 4),
            Text(
              helper!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.micro(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class ArthSection extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget child;

  const ArthSection({
    super.key,
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: AppTextStyles.sectionLabel(
                  color: AppColors.textSecondary,
                ).copyWith(letterSpacing: 1.2),
              ),
            ),
            if (actionLabel != null && onAction != null)
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class PremiumSkeleton extends StatefulWidget {
  final double height;
  final double? width;
  final BorderRadius borderRadius;

  const PremiumSkeleton({
    super.key,
    required this.height,
    this.width,
    this.borderRadius = AppRadius.card,
  });

  @override
  State<PremiumSkeleton> createState() => _PremiumSkeletonState();
}

class _PremiumSkeletonState extends State<PremiumSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return _box(0.08);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => _box(0.06 + (_controller.value * 0.06)),
    );
  }

  Widget _box(double alpha) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: alpha),
        borderRadius: widget.borderRadius,
      ),
    );
  }
}

class ArthStatePanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const ArthStatePanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: PremiumGlassPanel(
          elevated: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.gold, size: 36),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTextStyles.h2(),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.body(color: AppColors.textSecondary),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: AppButtons.primaryGold,
                    onPressed: onAction,
                    child: Text(actionLabel!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ArthLoadingPanel extends StatelessWidget {
  final String title;
  final List<String> insights;

  const ArthLoadingPanel({
    super.key,
    this.title = 'Building your tax intelligence',
    this.insights = const [
      'Checking regime fit.',
      'Prioritising recoverable deductions.',
      'Preparing next best actions.',
    ],
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MotionPolicy.reduce(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PremiumGlassPanel(
              borderRadius: BorderRadius.circular(28),
              padding: const EdgeInsets.all(22),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.gold,
                size: 34,
              ),
            )
                .animate(target: reduceMotion ? 0 : 1)
                .scale(
                  begin: const Offset(0.96, 0.96),
                  end: const Offset(1.04, 1.04),
                  duration: 900.ms,
                )
                .then()
                .scale(
                  begin: const Offset(1.04, 1.04),
                  end: const Offset(0.96, 0.96),
                  duration: 900.ms,
                ),
            const SizedBox(height: 22),
            Text(title, textAlign: TextAlign.center, style: AppTextStyles.h2()),
            const SizedBox(height: 8),
            Text(
              insights.first,
              textAlign: TextAlign.center,
              style: AppTextStyles.body(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 22),
            const PremiumSkeleton(height: 8, width: 180),
          ],
        ),
      ),
    );
  }
}

class _AmbientFinanceGlow extends StatelessWidget {
  const _AmbientFinanceGlow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -130,
            right: -90,
            child: _glow(AppColors.gold, 320, 0.08),
          ),
          Positioned(
            bottom: -160,
            left: -120,
            child: _glow(AppColors.teal, 300, 0.05),
          ),
        ],
      ),
    );
  }

  Widget _glow(Color color, double size, double alpha) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: alpha), Colors.transparent],
        ),
      ),
    );
  }
}

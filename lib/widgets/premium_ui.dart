import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_theme.dart';
import 'arth_bottom_nav.dart';
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
      backgroundColor: AppColors.bgPrimary,
      bottomNavigationBar: bottomNavigationBar,
      body: SafeArea(
        bottom: bottomNavigationBar == null,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class ArthShell extends StatelessWidget {
  final Widget child;
  final int selectedIndex;
  final ValueChanged<int> onTab;
  final bool showAmbientGlow;

  const ArthShell({
    super.key,
    required this.child,
    required this.selectedIndex,
    required this.onTab,
    this.showAmbientGlow = true,
  });

  @override
  Widget build(BuildContext context) {
    return ArthScaffold(
      showAmbientGlow: showAmbientGlow,
      bottomNavigationBar: ArthBottomNav(
        selectedIndex: selectedIndex,
        onTap: onTab,
      ),
      child: child,
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
                    ).copyWith(fontWeight: FontWeight.w700),
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

class PremiumHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String body;
  final IconData icon;
  final Widget? trailing;

  const PremiumHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumGlassPanel(
      elevated: true,
      tint: AppColors.gold,
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.14),
              borderRadius: AppRadius.card,
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.26)),
            ),
            child: Icon(icon, color: AppColors.gold),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow.toUpperCase(),
                  style: AppTextStyles.micro(color: AppColors.gold)
                      .copyWith(fontWeight: FontWeight.w700, letterSpacing: 0),
                ),
                const SizedBox(height: 6),
                Text(title, style: AppTextStyles.h1()),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: AppTextStyles.caption(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
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
    final borderColor =
        tint == Colors.white ? AppColors.border : tint.withValues(alpha: 0.34);

    return Material(
      color: elevated ? AppColors.bgCardHover : AppColors.bgCard,
      elevation: elevated ? 1 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
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

class StatusPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const StatusPill({
    super.key,
    required this.label,
    required this.icon,
    this.color = AppColors.gold,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.pill,
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.micro(color: AppColors.textPrimary)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class ActionDock extends StatelessWidget {
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final IconData? secondaryIcon;
  final VoidCallback? onSecondary;

  const ActionDock({
    super.key,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    this.secondaryLabel,
    this.secondaryIcon,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = secondaryLabel != null && secondaryIcon != null;
    final primaryButton = ElevatedButton.icon(
      style: AppButtons.primaryGold,
      onPressed: onPrimary,
      icon: Icon(primaryIcon, size: 18),
      label: Text(primaryLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    final secondaryButton = OutlinedButton.icon(
      style: AppButtons.outlineGold,
      onPressed: onSecondary,
      icon: Icon(secondaryIcon, size: 18),
      label: Text(
        secondaryLabel ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!secondary) {
          return SizedBox(width: double.infinity, child: primaryButton);
        }
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primaryButton,
              const SizedBox(height: 10),
              secondaryButton
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: primaryButton),
            const SizedBox(width: 10),
            Expanded(child: secondaryButton),
          ],
        );
      },
    );
  }
}

class StoryPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color color;
  final Widget? trailing;

  const StoryPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.color = AppColors.gold,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumGlassPanel(
      tint: color,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodyMedium()),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: AppTextStyles.caption(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
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
                ).copyWith(fontWeight: FontWeight.w700),
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
        color: AppColors.textMuted.withValues(alpha: alpha + 0.08),
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
            const PremiumGlassPanel(
              borderRadius: AppRadius.card,
              padding: EdgeInsets.all(22),
              child: Icon(
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

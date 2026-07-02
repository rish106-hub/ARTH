import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class QuestionProgressBar extends StatelessWidget {
  final int current; // 0-indexed
  final int total;

  const QuestionProgressBar({
    super.key,
    required this.current,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? (current + 1) / total : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Question ${current + 1} of $total',
              style: AppTextStyles.micro(color: AppColors.textSecondary),
            ),
            const Spacer(),
            Text(
              '${((progress) * 100).round()}%',
              style: AppTextStyles.micro(color: AppColors.gold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: AppRadius.pill,
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.bgSurface,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.gold),
            minHeight: 3,
          ),
        ),
      ],
    );
  }
}

// ─── CHIP SELECT ─────────────────────────────────────────────────────────────
class SelectChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  final bool fullWidth;

  const SelectChip({
    super.key,
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.12)
              : AppColors.bgCard,
          borderRadius: AppRadius.card,
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon!,
                size: 20,
                color: selected ? AppColors.gold : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
            ],
            Text(
              label,
              style: AppTextStyles.bodyMedium(
                color: selected ? AppColors.gold : AppColors.textPrimary,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: AppColors.gold,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── MULTI-SELECT CHIP ───────────────────────────────────────────────────────
class MultiSelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const MultiSelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.12)
              : AppColors.bgCard,
          borderRadius: AppRadius.pill,
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.caption(
            color: selected ? AppColors.gold : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ─── ARTH APP BAR ────────────────────────────────────────────────────────────
class ArthAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showBack;
  final VoidCallback? onBack;

  const ArthAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showBack = true,
    this.onBack,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.bgPrimary,
      elevation: 0,
      leading: showBack
          ? IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_rounded,
                size: 20,
                color: AppColors.textPrimary,
              ),
              onPressed: onBack ?? () => Navigator.of(context).pop(),
            )
          : null,
      title: Text(
        title,
        style: AppTextStyles.bodyMedium(color: AppColors.textPrimary),
      ),
      centerTitle: true,
      actions: actions,
    );
  }
}

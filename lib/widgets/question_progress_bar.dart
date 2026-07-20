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
              'STEP ${current + 1} OF $total',
              style: AppTextStyles.micro(color: AppColors.textSecondary),
            ),
            const Spacer(),
            Text(
              '${(progress * 100).round()}%',
              style: AppTextStyles.micro(color: AppColors.gold),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Row(
          children: List.generate(total, (index) {
            final completed = index <= current;
            return Expanded(
              child: AnimatedContainer(
                duration: AppMotion.fast,
                height: 4,
                margin: EdgeInsets.only(right: index == total - 1 ? 0 : 3),
                decoration: BoxDecoration(
                  color: completed ? AppColors.gold : AppColors.bgSurface,
                  borderRadius: AppRadius.pill,
                ),
              ),
            );
          }),
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
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.card,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            constraints: const BoxConstraints(minHeight: 52),
            width: fullWidth ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.gold.withValues(alpha: 0.10)
                  : AppColors.bgCard,
              borderRadius: AppRadius.card,
              border: Border.all(
                color: selected ? AppColors.gold : AppColors.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.gold.withValues(alpha: 0.12)
                          : AppColors.bgSurface,
                      borderRadius: AppRadius.card,
                    ),
                    child: Icon(
                      icon!,
                      size: 18,
                      color:
                          selected ? AppColors.gold : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 11),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.left,
                    style: AppTextStyles.bodyMedium(
                      color: selected ? AppColors.gold : AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 19,
                  color: selected ? AppColors.gold : AppColors.border,
                ),
              ],
            ),
          ),
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
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.card,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.gold.withValues(alpha: 0.10)
                  : AppColors.bgCard,
              borderRadius: AppRadius.card,
              border: Border.all(
                color: selected ? AppColors.gold : AppColors.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 16,
                  color: selected ? AppColors.gold : AppColors.textMuted,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    style: AppTextStyles.caption(
                      color: selected ? AppColors.gold : AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
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

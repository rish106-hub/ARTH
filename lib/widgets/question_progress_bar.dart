import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/paycheck_theme.dart';

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
              '${current + 1} of $total',
              style: PaycheckType.micro(color: PaycheckColors.textSecondary),
            ),
            const Spacer(),
            Text('TAX PLAN',
                style: PaycheckType.sectionLabel(
                  color: PaycheckColors.textSecondary,
                )),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: AppRadius.pill,
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            backgroundColor: PaycheckColors.surfaceMuted,
            valueColor: const AlwaysStoppedAnimation(PaycheckColors.primary),
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
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            constraints: const BoxConstraints(minHeight: 52),
            width: fullWidth ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? PaycheckColors.primarySoft : PaycheckColors.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? PaycheckColors.primary : PaycheckColors.border,
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
                          ? PaycheckColors.primarySoft
                          : PaycheckColors.bgSurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      icon!,
                      size: 18,
                      color: selected
                          ? PaycheckColors.primary
                          : PaycheckColors.textSecondary,
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
                    style: PaycheckType.bodyMedium(
                      color: selected
                          ? PaycheckColors.primaryDark
                          : PaycheckColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 19,
                  color: selected ? PaycheckColors.primary : PaycheckColors.border,
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
                  ? PaycheckColors.gold.withValues(alpha: 0.10)
                  : PaycheckColors.bgCard,
              borderRadius: AppRadius.card,
              border: Border.all(
                color: selected ? PaycheckColors.gold : PaycheckColors.border,
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
                  color: selected ? PaycheckColors.gold : PaycheckColors.textMuted,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    style: PaycheckType.caption(
                      color: selected ? PaycheckColors.gold : PaycheckColors.textPrimary,
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
      backgroundColor: PaycheckColors.bgPrimary,
      elevation: 0,
      leading: showBack
          ? IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_rounded,
                size: 20,
                color: PaycheckColors.textPrimary,
              ),
              onPressed: onBack ?? () => Navigator.of(context).pop(),
            )
          : null,
      title: Text(
        title,
        style: PaycheckType.bodyMedium(color: PaycheckColors.textPrimary),
      ),
      centerTitle: true,
      actions: actions,
    );
  }
}

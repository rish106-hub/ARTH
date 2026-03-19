import 'package:flutter/material.dart';
import '../models/gap_card.dart';
import '../theme/app_theme.dart';
import 'animated_number.dart';

class GapCardWidget extends StatelessWidget {
  final GapCard gap;
  final bool isDone;
  final VoidCallback onTap;
  final VoidCallback? onMarkDone;

  const GapCardWidget({
    super.key,
    required this.gap,
    required this.isDone,
    required this.onTap,
    this.onMarkDone,
  });

  Color _cardAccent() {
    if (gap.gapAmount >= 50000) return AppColors.gold;
    if (gap.gapAmount >= 10000) return AppColors.amber;
    return AppColors.teal;
  }

  @override
  Widget build(BuildContext context) {
    final accent = _cardAccent();

    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: isDone ? 0.45 : 1.0,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: AppRadius.card,
            border: Border.all(
              color: isDone ? AppColors.border : accent.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top accent bar
              Container(
                height: 3,
                decoration: BoxDecoration(
                  color: isDone ? AppColors.success : accent,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section badge + done indicator
                    Row(
                      children: [
                        _SectionBadge(
                            section: gap.section,
                            accent: accent,
                            isDone: isDone),
                        const Spacer(),
                        if (isDone)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.15),
                              borderRadius: AppRadius.pill,
                            ),
                            child: Text('Done',
                                style: AppTextStyles.micro(
                                    color: AppColors.success)),
                          )
                        else
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(gap.difficultyIcon,
                                  size: 11, color: AppColors.textSecondary),
                              const SizedBox(width: 3),
                              Text(
                                gap.difficultyLabel,
                                style: AppTextStyles.micro(
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Title
                    Text(gap.title, style: AppTextStyles.h3()),
                    const SizedBox(height: 2),
                    Text(gap.shortDesc, style: AppTextStyles.caption()),
                    const SizedBox(height: 12),

                    // Gap amount
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('You\'re leaving behind',
                                style: AppTextStyles.micro(
                                    color: AppColors.textSecondary)),
                            const SizedBox(height: 2),
                            RupeeText(
                              amount: gap.gapAmount,
                              style: AppTextStyles.displaySmall(
                                color: isDone ? AppColors.success : accent,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        // Arrow
                        if (!isDone)
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.arrow_forward_rounded,
                                color: accent, size: 20),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Deadline
                    Row(
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 12, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text('Deadline: ${gap.deadline}',
                            style: AppTextStyles.micro()),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionBadge extends StatelessWidget {
  final String section;
  final Color accent;
  final bool isDone;

  const _SectionBadge(
      {required this.section, required this.accent, required this.isDone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (isDone ? AppColors.success : accent).withValues(alpha: 0.12),
        borderRadius: AppRadius.pill,
        border: Border.all(
          color: (isDone ? AppColors.success : accent).withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Text(
        section,
        style: AppTextStyles.sectionLabel(
          color: isDone ? AppColors.success : accent,
        ),
      ),
    );
  }
}

// ─── ACTION PLAN LIST ITEM ───────────────────────────────────────────────────
class ActionListItem extends StatelessWidget {
  final GapCard gap;
  final bool isDone;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  const ActionListItem({
    super.key,
    required this.gap,
    required this.isDone,
    required this.onTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            // Checkbox
            GestureDetector(
              onTap: onToggle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isDone ? AppColors.success : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDone ? AppColors.success : AppColors.border,
                    width: 1.5,
                  ),
                ),
                child: isDone
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 14),

            // Title + section
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gap.title,
                    style: AppTextStyles.bodyMedium(
                      color: isDone
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(gap.section,
                      style: AppTextStyles.micro(color: AppColors.textGold)),
                ],
              ),
            ),

            // Amount
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatRupees(gap.gapAmount),
                  style: AppTextStyles.bodyMedium(
                    color: isDone ? AppColors.success : gap.accentColor,
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

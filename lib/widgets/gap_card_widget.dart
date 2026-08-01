import 'package:flutter/material.dart';
import '../models/gap_card.dart';
import '../theme/app_theme.dart';
import '../theme/paycheck_theme.dart';
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
    if (gap.gapAmount >= 50000) return PaycheckColors.gold;
    if (gap.gapAmount >= 10000) return PaycheckColors.amber;
    return PaycheckColors.teal;
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
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: PaycheckColors.bgCard,
            borderRadius: AppRadius.card,
            border: Border.all(
              color: isDone
                  ? PaycheckColors.border
                  : accent.withValues(alpha: 0.35),
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
                  color: isDone ? PaycheckColors.success : accent,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section badge + done indicator
                    Row(
                      children: [
                        Flexible(
                          child: _SectionBadge(
                            section: gap.section,
                            accent: accent,
                            isDone: isDone,
                          ),
                        ),
                        const Spacer(),
                        if (isDone)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: PaycheckColors.success
                                  .withValues(alpha: 0.15),
                              borderRadius: AppRadius.pill,
                            ),
                            child: Text(
                              'Done',
                              style: PaycheckType.micro(
                                color: PaycheckColors.success,
                              ),
                            ),
                          )
                        else
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Icon(
                                  gap.difficultyIcon,
                                  size: 11,
                                  color: PaycheckColors.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    gap.difficultyLabel,
                                    softWrap: true,
                                    textAlign: TextAlign.right,
                                    style: PaycheckType.micro(
                                      color: PaycheckColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Title
                    Text(gap.title, style: PaycheckType.heading()),
                    const SizedBox(height: 4),
                    Text(gap.shortDesc, style: PaycheckType.caption()),
                    const SizedBox(height: 12),

                    // Gap amount
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Deduction opportunity',
                                style: PaycheckType.micro(
                                  color: PaycheckColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formatRupeesCompact(gap.gapAmount),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PaycheckType.displaySmall(
                                  color:
                                      isDone ? PaycheckColors.success : accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Arrow
                        if (!isDone)
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              color: accent,
                              size: 20,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Deadline
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: PaycheckColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Deadline: ${gap.deadline}',
                          style: PaycheckType.micro(),
                        ),
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

  const _SectionBadge({
    required this.section,
    required this.accent,
    required this.isDone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color:
            (isDone ? PaycheckColors.success : accent).withValues(alpha: 0.12),
        borderRadius: AppRadius.pill,
        border: Border.all(
          color:
              (isDone ? PaycheckColors.success : accent).withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Text(
        section,
        style: PaycheckType.sectionLabel(
          color: isDone ? PaycheckColors.success : accent,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: PaycheckColors.divider)),
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
                  color: isDone ? PaycheckColors.success : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        isDone ? PaycheckColors.success : PaycheckColors.border,
                    width: 1.5,
                  ),
                ),
                child: isDone
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 16),

            // Title + section
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gap.title,
                    style: PaycheckType.bodyMedium(
                      color: isDone
                          ? PaycheckColors.textSecondary
                          : PaycheckColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    gap.section,
                    style: PaycheckType.micro(color: PaycheckColors.textGold),
                  ),
                ],
              ),
            ),

            // Amount
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatRupees(gap.gapAmount),
                  style: PaycheckType.bodyMedium(
                    color: isDone ? PaycheckColors.success : gap.accentColor,
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: PaycheckColors.textSecondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

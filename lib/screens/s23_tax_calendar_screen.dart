import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/product_insights.dart';
import '../providers/tax_year_provider.dart';
import '../theme/app_theme.dart';
import '../theme/paycheck_theme.dart';
import '../widgets/arth_bottom_nav.dart';
import '../widgets/premium_ui.dart';

class TaxCalendarScreen extends ConsumerWidget {
  const TaxCalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeYear = ref.watch(activeTaxYearProvider);
    final items = taxCalendarItems(activeYear.fyLabel);
    return ArthScaffold(
      bottomNavigationBar: ArthBottomNav(
        selectedIndex: 2,
        onTap: (i) => goToArthTab(context, i),
      ),
      child: Column(
        children: [
          ArthPremiumAppBar(
            eyebrow: 'Timeline',
            title: 'Tax Calendar',
            leading: IconButton(
              tooltip: 'Back',
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/discover');
                }
              },
              icon: const Icon(Icons.arrow_back_rounded),
              color: PaycheckColors.textSecondary,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PremiumGlassPanel(
                    elevated: true,
                    borderRadius: BorderRadius.circular(28),
                    tint: PaycheckColors.gold,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const TrustBadge(
                          icon: Icons.event_available_outlined,
                          label: 'Local milestones',
                        ),
                        const SizedBox(height: 16),
                        Text(activeYear.displayLabel, style: PaycheckType.h1()),
                        const SizedBox(height: 8),
                        Text(
                          'Readiness timeline. No reminders yet.',
                          style: PaycheckType.body(
                            color: PaycheckColors.textSecondary,
                          ),
                        ),
                        const ArthDisclosure(
                          label: 'What the timeline covers',
                          detail:
                              'Proofs, official-record review, accuracy cleanup and filing handoff. Push notifications are not built yet.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ArthSection(
                    title: 'Milestones',
                    child: Column(
                      children: [
                        for (var i = 0; i < items.length; i += 1) ...[
                          _CalendarMilestone(item: items[i], index: i + 1),
                          if (i != items.length - 1) const _TimelineConnector(),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarMilestone extends StatelessWidget {
  final TaxCalendarItem item;
  final int index;

  const _CalendarMilestone({required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    return PremiumGlassPanel(
      padding: const EdgeInsets.all(16),
      tint: index.isEven ? PaycheckColors.teal : PaycheckColors.gold,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: PaycheckColors.gold.withValues(alpha: 0.15),
            child: Text('$index',
                style: PaycheckType.caption(color: PaycheckColors.gold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(item.icon, color: PaycheckColors.gold, size: 18),
                    Text(item.title, style: PaycheckType.heading()),
                    TrustBadge(
                      icon: Icons.schedule_rounded,
                      label: item.date,
                      color: PaycheckColors.teal,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.body,
                  style:
                      PaycheckType.caption(color: PaycheckColors.textSecondary),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: AppButtons.outlineGold,
                  onPressed: () => context.push(item.route),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(item.cta),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineConnector extends StatelessWidget {
  const _TimelineConnector();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 32),
        width: 1,
        height: 18,
        color: PaycheckColors.border,
      ),
    );
  }
}

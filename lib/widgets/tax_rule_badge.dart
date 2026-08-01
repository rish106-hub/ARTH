import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tax_result.dart';
import '../models/tax_rule_set.dart';
import '../providers/tax_year_provider.dart';
import '../theme/paycheck_theme.dart';
import 'premium_ui.dart';

class TaxRuleBadge extends StatelessWidget {
  final TaxResult result;

  const TaxRuleBadge({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        TrustBadge(
          icon: Icons.gavel_outlined,
          label: result.ruleSetLabel,
          color: PaycheckColors.info,
        ),
        TrustBadge(
          icon: Icons.event_available_outlined,
          label: result.assessmentYear,
          color: PaycheckColors.teal,
        ),
      ],
    );
  }
}

class TaxYearSelector extends ConsumerWidget {
  const TaxYearSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeTaxYearProvider);
    return PremiumGlassPanel(
      padding: const EdgeInsets.all(12),
      tint: PaycheckColors.info,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _TaxYearChip(
            taxYear: TaxYearId.fy2025_26,
            selected: active == TaxYearId.fy2025_26,
            onSelected: () {
              ref.read(activeTaxYearProvider.notifier).set(
                    TaxYearId.fy2025_26,
                  );
            },
          ),
          _TaxYearChip(
            taxYear: TaxYearId.fy2026_27,
            selected: active == TaxYearId.fy2026_27,
            onSelected: () {
              ref.read(activeTaxYearProvider.notifier).set(
                    TaxYearId.fy2026_27,
                  );
            },
          ),
        ],
      ),
    );
  }
}

class _TaxYearChip extends StatelessWidget {
  final TaxYearId taxYear;
  final bool selected;
  final VoidCallback onSelected;

  const _TaxYearChip({
    required this.taxYear,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? PaycheckColors.gold : PaycheckColors.textSecondary;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      label: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(taxYear.displayLabel, style: PaycheckType.micro(color: color)),
          Text(
            taxYear.assessmentYear,
            style: PaycheckType.micro(color: PaycheckColors.textMuted),
          ),
        ],
      ),
    );
  }
}

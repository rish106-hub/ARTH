import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../theme/paycheck_theme.dart';

/// Segmented selector for how many months a job/income engagement runs
/// within the financial year. Options come from [kJobDurationOptions].
class JobDurationSelector extends StatelessWidget {
  const JobDurationSelector({
    super.key,
    required this.selectedMonths,
    required this.onChanged,
  });

  final int selectedMonths;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final months in kJobDurationOptions)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: months == kJobDurationOptions.last ? 0 : 8,
              ),
              child: _DurationChip(
                months: months,
                selected: months == selectedMonths,
                onTap: () => onChanged(months),
              ),
            ),
          ),
      ],
    );
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({
    required this.months,
    required this.selected,
    required this.onTap,
  });

  final int months;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? PaycheckColors.ink : PaycheckColors.paper,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? PaycheckColors.ink : PaycheckColors.line,
            ),
          ),
          child: Text(
            '$months mo',
            style: PaycheckType.bodyStrong(
              color: selected ? Colors.white : PaycheckColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

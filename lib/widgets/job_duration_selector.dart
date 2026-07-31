import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../theme/app_theme.dart';
import '../theme/paycheck_theme.dart';

/// Selector for how many months a job, income engagement, or goal runs.
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
    final isCustom = !kJobDurationOptions.contains(selectedMonths);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final months in kJobDurationOptions)
          SizedBox(
            width: 76,
            child: _DurationChip(
              label: '$months mo',
              selected: months == selectedMonths,
              onTap: () => onChanged(months),
            ),
          ),
        SizedBox(
          width: 104,
          child: _DurationChip(
            label: isCustom ? '$selectedMonths mo' : 'Custom',
            selected: isCustom,
            onTap: () => _chooseCustomDuration(context),
          ),
        ),
      ],
    );
  }

  Future<void> _chooseCustomDuration(BuildContext context) async {
    final controller = TextEditingController(
      text: selectedMonths.clamp(1, 12).toString(),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Custom duration'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Months in this financial year',
            helperText: 'Enter a number from 1 to 12',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final months = int.tryParse(controller.text.trim());
              if (months == null || months < 1 || months > 12) return;
              Navigator.pop(dialogContext, months);
            },
            child: const Text('Use duration'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) onChanged(result);
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? PaycheckColors.ink : PaycheckColors.paper,
      borderRadius: AppRadius.card,
      child: InkWell(
        borderRadius: AppRadius.control,
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: AppRadius.card,
            border: Border.all(
              color: selected ? PaycheckColors.ink : PaycheckColors.line,
            ),
          ),
          child: Text(
            label,
            style: PaycheckType.bodyStrong(
              color: selected ? Colors.white : PaycheckColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

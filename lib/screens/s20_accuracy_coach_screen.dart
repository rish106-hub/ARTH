import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/product_insights.dart';
import '../providers/tax_result_provider.dart';
import '../providers/user_profile_provider.dart';
import '../theme/app_theme.dart';
import '../theme/paycheck_theme.dart';
import '../widgets/arth_bottom_nav.dart';
import '../widgets/premium_ui.dart';
import '../widgets/retry_error_state.dart';

class AccuracyCoachScreen extends ConsumerWidget {
  const AccuracyCoachScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completeAsync = ref.watch(completedTaxProfileProvider);
    return ArthScaffold(
      bottomNavigationBar: ArthBottomNav(
        selectedIndex: 2,
        onTap: (i) => goToArthTab(context, i),
      ),
      child: Column(
        children: [
          ArthPremiumAppBar(
            eyebrow: 'Accuracy',
            title: 'Accuracy Coach',
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
            child: completeAsync.when(
              loading: () => const ArthLoadingPanel(
                title: 'Checking accuracy inputs',
                insights: ['Finding assumptions that can be replaced.'],
              ),
              error: (_, __) => RetryErrorState(
                message: 'Could not check diagnostic status',
                onRetry: () => ref.invalidate(completedTaxProfileProvider),
              ),
              data: (complete) {
                if (!complete) {
                  return ArthStatePanel(
                    icon: Icons.tune_rounded,
                    title: 'Run diagnostic first',
                    message:
                        'Accuracy Coach unlocks after ARTH has a baseline tax profile.',
                    actionLabel: 'Start diagnostic',
                    onAction: () => context.go('/questions'),
                  );
                }
                final profile = ref.watch(userProfileProvider);
                final tasks = buildAccuracyTasks(profile);
                final result = ref.watch(taxResultProvider).asData?.value;
                return SingleChildScrollView(
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
                              icon: Icons.verified_outlined,
                              label: 'No re-onboarding',
                            ),
                            const SizedBox(height: 16),
                            Text('Tighten your estimate',
                                style: PaycheckType.h1()),
                            const SizedBox(height: 8),
                            Text(
                              'Replace assumptions with exact values.',
                              style: PaycheckType.body(
                                color: PaycheckColors.textSecondary,
                              ),
                            ),
                            const ArthDisclosure(
                              label: 'Why it matters',
                              detail:
                                  'Exact payslip, proof and interest values can change which regime comes out ahead.',
                            ),
                            const SizedBox(height: 16),
                            TrustBadge(
                              icon: Icons.speed_rounded,
                              label: result == null
                                  ? 'Calculating confidence'
                                  : '${result.confidenceScore}% ${result.confidenceLabel.toLowerCase()}',
                              color:
                                  result != null && result.confidenceScore >= 85
                                      ? PaycheckColors.success
                                      : PaycheckColors.gold,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (tasks.isEmpty)
                        ArthStatePanel(
                          icon: Icons.task_alt_rounded,
                          title: 'Accuracy inputs look strong',
                          message:
                              'No major assumption task is pending. Keep documents and AIS/26AS review ready.',
                          actionLabel: 'Open Tax Story',
                          onAction: () => context.push('/tax-story'),
                        )
                      else
                        ArthSection(
                          title: '${tasks.length} improvements available',
                          child: Column(
                            children: [
                              for (final task in tasks) ...[
                                _AccuracyTaskCard(task: task),
                                const SizedBox(height: 12),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AccuracyTaskCard extends ConsumerWidget {
  final AccuracyTask task;

  const _AccuracyTaskCard({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PremiumGlassPanel(
      padding: const EdgeInsets.all(16),
      tint: PaycheckColors.teal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(task.icon, color: PaycheckColors.gold, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, style: PaycheckType.bodyMedium()),
                const SizedBox(height: 4),
                Text(
                  task.body,
                  style:
                      PaycheckType.caption(color: PaycheckColors.textSecondary),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: AppButtons.outlineGold,
                  onPressed: () => _showAccuracyInput(context, ref, task),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(task.currentValue == null ? 'Add value' : 'Edit'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAccuracyInput(
    BuildContext context,
    WidgetRef ref,
    AccuracyTask task,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _AccuracyInputSheet(
          task: task,
          onSave: (value) async {
            final notifier = ref.read(userProfileProvider.notifier);
            final previous = ref.read(userProfileProvider);
            notifier.updateField(
              (profile) => task.apply(profile, value),
            );
            try {
              await notifier.save();
              ref.invalidate(taxResultProvider);
              await computeAndSyncCurrentTaxResult(ref);
            } catch (_) {
              notifier.update(previous);
              rethrow;
            }
          },
        );
      },
    );
  }
}

class _AccuracyInputSheet extends StatefulWidget {
  final AccuracyTask task;
  final Future<void> Function(int value) onSave;

  const _AccuracyInputSheet({
    required this.task,
    required this.onSave,
  });

  @override
  State<_AccuracyInputSheet> createState() => _AccuracyInputSheetState();
}

class _AccuracyInputSheetState extends State<_AccuracyInputSheet> {
  late final TextEditingController _controller;
  String? _error;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final value = widget.task.currentValue;
    _controller = TextEditingController(
      text: value == null ? '' : value.toString(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final task = widget.task;
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value < task.min || value > task.max) {
      setState(() {
        _error =
            'Enter a value between ${task.min} and ${task.max} ${task.suffix}.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(value);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save this input. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final height = MediaQuery.sizeOf(context).height;
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height * 0.58),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: PaycheckColors.graphite,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: PaycheckColors.gold.withValues(alpha: 0.28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(task.fieldLabel, style: PaycheckType.h2()),
                    const SizedBox(height: 8),
                    Text(
                      task.body,
                      style: PaycheckType.caption(
                        color: PaycheckColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) {
                        if (_error != null) {
                          setState(() => _error = null);
                        }
                      },
                      decoration: InputDecoration(
                        prefixText: task.suffix == '₹' ? '₹ ' : null,
                        suffixText: task.suffix == '%' ? '%' : null,
                        errorText: _error,
                        labelText: task.fieldLabel,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: AppButtons.primaryGold,
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(_saving ? 'Saving' : 'Save input'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

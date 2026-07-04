import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/product_insights.dart';
import '../providers/tax_result_provider.dart';
import '../providers/user_profile_provider.dart';
import '../theme/app_theme.dart';
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
        selectedIndex: 0,
        onTap: (i) {
          switch (i) {
            case 0:
              context.go('/discover');
              break;
            case 1:
              context.go('/action-plan');
              break;
            case 2:
              context.go('/progress');
              break;
            case 3:
              context.go('/profile');
              break;
          }
        },
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
              color: AppColors.textSecondary,
            ),
          ),
          Expanded(
            child: completeAsync.when(
              loading: () => const ArthLoadingPanel(
                title: 'Checking accuracy inputs',
                insights: ['Finding assumptions that can be replaced.'],
              ),
              error: (_, __) => RetryErrorState(
                message: 'Could not check diagnostic status.',
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
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PremiumGlassPanel(
                        elevated: true,
                        borderRadius: BorderRadius.circular(28),
                        tint: AppColors.gold,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const TrustBadge(
                              icon: Icons.verified_outlined,
                              label: 'No re-onboarding',
                            ),
                            const SizedBox(height: 16),
                            Text('Tighten your estimate',
                                style: AppTextStyles.h1()),
                            const SizedBox(height: 8),
                            Text(
                              'Replace assumptions with exact payslip, proof, and interest values. This can change old/new regime comparison.',
                              style: AppTextStyles.body(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 14),
                            TrustBadge(
                              icon: Icons.speed_rounded,
                              label: result == null
                                  ? 'Calculating confidence'
                                  : '${result.confidenceScore}% ${result.confidenceLabel.toLowerCase()}',
                              color:
                                  result != null && result.confidenceScore >= 85
                                      ? AppColors.success
                                      : AppColors.gold,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
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
                                const SizedBox(height: 10),
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
      tint: AppColors.teal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(task.icon, color: AppColors.gold, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, style: AppTextStyles.bodyMedium()),
                const SizedBox(height: 4),
                Text(
                  task.body,
                  style: AppTextStyles.caption(color: AppColors.textSecondary),
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
    final controller = TextEditingController(
      text: task.currentValue == null ? '' : task.currentValue.toString(),
    );
    String? error;
    var saving = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> save() async {
              final raw = int.tryParse(controller.text.trim());
              if (raw == null || raw < task.min || raw > task.max) {
                setSheetState(() {
                  error =
                      'Enter a value between ${task.min} and ${task.max} ${task.suffix}.';
                });
                return;
              }
              setSheetState(() {
                saving = true;
                error = null;
              });
              ref.read(userProfileProvider.notifier).updateField(
                    (profile) => task.apply(profile, raw),
                  );
              await ref.read(userProfileProvider.notifier).save();
              ref.invalidate(taxResultProvider);
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: PremiumGlassPanel(
                  borderRadius: BorderRadius.circular(28),
                  tint: AppColors.gold,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(task.fieldLabel, style: AppTextStyles.h2()),
                      const SizedBox(height: 8),
                      Text(
                        task.body,
                        style: AppTextStyles.caption(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          prefixText: task.suffix == '₹' ? '₹ ' : null,
                          suffixText: task.suffix == '%' ? '%' : null,
                          errorText: error,
                          labelText: task.fieldLabel,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: AppButtons.primaryGold,
                        onPressed: saving ? null : save,
                        icon: saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(saving ? 'Saving' : 'Save input'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    controller.dispose();
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../providers/tax_result_provider.dart';

class BudgetAlertScreen extends ConsumerWidget {
  const BudgetAlertScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false, // Force user to tap CTA — intentional friction
      child: Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 760;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 56,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: compact ? 12 : 28),

                      // Alert icon
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.alert.withValues(alpha: 0.12),
                          border: Border.all(
                            color: AppColors.alert.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.campaign_rounded,
                          color: AppColors.alert,
                          size: 36,
                        ),
                      )
                          .animate()
                          .scale(duration: 400.ms, curve: Curves.elasticOut)
                          .fadeIn(duration: 300.ms),

                      SizedBox(height: compact ? 20 : 28),

                      Text(
                        'Planning rules\nare ready for\nFY2026-27.',
                        style: AppTextStyles.h1().copyWith(
                          fontSize: compact ? 28 : 32,
                          height: 1.2,
                        ),
                        textAlign: TextAlign.center,
                      )
                          .animate(delay: 300.ms)
                          .fadeIn(duration: 500.ms)
                          .slideY(begin: 0.1),

                      const SizedBox(height: 16),

                      Text(
                        'ARTH now separates filing-year calculations from planning-year estimates.',
                        style: AppTextStyles.body(
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ).animate(delay: 500.ms).fadeIn(duration: 500.ms),

                      SizedBox(height: compact ? 28 : 48),

                      // Date badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.alert.withValues(alpha: 0.1),
                          borderRadius: AppRadius.pill,
                          border: Border.all(
                            color: AppColors.alert.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          'Finance Act 2026 planning context',
                          style: AppTextStyles.caption(color: AppColors.alert),
                          textAlign: TextAlign.center,
                        ),
                      ).animate(delay: 700.ms).fadeIn(),

                      SizedBox(height: compact ? 24 : 32),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: AppButtons.primaryGold,
                          onPressed: () {
                            ref.invalidate(taxResultProvider);
                            context.go('/questions');
                          },
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(child: Text('Review diagnostic')),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward_rounded, size: 18),
                            ],
                          ),
                        ),
                      ).animate(delay: 900.ms).fadeIn().slideY(begin: 0.2),

                      SizedBox(height: compact ? 24 : 32),

                      Text(
                        'Default filing view remains FY2025-26 / AY2026-27.',
                        style: AppTextStyles.micro(color: AppColors.textMuted),
                        textAlign: TextAlign.center,
                      ).animate(delay: 1100.ms).fadeIn(),

                      SizedBox(height: compact ? 12 : 16),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

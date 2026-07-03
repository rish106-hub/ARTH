import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../widgets/arth_bottom_nav.dart';
import '../widgets/premium_ui.dart';

class AisGuideScreen extends StatelessWidget {
  const AisGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ArthScaffold(
      bottomNavigationBar: ArthBottomNav(
        selectedIndex: 2,
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
            eyebrow: 'Progress',
            title: 'AIS & 26AS guide',
            leading: IconButton(
              tooltip: 'Back',
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              color: AppColors.textSecondary,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PremiumGlassPanel(
                    elevated: true,
                    borderRadius: BorderRadius.circular(28),
                    tint: AppColors.teal,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TrustBadge(
                              icon: Icons.visibility_off_outlined,
                              label: 'No AIS import',
                              color: AppColors.teal,
                            ),
                            TrustBadge(
                              icon: Icons.verified_user_outlined,
                              label: 'Official-source guide',
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Use AIS and 26AS before filing.',
                          style: AppTextStyles.h1(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'ARTH does not fetch AIS, ask for income-tax OTP, or store official statements. This guide tells you what to inspect in the official Income Tax portal or AIS app.',
                          style: AppTextStyles.body(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          style: AppButtons.outlineGold,
                          onPressed: () => launchUrl(
                            Uri.parse(
                                'https://www.incometax.gov.in/iec/foportal/'),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('Open official portal'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ArthSection(
                    title: 'What to check',
                    child: Column(
                      children: const [
                        _GuideStep(
                          number: '01',
                          title: 'TDS and salary entries',
                          body:
                              'Match employer TDS with Form 16 and payslip expectation.',
                        ),
                        _GuideStep(
                          number: '02',
                          title: 'Interest and dividend income',
                          body:
                              'Banks, brokers, and companies may report income you forgot to include.',
                        ),
                        _GuideStep(
                          number: '03',
                          title: 'Tax payments and refunds',
                          body:
                              'Confirm self-assessment tax, advance tax, and refund history.',
                        ),
                        _GuideStep(
                          number: '04',
                          title: 'Mismatch feedback',
                          body:
                              'If official data looks wrong, use the official feedback path before filing.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ArthSection(
                    title: 'Risk signals',
                    child: PremiumGlassPanel(
                      child: Column(
                        children: const [
                          _RiskRow('Employer TDS lower than salary tax due'),
                          Divider(color: AppColors.divider),
                          _RiskRow(
                              'Bank interest present but not planned in return'),
                          Divider(color: AppColors.divider),
                          _RiskRow('High-value transactions not understood'),
                          Divider(color: AppColors.divider),
                          _RiskRow(
                              'Refund claimed without matching tax credit'),
                        ],
                      ),
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

class _GuideStep extends StatelessWidget {
  final String number;
  final String title;
  final String body;

  const _GuideStep({
    required this.number,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PremiumGlassPanel(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(number, style: AppTextStyles.h3(color: AppColors.gold)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.bodyMedium()),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style:
                        AppTextStyles.caption(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskRow extends StatelessWidget {
  final String text;

  const _RiskRow(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.amber, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.caption(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

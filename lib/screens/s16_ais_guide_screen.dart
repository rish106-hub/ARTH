import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../theme/paycheck_theme.dart';
import '../widgets/arth_bottom_nav.dart';
import '../widgets/premium_ui.dart';

class AisGuideScreen extends StatelessWidget {
  const AisGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ArthScaffold(
      bottomNavigationBar: ArthBottomNav(
        selectedIndex: 2,
        onTap: (i) => goToArthTab(context, i),
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
                    tint: PaycheckColors.teal,
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
                              color: PaycheckColors.teal,
                            ),
                            TrustBadge(
                              icon: Icons.verified_user_outlined,
                              label: 'Official-source guide',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Use AIS and 26AS before filing.',
                          style: PaycheckType.h1(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'What to inspect in the portal or AIS app.',
                          style: PaycheckType.body(
                            color: PaycheckColors.textSecondary,
                          ),
                        ),
                        const ArthDisclosure(
                          label: 'What ARTH does not do',
                          icon: Icons.lock_outline,
                          detail:
                              'ARTH never fetches AIS, asks for an income-tax OTP, or stores official statements.',
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
                  const ArthSection(
                    title: 'What to check',
                    child: Column(
                      children: [
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
                  const ArthSection(
                    title: 'Risk signals',
                    child: PremiumGlassPanel(
                      child: Column(
                        children: [
                          _RiskRow('Employer TDS lower than salary tax due'),
                          Divider(color: PaycheckColors.divider),
                          _RiskRow(
                              'Bank interest present but not planned in return'),
                          Divider(color: PaycheckColors.divider),
                          _RiskRow('High-value transactions not understood'),
                          Divider(color: PaycheckColors.divider),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: PremiumGlassPanel(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(number,
                style: PaycheckType.heading(color: PaycheckColors.gold)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: PaycheckType.bodyMedium()),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: PaycheckType.caption(
                        color: PaycheckColors.textSecondary),
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
              color: PaycheckColors.amber, size: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: PaycheckType.caption(color: PaycheckColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

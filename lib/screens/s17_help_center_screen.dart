import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/tax_year_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/arth_bottom_nav.dart';
import '../widgets/premium_ui.dart';

const _supportName = 'Rishav Dewan';
const _supportEmail = 'rishavdewan10@gmail.com';
const _supportPhone = '9749452397';

class HelpCenterScreen extends ConsumerWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeYear = ref.watch(activeTaxYearProvider);
    final safeContext =
        'Tax year: ${activeYear.displayLabel} / ${activeYear.assessmentYear}\nDo not include PAN, passwords, tokens, or uploaded documents in this email.\n\n';
    return ArthScaffold(
      bottomNavigationBar: ArthBottomNav(
        selectedIndex: 3,
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
            eyebrow: 'Support',
            title: 'Help Center',
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
                    tint: AppColors.gold,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const TrustBadge(
                          icon: Icons.support_agent_rounded,
                          label: 'Human support',
                        ),
                        const SizedBox(height: 16),
                        Text('Need help with ARTH?', style: AppTextStyles.h1()),
                        const SizedBox(height: 8),
                        Text(
                          'Use this for product issues, tax-readiness questions, and data/privacy help. ARTH does not provide official tax filing or legal advice.',
                          style: AppTextStyles.body(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            OutlinedButton.icon(
                              style: AppButtons.outlineGold,
                              onPressed: () => _email(
                                subject: 'ARTH support request',
                                body: safeContext,
                              ),
                              icon: const Icon(Icons.mail_outline_rounded),
                              label: const Text('Email'),
                            ),
                            OutlinedButton.icon(
                              style: AppButtons.outlineGold,
                              onPressed: () => _call(),
                              icon: const Icon(Icons.call_outlined),
                              label: const Text('Call'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ArthSection(
                    title: 'Contact',
                    child: PremiumGlassPanel(
                      child: Column(
                        children: const [
                          _ContactRow(
                            icon: Icons.person_outline_rounded,
                            label: 'Contact person',
                            value: _supportName,
                          ),
                          Divider(color: AppColors.divider),
                          _ContactRow(
                            icon: Icons.mail_outline_rounded,
                            label: 'Email',
                            value: _supportEmail,
                          ),
                          Divider(color: AppColors.divider),
                          _ContactRow(
                            icon: Icons.call_outlined,
                            label: 'Phone',
                            value: _supportPhone,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ArthSection(
                    title: 'Support topics',
                    child: Column(
                      children: [
                        _SupportTopic(
                          icon: Icons.bug_report_outlined,
                          title: 'Report an issue',
                          body:
                              'Share what broke, where it happened, and your device.',
                          onTap: () => _email(
                            subject: 'ARTH issue report',
                            body:
                                '${safeContext}Issue:\n\nScreen:\n\nDevice:\n\nSteps to reproduce:\n',
                          ),
                        ),
                        const SizedBox(height: 10),
                        _SupportTopic(
                          icon: Icons.question_answer_outlined,
                          title: 'Ask tax question',
                          body:
                              'Ask for product guidance or tax-readiness explanation.',
                          onTap: () => _email(
                            subject: 'ARTH tax-readiness question',
                            body: '${safeContext}Question:\n\nContext:\n',
                          ),
                        ),
                        const SizedBox(height: 10),
                        _SupportTopic(
                          icon: Icons.privacy_tip_outlined,
                          title: 'Data/privacy help',
                          body:
                              'Ask about PAN vault, account deletion, or saved data.',
                          onTap: () => _email(
                            subject: 'ARTH data/privacy help',
                            body: '${safeContext}Privacy question:\n\n',
                          ),
                        ),
                        const SizedBox(height: 10),
                        _SupportTopic(
                          icon: Icons.slideshow_outlined,
                          title: 'Demo walkthrough',
                          body:
                              'Ask for a quick walkthrough of Home, Accuracy, Simulator, and Dossier.',
                          onTap: () => _email(
                            subject: 'ARTH demo walkthrough request',
                            body:
                                '${safeContext}I would like a walkthrough of:\n\nBest time to connect:\n',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ArthSection(
                    title: 'FAQ',
                    child: PremiumGlassPanel(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: const [
                          _FaqTile(
                            question: 'Does ARTH file ITR?',
                            answer:
                                'No. This version prepares your tax view, checklist, gaps, and handoff readiness.',
                          ),
                          Divider(color: AppColors.divider, height: 1),
                          _FaqTile(
                            question: 'Do I need to add PAN?',
                            answer:
                                'No. PAN is optional and stays in Profile only. The diagnostic works without it.',
                          ),
                          Divider(color: AppColors.divider, height: 1),
                          _FaqTile(
                            question: 'Are documents uploaded?',
                            answer:
                                'Only if you choose. ARTH stores supported PDFs/images in an encrypted server vault.',
                          ),
                          Divider(color: AppColors.divider, height: 1),
                          _FaqTile(
                            question: 'What data can I delete?',
                            answer:
                                'Profile has a clear-data action for diagnostic, calculations, progress, and PAN vault.',
                          ),
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

  static Future<void> _email({required String subject, String? body}) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {
        'subject': subject,
        if (body != null) 'body': body,
      },
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> _call() async {
    await launchUrl(
      Uri(scheme: 'tel', path: _supportPhone),
      mode: LaunchMode.externalApplication,
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.gold, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.micro()),
                const SizedBox(height: 2),
                Text(value, style: AppTextStyles.bodyMedium()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportTopic extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  const _SupportTopic({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumGlassPanel(
      padding: const EdgeInsets.all(16),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: AppColors.teal),
        title: Text(title, style: AppTextStyles.bodyMedium()),
        subtitle: Text(
          body,
          style: AppTextStyles.caption(color: AppColors.textSecondary),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final String question;
  final String answer;

  const _FaqTile({
    required this.question,
    required this.answer,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        collapsedIconColor: AppColors.textSecondary,
        iconColor: AppColors.gold,
        title: Text(question, style: AppTextStyles.bodyMedium()),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              answer,
              style: AppTextStyles.caption(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

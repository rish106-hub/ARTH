import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../widgets/premium_ui.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _continue() {
    if (_page == 2) {
      context.go('/questions');
      return;
    }
    _controller.nextPage(
      duration: AppMotion.medium,
      curve: AppMotion.standard,
    );
  }

  void _showDigiLockerStatus() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('DigiLocker connection is being prepared.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ArthScaffold(
      showAmbientGlow: false,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 14, 8),
              child: Row(
                children: [
                  Text(
                    'ARTH',
                    style: AppTextStyles.h3(color: AppColors.gold),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => context.go('/questions'),
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (value) => setState(() => _page = value),
                children: const [
                  _OpeningChapter(),
                  _TaxPathChapter(),
                  _InputChapter(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PageIndicator(current: _page, total: 3),
                  const SizedBox(height: 18),
                  if (_page == 2) ...[
                    OutlinedButton.icon(
                      style: AppButtons.outlineGold,
                      onPressed: _showDigiLockerStatus,
                      icon: const Icon(Icons.account_balance_outlined, size: 18),
                      label: const Text('Fetch from DigiLocker'),
                    ),
                    const SizedBox(height: 10),
                  ],
                  ElevatedButton.icon(
                    style: AppButtons.primaryGold,
                    onPressed: _continue,
                    icon: Icon(
                      _page == 2
                          ? Icons.arrow_forward_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      size: 19,
                    ),
                    label: Text(
                      _page == 2 ? 'Begin my tax journey' : 'Continue',
                    ),
                  )
                      .animate(target: reduceMotion ? 0 : 1)
                      .fadeIn(duration: 260.ms),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpeningChapter extends StatelessWidget {
  const _OpeningChapter();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 238,
            width: double.infinity,
            decoration: const BoxDecoration(
              color: AppColors.gold,
              borderRadius: AppRadius.card,
            ),
            child: Stack(
              children: [
                const Positioned(
                  top: 24,
                  left: 24,
                  child: Text(
                    'FY 2026-27',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        '₹',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 64,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  right: 24,
                  bottom: 22,
                  child: Icon(
                    Icons.north_east_rounded,
                    color: AppColors.amber,
                    size: 30,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Text(
            'You earned it.\nKeep more of it.',
            style: AppTextStyles.h1().copyWith(fontSize: 34, height: 1.08),
          ),
          const SizedBox(height: 14),
          Text(
            'ARTH turns salary, deductions and proofs into a clear tax position. No spreadsheets. No rule-book hunting.',
            style: AppTextStyles.body(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _TaxPathChapter extends StatelessWidget {
  const _TaxPathChapter();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your tax year has a shape.', style: AppTextStyles.h1()),
          const SizedBox(height: 12),
          Text(
            'We move through it in the same order you do.',
            style: AppTextStyles.body(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 36),
          const _PathStep(
            index: '01',
            icon: Icons.payments_outlined,
            title: 'Earn',
            body: 'Map salary, work type and income.',
          ),
          const _PathConnector(),
          const _PathStep(
            index: '02',
            icon: Icons.tune_rounded,
            title: 'Optimise',
            body: 'Find regime and deduction opportunities.',
          ),
          const _PathConnector(),
          const _PathStep(
            index: '03',
            icon: Icons.folder_open_outlined,
            title: 'Prepare',
            body: 'Turn opportunities into proof-ready actions.',
          ),
          const _PathConnector(),
          const _PathStep(
            index: '04',
            icon: Icons.task_alt_rounded,
            title: 'File',
            body: 'Create a clean handoff when you are ready.',
          ),
        ],
      ),
    );
  }
}

class _InputChapter extends StatelessWidget {
  const _InputChapter();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Start with what you know.', style: AppTextStyles.h1()),
          const SizedBox(height: 12),
          Text(
            'Approximate answers are enough for the first pass. You can tighten the numbers later.',
            style: AppTextStyles.body(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 34),
          const _MethodRow(
            icon: Icons.edit_note_rounded,
            title: 'Enter manually',
            body: '12 guided questions · about 3 minutes',
            active: true,
          ),
          const Divider(height: 1),
          const _MethodRow(
            icon: Icons.account_balance_outlined,
            title: 'DigiLocker connection',
            body: 'A faster route for verified documents is coming next.',
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: AppRadius.card,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome_outlined, color: AppColors.gold),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'The first result is an optimisation map: what matters, how much it may affect, and what to do next.',
                    style: AppTextStyles.caption(color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PathStep extends StatelessWidget {
  final String index;
  final IconData icon;
  final String title;
  final String body;

  const _PathStep({
    required this.index,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            color: AppColors.goldLight,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.gold, size: 23),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$index  $title', style: AppTextStyles.h3()),
              const SizedBox(height: 3),
              Text(
                body,
                style: AppTextStyles.caption(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PathConnector extends StatelessWidget {
  const _PathConnector();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 2,
      height: 22,
      margin: const EdgeInsets.only(left: 25),
      color: AppColors.border,
    );
  }
}

class _MethodRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool active;

  const _MethodRow({
    required this.icon,
    required this.title,
    required this.body,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          Icon(icon, color: active ? AppColors.gold : AppColors.textMuted),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodyMedium()),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: AppTextStyles.caption(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (active)
            const Icon(Icons.check_circle_rounded, color: AppColors.success),
        ],
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  final int current;
  final int total;

  const _PageIndicator({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        total,
        (index) => Expanded(
          child: AnimatedContainer(
            duration: AppMotion.fast,
            height: 3,
            margin: EdgeInsets.only(right: index == total - 1 ? 0 : 6),
            decoration: BoxDecoration(
              color: index <= current ? AppColors.gold : AppColors.border,
              borderRadius: AppRadius.pill,
            ),
          ),
        ),
      ),
    );
  }
}

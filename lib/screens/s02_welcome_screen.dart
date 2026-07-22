import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../widgets/premium_ui.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ArthScaffold(
      showAmbientGlow: false,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('ARTH', style: AppTextStyles.h3()),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Skip introduction',
                      onPressed: () => context.go('/money-setup'),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 34),
                Text(
                  'Know what your\nmoney needs next.',
                  style:
                      AppTextStyles.h1().copyWith(fontSize: 38, height: 1.02),
                ),
                const SizedBox(height: 16),
                Text(
                  'ARTH turns compensation, commitments and goals into a monthly plan you can act on.',
                  style: AppTextStyles.body(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 28),
                AnimatedBuilder(
                  animation: _motion,
                  builder: (context, _) => _JourneyPath(
                    pulse: reduceMotion ? 0.5 : _motion.value,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: AppButtons.primaryGold,
                    onPressed: () => context.go('/money-setup'),
                    child: const Text('Build my money baseline'),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'About 4 minutes. You control every input.',
                    style: AppTextStyles.micro(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JourneyPath extends StatelessWidget {
  final double pulse;

  const _JourneyPath({required this.pulse});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            children: [
              Positioned(
                left: 24,
                right: 24,
                top: 40,
                child: Container(height: 2, color: AppColors.border),
              ),
              Positioned(
                left: 24,
                top: 40,
                child: Container(
                  width: (width - 48) * (0.15 + pulse * 0.7),
                  height: 2,
                  color: AppColors.primary,
                ),
              ),
              const _JourneyPoint(
                alignment: Alignment.topLeft,
                icon: Icons.payments_outlined,
                label: 'Income',
              ),
              const _JourneyPoint(
                alignment: Alignment.topCenter,
                icon: Icons.lock_outline_rounded,
                label: 'Commit',
              ),
              const _JourneyPoint(
                alignment: Alignment.topRight,
                icon: Icons.call_split_rounded,
                label: 'Decide',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _JourneyPoint extends StatelessWidget {
  final Alignment alignment;
  final IconData icon;
  final String label;

  const _JourneyPoint({
    required this.alignment,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: AppColors.ink,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 21),
            ),
            const SizedBox(height: 12),
            Text(label, style: AppTextStyles.caption()),
          ],
        ),
      ),
    );
  }
}

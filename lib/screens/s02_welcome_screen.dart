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

  static const _slides = [
    _WelcomeSlide(
      icon: Icons.savings_rounded,
      eyebrow: 'Discover',
      title: 'Find money your salary already earned.',
      body:
          'ARTH scans your answers for deduction gaps across old and new tax regimes.',
      badge: 'Built for Indian salaried taxpayers',
    ),
    _WelcomeSlide(
      icon: Icons.privacy_tip_rounded,
      eyebrow: 'Private by default',
      title: 'No PAN. No ITR upload. No document dragnet.',
      body:
          'Start with a guided diagnostic. Share only what is needed to calculate useful next actions.',
      badge: 'Trust-first tax intelligence',
    ),
    _WelcomeSlide(
      icon: Icons.route_rounded,
      eyebrow: 'Act',
      title: 'Get a cockpit, not a spreadsheet.',
      body:
          'See your gap, best regime, deadlines, and a prioritized action plan in one flow.',
      badge: 'About 3 minutes',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _slides.length - 1) {
      context.go('/questions');
      return;
    }
    _controller.nextPage(duration: AppMotion.medium, curve: AppMotion.standard);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ArthScaffold(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ARTH',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium().copyWith(letterSpacing: 4),
                ),
              ),
              const SizedBox(width: 12),
              const Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: TrustBadge(
                      icon: Icons.lock_outline_rounded,
                      label: 'No PAN required',
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _slides.length,
              onPageChanged: (value) => setState(() => _page = value),
              itemBuilder: (context, index) {
                final slide = _slides[index];
                return _SlideCard(slide: slide)
                    .animate(target: reduceMotion ? 0 : 1)
                    .fadeIn(duration: 320.ms)
                    .slideY(begin: 0.05, end: 0);
              },
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _slides.length,
              (index) => AnimatedContainer(
                duration: AppMotion.fast,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: index == _page ? 28 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: index == _page ? AppColors.gold : AppColors.bgSurface,
                  borderRadius: AppRadius.pill,
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              style: AppButtons.primaryGold,
              onPressed: _next,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      _page == _slides.length - 1
                          ? 'Start diagnostic'
                          : 'Continue',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go('/questions'),
            child: Text(
              'Skip story and answer questions',
              style: AppTextStyles.caption(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideCard extends StatelessWidget {
  final _WelcomeSlide slide;

  const _SlideCard({required this.slide});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 520;
        return Center(
          child: SingleChildScrollView(
            child: PremiumGlassPanel(
              elevated: true,
              borderRadius: BorderRadius.circular(26),
              padding: EdgeInsets.all(compact ? 18 : 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: compact ? 54 : 66,
                    height: compact ? 54 : 66,
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: AppColors.gold.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Icon(
                      slide.icon,
                      color: AppColors.gold,
                      size: compact ? 27 : 32,
                    ),
                  ),
                  SizedBox(height: compact ? 18 : 24),
                  Text(
                    slide.eyebrow.toUpperCase(),
                    style: AppTextStyles.sectionLabel()
                        .copyWith(letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    slide.title,
                    style: AppTextStyles.h1().copyWith(
                      fontSize: compact ? 25 : 30,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    slide.body,
                    style: AppTextStyles.body(color: AppColors.textSecondary),
                  ),
                  SizedBox(height: compact ? 16 : 20),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: TrustBadge(
                      icon: Icons.verified_user_outlined,
                      label: slide.badge,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WelcomeSlide {
  final IconData icon;
  final String eyebrow;
  final String title;
  final String body;
  final String badge;

  const _WelcomeSlide({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.badge,
  });
}

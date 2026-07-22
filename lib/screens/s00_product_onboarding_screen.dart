import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/paycheck_theme.dart';
import '../widgets/arth_brand_mark.dart';

class ProductOnboardingScreen extends StatefulWidget {
  const ProductOnboardingScreen({super.key});

  @override
  State<ProductOnboardingScreen> createState() =>
      _ProductOnboardingScreenState();
}

class _ProductOnboardingScreenState extends State<ProductOnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardingPageData(
      image: 'assets/images/onboarding_offer.jpg',
      eyebrow: 'START WITH THE PROMISE',
      title: 'Know what your offer letter is worth.',
      body:
          'ARTH turns salary, variable pay and benefits into one clear monthly promise.',
      accent: PaycheckColors.contract,
    ),
    _OnboardingPageData(
      image: 'assets/images/onboarding_paycheck.jpg',
      eyebrow: 'MATCH EVERY PAYDAY',
      title: 'See what arrived and what did not.',
      body:
          'Compare the promise with payslips, salary credits and employer contributions.',
      accent: PaycheckColors.matched,
    ),
    _OnboardingPageData(
      image: 'assets/images/onboarding_claim.jpg',
      eyebrow: 'ACT BEFORE IT EXPIRES',
      title: 'Prepare money you can still claim.',
      body:
          'Keep proof together, catch deadlines and approve every action yourself.',
      accent: PaycheckColors.claim,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _continue() {
    if (_page == _pages.length - 1) {
      context.go('/auth');
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: PaycheckColors.paper,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: _pages.length,
            onPageChanged: (value) => setState(() => _page = value),
            itemBuilder: (context, index) => _OnboardingPage(
              data: _pages[index],
              active: index == _page,
              reduceMotion: reduceMotion,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: ArthBrandMark(size: 30),
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    key: const Key('explore_app_button'),
                    onPressed: () => context.go('/explore'),
                    style: TextButton.styleFrom(
                      foregroundColor: PaycheckColors.ink,
                      backgroundColor: Colors.white.withValues(alpha: 0.94),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.explore_outlined, size: 19),
                    label: Text(
                      'Explore app',
                      style: PaycheckType.bodyStrong(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: MediaQuery.paddingOf(context).bottom + 18,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Row(
                      children: List.generate(
                        _pages.length,
                        (index) => AnimatedContainer(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          width: index == _page ? 24 : 7,
                          height: 7,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: index == _page
                                ? _pages[_page].accent
                                : PaycheckColors.line,
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => context.go('/auth?mode=sign-in'),
                      child: Text('Sign in', style: PaycheckType.bodyStrong()),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _continue,
                    style: FilledButton.styleFrom(
                      backgroundColor: PaycheckColors.ink,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: Icon(
                      _page == _pages.length - 1
                          ? Icons.person_add_alt_1_rounded
                          : Icons.arrow_forward_rounded,
                      size: 20,
                    ),
                    label: Text(
                      _page == _pages.length - 1 ? 'Sign up' : 'Continue',
                      style: PaycheckType.bodyStrong(color: Colors.white),
                    ),
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

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.data,
    required this.active,
    required this.reduceMotion,
  });

  final _OnboardingPageData data;
  final bool active;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ClipRect(
            child: TweenAnimationBuilder<double>(
              key: ValueKey('${data.image}-$active'),
              tween: Tween(begin: active && !reduceMotion ? 1.07 : 1, end: 1),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 5200),
              curve: Curves.easeOutCubic,
              builder: (context, scale, child) => Transform.scale(
                scale: scale,
                child: child,
              ),
              child: SizedBox.expand(
                child: Image.asset(
                  data.image,
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, 0.1),
                ),
              ),
            ),
          ),
        ),
        Container(
          height: 292,
          width: double.infinity,
          color: PaycheckColors.paper,
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 112),
          child: AnimatedOpacity(
            opacity: active ? 1 : 0.45,
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 260),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.eyebrow,
                  style: PaycheckType.utility(color: data.accent),
                ),
                const SizedBox(height: 9),
                Text(
                  data.title,
                  maxLines: 2,
                  style: PaycheckType.title().copyWith(fontSize: 30),
                ),
                const SizedBox(height: 9),
                Text(
                  data.body,
                  maxLines: 3,
                  style: PaycheckType.body(color: PaycheckColors.inkSoft),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.image,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.accent,
  });

  final String image;
  final String eyebrow;
  final String title;
  final String body;
  final Color accent;
}

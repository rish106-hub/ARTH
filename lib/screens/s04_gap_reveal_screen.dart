import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../providers/tax_result_provider.dart';
import '../widgets/animated_number.dart';
import '../widgets/arth_bottom_nav.dart';

class GapRevealScreen extends ConsumerStatefulWidget {
  const GapRevealScreen({super.key});

  @override
  ConsumerState<GapRevealScreen> createState() => _GapRevealScreenState();
}

class _GapRevealScreenState extends ConsumerState<GapRevealScreen>
    with SingleTickerProviderStateMixin {
  bool _revealed = false;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _revealed = true);
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _onNumberSettle(int amount) {
    HapticFeedback.mediumImpact();
    if (amount >= 100000) {
      // Confetti/pulse for large gap
      _pulseCtrl.repeat(reverse: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resultAsync = ref.watch(taxResultProvider);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: Stack(
        children: [
          // Background glow
          Positioned(
            top: -100,
            left: -50,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold.withOpacity(0.04),
              ),
            ),
          ),

          SafeArea(
            bottom: false,
            child: resultAsync.when(
              loading: () => const Center(
                child: _CalculatingAnimation(),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Could not calculate your gap.',
                          style: AppTextStyles.body()),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: AppButtons.primaryGold,
                        onPressed: () {
                          ref.invalidate(taxResultProvider);
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (result) {
                final gapAmount = result.totalGapAmount;
                final isZeroGap = gapAmount == 0;

                return Column(
                  children: [
                    // Top bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // ARTH wordmark
                          Text('ARTH',
                              style: AppTextStyles.body()
                                  .copyWith(letterSpacing: 4)),
                          // Share icon
                          IconButton(
                            icon: const Icon(Icons.ios_share_rounded,
                                color: AppColors.textSecondary, size: 20),
                            onPressed: () => context.push('/share'),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(flex: 2),

                    // Main reveal
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          if (isZeroGap)
                            _ZeroGapDisplay()
                          else
                            _GapDisplay(
                              gapAmount: gapAmount,
                              gapCount: result.gapCount,
                              revealed: _revealed,
                              onSettle: _onNumberSettle,
                              pulseAnim: _pulseAnim,
                            ),
                        ],
                      ),
                    ),

                    const Spacer(flex: 2),

                    // CTAs
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: AppButtons.primaryGold,
                              onPressed: () => context.push('/deduction-cards'),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('See My Gaps'),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward_rounded, size: 18),
                                ],
                              ),
                            ),
                          ).animate(delay: 2000.ms).fadeIn(duration: 600.ms).slideY(begin: 0.3),

                          const SizedBox(height: 12),

                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              style: AppButtons.outlineGold,
                              onPressed: () =>
                                  context.push('/regime-comparison'),
                              child: const Text('Compare Old vs New Regime'),
                            ),
                          ).animate(delay: 2200.ms).fadeIn(duration: 500.ms),

                          const SizedBox(height: 12),

                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              side: const BorderSide(color: AppColors.border),
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                            ),
                            onPressed: () => context.push('/action-plan'),
                            icon: const Icon(Icons.checklist_rounded, size: 16),
                            label: const Text('Action Plan'),
                          ).animate(delay: 2400.ms).fadeIn(duration: 500.ms),

                          const SizedBox(height: 8),
                        ],
                      ),
                    ),

                    // Bottom nav
                    ArthBottomNav(
                      selectedIndex: 0,
                      onTap: (i) {
                        switch (i) {
                          case 0: break;
                          case 1: context.go('/action-plan'); break;
                          case 2: context.go('/progress'); break;
                          case 3: context.go('/settings'); break;
                        }
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── GAP DISPLAY ─────────────────────────────────────────────────────────────
class _GapDisplay extends StatelessWidget {
  final int gapAmount;
  final int gapCount;
  final bool revealed;
  final void Function(int) onSettle;
  final Animation<double> pulseAnim;

  const _GapDisplay({
    required this.gapAmount,
    required this.gapCount,
    required this.revealed,
    required this.onSettle,
    required this.pulseAnim,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'You are leaving behind',
          style: AppTextStyles.body(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ).animate(delay: 300.ms).fadeIn(duration: 500.ms),

        const SizedBox(height: 20),

        if (revealed)
          AnimatedBuilder(
            animation: pulseAnim,
            builder: (_, child) => Transform.scale(
              scale: pulseAnim.value,
              child: child,
            ),
            child: AnimatedRupeeNumber(
              value: gapAmount,
              duration: const Duration(milliseconds: 1800),
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 64,
                fontWeight: FontWeight.w900,
                color: AppColors.gold,
                letterSpacing: -2,
                height: 1,
              ),
            ),
          ).animate().fadeIn(duration: 400.ms)
        else
          const Text(
            '₹ —',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 64,
              fontWeight: FontWeight.w900,
              color: AppColors.textSecondary,
            ),
          ),

        const SizedBox(height: 16),

        Text(
          'every year in unclaimed\ntax deductions.',
          style: AppTextStyles.h2(color: AppColors.textPrimary)
              .copyWith(height: 1.3),
          textAlign: TextAlign.center,
        ).animate(delay: 800.ms).fadeIn(duration: 600.ms),

        const SizedBox(height: 16),

        if (gapCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: AppRadius.pill,
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              'Across $gapCount sections of the Income Tax Act',
              style: AppTextStyles.caption(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ).animate(delay: 1200.ms).fadeIn(duration: 500.ms),
      ],
    );
  }
}

// ─── ZERO GAP ────────────────────────────────────────────────────────────────
class _ZeroGapDisplay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.verified_outlined, size: 64, color: AppColors.gold),
        const SizedBox(height: 16),
        Text(
          'You\'re a tax ninja.',
          style: AppTextStyles.h1(color: AppColors.gold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Your deductions are fully optimised.\nNot a rupee more to claim.',
          style: AppTextStyles.body(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ─── CALCULATING ANIMATION ───────────────────────────────────────────────────
class _CalculatingAnimation extends StatefulWidget {
  const _CalculatingAnimation();

  @override
  State<_CalculatingAnimation> createState() => _CalculatingAnimationState();
}

class _CalculatingAnimationState extends State<_CalculatingAnimation>
    with TickerProviderStateMixin {
  late AnimationController _dotCtrl;
  late Animation<int> _dotAnim;

  @override
  void initState() {
    super.initState();
    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _dotAnim = IntTween(begin: 0, end: 3).animate(_dotCtrl);
  }

  @override
  void dispose() {
    _dotCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('₹', style: TextStyle(fontSize: 64, color: AppColors.gold)),
        const SizedBox(height: 16),
        AnimatedBuilder(
          animation: _dotAnim,
          builder: (_, __) => Text(
            'Calculating your gap${['', '.', '..', '...'][_dotAnim.value]}',
            style: AppTextStyles.h3(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

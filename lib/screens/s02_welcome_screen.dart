import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: Stack(
        children: [
          // Ambient particles (simple circles)
          const _AmbientParticles(),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(flex: 2),

                  // Main headline
                  Text(
                    'Most Indians\noverpay their\ntaxes.',
                    style: AppTextStyles.h1().copyWith(fontSize: 36, height: 1.2),
                  )
                      .animate(delay: 200.ms)
                      .fadeIn(duration: 700.ms)
                      .slideY(begin: 0.15, end: 0, curve: Curves.easeOut),

                  const SizedBox(height: 20),

                  Text(
                    'ARTH finds what\nyou\'re leaving behind.',
                    style: AppTextStyles.h2(color: AppColors.gold).copyWith(height: 1.3),
                  )
                      .animate(delay: 500.ms)
                      .fadeIn(duration: 700.ms)
                      .slideY(begin: 0.15, end: 0, curve: Curves.easeOut),

                  const SizedBox(height: 32),

                  Text(
                    'The average salaried Indian leaves\n₹50,000 – ₹2,00,000 unclaimed\nevery year. Not this year.',
                    style: AppTextStyles.body(color: AppColors.textSecondary),
                  )
                      .animate(delay: 750.ms)
                      .fadeIn(duration: 600.ms),

                  const Spacer(flex: 3),

                  // CTA
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: AppButtons.primaryGold,
                      onPressed: () => context.go('/questions'),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Find My Gap'),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
                    ),
                  )
                      .animate(delay: 1000.ms)
                      .fadeIn(duration: 500.ms)
                      .slideY(begin: 0.2, end: 0),

                  const SizedBox(height: 16),

                  Center(
                    child: Text(
                      'Takes 3 minutes. No PAN. No login. No nonsense.',
                      style: AppTextStyles.micro(color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ).animate(delay: 1100.ms).fadeIn(duration: 500.ms),

                  const SizedBox(height: 12),

                  // Trust badge
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: AppRadius.pill,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shield_outlined,
                              size: 14, color: AppColors.gold),
                          const SizedBox(width: 6),
                          Text(
                            'Nothing you enter leaves your phone',
                            style: AppTextStyles.micro(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ).animate(delay: 1200.ms).fadeIn(),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Simple ambient particle effect
class _AmbientParticles extends StatefulWidget {
  const _AmbientParticles();

  @override
  State<_AmbientParticles> createState() => _AmbientParticlesState();
}

class _AmbientParticlesState extends State<_AmbientParticles>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  final List<Offset> _positions = [
    const Offset(0.1, 0.2),
    const Offset(0.85, 0.1),
    const Offset(0.5, 0.3),
    const Offset(0.7, 0.7),
    const Offset(0.2, 0.8),
    const Offset(0.9, 0.5),
  ];

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      _positions.length,
      (i) => AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 2000 + i * 400),
      )
        ..forward()
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) {
            _controllers[i].reverse();
          } else if (s == AnimationStatus.dismissed) {
            _controllers[i].forward();
          }
        }),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Stack(
      children: List.generate(_positions.length, (i) {
        return AnimatedBuilder(
          animation: _controllers[i],
          builder: (_, __) {
            final opacity = 0.04 + _controllers[i].value * 0.06;
            return Positioned(
              left: _positions[i].dx * size.width,
              top: _positions[i].dy * size.height,
              child: Container(
                width: 6 + i * 3.0,
                height: 6 + i * 3.0,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.gold.withOpacity(opacity),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

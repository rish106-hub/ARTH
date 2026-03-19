import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../providers/user_profile_provider.dart';
import '../providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _rupeePulse;

  @override
  void initState() {
    super.initState();
    _rupeePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _start();
  }

  Future<void> _start() async {
    await Future.delayed(const Duration(milliseconds: 300));
    _rupeePulse.forward();
    await Future.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;

    // 1. Check if account exists
    final account = await ref.read(authServiceProvider).loadAccount();
    if (!mounted) return;

    if (account == null) {
      // First install — go to auth
      context.go('/auth');
      return;
    }

    // 2. Account exists — check biometrics
    if (account.biometricsEnabled) {
      final success = await ref.read(authProvider.notifier).authenticate();
      if (!mounted) return;
      if (!success) {
        // Auth failed — stay on auth screen for manual login
        context.go('/auth');
        return;
      }
    }

    // 3. Check onboarding
    final done = await ref.read(userProfileProvider.notifier).isOnboardingComplete();
    if (!mounted) return;
    if (done) {
      await ref.read(userProfileProvider.notifier).load();
      if (mounted) context.go('/gap-reveal');
    } else {
      if (mounted) context.go('/welcome');
    }
  }

  @override
  void dispose() {
    _rupeePulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Rupee symbol — animates grey → gold
            AnimatedBuilder(
              animation: _rupeePulse,
              builder: (_, __) {
                final t = _rupeePulse.value;
                final color = Color.lerp(
                  const Color(0xFF616161),
                  AppColors.gold,
                  Curves.easeOut.transform(t),
                )!;
                return Text(
                  '₹',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 80,
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1,
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // App name
            Text(
              'ARTH',
              style: AppTextStyles.h1(color: AppColors.textPrimary).copyWith(
                letterSpacing: 8,
                fontSize: 32,
              ),
            )
                .animate(delay: 600.ms)
                .fadeIn(duration: 600.ms, curve: Curves.easeOut),

            const SizedBox(height: 12),

            // Tagline
            Text(
              'Not a rupee less. Not a rupee more.',
              style: AppTextStyles.caption(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            )
                .animate(delay: 900.ms)
                .fadeIn(duration: 600.ms),
          ],
        ),
      ),
    );
  }
}

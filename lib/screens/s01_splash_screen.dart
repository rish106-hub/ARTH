import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../providers/user_profile_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/premium_ui.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _rupeePulse;
  Timer? _pulseStartTimer;
  Timer? _routeTimer;

  @override
  void initState() {
    super.initState();
    _rupeePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scheduleStartup();
  }

  void _scheduleStartup() {
    _pulseStartTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _rupeePulse.forward();
    });
    _routeTimer = Timer(const Duration(milliseconds: 1400), _routeFromSplash);
  }

  Future<void> _routeFromSplash() async {
    if (!mounted) return;
    // 1. Check if account exists
    final account = await ref.read(authServiceProvider).loadAccount();
    if (!mounted) return;

    if (account == null) {
      context.go('/auth');
      return;
    }

    ref.read(userProfileProvider.notifier).applyAccountIdentity(account);

    // 2. Server is source of truth — load fetches this user's unique profile.
    //    Returns true if a saved profile exists (onboarding done).
    //    Also works correctly on fresh device installs.
    await ref.read(userProfileProvider.notifier).load();
    if (!mounted) return;
    context.go('/paycheck');
  }

  @override
  void dispose() {
    _pulseStartTimer?.cancel();
    _routeTimer?.cancel();
    _rupeePulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ArthScaffold(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _rupeePulse,
              builder: (_, __) {
                final t = _rupeePulse.value;
                return Transform.scale(
                  scale: 0.88 + (0.12 * t),
                  child: Opacity(
                    opacity: 0.55 + (0.45 * t),
                    child: Image.asset(
                      'assets/icon/icon_1024.png',
                      width: 112,
                      height: 112,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // App name
            Text(
              'ARTH',
              style: AppTextStyles.h1(
                color: AppColors.textPrimary,
              ).copyWith(letterSpacing: 8, fontSize: 32),
            )
                .animate(delay: 600.ms)
                .fadeIn(duration: 600.ms, curve: Curves.easeOut),

            const SizedBox(height: 12),

            // Tagline
            Text(
              'Know what your paycheck still owes you.',
              style: AppTextStyles.caption(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ).animate(delay: 900.ms).fadeIn(duration: 600.ms),
            const SizedBox(height: 18),
            const TrustBadge(
              icon: Icons.auto_awesome_outlined,
              label: 'Promised · Received · Claimable',
            ).animate(delay: 1050.ms).fadeIn(duration: 260.ms),
          ],
        ),
      ),
    );
  }
}

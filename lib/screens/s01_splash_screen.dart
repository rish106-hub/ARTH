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
    final hasProfile = await ref.read(userProfileProvider.notifier).load();
    if (!mounted) return;
    context.go(hasProfile ? '/gap-reveal' : '/welcome');
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
              style: AppTextStyles.h1(
                color: AppColors.textPrimary,
              ).copyWith(letterSpacing: 8, fontSize: 32),
            )
                .animate(delay: 600.ms)
                .fadeIn(duration: 600.ms, curve: Curves.easeOut),

            const SizedBox(height: 12),

            // Tagline
            Text(
              'Tax intelligence. Private by default.',
              style: AppTextStyles.caption(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ).animate(delay: 900.ms).fadeIn(duration: 600.ms),
            const SizedBox(height: 18),
            const TrustBadge(
              icon: Icons.shield_outlined,
              label: 'No PAN required to begin',
            ).animate(delay: 1050.ms).fadeIn(duration: 260.ms),
          ],
        ),
      ),
    );
  }
}

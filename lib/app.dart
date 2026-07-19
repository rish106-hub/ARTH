import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'theme/app_theme.dart';
import 'screens/s00_auth_screen.dart';
import 'screens/s01_splash_screen.dart';
import 'screens/s02_welcome_screen.dart';
import 'screens/s03_questions_screen.dart';
import 'screens/s04_gap_reveal_screen.dart';
import 'screens/s05_regime_comparison_screen.dart';
import 'screens/s06_deduction_cards_screen.dart';
import 'screens/s07_deduction_detail_screen.dart';
import 'screens/s08_action_plan_screen.dart';
import 'screens/s09_progress_tracker_screen.dart';
import 'screens/s10_share_card_screen.dart';
import 'screens/s12_budget_alert_screen.dart';
import 'screens/s13_discover_screen.dart';
import 'screens/s14_profile_screen.dart';
import 'screens/s15_document_checklist_screen.dart';
import 'screens/s16_ais_guide_screen.dart';
import 'screens/s17_help_center_screen.dart';
import 'screens/s18_tax_dossier_screen.dart';
import 'screens/s19_filing_assistant_screen.dart';
import 'screens/s20_accuracy_coach_screen.dart';
import 'screens/s21_tax_simulator_screen.dart';
import 'screens/s22_tax_story_screen.dart';
import 'screens/s23_tax_calendar_screen.dart';
import 'models/gap_card.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/auth', builder: (_, __) => const AuthScreen()),
    GoRoute(path: '/discover', builder: (_, __) => const DiscoverScreen()),
    GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
    GoRoute(path: '/questions', builder: (_, __) => const QuestionsScreen()),
    GoRoute(path: '/gap-reveal', builder: (_, __) => const GapRevealScreen()),
    GoRoute(
      path: '/regime-comparison',
      builder: (_, __) => const RegimeComparisonScreen(),
    ),
    GoRoute(
      path: '/deduction-cards',
      builder: (_, __) => const DeductionCardsScreen(),
    ),
    GoRoute(
      path: '/deduction-detail',
      builder: (context, state) {
        final extra = state.extra;
        if (extra is GapCard) {
          return DeductionDetailScreen(gap: extra);
        }
        return const DeductionCardsScreen();
      },
    ),
    GoRoute(path: '/action-plan', builder: (_, __) => const ActionPlanScreen()),
    GoRoute(path: '/coach', builder: (_, __) => const ActionPlanScreen()),
    GoRoute(
      path: '/progress',
      builder: (_, __) => const ProgressTrackerScreen(),
    ),
    GoRoute(path: '/share', builder: (_, __) => const ShareCardScreen()),
    GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
    GoRoute(path: '/settings', builder: (_, __) => const ProfileScreen()),
    GoRoute(
        path: '/documents',
        builder: (_, __) => const DocumentChecklistScreen()),
    GoRoute(
        path: '/vault', builder: (_, __) => const DocumentChecklistScreen()),
    GoRoute(path: '/ais-guide', builder: (_, __) => const AisGuideScreen()),
    GoRoute(path: '/help', builder: (_, __) => const HelpCenterScreen()),
    GoRoute(path: '/tax-dossier', builder: (_, __) => const TaxDossierScreen()),
    GoRoute(
      path: '/accuracy-coach',
      builder: (_, __) => const AccuracyCoachScreen(),
    ),
    GoRoute(
      path: '/tax-simulator',
      builder: (_, __) => const TaxSimulatorScreen(),
    ),
    GoRoute(path: '/tax-story', builder: (_, __) => const TaxStoryScreen()),
    GoRoute(
      path: '/tax-calendar',
      builder: (_, __) => const TaxCalendarScreen(),
    ),
    GoRoute(
      path: '/filing-assistant',
      builder: (_, __) => const FilingAssistantScreen(),
    ),
    GoRoute(
      path: '/budget-alert',
      builder: (_, __) => const BudgetAlertScreen(),
    ),
  ],
);

class ArthApp extends ConsumerWidget {
  const ArthApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'ARTH — Tax Readiness Cockpit',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: _router,
    );
  }
}

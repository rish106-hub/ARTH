import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'theme/app_theme.dart';
import 'screens/s00_auth_screen.dart';
import 'screens/s01_splash_screen.dart';
import 'screens/s03_questions_screen.dart';
import 'screens/s04_gap_reveal_screen.dart';
import 'screens/s05_regime_comparison_screen.dart';
import 'screens/s06_deduction_cards_screen.dart';
import 'screens/s07_deduction_detail_screen.dart';
import 'screens/s08_action_plan_screen.dart';
import 'screens/s09_progress_tracker_screen.dart';
import 'screens/s10_share_card_screen.dart';
import 'screens/s12_budget_alert_screen.dart';
import 'screens/s15_document_checklist_screen.dart';
import 'screens/s16_ais_guide_screen.dart';
import 'screens/s17_help_center_screen.dart';
import 'screens/s18_tax_dossier_screen.dart';
import 'screens/s19_filing_assistant_screen.dart';
import 'screens/s20_accuracy_coach_screen.dart';
import 'screens/s21_tax_simulator_screen.dart';
import 'screens/s22_tax_story_screen.dart';
import 'screens/s23_tax_calendar_screen.dart';
import 'screens/s28_paycheck_setup_screen.dart';
import 'screens/s29_paycheck_shell_screen.dart';
import 'screens/s30_tax_plan_entry_screen.dart';
import 'screens/s31_profile_screens.dart';
import 'models/gap_card.dart';

String _initialLocation() {
  final platformRoute =
      WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  return platformRoute.startsWith('/') ? platformRoute : '/';
}

final _router = GoRouter(
  initialLocation: _initialLocation(),
  routes: [
    GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/auth', builder: (_, __) => const AuthScreen()),
    GoRoute(
      path: '/paycheck-setup',
      builder: (_, __) => const PaycheckSetupScreen(),
    ),
    GoRoute(
      path: '/paycheck',
      builder: (_, __) => const PaycheckShellScreen(),
    ),
    GoRoute(
      path: '/paycheck/promise',
      builder: (_, __) => const PaycheckShellScreen(initialIndex: 1),
    ),
    GoRoute(
      path: '/paycheck/inbox',
      builder: (_, __) => const PaycheckShellScreen(initialIndex: 2),
    ),
    GoRoute(
      path: '/paycheck/you',
      builder: (_, __) => const PaycheckShellScreen(initialIndex: 3),
    ),
    GoRoute(
      path: '/tax-plan',
      builder: (_, __) => const TaxPlanEntryScreen(),
    ),
    GoRoute(
      path: '/tax-plan/questions',
      builder: (_, __) => const QuestionsScreen(paycheckMode: true),
    ),
    GoRoute(
      path: '/tax-plan/results',
      builder: (_, __) => const GapRevealScreen(paycheckMode: true),
    ),
    GoRoute(
      path: '/tax-plan/simulator',
      builder: (_, __) => const TaxSimulatorScreen(paycheckMode: true),
    ),
    GoRoute(path: '/discover', redirect: (_, __) => '/paycheck'),
    GoRoute(path: '/today', redirect: (_, __) => '/paycheck'),
    GoRoute(path: '/welcome', redirect: (_, __) => '/paycheck-setup'),
    GoRoute(path: '/questions', redirect: (_, __) => '/tax-plan/questions'),
    GoRoute(path: '/gap-reveal', redirect: (_, __) => '/tax-plan/results'),
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
    GoRoute(path: '/coach', redirect: (_, __) => '/action-plan'),
    GoRoute(
      path: '/progress',
      builder: (_, __) => const ProgressTrackerScreen(),
    ),
    GoRoute(path: '/share', builder: (_, __) => const ShareCardScreen()),
    GoRoute(path: '/profile', redirect: (_, __) => '/paycheck/you'),
    GoRoute(
      path: '/profile/details',
      builder: (_, __) => const ProfileDetailsScreen(),
    ),
    GoRoute(
      path: '/profile/connections',
      builder: (_, __) => const ProfileConnectionsScreen(),
    ),
    GoRoute(
      path: '/profile/tax-identity',
      builder: (_, __) => const TaxIdentityScreen(),
    ),
    GoRoute(
      path: '/profile/privacy',
      builder: (_, __) => const ProfilePrivacyScreen(),
    ),
    GoRoute(path: '/you', redirect: (_, __) => '/paycheck/you'),
    GoRoute(path: '/settings', redirect: (_, __) => '/paycheck/you'),
    GoRoute(
        path: '/documents',
        builder: (_, __) => const DocumentChecklistScreen()),
    GoRoute(path: '/vault', redirect: (_, __) => '/documents'),
    GoRoute(path: '/ais-guide', builder: (_, __) => const AisGuideScreen()),
    GoRoute(path: '/help', builder: (_, __) => const HelpCenterScreen()),
    GoRoute(path: '/tax-dossier', builder: (_, __) => const TaxDossierScreen()),
    GoRoute(
      path: '/accuracy-coach',
      builder: (_, __) => const AccuracyCoachScreen(),
    ),
    GoRoute(path: '/tax-simulator', redirect: (_, __) => '/tax-plan/simulator'),
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
    GoRoute(path: '/control-room-demo', redirect: (_, __) => '/paycheck'),
  ],
);

class ArthApp extends ConsumerWidget {
  const ArthApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'ARTH - Know your paycheck',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: _router,
    );
  }
}

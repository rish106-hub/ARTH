import 'package:arth/screens/s00_auth_screen.dart';
import 'package:arth/screens/s00_product_onboarding_screen.dart';
import 'package:arth/screens/s03_questions_screen.dart';
import 'package:arth/screens/s29_paycheck_shell_screen.dart';
import 'package:arth/screens/s30_tax_plan_entry_screen.dart';
import 'package:arth/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('ARTH emulator UI smoke', () {
    testWidgets('onboarding, explore mode, and primary navigation work',
        (tester) async {
      final router = _router('/onboarding');
      addTearDown(router.dispose);
      await _pump(tester, router);

      expect(
          find.text('Know what your offer letter is worth.'), findsOneWidget);
      expect(find.byKey(const Key('explore_app_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('explore_app_button')));
      await _waitForTransition(tester);
      expect(find.text('You are exploring sample data'), findsOneWidget);
      expect(find.text('READY TO CLAIM'), findsOneWidget);

      await tester.tap(find.text('Promise').last);
      await _waitForTransition(tester);
      expect(find.text('What your employer\npromised.'), findsOneWidget);

      await tester.tap(find.text('Inbox').last);
      await _waitForTransition(tester);
      expect(find.text('Your pay evidence.'), findsOneWidget);

      await tester.tap(find.text('You').last);
      await _waitForTransition(tester);
      expect(find.text('Make this workspace yours.'), findsOneWidget);

      await tester.tap(find.text('Sign up'));
      await _waitForTransition(tester);
      expect(find.text('Give your income a job.'), findsOneWidget);
    });

    testWidgets('auth mode switch validates fields without a network request',
        (tester) async {
      final router = _router('/auth');
      addTearDown(router.dispose);
      await _pump(tester, router);

      expect(find.text('Sign up'), findsWidgets);
      expect(find.text('Continue with Google'), findsOneWidget);
      await tester.tap(find.text('Sign in').first);
      await _waitForTransition(tester);
      expect(find.text('Welcome back.'), findsOneWidget);

      await tester.tap(find.text('Sign in').last);
      await _waitForTransition(tester);
      expect(find.text('Enter a valid email'), findsOneWidget);
      expect(
          find.text('Password must be at least 8 characters'), findsOneWidget);
    });

    testWidgets('tax diagnostic keeps the selected city visible before next',
        (tester) async {
      final router = _router('/tax-plan/questions');
      addTearDown(router.dispose);
      await _pump(tester, router);

      expect(find.text('What is your annual CTC?'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await _waitForTransition(tester);
      expect(find.text('Are you salaried or self-employed?'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await _waitForTransition(tester);
      expect(find.text('Which city do you live in?'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Durgapur'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Durgapur'));
      await _waitForTransition(tester);
      expect(find.text('Durgapur'), findsWidgets);
      expect(find.text('Continue'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await _waitForTransition(tester);
      expect(find.textContaining('Do you pay rent'), findsOneWidget);
    });

    testWidgets('tax tool opens and returns to the paycheck profile',
        (tester) async {
      final router = _router('/tax-plan');
      addTearDown(router.dispose);
      await _pump(tester, router);

      expect(find.text('Plan your tax.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tax_plan_close')));
      await _waitForTransition(tester);
      expect(find.text('Your information'), findsOneWidget);
    });
  });
}

GoRouter _router(String initialLocation) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
            path: '/onboarding',
            builder: (_, __) => const ProductOnboardingScreen()),
        GoRoute(
            path: '/explore',
            builder: (_, __) => const PaycheckShellScreen(exploreMode: true)),
        GoRoute(
            path: '/auth',
            builder: (_, state) => AuthScreen(
                initialSignUp: state.uri.queryParameters['mode'] != 'sign-in')),
        GoRoute(
            path: '/tax-plan', builder: (_, __) => const TaxPlanEntryScreen()),
        GoRoute(
            path: '/tax-plan/questions',
            builder: (_, __) => const QuestionsScreen(paycheckMode: true)),
        GoRoute(
            path: '/paycheck/you',
            builder: (_, __) => const PaycheckShellScreen(initialIndex: 3)),
      ],
    );

Future<void> _pump(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await _waitForTransition(tester);
}

Future<void> _waitForTransition(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 700));
}

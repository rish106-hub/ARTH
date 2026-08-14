import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against a route that builds a screen nothing navigates to.
///
/// Three screens shipped unreachable before this test existed: the Workday Cost
/// Lens had no route at all, and Month on month had a route no widget pushed.
/// Both were found only by hand-auditing `app.dart` against the running app. A
/// screen no user can open is dead product, so fail the build instead.
///
/// Redirect-only routes are skipped by design — they exist to catch links the
/// app itself no longer emits, so being unreferenced is the whole point.
void main() {
  /// Chosen by the router or the platform rather than by a tap.
  const entryPoints = <String>{'/', '/onboarding', '/auth', '/paycheck'};

  /// Screens that are built and routed but have no entry point yet.
  ///
  /// This is a baseline of pre-existing debt, not permission to add more: the
  /// test fails if a new orphan appears, and also fails if one of these becomes
  /// reachable and is not removed from the list. Wiring them up is a product
  /// decision — each needs a home in Home, Money or Plan, or deleting.
  const knownOrphans = <String>{
    // Reachable only as `/tax-simulator`; the paycheck-mode variant has no caller.
    '/tax-plan/simulator',
    '/deduction-cards',
    '/tax-calendar',
    // Gated by the `budget_alert_enabled` Remote Config flag, which currently
    // turns on a screen with no way in.
    '/budget-alert',
  };

  late Set<String> orphans;

  setUpAll(() {
    final app = File('lib/app.dart').readAsStringSync();

    // Each chunk after the split holds one route's arguments, so a `redirect:`
    // found here belongs to the path found here.
    final declared = <String>{};
    for (final chunk in app.split('GoRoute(').skip(1)) {
      final path = RegExp(r"path: '([^']+)'").firstMatch(chunk)?.group(1);
      if (path == null) continue;
      if (chunk.contains('redirect:')) continue;
      declared.add(path);
    }
    declared.removeAll(entryPoints);

    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('app.dart'))
        .map((f) => f.readAsStringSync())
        .toList(growable: false);

    orphans = {
      for (final path in declared)
        // Strip `:id`-style segments: callers build those by interpolation, so
        // only the literal prefix ever appears in source.
        if (!sources.any((s) => s.contains("'${path.split('/:').first}"))) path,
    };
  });

  test('no new unreachable route', () {
    expect(
      orphans.difference(knownOrphans),
      isEmpty,
      reason: 'These routes build a screen that nothing in lib/ navigates to, '
          'so no user can reach it. Add an entry point, or delete the route.',
    );
  });

  test('knownOrphans lists only routes that are still unreachable', () {
    expect(
      knownOrphans.difference(orphans),
      isEmpty,
      reason: 'These routes now have an entry point. Remove them from '
          'knownOrphans so the baseline keeps shrinking.',
    );
  });
}

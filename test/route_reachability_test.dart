import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against a route that builds a screen nothing navigates to.
///
/// Three screens shipped unreachable before this test existed: the Workday Cost
/// Lens had no route at all, and Month on month had a route no widget pushed.
/// Both were found only by hand-auditing `app.dart` against the running app. A
/// screen no user can open is dead product, so fail the build instead.
///
/// A redirect is a real door: `/tax-simulator` redirects to
/// `/tax-plan/simulator`, so a widget pushing the old path reaches the new
/// screen. Redirects are therefore followed, not skipped — an unreferenced
/// redirect simply passes nothing on.
void main() {
  /// Chosen by the router or the platform rather than by a tap.
  const entryPoints = <String>{'/', '/onboarding', '/auth', '/paycheck'};

  late Set<String> orphans;

  setUpAll(() {
    final app = File('lib/app.dart').readAsStringSync();

    // Each chunk after the split holds one route's arguments, so a `path:` and
    // a `redirect:` found in the same chunk belong to the same route.
    final declared = <String>{};
    final redirects = <String, String>{};
    for (final chunk in app.split('GoRoute(').skip(1)) {
      final path = RegExp(r"path: '([^']+)'").firstMatch(chunk)?.group(1);
      if (path == null) continue;
      if (!chunk.contains('redirect:')) {
        declared.add(path);
        continue;
      }
      final target =
          RegExp(r"redirect:[^\n]*?'(/[^']*)'").firstMatch(chunk)?.group(1);
      // A redirect whose target is computed rather than literal passes its
      // reachability nowhere, which is the safe reading: it cannot be the only
      // door to a screen this test is asked to trust.
      if (target != null) redirects[path] = target;
    }
    declared.removeAll(entryPoints);

    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('app.dart'))
        .map((f) => f.readAsStringSync())
        .toList(growable: false);

    // Strip `:id`-style segments: callers build those by interpolation, so
    // only the literal prefix ever appears in source.
    bool isPushed(String path) =>
        sources.any((s) => s.contains("'${path.split('/:').first}"));

    final reached = {
      for (final path in declared)
        if (isPushed(path)) path,
    };

    // A redirect passes its own reachability on to its target, and one redirect
    // can point at another, so keep resolving until nothing new is reached.
    for (var changed = true; changed;) {
      changed = false;
      for (final entry in redirects.entries) {
        final reachable = isPushed(entry.key) || reached.contains(entry.key);
        if (reachable && reached.add(entry.value)) changed = true;
      }
    }

    orphans = declared.difference(reached);
  });

  test('no unreachable route', () {
    expect(
      orphans,
      isEmpty,
      reason: 'These routes build a screen that nothing in lib/ navigates to, '
          'so no user can reach it. Add an entry point, or delete the route.',
    );
  });
}

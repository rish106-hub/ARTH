// Renders widgets to PNG so a change can be looked at, not just reasoned about.
//
// Not part of the suite's assertions — it writes files and passes. Run it with
//   flutter test test/render_preview.dart
// and open the PNGs it drops in build/previews/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:arth/providers/spend_map_provider.dart';
import 'package:arth/screens/s33_spend_insights_screen.dart';
import 'package:arth/theme/app_theme.dart';
import 'package:arth/theme/paycheck_theme.dart';
import 'package:arth/widgets/premium_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadAnek() async {
  final loader = FontLoader('Anek');
  loader.addFont(
    File('assets/fonts/AnekLatin[wdth,wght].ttf')
        .readAsBytes()
        .then((b) => ByteData.sublistView(b)),
  );
  await loader.load();
}

Future<void> _shoot(WidgetTester tester, String name) async {
  final element = find.byType(MaterialApp).evaluate().single;
  final boundary = element.renderObject!;
  RenderRepaintBoundary? target;
  void walk(RenderObject node) {
    if (target != null) return;
    if (node is RenderRepaintBoundary) {
      target = node;
      return;
    }
    node.visitChildren(walk);
  }

  walk(boundary);
  // toImage has to run outside the fake async zone, or the test binding never
  // finishes even though the file lands on disk.
  await tester.runAsync(() async {
    final image = await target!.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = Directory('build/previews')..createSync(recursive: true);
    File('${out.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Widget _frame(Widget child, {double width = 390, double height = 450}) {
  return RepaintBoundary(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, height)),
        child: Scaffold(
          backgroundColor: PaycheckColors.canvas,
          body: SafeArea(child: child),
        ),
      ),
    ),
  );
}

/// Pins the spend map to a fixed state so a screen state can be rendered
/// without an inbox, a network, or a device.
class _FixedSpendMap extends SpendMapNotifier {
  _FixedSpendMap(this._fixed);

  final SpendMapState _fixed;

  @override
  SpendMapState build() => _fixed;
}

Widget _screen(SpendMapState state, {double height = 780}) {
  return ProviderScope(
    overrides: [
      spendMapProvider.overrideWith(() => _FixedSpendMap(state)),
    ],
    child: RepaintBoundary(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(size: Size(390, height)),
          child: const SpendInsightsScreen(),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(_loadAnek);

  testWidgets('spend map, empty state', (tester) async {
    tester.view.physicalSize = const Size(780, 1560);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_screen(const SpendMapState()));
    await tester.pumpAndSettle();
    await _shoot(tester, '04_spend_empty');
  });

  testWidgets('spend map, permission denied', (tester) async {
    tester.view.physicalSize = const Size(780, 1560);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _screen(const SpendMapState(permissionDenied: true)),
    );
    await tester.pumpAndSettle();
    await _shoot(tester, '05_spend_permission');
  });

  Future<void> spendCard(
    WidgetTester tester,
    String name, {
    required bool openDetail,
  }) async {
    tester.view.physicalSize = const Size(780, 900);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_frame(
      Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Spend map', style: PaycheckType.h1()),
            const SizedBox(height: 8),
            const ArthDisclosure(
              label: 'Transaction SMS only, parsed on this device',
              icon: Icons.lock_outline,
              detail: 'ARTH reads only bank and UPI transaction SMS. Personal '
                  'messages are ignored, and parsing stays on-device.',
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: PaycheckColors.paper,
                borderRadius: AppRadius.card,
                border: Border.all(color: PaycheckColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TOTAL SPENT', style: PaycheckType.utility()),
                  const SizedBox(height: 4),
                  Text('₹48,320', style: PaycheckType.display()),
                  const SizedBox(height: 4),
                  Text(
                    'Across 3 months with spend.',
                    style: PaycheckType.body(color: PaycheckColors.inkSoft),
                  ),
                  const ArthDisclosure(
                    label: 'Why this is approximate',
                    detail:
                        'Income is a payslip estimate while spend comes from '
                        'SMS, so this balance mixes two sources.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    if (openDetail) {
      await tester.tap(find.text('Why this is approximate'));
      await tester.pumpAndSettle();
    }
    await _shoot(tester, name);
  }

  testWidgets('spend card, disclosure collapsed', (tester) async {
    await spendCard(tester, '01_disclosure_collapsed', openDetail: false);
  });

  testWidgets('spend card, disclosure open', (tester) async {
    await spendCard(tester, '02_disclosure_open', openDetail: true);
  });

  testWidgets('state panel with detail', (tester) async {
    tester.view.physicalSize = const Size(780, 900);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_frame(
      ArthStatePanel(
        icon: Icons.inventory_2_outlined,
        title: 'Prepare your filing pack',
        message: 'Complete the diagnostic first.',
        detail: 'ARTH then maps your result, proofs and assumptions into a '
            'filing handoff checklist.',
        actionLabel: 'Start diagnostic',
        onAction: () {},
      ),
      height: 450,
    ));
    await tester.pumpAndSettle();
    await _shoot(tester, '03_state_panel');
  });
}

// Previews of the shared empty/error/locked states, so "one state system" can
// be checked by looking rather than by reading three widget files.
//
// Not part of the suite's assertions — it writes files and passes. Run with
//   flutter test test/render_preview_states.dart
// and open the PNGs in build/previews/.
//
// Kept separate from render_preview.dart so the two can be edited in parallel.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:arth/theme/app_theme.dart';
import 'package:arth/theme/paycheck_theme.dart';
import 'package:arth/widgets/premium_ui.dart';
import 'package:arth/widgets/retry_error_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
  RenderRepaintBoundary? target;
  void walk(RenderObject node) {
    if (target != null) return;
    if (node is RenderRepaintBoundary) {
      target = node;
      return;
    }
    node.visitChildren(walk);
  }

  walk(element.renderObject!);
  // toImage has to run outside the fake async zone, or the binding never
  // finishes even though the file lands on disk.
  await tester.runAsync(() async {
    final image = await target!.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = Directory('build/previews')..createSync(recursive: true);
    File('${out.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Widget _frame(Widget child, {double height = 460}) {
  return RepaintBoundary(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(size: Size(390, height)),
        child: Scaffold(
          backgroundColor: PaycheckColors.canvas,
          body: SafeArea(child: child),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(_loadAnek);

  Future<void> pumpAndShoot(
    WidgetTester tester,
    Widget child,
    String name,
  ) async {
    tester.view.physicalSize = const Size(780, 920);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_frame(child));
    await tester.pumpAndSettle();
    await _shoot(tester, name);
  }

  testWidgets('error state', (tester) async {
    await pumpAndShoot(
      tester,
      RetryErrorState(
        message: 'Could not load your Tax Dossier',
        onRetry: () {},
      ),
      '10_state_error',
    );
  });

  testWidgets('empty state', (tester) async {
    await pumpAndShoot(
      tester,
      ArthStatePanel(
        icon: Icons.checklist_rounded,
        title: 'Actions start with your diagnostic',
        message: 'Complete it to unlock your deduction tasks.',
        actionLabel: 'Start diagnostic',
        onAction: () {},
      ),
      '11_state_empty',
    );
  });

  testWidgets('inline empties, in flow', (tester) async {
    await pumpAndShoot(
      tester,
      Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DOCUMENTS', style: PaycheckType.utility()),
            const SizedBox(height: 8),
            const ArthInlineEmpty(
              icon: Icons.folder_open_outlined,
              title: 'No uploads yet',
              message: 'Use the upload icon beside any document to begin.',
            ),
            const SizedBox(height: 12),
            ArthInlineEmpty(
              icon: Icons.add_to_drive_outlined,
              title: 'No evidence yet',
              message: 'Add an offer letter, payslip, bill or receipt first.',
              actionLabel: 'Add',
              onAction: () {},
            ),
            const SizedBox(height: 12),
            const ArthInlineEmpty(
              icon: Icons.inbox_outlined,
              title: 'No confirmed monthly snapshot yet.',
            ),
          ],
        ),
      ),
      '13_inline_empty',
    );
  });

  testWidgets('locked state', (tester) async {
    await pumpAndShoot(
      tester,
      ArthStatePanel(
        icon: Icons.lock_clock_outlined,
        title: 'Your Tax Story is locked',
        message: 'Finish the diagnostic to unlock it.',
        actionLabel: 'Start diagnostic',
        onAction: () {},
      ),
      '12_state_locked',
    );
  });
}

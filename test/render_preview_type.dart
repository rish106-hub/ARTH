// Type specimen. Throwaway preview used to judge the scale by looking.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:arth/theme/app_theme.dart';
import 'package:arth/theme/paycheck_theme.dart';
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
  await tester.runAsync(() async {
    final image = await target!.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = Directory('build/previews')..createSync(recursive: true);
    File('${out.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_loadAnek);

  testWidgets('type specimen', (tester) async {
    tester.view.physicalSize = const Size(880, 1700);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final rows = <(String, TextStyle)>[
      ('display 38', PaycheckType.display()),
      ('displaySmall 32', PaycheckType.displaySmall()),
      ('h1 28', PaycheckType.h1()),
      ('title 24', PaycheckType.title()),
      ('h2 22', PaycheckType.h2()),
      ('heading 17', PaycheckType.heading()),
      ('body 15', PaycheckType.body()),
      ('bodyMedium 15', PaycheckType.bodyMedium()),
      ('bodyStrong 15', PaycheckType.bodyStrong()),
      ('caption 13', PaycheckType.caption()),
      ('micro 12', PaycheckType.micro()),
      ('utility 12', PaycheckType.utility()),
      ('sectionLabel 12', PaycheckType.sectionLabel()),
    ];

    await tester.pumpWidget(
      RepaintBoundary(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: Scaffold(
            backgroundColor: PaycheckColors.canvas,
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (label, style) in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          SizedBox(
                            width: 132,
                            child: Text(
                              label,
                              style: PaycheckType.micro(
                                color: PaycheckColors.inkMuted,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text('Spend map ₹48,320', style: style),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _shoot(tester, '20_type_specimen');
  });
}

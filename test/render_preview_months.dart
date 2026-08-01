// Preview of the month-on-month screen. Writes PNGs, asserts nothing.
//   flutter test test/render_preview_months.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:arth/features/month_on_month/screens/month_on_month_screen.dart';
import 'package:arth/models/spend_map.dart';
import 'package:arth/providers/spend_map_provider.dart';
import 'package:arth/theme/app_theme.dart';
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

class _FixedSpendMap extends SpendMapNotifier {
  _FixedSpendMap(this._fixed);
  final SpendMapState _fixed;

  @override
  SpendMapState build() => _fixed;
}

FinanceTxn _txn(int amount, DateTime date, String category,
        {bool salary = false}) =>
    FinanceTxn(
      amount: amount,
      direction: salary ? TxnDirection.credit : TxnDirection.debit,
      date: date,
      category: category,
      isSalary: salary,
    );

void main() {
  setUpAll(_loadAnek);

  testWidgets('month on month', (tester) async {
    tester.view.physicalSize = const Size(780, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final map = SpendMap(
      txns: [
        _txn(54500, DateTime(2026, 6, 1), SpendCategory.other, salary: true),
        _txn(54500, DateTime(2026, 7, 1), SpendCategory.other, salary: true),
        _txn(9000, DateTime(2026, 6, 3), SpendCategory.rent),
        _txn(9000, DateTime(2026, 7, 3), SpendCategory.rent),
        _txn(4200, DateTime(2026, 6, 8), SpendCategory.food),
        _txn(7100, DateTime(2026, 7, 8), SpendCategory.food),
        _txn(3000, DateTime(2026, 6, 12), SpendCategory.shopping),
        _txn(900, DateTime(2026, 7, 12), SpendCategory.shopping),
      ],
      windowStart: DateTime(2026, 6),
      windowEnd: DateTime(2026, 7, 31),
      generatedAt: DateTime(2026, 7, 31),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          spendMapProvider.overrideWith(
            () => _FixedSpendMap(SpendMapState(map: map)),
          ),
        ],
        child: RepaintBoundary(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const MonthOnMonthScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _shoot(tester, '30_month_on_month');
  });
}

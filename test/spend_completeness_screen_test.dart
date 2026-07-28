import 'package:arth/features/spend_completeness/models/spend_completeness_models.dart';
import 'package:arth/features/spend_completeness/providers/spend_completeness_provider.dart';
import 'package:arth/features/spend_completeness/screens/spend_completeness_screen.dart';
import 'package:arth/models/spend_map.dart';
import 'package:arth/providers/spend_map_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('spend coverage works on a small Android screen', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final map = SpendMap(
      txns: [
        FinanceTxn(
          amount: 50000,
          direction: TxnDirection.credit,
          date: DateTime(2026, 6, 1),
          category: SpendCategory.other,
          isSalary: true,
          sender: 'VM-HDFC',
        ),
        for (var month = 5; month <= 7; month++)
          FinanceTxn(
            amount: 20000,
            direction: TxnDirection.debit,
            date: DateTime(2026, month, 2),
            category: SpendCategory.rent,
            isSalary: false,
            merchant: 'Landlord',
            sender: 'VM-HDFC',
          ),
      ],
      windowStart: DateTime(2026, 5, 1),
      windowEnd: DateTime(2026, 7, 28),
      generatedAt: DateTime(2026, 7, 28),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          spendMapProvider.overrideWith(
            () => _StubSpendMapNotifier(map),
          ),
          spendCompletenessProvider.overrideWith(
            _StubCompletenessNotifier.new,
          ),
        ],
        child: const MaterialApp(home: SpendCompletenessScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Spend coverage'), findsOneWidget);
    expect(find.text('COVERAGE RECEIPT'), findsOneWidget);
    expect(find.text('Pick the salary account'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Likely recurring spend'), 250);
    expect(find.text('Likely recurring spend'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Shared household'), 250);
    expect(find.text('Shared household'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Category budgets'), 250);
    expect(find.text('Category budgets'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _StubSpendMapNotifier extends SpendMapNotifier {
  _StubSpendMapNotifier(this.map);

  final SpendMap map;

  @override
  SpendMapState build() => SpendMapState(map: map);
}

class _StubCompletenessNotifier extends SpendCompletenessNotifier {
  @override
  SpendCompletenessState build() => const SpendCompletenessState();
}

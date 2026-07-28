import 'package:arth/features/spend_completeness/engine/spend_completeness_engine.dart';
import 'package:arth/features/spend_completeness/models/spend_completeness_models.dart';
import 'package:arth/models/spend_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FinanceTxn txn({
    required int amount,
    required DateTime date,
    required String category,
    TxnDirection direction = TxnDirection.debit,
    bool isSalary = false,
    String sender = 'VM-BANK',
    String? merchant,
    String? body,
  }) =>
      FinanceTxn(
        amount: amount,
        direction: direction,
        date: date,
        category: category,
        isSalary: isSalary,
        sender: sender,
        merchant: merchant,
        bodyPreview: body,
      );

  SpendMap map(List<FinanceTxn> txns) => SpendMap(
        txns: txns,
        windowStart: DateTime(2026, 5, 1),
        windowEnd: DateTime(2026, 7, 28),
        generatedAt: DateTime(2026, 7, 28),
      );

  test('trusted salary source excludes other detected salary streams', () {
    final spendMap = map([
      txn(
        amount: 50000,
        date: DateTime(2026, 6, 1),
        category: SpendCategory.other,
        direction: TxnDirection.credit,
        isSalary: true,
        sender: 'VM-HDFC',
      ),
      txn(
        amount: 80000,
        date: DateTime(2026, 6, 2),
        category: SpendCategory.other,
        direction: TxnDirection.credit,
        isSalary: true,
        sender: 'VM-ICICI',
      ),
    ]);

    expect(spendMap.salaryCredited, 130000);
    final trusted = spendMap.withTrustedSalarySource('VM-HDFC');
    expect(trusted.salaryCredited, 50000);
    expect(trusted.observedPrimaryMonthlyIncome, 50000);
    expect(trusted.trustedSalaryTransactions.single.sender, 'VM-HDFC');
  });

  test('detects monthly rent, SIP, and subscription patterns', () {
    final spendMap = map([
      for (var month = 5; month <= 7; month++)
        txn(
          amount: 20000 + (month == 6 ? 200 : 0),
          date: DateTime(2026, month, 2),
          category: SpendCategory.rent,
          merchant: 'Landlord',
        ),
      for (var month = 5; month <= 7; month++)
        txn(
          amount: 5000,
          date: DateTime(2026, month, 5),
          category: SpendCategory.investment,
          merchant: 'Index Fund',
        ),
      txn(
        amount: 649,
        date: DateTime(2026, 6, 10),
        category: SpendCategory.entertainment,
        merchant: 'Netflix',
        body: 'Netflix subscription renewal',
      ),
      txn(
        amount: 649,
        date: DateTime(2026, 7, 10),
        category: SpendCategory.entertainment,
        merchant: 'Netflix',
        body: 'Netflix subscription renewal',
      ),
      txn(
        amount: 3000,
        date: DateTime(2026, 7, 18),
        category: SpendCategory.shopping,
        merchant: 'One-off store',
      ),
    ]);

    final recurring = SpendCompletenessEngine.recurringSpend(spendMap);
    expect(
      recurring.map((item) => item.kind),
      containsAll([
        RecurringKind.rent,
        RecurringKind.sip,
        RecurringKind.subscription,
      ]),
    );
    expect(
      recurring.where((item) => item.label == 'One-off store'),
      isEmpty,
    );
    expect(
      recurring
          .firstWhere((item) => item.kind == RecurringKind.rent)
          .highConfidence,
      isTrue,
    );
  });

  test('budget suggestions use all observed spend months', () {
    final spendMap = map([
      txn(
        amount: 1000,
        date: DateTime(2026, 5, 2),
        category: SpendCategory.food,
      ),
      txn(
        amount: 2000,
        date: DateTime(2026, 6, 2),
        category: SpendCategory.food,
      ),
      txn(
        amount: 3000,
        date: DateTime(2026, 7, 2),
        category: SpendCategory.food,
      ),
      txn(
        amount: 900,
        date: DateTime(2026, 7, 3),
        category: SpendCategory.transport,
      ),
    ]);

    final food = SpendCompletenessEngine.budgetSuggestions(spendMap)
        .firstWhere((item) => item.category == SpendCategory.food);
    expect(food.historicalMonthlyAverage, 2000);
    expect(food.suggestedLimit, 2000);
    expect(food.currentMonthSpend, 3000);
    expect(food.projectedMonthSpend, 3321);
  });

  test('local settings round-trip every user choice', () {
    const original = SpendCompletenessState(
      trustedSalarySourceId: 'VM-HDFC',
      missingSources: {
        MissingSpendSource.cash,
        MissingSpendSource.cardWithoutSms,
      },
      confirmedRecurringIds: {'rent-landlord-200'},
      dismissedRecurringIds: {'repeat-store-30'},
      household: HouseholdPlan(
        enabled: true,
        memberName: 'A',
        otherMonthlyIncome: 40000,
        sharedEssentials: 30000,
        yourSharePercent: 60,
      ),
      categoryBudgets: {SpendCategory.food: 5000},
    );

    final restored =
        SpendCompletenessState.fromJsonString(original.toJsonString());
    expect(restored.trustedSalarySourceId, 'VM-HDFC');
    expect(restored.missingSources, original.missingSources);
    expect(restored.household.yourSharedCost, 18000);
    expect(restored.categoryBudgets[SpendCategory.food], 5000);
  });
}

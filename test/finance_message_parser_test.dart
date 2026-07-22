import 'package:flutter_test/flutter_test.dart';

import 'package:arth/models/spend_map.dart';
import 'package:arth/services/finance_message_parser.dart';

void main() {
  const parser = FinanceMessageParser();
  final date = DateTime(2026, 7, 1);

  FinanceTxn? parse(String body) =>
      parser.parse(sender: 'BANK', body: body, date: date);

  group('salary credit', () {
    test('detects salary credit as income', () {
      final txn = parse(
        'Rs.54,500.00 credited to a/c XX1234 on 01-07-26 towards SALARY. Avbl bal Rs 61,200.',
      );
      expect(txn, isNotNull);
      expect(txn!.direction, TxnDirection.credit);
      expect(txn.isSalary, isTrue);
      expect(txn.amount, 54500);
    });

    test('ignores the available-balance amount', () {
      final txn = parse('INR 20000 credited by payroll. Avbl bal Rs 99999.');
      expect(txn!.amount, 20000);
    });
  });

  group('spend / debit', () {
    test('food merchant → food category', () {
      final txn = parse(
        'Rs 499 debited from a/c XX99 for UPI to SWIGGY on 02-07-26.',
      );
      expect(txn!.direction, TxnDirection.debit);
      expect(txn.category, SpendCategory.food);
      expect(txn.amount, 499);
      expect(txn.isSalary, isFalse);
    });

    test('card spend at Amazon → shopping', () {
      final txn = parse('Rs 1,299 spent on HDFC Card at AMAZON on 03-07.');
      expect(txn!.category, SpendCategory.shopping);
      expect(txn.amount, 1299);
    });

    test('uber → transport', () {
      final txn = parse('₹ 250 paid to UBER via UPI.');
      expect(txn!.category, SpendCategory.transport);
    });

    test('electricity recharge → bills', () {
      final txn = parse('Rs 1500 debited for BESCOM electricity bill.');
      expect(txn!.category, SpendCategory.bills);
    });

    test('unknown merchant → other', () {
      final txn = parse('Rs 300 debited at LOCAL STORE.');
      expect(txn!.category, SpendCategory.other);
    });
  });

  group('noise rejection', () {
    test('OTP is ignored', () {
      expect(
          parse('123456 is your OTP for Rs 5000 txn. Do not share.'), isNull);
    });

    test('future/reminder debit is ignored', () {
      expect(parse('Rs 999 will be debited on 05-07 for autopay.'), isNull);
    });

    test('no amount → null', () {
      expect(parse('Your account was credited today.'), isNull);
    });

    test('no direction → null', () {
      expect(parse('Your balance is Rs 5000.'), isNull);
    });
  });

  group('SpendMap aggregation', () {
    test('computes monthly spend, income and realistic savings', () {
      final txns = [
        parse('Rs 60000 credited towards SALARY.')!,
        parse('Rs 499 debited to SWIGGY.')!,
        parse('Rs 1299 spent at AMAZON.')!,
        parse('Rs 250 paid to UBER.')!,
      ];
      final map = SpendMap(
        txns: txns,
        windowStart: DateTime(2026, 7, 1),
        windowEnd: DateTime(2026, 7, 31),
        generatedAt: DateTime(2026, 7, 31),
      );
      expect(map.monthsSpan, 1);
      expect(map.salaryCredited, 60000);
      expect(map.totalSpent, 499 + 1299 + 250);
      expect(map.monthlyIncome, 60000);
      expect(map.monthlySpend, 2048);
      expect(map.realisticMonthlySavings, 60000 - 2048);
      expect(map.topCategories.first.key, SpendCategory.shopping);
    });

    test('round-trips through JSON', () {
      final map = SpendMap(
        txns: [parse('Rs 500 debited to SWIGGY.')!],
        windowStart: DateTime(2026, 7, 1),
        windowEnd: DateTime(2026, 7, 31),
        generatedAt: DateTime(2026, 7, 31),
      );
      final restored = SpendMap.fromJsonString(map.toJsonString());
      expect(restored.totalSpent, 500);
      expect(restored.txns.single.category, SpendCategory.food);
    });
  });
}

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

  group('recurring salary inference', () {
    ({int? id, String sender, String body, DateTime date}) msg(
      String body,
      DateTime when,
    ) =>
        (id: null, sender: 'BANK', body: body, date: when);

    test('tags a same-size NEFT credit recurring across months as salary', () {
      final txns = parser.parseAll([
        msg('Rs 85,000 credited to a/c XX12 by NEFT ref ACME-CORP.',
            DateTime(2026, 5, 1)),
        msg('Rs 85,000 credited to a/c XX12 by NEFT ref ACME-CORP.',
            DateTime(2026, 6, 1)),
        msg('Rs 85,000 credited to a/c XX12 by NEFT ref ACME-CORP.',
            DateTime(2026, 7, 1)),
        msg('Rs 499 debited to SWIGGY.', DateTime(2026, 7, 2)),
      ]);
      final credits = txns.where((t) => t.direction == TxnDirection.credit);
      expect(credits.every((t) => t.isSalary), isTrue);
      expect(credits.length, 3);
    });

    test('leaves a one-off large credit untagged', () {
      final txns = parser.parseAll([
        msg('Rs 90,000 credited to a/c XX12 by NEFT.', DateTime(2026, 6, 1)),
        msg('Rs 499 debited to SWIGGY.', DateTime(2026, 6, 2)),
      ]);
      expect(txns.any((t) => t.isSalary), isFalse);
    });

    test('ignores small recurring credits (refunds/cashback)', () {
      final txns = parser.parseAll([
        msg('Rs 200 credited as refund.', DateTime(2026, 6, 1)),
        msg('Rs 200 credited as refund.', DateTime(2026, 7, 1)),
      ]);
      expect(txns.any((t) => t.isSalary), isFalse);
    });

    test('keyword salary still wins without recurrence', () {
      final txns = parser.parseAll([
        msg('Rs 54,500 credited towards SALARY.', DateTime(2026, 7, 1)),
      ]);
      expect(txns.single.isSalary, isTrue);
    });

    test('caps at one credit per month so same-month payouts do not inflate',
        () {
      final txns = parser.parseAll([
        // Two same-size credits in June (e.g. split payout) + one in July.
        msg('Rs 85,000 credited by NEFT.', DateTime(2026, 6, 1)),
        msg('Rs 85,000 credited by NEFT.', DateTime(2026, 6, 15)),
        msg('Rs 85,000 credited by NEFT.', DateTime(2026, 7, 1)),
      ]);
      final map = SpendMap(
        txns: txns,
        windowStart: DateTime(2026, 6, 1),
        windowEnd: DateTime(2026, 7, 31),
        generatedAt: DateTime(2026, 7, 31),
      );
      // 2 tagged months × 85k, averaged over 2 salary-months → 85k (not 127.5k).
      expect(map.monthlyIncome, 85000);
    });

    test('tags multiple recurring income streams', () {
      final txns = parser.parseAll([
        msg('Rs 85,000 credited by NEFT.', DateTime(2026, 6, 1)),
        msg('Rs 85,000 credited by NEFT.', DateTime(2026, 7, 1)),
        msg('Rs 20,000 credited by IMPS.', DateTime(2026, 6, 3)),
        msg('Rs 20,000 credited by IMPS.', DateTime(2026, 7, 3)),
      ]);
      final salaryCount = txns.where((t) => t.isSalary).length;
      expect(salaryCount, 4); // both streams recognised
    });
  });

  group('dedup & amount coverage', () {
    ({int? id, String sender, String body, DateTime date}) msg(
      String body,
      DateTime when, [
      String sender = 'BANK',
    ]) =>
        (id: null, sender: sender, body: body, date: when);

    test('drops duplicate alerts (same amount, direction, day)', () {
      final txns = parser.parseAll([
        msg('Rs 499 debited to SWIGGY.', DateTime(2026, 7, 5), 'HDFCBK'),
        msg('Rs 499 paid to SWIGGY via UPI.', DateTime(2026, 7, 5), 'PAYTM'),
      ]);
      expect(txns.length, 1);
    });

    test('parses worded lakh amounts', () {
      final txn = parse('Rs 1.5 lakh credited towards SALARY.');
      expect(txn!.amount, 150000);
      expect(txn.isSalary, isTrue);
    });

    test('parses crore amounts', () {
      final txn = parse('INR 2 crore credited to a/c.');
      expect(txn!.amount, 20000000);
    });

    test('word-boundary skip words do not drop legit merchants', () {
      // "declined" only as a substring would wrongly drop this; word-boundary
      // matching keeps it since there is no standalone skip word.
      final txn = parse('Rs 300 debited at STORE for undeclinedX.');
      expect(txn, isNotNull);
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
      expect(map.observedMonths, 1);
      expect(map.salaryCredited, 60000);
      expect(map.totalSpent, 499 + 1299 + 250);
      expect(map.monthlyIncome, 60000);
      expect(map.monthlySpend, 2048);
      expect(map.realisticMonthlySavings, 60000 - 2048);
      expect(map.topCategories.first.key, SpendCategory.shopping);
    });

    test('falls back to payslip/CTC income when no salary detected', () {
      final base = SpendMap(
        txns: [parse('Rs 499 debited to SWIGGY.')!],
        windowStart: DateTime(2026, 7, 1),
        windowEnd: DateTime(2026, 7, 31),
        generatedAt: DateTime(2026, 7, 31),
      );
      expect(base.salaryCredited, 0);
      expect(base.monthlyIncome, 0); // no fallback yet

      final withFallback = base.withFallbackIncome(70000);
      expect(withFallback.monthlyIncome, 70000);
      expect(withFallback.realisticMonthlySavings, 70000 - 499);
      expect(withFallback.savingsRate, greaterThan(0));
    });

    test('detected salary overrides the fallback', () {
      final map = SpendMap(
        txns: [parse('Rs 60000 credited towards SALARY.')!],
        windowStart: DateTime(2026, 7, 1),
        windowEnd: DateTime(2026, 7, 31),
        generatedAt: DateTime(2026, 7, 31),
      ).withFallbackIncome(999999);
      expect(map.monthlyIncome, 60000);
    });

    test('fallback is not persisted through JSON', () {
      final map = SpendMap(
        txns: [parse('Rs 500 debited to SWIGGY.')!],
        windowStart: DateTime(2026, 7, 1),
        windowEnd: DateTime(2026, 7, 31),
        generatedAt: DateTime(2026, 7, 31),
      ).withFallbackIncome(50000);
      final restored = SpendMap.fromJsonString(map.toJsonString());
      expect(restored.fallbackMonthlyIncome, isNull);
      expect(restored.monthlyIncome, 0);
    });

    test('income and spend average over their own months, not a shared span',
        () {
      // Salary in Apr/May/Jun; spend only in Jun. Income must average over its
      // 3 months (60k) while spend reflects its 1 month (3k) — not 3k/3.
      final txns = [
        parser.parse(
            sender: 'B',
            body: 'Rs 60000 credited towards SALARY.',
            date: DateTime(2026, 4, 1))!,
        parser.parse(
            sender: 'B',
            body: 'Rs 60000 credited towards SALARY.',
            date: DateTime(2026, 5, 1))!,
        parser.parse(
            sender: 'B',
            body: 'Rs 60000 credited towards SALARY.',
            date: DateTime(2026, 6, 1))!,
        parser.parse(
            sender: 'B',
            body: 'Rs 3000 spent at AMAZON.',
            date: DateTime(2026, 6, 10))!,
      ];
      final map = SpendMap(
        txns: txns,
        windowStart: DateTime(2026, 4, 1),
        windowEnd: DateTime(2026, 6, 30),
        generatedAt: DateTime(2026, 6, 30),
      );
      expect(map.observedMonths, 3);
      expect(map.monthlyIncome, 60000);
      expect(map.monthlySpend, 3000);
      expect(map.realisticMonthlySavings, 57000);
    });

    test('essential spend excludes discretionary categories', () {
      final txns = [
        parser.parse(
            sender: 'B',
            body: 'Rs 12000 debited for RENT to NOBROKER.',
            date: DateTime(2026, 7, 1))!,
        parser.parse(
            sender: 'B',
            body: 'Rs 1500 debited for BESCOM electricity bill.',
            date: DateTime(2026, 7, 2))!,
        parser.parse(
            sender: 'B',
            body: 'Rs 5000 spent at AMAZON.',
            date: DateTime(2026, 7, 3))!,
      ];
      final map = SpendMap(
        txns: txns,
        windowStart: DateTime(2026, 7, 1),
        windowEnd: DateTime(2026, 7, 31),
        generatedAt: DateTime(2026, 7, 31),
      );
      // rent + bills only (shopping excluded), single month.
      expect(map.monthlyEssentialSpend, 13500);
      expect(map.monthlySpend, 18500);
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

  group('credit card bill payments are not mistaken for income', () {
    test('"received...credited to your credit card" is a debit, not salary',
        () {
      final txn = parse(
        'Payment of Rs 15,000 received towards your SBI Credit Card ending 1234 through UPI.',
      );
      expect(txn, isNotNull);
      expect(txn!.direction, TxnDirection.debit);
      expect(txn.isSalary, isFalse);
      expect(txn.category, SpendCategory.bills);
    });

    test('recurring card bill payments never get inferred as salary', () {
      final txns = parser.parseAll([
        (
          id: null,
          sender: 'BANK',
          body:
              'Payment of Rs 25,000 received towards your HDFC Credit Card ending 5678.',
          date: DateTime(2026, 5, 5),
        ),
        (
          id: null,
          sender: 'BANK',
          body:
              'Payment of Rs 25,000 received towards your HDFC Credit Card ending 5678.',
          date: DateTime(2026, 6, 5),
        ),
      ]);
      expect(txns.every((t) => t.direction == TxnDirection.debit), isTrue);
      expect(txns.every((t) => !t.isSalary), isTrue);
    });

    test('a refund credited to a credit card is still a credit', () {
      final txn = parse(
        'Rs 500 refund credited to your ICICI Credit Card ending 9012.',
      );
      expect(txn, isNotNull);
      expect(txn!.direction, TxnDirection.credit);
    });

    test('a normal card spend is still a debit in the right category', () {
      final txn = parse('Rs 899 spent on your Axis Credit Card at SWIGGY.');
      expect(txn, isNotNull);
      expect(txn!.direction, TxnDirection.debit);
      expect(txn.category, SpendCategory.food);
    });
  });
}

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

  group('issuer SMS formats that were previously dropped', () {
    test('HDFC "Sent Rs.X From A/C To MERCHANT" is a debit', () {
      final txn = parse(
        'Sent Rs.120.00 From HDFC Bank A/C x1234 To ZEPTO On 12/07/26 '
        'Ref 419203847362 Not You? Call 18002586161',
      );
      expect(txn, isNotNull);
      expect(txn!.direction, TxnDirection.debit);
      expect(txn.amount, 120);
      expect(txn.merchant, 'ZEPTO');
      expect(txn.category, SpendCategory.groceries);
      expect(txn.refNo, '419203847362');
    });

    test('SBI bare amount with no currency prefix is parsed', () {
      final txn = parse(
        'Dear UPI user A/C X1234 debited by 250.0 on date 12Jul26 '
        'trf to SWIGGY Refno 419203847362',
      );
      expect(txn, isNotNull);
      expect(txn!.amount, 250);
      expect(txn.direction, TxnDirection.debit);
      expect(txn.category, SpendCategory.food);
    });

    test('a bare number is only read as an amount after a money verb', () {
      // Account tail, date and reference digits must not become the amount.
      expect(parse('A/C X1234 statement for 12Jul26 ref 998877 is ready.'),
          isNull);
    });

    test('a completed UPI Autopay debit counts as spend', () {
      final txn = parse(
        'Rs 649 debited from A/c XX1234 towards NETFLIX subscription '
        'via UPI Autopay on 12-Jul-26.',
      );
      expect(txn, isNotNull);
      expect(txn!.amount, 649);
      expect(txn.category, SpendCategory.entertainment);
    });

    test('a completed e-mandate debit counts as spend', () {
      final txn = parse(
        'Rs 5000 debited via e-mandate for SIP in Axis Bluechip Fund '
        'on 12-Jul-26.',
      );
      expect(txn, isNotNull);
      expect(txn!.amount, 5000);
      expect(txn.category, SpendCategory.investment);
    });

    test('mandate REGISTRATION is still ignored', () {
      expect(
        parse('E-mandate registered for Rs 5000 monthly on your A/c XX1234.'),
        isNull,
      );
    });
  });

  group('merchant extraction', () {
    test('does not mistake the amount for the merchant', () {
      final txn = parse(
        'ICICI Bank Acct XX123 debited for Rs 99.00 on 12-Jul-26. '
        'UPI:419203847362',
      );
      expect(txn!.merchant, isNot(contains('99')));
    });

    test('strips wrapping words before the merchant', () {
      final txn = parse(
          'Rs 2400 debited for purchase at METRO CASH AND CARRY on 12-Jul-26.');
      expect(txn!.merchant, 'METRO CASH AND CARRY');
    });

    test('strips trailing rails words after the merchant', () {
      expect(parse('Rs 499 paid to SWIGGY via UPI.')!.merchant, 'SWIGGY');
    });

    test('drops an account tail rather than showing it as a merchant', () {
      final txn = parse('Rs 85,000 credited to a/c XX12 by NEFT ref ACME.');
      expect(txn!.merchant, isNull);
    });
  });

  group('category keyword precision', () {
    test('"gossip" does not match the investment keyword "sip"', () {
      expect(parse('Rs 300 paid to GOSSIP CAFE BANDRA on 12-Jul-26.')!.category,
          SpendCategory.food);
    });

    test('METRO CASH AND CARRY is groceries, not transport', () {
      expect(
          parse('Rs 2400 debited at METRO CASH AND CARRY on 12-Jul.')!.category,
          SpendCategory.groceries);
    });

    test('APOLLO TYRES is transport, not health', () {
      expect(parse('Rs 8000 paid to APOLLO TYRES DEALER via UPI.')!.category,
          SpendCategory.transport);
    });

    test('APOLLO PHARMACY is still health', () {
      expect(parse('Rs 800 paid to APOLLO PHARMACY via UPI.')!.category,
          SpendCategory.health);
    });
  });

  group('categories added for common Indian spend', () {
    test('home loan EMI → loan', () {
      expect(
        parse('Rs 12,450 debited from A/c XX1234 towards HOME LOAN EMI.')!
            .category,
        SpendCategory.loan,
      );
    });

    test('bank charges → fees', () {
      expect(
        parse('Rs 590 debited towards Annual Maintenance Charges GST incl.')!
            .category,
        SpendCategory.fees,
      );
    });

    test('school fees → education, not fees', () {
      expect(
          parse('Rs 45,000 paid to VIDYASHRAM SCHOOL FEES via UPI.')!.category,
          SpendCategory.education);
    });

    test('hotel booking → travel', () {
      expect(
          parse('Rs 6,700 debited at MAKEMYTRIP HOTELS on 12-Jul.')!.category,
          SpendCategory.travel);
    });

    test('NETFLIX stays entertainment ahead of the subscriptions keyword', () {
      expect(parse('Rs 649 debited towards NETFLIX subscription.')!.category,
          SpendCategory.entertainment);
    });

    test('iCloud storage → subscriptions', () {
      expect(parse('Rs 219 debited towards ICLOUD renewal.')!.category,
          SpendCategory.subscriptions);
    });

    test('loan EMI and school fees count as essential spend', () {
      expect(SpendCategory.isEssential(SpendCategory.loan), isTrue);
      expect(SpendCategory.isEssential(SpendCategory.education), isTrue);
      expect(SpendCategory.isEssential(SpendCategory.shopping), isFalse);
    });

    test('an insurance sub-type is essential like its parent', () {
      expect(SpendCategory.isEssential(SpendCategory.insuranceCar), isTrue);
      expect(SpendCategory.parentOf(SpendCategory.insuranceCar),
          SpendCategory.insurance);
    });
  });

  group('duplicate alerts vs distinct same-amount payments', () {
    ({int? id, String sender, String body, DateTime date}) msg(
      String body,
      String sender,
    ) =>
        (id: null, sender: sender, body: body, date: DateTime(2026, 7, 12));

    test('two alerts sharing a UPI reference collapse to one', () {
      final txns = parser.parseAll([
        msg('Rs 499 debited to SWIGGY. Ref 419203847362', 'HDFCBK'),
        msg('Rs 499 paid to Swiggy via UPI. Refno 419203847362', 'PAYTM'),
      ]);
      expect(txns.length, 1);
    });

    test('two different same-amount payments on one day are both kept', () {
      final txns = parser.parseAll([
        msg('Sent Rs.50.00 From A/C x1234 To CHAI POINT Ref 111111111111',
            'HDFCBK'),
        msg('Sent Rs.50.00 From A/C x1234 To TEA VILLA Ref 222222222222',
            'HDFCBK'),
      ]);
      expect(txns.length, 2);
    });

    test('same-amount payments to different merchants survive without a ref',
        () {
      final txns = parser.parseAll([
        msg('Rs 50 paid to CHAI POINT.', 'HDFCBK'),
        msg('Rs 50 paid to TEA VILLA.', 'HDFCBK'),
      ]);
      expect(txns.length, 2);
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

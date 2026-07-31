import 'package:arth/models/spend_map.dart';
import 'package:arth/services/card_spend_integrity.dart';
import 'package:arth/services/finance_message_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = FinanceMessageParser();
  const integrity = CardSpendIntegrity();

  FinanceTxn leg(String sender, String body, DateTime at) =>
      parser.parse(sender: sender, body: body, date: at)!;

  int spendOf(List<FinanceTxn> txns) => SpendMap(
        txns: txns,
        windowStart: DateTime(2026, 8, 1),
        windowEnd: DateTime(2026, 8, 31),
        generatedAt: DateTime(2026, 8, 31),
      ).totalSpent;

  FinanceTxn bill(int amount, {int day = 20, String card = '4321'}) => leg(
        'VM-ICICIC',
        'Payment of Rs $amount received towards your ICICI Credit Card XX$card.',
        DateTime(2026, 8, day),
      );

  FinanceTxn purchase(int amount, {int day = 5, String card = '4321'}) => leg(
        'VM-ICICIC',
        'Rs $amount spent on your ICICI Credit Card ending $card at AMAZON.',
        DateTime(2026, 8, day),
      );

  group('cards that itemise their purchases', () {
    test('the bill stays internal and only purchases count', () {
      final result = integrity.apply([purchase(1299), bill(1299)]);

      expect(spendOf(result), 1299);
      expect(result.any((t) => t.isLowDetailCardBill), isFalse);
    });

    test('several purchases and one bill still count once', () {
      final result = integrity.apply([
        purchase(1299, day: 3),
        purchase(700, day: 9),
        bill(1999),
      ]);
      expect(spendOf(result), 1999);
    });
  });

  group('cards that never itemise', () {
    test('the bill is counted so the spending does not vanish', () {
      // Only a bill arrived: excluding it would leave a card the user clearly
      // uses contributing nothing, with nothing on screen to explain the gap.
      final result = integrity.apply([bill(40000)]);

      expect(spendOf(result), 40000);
      final counted = result.single;
      expect(counted.isInternalTransfer, isFalse);
      expect(counted.isLowDetailCardBill, isTrue);
    });

    test('a part payment and the rest both count', () {
      // Two bills in one month is a part payment followed by the remainder.
      // Counting only the largest would under-report what actually left.
      final result = integrity.apply([
        bill(10000, day: 12),
        bill(30000, day: 20),
      ]);
      expect(spendOf(result), 40000);
      expect(result.every((t) => t.isLowDetailCardBill), isTrue);
    });

    test('judged per card, so one silent card does not affect a talkative one',
        () {
      final result = integrity.apply([
        purchase(1299, card: '4321'),
        bill(1299, card: '4321'),
        bill(40000, card: '8888'),
      ]);

      // 4321 itemised, so its bill stays internal. 8888 did not, so its bill
      // counts.
      expect(spendOf(result), 1299 + 40000);
      final promoted =
          result.where((t) => t.isLowDetailCardBill).toList(growable: false);
      expect(promoted.length, 1);
      expect(promoted.single.source?.tail, '8888');
    });

    test('judged per month, so a quiet month does not lose its bill', () {
      final julyBill = leg(
        'VM-ICICIC',
        'Payment of Rs 20000 received towards your ICICI Credit Card XX4321.',
        DateTime(2026, 7, 20),
      );
      final result = integrity.apply([
        purchase(1299, day: 5), // August, itemised
        bill(1299, day: 20), // August bill stays internal
        julyBill, // July had no purchases
      ]);

      final promoted = result.where((t) => t.isLowDetailCardBill);
      expect(promoted.length, 1);
      expect(promoted.single.date.month, 7);
    });
  });

  group('leaves everything else alone', () {
    test('a bank transfer is untouched', () {
      final transfer = leg(
        'VM-SBIINB',
        'Rs 25000 debited from A/c XX1234 and credited to XX9012 ICICI BANK',
        DateTime(2026, 8, 5),
      ).copyWith(isInternalTransfer: true);

      final result = integrity.apply([transfer]);
      expect(result.single.isInternalTransfer, isTrue);
      expect(result.single.isLowDetailCardBill, isFalse);
    });

    test('the flag round-trips through JSON', () {
      final result = integrity.apply([bill(40000)]);
      final map = SpendMap(
        txns: result,
        windowStart: DateTime(2026, 8, 1),
        windowEnd: DateTime(2026, 8, 31),
        generatedAt: DateTime(2026, 8, 31),
      );
      final restored = SpendMap.fromJsonString(map.toJsonString());
      expect(restored.txns.single.isLowDetailCardBill, isTrue);
      expect(restored.totalSpent, 40000);
    });

    test('nothing to promote returns the same list', () {
      final txns = [purchase(1299)];
      expect(integrity.apply(txns), same(txns));
    });
  });
}

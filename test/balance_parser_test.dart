import 'package:arth/models/spend_map.dart';
import 'package:arth/services/finance_message_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = FinanceMessageParser();
  final now = DateTime(2026, 8, 1, 9);

  AccountBalance? read(String body, {String sender = 'VM-HDFCBK'}) =>
      parser.parseBalance(sender: sender, body: body, date: now);

  group('balance is read from the shapes banks actually send', () {
    test('trailing balance on a debit alert', () {
      final balance = read(
        'Sent Rs.120 From HDFC Bank A/C x1234 To ZEPTO. Avl Bal Rs 12,345.67',
      );
      expect(balance, isNotNull);
      expect(balance!.amount, 12346);
      expect(balance.tail, '1234');
    });

    test('worded available balance', () {
      final balance = read(
        'A/c XX9012 credited by Rs 5000. Available balance is Rs.48250',
      );
      expect(balance?.amount, 48250);
      expect(balance?.tail, '9012');
    });

    test('clear balance with INR', () {
      expect(read('Acct 4455 debited 900. Clear Bal INR 3,100')?.amount, 3100);
    });
  });

  group('what must not be read as a balance', () {
    test('a payment with no balance stated', () {
      expect(read('Rs 700 debited via UPI to LOCAL STORE from A/c XX1234'),
          isNull);
    });

    test('a credit card outstanding is not money the user holds', () {
      expect(
        read('Your HDFC Credit Card ending 4321 has an outstanding bal of Rs '
            '25,000'),
        isNull,
      );
    });

    test('a balance with no identifiable account is dropped', () {
      expect(read('Your available balance is Rs 5,000'), isNull);
    });

    test('promotional noise is skipped', () {
      expect(
        read('Get a loan against your balance of Rs 50,000! Click here to win'),
        isNull,
      );
    });
  });

  test('newest balance per account wins, never summed', () {
    final balances = parser.parseBalances([
      (
        id: 1,
        sender: 'VM-HDFCBK',
        body: 'A/c XX1234 debited Rs 100. Avl Bal Rs 9,000',
        date: DateTime(2026, 7, 30),
      ),
      (
        id: 2,
        sender: 'VM-HDFCBK',
        body: 'A/c XX1234 debited Rs 200. Avl Bal Rs 8,800',
        date: DateTime(2026, 7, 31),
      ),
      (
        id: 3,
        sender: 'VM-ICICIB',
        body: 'A/c XX5678 credited Rs 500. Avl Bal Rs 2,500',
        date: DateTime(2026, 7, 29),
      ),
    ]);

    expect(balances.length, 2);
    final hdfc = balances.firstWhere((b) => b.tail == '1234');
    expect(hdfc.amount, 8800, reason: 'the older 9,000 is superseded');
    expect(balances.firstWhere((b) => b.tail == '5678').amount, 2500);
  });
}

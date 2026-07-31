import 'package:arth/models/spend_map.dart';
import 'package:arth/services/finance_message_parser.dart';
import 'package:arth/services/transfer_correlator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = FinanceMessageParser();
  const correlator = TransferCorrelator();

  /// Parses without any correlation, so each test can apply exactly the rules it
  /// is about.
  List<FinanceTxn> legs(List<(String, String, DateTime)> messages) => [
        for (final (sender, body, at) in messages)
          parser.parse(sender: sender, body: body, date: at)!,
      ];

  /// Treats any account whose tail is in [tails] as the user's.
  EndpointOwnership ownsTails(Set<String> tails) =>
      (endpoint) => endpoint?.tail != null && tails.contains(endpoint!.tail);

  int spendOf(List<FinanceTxn> txns) => SpendMap(
        txns: txns,
        windowStart: DateTime(2026, 8, 1),
        windowEnd: DateTime(2026, 8, 31),
        generatedAt: DateTime(2026, 8, 31),
      ).totalSpent;

  group('correlating by shared reference', () {
    test('opposite directions on one reference are one movement', () {
      final result = correlator.correlate(legs([
        (
          'VM-SBIINB',
          'Rs 25000 debited from A/c XX1234 Ref 111222333444',
          DateTime(2026, 8, 5, 10)
        ),
        (
          'VM-ICICIB',
          'Rs 25000 credited to your ICICI Bank Account XX9012 Ref 111222333444',
          DateTime(2026, 8, 5, 10)
        ),
      ]));

      expect(result.every((t) => t.isInternalTransfer), isTrue);
      expect(result.map((t) => t.transferGroupId).toSet().length, 1);
      expect(spendOf(result), 0);
    });

    test('needs both directions, not just a shared reference', () {
      // Two payments that happen to quote the same reference are still two
      // payments. Money has to have both left and arrived.
      final result = correlator.correlate(legs([
        (
          'VM-HDFCBK',
          'Rs 499 debited to SWIGGY Ref 111222333444',
          DateTime(2026, 8, 5)
        ),
        (
          'VM-HDFCBK',
          'Rs 250 debited to UBER Ref 111222333444',
          DateTime(2026, 8, 5)
        ),
      ]));
      expect(result.every((t) => !t.isInternalTransfer), isTrue);
      expect(spendOf(result), 749);
    });

    test('an unpaired reference is left as ordinary spend', () {
      final result = correlator.correlate(legs([
        (
          'VM-HDFCBK',
          'Rs 499 debited to SWIGGY Ref 555666777888',
          DateTime(2026, 8, 5)
        ),
      ]));
      expect(result.single.isInternalTransfer, isFalse);
      expect(spendOf(result), 499);
    });
  });

  group('correlating by endpoint, with no shared reference', () {
    // The gap the reference rule cannot close: banks frequently omit the UTR on
    // one side, and those transfers were counted as spend on one account and
    // income on the other.
    List<FinanceTxn> refless() => legs([
          (
            'VM-SBIINB',
            'Rs 25000 debited from A/c XX1234 and credited to XX9012 ICICI BANK',
            DateTime(2026, 8, 5, 10)
          ),
          (
            'VM-ICICIB',
            'Rs 25000 credited to your ICICI Bank Account XX9012 via IMPS',
            DateTime(2026, 8, 5, 11)
          ),
        ]);

    test('a named destination matching another account is one movement', () {
      final result =
          correlator.correlate(refless(), owns: ownsTails({'1234', '9012'}));
      expect(result.every((t) => t.isInternalTransfer), isTrue);
      expect(spendOf(result), 0);
    });

    test('without ownership it stays ordinary spend', () {
      // Correlation must not assume. An unknown account could be anyone's.
      final result = correlator.correlate(refless());
      expect(result.first.isInternalTransfer, isFalse);
      expect(spendOf(result), 25000);
    });

    test('paying somebody else at the same bank is not a transfer', () {
      // The destination is not the user's, so this is a real payment.
      final result = correlator.correlate(refless(), owns: ownsTails({'1234'}));
      expect(result.first.isInternalTransfer, isFalse);
      expect(spendOf(result), 25000);
    });

    test('legs too far apart are not linked', () {
      final stale = legs([
        (
          'VM-SBIINB',
          'Rs 25000 debited from A/c XX1234 and credited to XX9012 ICICI BANK',
          DateTime(2026, 8, 1)
        ),
        (
          'VM-ICICIB',
          'Rs 25000 credited to your ICICI Bank Account XX9012 via IMPS',
          DateTime(2026, 8, 20)
        ),
      ]);
      final result =
          correlator.correlate(stale, owns: ownsTails({'1234', '9012'}));
      expect(result.first.isInternalTransfer, isFalse);
    });

    test('a different amount is not the same movement', () {
      final mismatched = legs([
        (
          'VM-SBIINB',
          'Rs 25000 debited from A/c XX1234 and credited to XX9012 ICICI BANK',
          DateTime(2026, 8, 5)
        ),
        (
          'VM-ICICIB',
          'Rs 30000 credited to your ICICI Bank Account XX9012 via IMPS',
          DateTime(2026, 8, 5)
        ),
      ]);
      final result =
          correlator.correlate(mismatched, owns: ownsTails({'1234', '9012'}));
      expect(result.first.isInternalTransfer, isFalse);
    });
  });

  group('chaining more than two legs', () {
    test('a three-hop card payment collapses to one movement', () {
      // Bank A out -> bank B in -> bank B out to the card. A never links to the
      // card directly; the chain has to be transitive.
      final result = correlator.correlate(
        legs([
          (
            'VM-SBIINB',
            'Rs 25000 debited from A/c XX1234 and credited to XX9012 ICICI BANK',
            DateTime(2026, 8, 5, 10)
          ),
          (
            'VM-ICICIB',
            'Rs 25000 credited to your ICICI Bank Account XX9012 via IMPS',
            DateTime(2026, 8, 5, 10)
          ),
          (
            'VM-ICICIB',
            'Rs 25000 debited from ICICI Bank Account XX9012 towards ICICI Credit Card XX4321 payment',
            DateTime(2026, 8, 5, 11)
          ),
        ]),
        owns: ownsTails({'1234', '9012', '4321'}),
      );

      expect(result.length, 3);
      expect(result.every((t) => t.isInternalTransfer), isTrue);
      // One movement, so one group.
      expect(result.map((t) => t.transferGroupId).toSet().length, 1);
      expect(spendOf(result), 0);
    });

    test('a real purchase alongside a transfer still counts', () {
      final result = correlator.correlate(
        legs([
          (
            'VM-SBIINB',
            'Rs 25000 debited from A/c XX1234 and credited to XX9012 ICICI BANK',
            DateTime(2026, 8, 5)
          ),
          (
            'VM-ICICIB',
            'Rs 25000 credited to your ICICI Bank Account XX9012 via IMPS',
            DateTime(2026, 8, 5)
          ),
          (
            'VM-ICICIC',
            'Rs 1299 spent on your ICICI Credit Card ending 4321 at AMAZON.',
            DateTime(2026, 8, 2)
          ),
        ]),
        owns: ownsTails({'1234', '9012', '4321'}),
      );
      expect(spendOf(result), 1299);
      expect(
        result.where((t) => t.transferGroupId != null).length,
        2,
      );
    });
  });

  group('salary safety', () {
    test('a monthly self-transfer is never salary', () {
      final months = [6, 7, 8];
      final result = correlator.correlate(
        legs([
          for (final month in months) ...[
            (
              'VM-SBIINB',
              'Rs 50000 debited from A/c XX1234 and credited to XX9012 ICICI BANK',
              DateTime(2026, month, 5)
            ),
            (
              'VM-ICICIB',
              'Rs 50000 credited to your ICICI Bank Account XX9012 via IMPS',
              DateTime(2026, month, 5)
            ),
          ],
        ]),
        owns: ownsTails({'1234', '9012'}),
      );
      final withSalary = FinanceMessageParser.inferRecurringSalary(result);
      expect(withSalary.any((t) => t.isSalary), isFalse);
    });
  });

  test('a single transaction is returned untouched', () {
    final one = legs([
      ('VM-HDFCBK', 'Rs 499 debited to SWIGGY.', DateTime(2026, 8, 5)),
    ]);
    expect(correlator.correlate(one), same(one));
  });
}

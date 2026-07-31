import 'package:arth/models/spend_map.dart';
import 'package:arth/services/card_spend_integrity.dart';
import 'package:arth/services/finance_message_parser.dart';
import 'package:arth/services/transfer_correlator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/sms_sequences.dart';

/// Runs every fixture through the whole pipeline in the same order the app does,
/// and checks the figures a user would actually see.
///
/// Unit tests prove each stage in isolation; this proves they compose. Most of
/// the bugs in this analyzer were not inside a stage but between two of them —
/// dedup eating a leg correlation needed, direction being decided before the
/// instrument was known.
void main() {
  const parser = FinanceMessageParser();
  const correlator = TransferCorrelator();
  const cardIntegrity = CardSpendIntegrity();

  SpendMap run(SmsFixture fixture) {
    final raw = fixture.messages
        .map((message) => (
              id: null as int?,
              sender: message.sender,
              body: message.body,
              date: message.date,
            ))
        .toList(growable: false);

    // Same order as SpendMapNotifier._performScan.
    final parsed = parser.parseAll(raw);
    final correlated = correlator.correlate(
      parsed,
      owns: (endpoint) =>
          endpoint?.tail != null && fixture.ownedTails.contains(endpoint!.tail),
    );
    final reconciled = cardIntegrity.apply(correlated);

    final dates = fixture.messages.map((m) => m.date).toList()..sort();
    return SpendMap(
      txns: reconciled,
      windowStart: DateTime(dates.first.year, dates.first.month),
      windowEnd: dates.last,
      generatedAt: dates.last,
    );
  }

  group('golden SMS corpus', () {
    for (final fixture in smsFixtures) {
      test(fixture.name, () {
        final map = run(fixture);
        final because = fixture.note ?? fixture.name;

        expect(map.totalSpent, fixture.expectedSpend,
            reason: 'spend: $because');
        expect(map.salaryCredited, fixture.expectedSalary,
            reason: 'salary: $because');
        expect(
          map.txns.where((t) => t.isInternalTransfer).length,
          fixture.expectedInternalLegs,
          reason: 'internal legs: $because',
        );
      });
    }

    test('every fixture survives a JSON round-trip unchanged', () {
      // Figures must not shift when the map is reloaded from storage, which is
      // how the app sees them on every cold start.
      for (final fixture in smsFixtures) {
        final map = run(fixture);
        final restored = SpendMap.fromJsonString(map.toJsonString());
        expect(restored.totalSpent, map.totalSpent, reason: fixture.name);
        expect(restored.salaryCredited, map.salaryCredited,
            reason: fixture.name);
        expect(
          restored.txns.where((t) => t.isInternalTransfer).length,
          map.txns.where((t) => t.isInternalTransfer).length,
          reason: fixture.name,
        );
      }
    });
  });

  group('invariants that must hold for any sequence', () {
    test('internal legs contribute nothing to spend or income', () {
      for (final fixture in smsFixtures) {
        final map = run(fixture);
        final internal = map.txns.where((t) => t.isInternalTransfer);

        expect(internal.any((t) => t.countsAsSpend), isFalse,
            reason: fixture.name);
        expect(internal.any((t) => t.isSalary), isFalse, reason: fixture.name);

        // Removing them entirely must not change a single figure — the whole
        // point of the flag.
        final withoutInternal = SpendMap(
          txns: map.txns.where((t) => !t.isInternalTransfer).toList(),
          windowStart: map.windowStart,
          windowEnd: map.windowEnd,
          generatedAt: map.generatedAt,
        );
        expect(withoutInternal.totalSpent, map.totalSpent,
            reason: fixture.name);
        expect(withoutInternal.salaryCredited, map.salaryCredited,
            reason: fixture.name);
      }
    });

    test('spend is the sum of exactly the legs that count', () {
      for (final fixture in smsFixtures) {
        final map = run(fixture);
        final counted = map.txns
            .where((t) => t.countsAsSpend)
            .fold<int>(0, (sum, t) => sum + t.amount);
        expect(counted, map.totalSpent, reason: fixture.name);
      }
    });

    test('every leg of one movement shares its group id', () {
      for (final fixture in smsFixtures) {
        final map = run(fixture);
        final grouped = map.txns.where((t) => t.transferGroupId != null);
        if (grouped.isEmpty) continue;
        for (final group in grouped.map((t) => t.transferGroupId!).toSet()) {
          final members =
              grouped.where((t) => t.transferGroupId == group).toList();
          // A group is a movement, so it needs at least two legs and they must
          // all be internal.
          expect(members.length, greaterThanOrEqualTo(2), reason: fixture.name);
          expect(members.every((t) => t.isInternalTransfer), isTrue,
              reason: fixture.name);
        }
      }
    });

    test('no leg is both spend and salary', () {
      for (final fixture in smsFixtures) {
        final map = run(fixture);
        expect(
          map.txns.any((t) => t.countsAsSpend && t.isSalary),
          isFalse,
          reason: fixture.name,
        );
      }
    });

    test('amounts are always positive', () {
      for (final fixture in smsFixtures) {
        final map = run(fixture);
        expect(map.txns.every((t) => t.amount > 0), isTrue,
            reason: fixture.name);
      }
    });
  });
}

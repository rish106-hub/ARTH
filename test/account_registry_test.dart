import 'package:arth/features/accounts/engine/account_inference.dart';
import 'package:arth/features/accounts/models/owned_account.dart';
import 'package:arth/models/spend_map.dart';
import 'package:arth/services/finance_message_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = FinanceMessageParser();
  const inference = AccountInference();

  List<FinanceTxn> parse(List<(String, String)> messages) => [
        for (final (index, message) in messages.indexed)
          parser.parse(
            sender: message.$1,
            body: message.$2,
            date: DateTime(2026, 8, 1 + index),
          )!,
      ];

  group('inferring which accounts are the user\'s', () {
    test('claims an account named as the subject more than once', () {
      final registry = inference.learn(
        parse([
          ('VM-HDFCBK', 'Rs 499 debited from A/c XX1234 to SWIGGY.'),
          ('VM-HDFCBK', 'Rs 250 debited from A/c XX1234 to UBER.'),
        ]),
        const AccountRegistry.empty(),
      );

      expect(registry.length, 1);
      final account = registry.accounts.values.single;
      expect(account.tail, '1234');
      expect(account.institution, 'HDFCBK');
      expect(account.kind, InstrumentKind.bankAccount);
      expect(account.sightings, 2);
      expect(account.needsConfirmation, isTrue);
    });

    test('ignores an account seen only once', () {
      // One sighting could be anything — a one-off payee, a mangled string. Not
      // worth putting in front of the user.
      final registry = inference.learn(
        parse([('VM-HDFCBK', 'Rs 499 debited from A/c XX1234 to SWIGGY.')]),
        const AccountRegistry.empty(),
      );
      expect(registry.isEmpty, isTrue);
    });

    test('never claims an account seen only as a destination', () {
      // XX9012 is where money went. Claiming a stranger's account as the user's
      // would net a real payment off their spending and hide it — the one error
      // that produces a silently wrong number.
      final registry = inference.learn(
        parse([
          (
            'VM-SBIINB',
            'Rs 5000 debited from A/c XX1234 and credited to XX9012 on 01-Aug'
          ),
          (
            'VM-SBIINB',
            'Rs 7000 debited from A/c XX1234 and credited to XX9012 on 02-Aug'
          ),
        ]),
        const AccountRegistry.empty(),
      );

      expect(registry.accounts.keys.single, endsWith(':1234'));
      expect(
        registry.accounts.values.any((account) => account.tail == '9012'),
        isFalse,
      );
    });

    test('tells a card apart from a bank account', () {
      final registry = inference.learn(
        parse([
          (
            'VM-ICICIC',
            'Rs 1299 spent on your ICICI Credit Card ending 4321 at AMAZON.'
          ),
          (
            'VM-ICICIC',
            'Rs 800 spent on your ICICI Credit Card ending 4321 at ZOMATO.'
          ),
        ]),
        const AccountRegistry.empty(),
      );
      expect(registry.accounts.values.single.kind, InstrumentKind.creditCard);
    });
  });

  group('the user\'s answers outrank inference', () {
    AccountRegistry seeded() => inference.learn(
          parse([
            ('VM-HDFCBK', 'Rs 499 debited from A/c XX1234 to SWIGGY.'),
            ('VM-HDFCBK', 'Rs 250 debited from A/c XX1234 to UBER.'),
          ]),
          const AccountRegistry.empty(),
        );

    test('a rejected account is not owned, and a later scan does not revive it',
        () {
      final id = seeded().accounts.keys.single;
      final rejected = seeded().withOwnership(id, AccountOwnership.rejected);
      expect(rejected.accounts[id]!.isOwned, isFalse);

      // Re-learning from the same messages must not overwrite the answer.
      final rescanned = inference.learn(
        parse([
          ('VM-HDFCBK', 'Rs 499 debited from A/c XX1234 to SWIGGY.'),
          ('VM-HDFCBK', 'Rs 250 debited from A/c XX1234 to UBER.'),
        ]),
        rejected,
      );
      expect(rescanned.accounts[id]!.ownership, AccountOwnership.rejected);
    });

    test('a confirmed account leaves the pending queue but keeps counting', () {
      final id = seeded().accounts.keys.single;
      final confirmed = seeded().withOwnership(id, AccountOwnership.confirmed);

      expect(confirmed.pendingConfirmation, isEmpty);
      expect(confirmed.confirmed.single.id, id);

      final rescanned = inference.learn(
        parse([
          ('VM-HDFCBK', 'Rs 499 debited from A/c XX1234 to SWIGGY.'),
          ('VM-HDFCBK', 'Rs 250 debited from A/c XX1234 to UBER.'),
          ('VM-HDFCBK', 'Rs 100 debited from A/c XX1234 to OLA.'),
        ]),
        confirmed,
      );
      expect(rescanned.accounts[id]!.ownership, AccountOwnership.confirmed);
      expect(rescanned.accounts[id]!.sightings, 3);
    });
  });

  group('ownership lookup', () {
    test('an inferred account counts as owned, an unknown one does not', () {
      final registry = inference.learn(
        parse([
          ('VM-HDFCBK', 'Rs 499 debited from A/c XX1234 to SWIGGY.'),
          ('VM-HDFCBK', 'Rs 250 debited from A/c XX1234 to UBER.'),
        ]),
        const AccountRegistry.empty(),
      );

      const mine = TxnEndpoint(
        institution: 'HDFCBK',
        tail: '1234',
        kind: InstrumentKind.bankAccount,
      );
      const somebodyElse = TxnEndpoint(
        institution: 'HDFCBK',
        tail: '7777',
        kind: InstrumentKind.bankAccount,
      );

      expect(registry.owns(mine), isTrue);
      expect(registry.owns(somebodyElse), isFalse);
      expect(registry.owns(null), isFalse);
      // No tail means no identity, so it can never be matched.
      expect(registry.owns(const TxnEndpoint(institution: 'HDFCBK')), isFalse);
    });

    test('both ends owned makes a movement internal', () {
      var registry = const AccountRegistry.empty();
      for (final tail in ['1234', '9012']) {
        registry = registry.withAccount(OwnedAccount(
          id: 'BANK:bankAccount:$tail',
          institution: 'BANK',
          tail: tail,
          kind: InstrumentKind.bankAccount,
        ));
      }
      // Real bank phrasing. "credited to your ... Account XX9012" names the
      // account as the subject; "credited to XX9012" would name it as a
      // destination, and the parser deliberately refuses to claim those.
      final legs = parse([
        ('VM-BANK', 'Rs 5000 debited from A/c XX1234 via IMPS.'),
        ('VM-BANK', 'Rs 5000 credited to your BANK Account XX9012 via IMPS.'),
      ]);
      expect(inference.isInternalPair(legs[0], legs[1], registry), isTrue);
    });
  });

  group('registry persistence', () {
    test('round-trips through JSON, answers included', () {
      var registry = inference.learn(
        parse([
          ('VM-HDFCBK', 'Rs 499 debited from A/c XX1234 to SWIGGY.'),
          ('VM-HDFCBK', 'Rs 250 debited from A/c XX1234 to UBER.'),
        ]),
        const AccountRegistry.empty(),
      );
      final id = registry.accounts.keys.single;
      registry = registry
          .withOwnership(id, AccountOwnership.confirmed)
          .withLabel(id, 'Salary account');

      final restored = AccountRegistry.fromJsonString(registry.toJsonString());
      expect(restored.accounts[id]!.ownership, AccountOwnership.confirmed);
      expect(restored.accounts[id]!.label, 'Salary account');
      expect(restored.accounts[id]!.displayLabel, 'Salary account');
    });

    test('a corrupt blob reads as an empty registry', () {
      for (final raw in [null, '', 'not json', '[1,2]', '{"accounts":3}']) {
        expect(AccountRegistry.fromJsonString(raw).isEmpty, isTrue,
            reason: '$raw');
      }
    });

    test('falls back to a readable label when unnamed', () {
      const account = OwnedAccount(
        id: 'HDFCBK:bankAccount:1234',
        institution: 'HDFCBK',
        tail: '1234',
        kind: InstrumentKind.bankAccount,
      );
      expect(account.displayLabel, 'HDFCBK ••1234');
      expect(account.kindLabel, 'Bank account');
    });
  });
}

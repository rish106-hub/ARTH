import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arth/models/spend_map.dart';
import 'package:arth/providers/other_income_provider.dart';
import 'package:arth/providers/spend_map_provider.dart';
import 'package:arth/services/sms_reader_service.dart';
import 'package:arth/services/spend_map_service.dart';

/// Fake reader returning the same messages we inject into the emulator inbox.
class _FakeReader extends SmsReaderService {
  _FakeReader(this.messages);
  final List<RawSms> messages;
  bool granted = true;
  DateTime? lastSince;

  @override
  bool get isSupported => true;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<List<RawSms>> readInbox({DateTime? since}) async {
    lastSince = since;
    return messages;
  }
}

/// No-op sync so the test never touches the network.
class _NoopSync extends SpendMapService {
  @override
  Future<void> push(SpendMap map) async {}

  @override
  Future<Map<String, AiCategoryGuess>> categorize(
    List<CategorizeItem> items,
  ) async =>
      const {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<RawSms> sampleMessages() => [
        (
          id: null,
          sender: 'VMHDFCBK',
          body:
              'Rs.54,500.00 credited to a/c XX1234 on 01-07-26 towards SALARY. Avbl bal Rs 61200.',
          date: DateTime(2026, 7, 1),
        ),
        (
          id: null,
          sender: 'VMHDFCBK',
          body: 'Rs 499 debited from a/c XX99 for UPI to SWIGGY on 05-07-26.',
          date: DateTime(2026, 7, 5),
        ),
        (
          id: null,
          sender: 'VMICICI',
          body: 'Rs 1,299 spent on ICICI Card at AMAZON on 08-07-26.',
          date: DateTime(2026, 7, 8),
        ),
        (
          id: null,
          sender: 'VMPAYTM',
          body: 'Rs 250 paid to UBER via UPI on 10-07-26.',
          date: DateTime(2026, 7, 10),
        ),
        (
          id: null,
          sender: 'VMBESCOM',
          body: 'Rs 1500 debited for BESCOM electricity bill on 12-07-26.',
          date: DateTime(2026, 7, 12),
        ),
        (
          id: null,
          sender: 'VMHDFCBK',
          body: '123456 is your OTP for Rs 5000 txn. Do not share.',
          date: DateTime(2026, 7, 13),
        ),
      ];

  test('scan builds spend map from inbox messages, skipping noise', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(spendMapProvider.notifier);
    notifier.debugInjectDependencies(
      reader: _FakeReader(sampleMessages()),
      sync: _NoopSync(),
    );
    await container.read(otherIncomeProvider.notifier).markAsked();

    await notifier.scan();

    final state = container.read(spendMapProvider);
    expect(state.loading, isFalse);
    expect(state.permissionDenied, isFalse);
    expect(state.error, isNull);
    expect(state.hasData, isTrue);

    final map = state.map!;
    // OTP dropped → 5 real txns.
    expect(map.txns.length, 5);
    expect(map.salaryCredited, 54500);
    expect(map.totalSpent, 499 + 1299 + 250 + 1500);
    expect(map.monthlyIncome, 54500);
    expect(map.realisticMonthlySavings, 54500 - (499 + 1299 + 250 + 1500));
    // Bills (₹1500 BESCOM) is the single largest spend.
    expect(map.topCategories.first.key, SpendCategory.bills);
  });

  test('denied permission surfaces permissionDenied without data', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(spendMapProvider.notifier);
    final reader = _FakeReader(const [])..granted = false;
    notifier.debugInjectDependencies(reader: reader, sync: _NoopSync());

    await notifier.scan();

    final state = container.read(spendMapProvider);
    expect(state.permissionDenied, isTrue);
    expect(state.hasData, isFalse);
  });

  test('scan uses the selected period and supports limited recategorization',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final reader = _FakeReader([
      (
        id: null,
        sender: 'VMBANK',
        body: 'Rs 700 debited via UPI to LOCAL STORE.',
        date: DateTime.now(),
      ),
    ]);
    final notifier = container.read(spendMapProvider.notifier);
    notifier.debugInjectDependencies(reader: reader, sync: _NoopSync());
    await container.read(otherIncomeProvider.notifier).markAsked();

    notifier.selectPeriod(SpendScanPeriod.sixMonths);
    await notifier.scan();

    final expected = SpendScanPeriod.sixMonths.since(DateTime.now());
    expect(reader.lastSince?.year, expected.year);
    expect(reader.lastSince?.month, expected.month);
    expect(
      container.read(spendMapProvider).selectedPeriod,
      SpendScanPeriod.sixMonths,
    );

    await notifier.recategorize(0, SpendCategory.groceries);
    expect(
      container.read(spendMapProvider).map!.txns.single.category,
      SpendCategory.groceries,
    );
  });

  test('AI fallback upgrades an unclear debit; low-confidence is ignored',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final reader = _FakeReader([
      (
        id: null,
        sender: 'VMBANK',
        // No keyword match → parsed as category "other".
        body: 'Rs 640 debited via UPI to QUIKPAY SERVICES.',
        date: DateTime.now(),
      ),
    ]);
    final notifier = container.read(spendMapProvider.notifier);
    notifier.debugInjectDependencies(
      reader: reader,
      sync: _StubCategorizer(const AiCategoryGuess(
        category: SpendCategory.entertainment,
        confidence: 'high',
        merchant: 'Quikpay',
      )),
    );
    await container.read(otherIncomeProvider.notifier).markAsked();

    await notifier.scan();
    final txn = container.read(spendMapProvider).map!.txns.single;
    expect(txn.category, SpendCategory.entertainment);
    expect(txn.merchant, 'Quikpay');
    expect(txn.categorySource, CategorySource.ai);
  });

  test('one payee is classified once and applied to all its transactions',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final reader = _FakeReader([
      for (final day in [3, 11, 24])
        (
          id: null,
          sender: 'VMBANK',
          body: 'Rs ${day * 10} debited via UPI to QUIKPAY SERVICES.',
          date: DateTime(2026, 7, day),
        ),
    ]);
    final stub = _StubCategorizer(const AiCategoryGuess(
      category: SpendCategory.entertainment,
      confidence: 'high',
      merchant: 'Quikpay',
    ));
    final notifier = container.read(spendMapProvider.notifier);
    notifier.debugInjectDependencies(reader: reader, sync: stub);
    await container.read(otherIncomeProvider.notifier).markAsked();

    await notifier.scan();

    // Three transactions, one payee → one billable item, three updates.
    expect(stub.received.length, 1);
    expect(stub.received.single.merchant, 'QUIKPAY SERVICES');
    expect(stub.received.single.sender, 'VMBANK');
    expect(stub.received.single.amountBand, isNotNull);
    final txns = container.read(spendMapProvider).map!.txns;
    expect(txns.length, 3);
    expect(
      txns.every((t) => t.category == SpendCategory.entertainment),
      isTrue,
    );
  });

  test('a payee already classified is never sent again on a re-scan', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final messages = <RawSms>[
      (
        id: null,
        sender: 'VMBANK',
        body: 'Rs 640 debited via UPI to QUIKPAY SERVICES.',
        date: DateTime(2026, 7, 4),
      ),
    ];
    final stub = _StubCategorizer(const AiCategoryGuess(
      category: SpendCategory.entertainment,
      confidence: 'high',
      merchant: 'Quikpay',
    ));
    final notifier = container.read(spendMapProvider.notifier);
    notifier.debugInjectDependencies(
      reader: _FakeReader(messages),
      sync: stub,
    );

    await container.read(otherIncomeProvider.notifier).markAsked();
    await notifier.scan();
    expect(stub.received.length, 1);

    // Widening the window (what a period-chip tap does) re-reads the inbox and
    // re-parses everything. The already-classified payee must not be re-sent —
    // the spend cap is one fixed total across all users, not per scan.
    stub.received.clear();
    messages.add((
      id: null,
      sender: 'VMBANK',
      body: 'Rs 900 debited via UPI to QUIKPAY SERVICES.',
      date: DateTime(2026, 5, 9),
    ));
    await container.read(otherIncomeProvider.notifier).markAsked();
    await container.read(spendMapProvider.notifier).scan();

    expect(stub.received, isEmpty);
    final txns = container.read(spendMapProvider).map!.txns;
    expect(txns.length, 2);
    expect(
      txns.every((t) =>
          t.category == SpendCategory.entertainment &&
          t.categorySource == CategorySource.ai),
      isTrue,
    );
  });

  test('a manual correction outranks the remembered AI answer', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final messages = <RawSms>[
      (
        id: null,
        sender: 'VMBANK',
        body: 'Rs 640 debited via UPI to QUIKPAY SERVICES.',
        date: DateTime(2026, 7, 4),
      ),
    ];
    final notifier = container.read(spendMapProvider.notifier);
    notifier.debugInjectDependencies(
      reader: _FakeReader(messages),
      sync: _StubCategorizer(const AiCategoryGuess(
        category: SpendCategory.entertainment,
        confidence: 'high',
      )),
    );

    await container.read(otherIncomeProvider.notifier).markAsked();
    await notifier.scan();
    await notifier.recategorize(0, SpendCategory.fees);

    await container.read(otherIncomeProvider.notifier).markAsked();
    await notifier.scan();

    final txn = container.read(spendMapProvider).map!.txns.single;
    expect(txn.category, SpendCategory.fees);
    expect(txn.categorySource, CategorySource.manual);
  });

  test('AI fallback keeps "other" when confidence is low', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final reader = _FakeReader([
      (
        id: null,
        sender: 'VMBANK',
        body: 'Rs 640 debited via UPI to QUIKPAY SERVICES.',
        date: DateTime.now(),
      ),
    ]);
    final notifier = container.read(spendMapProvider.notifier);
    notifier.debugInjectDependencies(
      reader: reader,
      sync: _StubCategorizer(const AiCategoryGuess(
        category: SpendCategory.entertainment,
        confidence: 'low',
      )),
    );
    await container.read(otherIncomeProvider.notifier).markAsked();

    await notifier.scan();
    final txn = container.read(spendMapProvider).map!.txns.single;
    expect(txn.category, SpendCategory.other);
    expect(txn.categorySource, CategorySource.rules);
  });

  group('other-income follow-up', () {
    test('first scan pauses for the question instead of reading the inbox',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final reader = _FakeReader(sampleMessages());
      final notifier = container.read(spendMapProvider.notifier);
      notifier.debugInjectDependencies(reader: reader, sync: _NoopSync());

      await notifier.scan();

      final state = container.read(spendMapProvider);
      expect(state.awaitingOtherIncomeAnswer, isTrue);
      expect(state.hasData, isFalse);
      expect(reader.lastSince, isNull); // inbox never read yet
    });

    test('resuming after "no" proceeds with the paused scan', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final reader = _FakeReader(sampleMessages());
      final notifier = container.read(spendMapProvider.notifier);
      notifier.debugInjectDependencies(reader: reader, sync: _NoopSync());

      await notifier.scan();
      expect(
          container.read(spendMapProvider).awaitingOtherIncomeAnswer, isTrue);

      await container.read(otherIncomeProvider.notifier).markAsked();
      await notifier.resumeScanAfterOtherIncomeAnswer();

      final state = container.read(spendMapProvider);
      expect(state.awaitingOtherIncomeAnswer, isFalse);
      expect(state.hasData, isTrue);
      expect(reader.lastSince, isNotNull);
    });

    test('a returning user who already answered is never asked again',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final reader = _FakeReader(sampleMessages());
      final notifier = container.read(spendMapProvider.notifier);
      notifier.debugInjectDependencies(reader: reader, sync: _NoopSync());
      await container.read(otherIncomeProvider.notifier).markAsked();

      await notifier.scan();

      final state = container.read(spendMapProvider);
      expect(state.awaitingOtherIncomeAnswer, isFalse);
      expect(state.hasData, isTrue);
    });

    test(
        'manual other-income sources add into monthlyIncome, never into '
        'the synced payload', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final reader = _FakeReader(sampleMessages());
      final notifier = container.read(spendMapProvider.notifier);
      notifier.debugInjectDependencies(reader: reader, sync: _NoopSync());
      await container.read(otherIncomeProvider.notifier).markAsked();
      await container.read(otherIncomeProvider.notifier).add('Freelance', 8000);

      await notifier.scan();

      final spendState = container.read(spendMapProvider);
      expect(spendState.error, isNull);
      expect(spendState.map, isNotNull);
      final map = spendState.map!;
      expect(map.primaryMonthlyIncome, 54500); // detected salary, unaffected
      expect(map.otherMonthlyIncome, 8000);
      expect(map.monthlyIncome, 54500 + 8000); // on-screen total includes it
      expect(map.hasOtherIncome, isTrue);
    });
  });

  group('manual categories survive a re-scan', () {
    /// A transaction with no extractable payee name, so the only thing that can
    /// carry its category across a re-scan is the per-transaction identity.
    RawSms unnamedDebit() => (
          id: null,
          sender: 'VMBANK',
          body: 'Rs 700 debited from A/c XX1234 towards QUIKPAY on 05-07-26.',
          date: DateTime(2026, 7, 5),
        );

    /// The "already asked about other income" flag lives in memory on its
    /// notifier, which Riverpod may rebuild between reads in a test container.
    /// Re-marking before each scan keeps the scan from parking on that one-time
    /// question instead of reading the inbox.
    Future<void> scan(ProviderContainer container) async {
      await container.read(otherIncomeProvider.notifier).markAsked();
      await container.read(spendMapProvider.notifier).scan();
    }

    test('an exact correction is re-applied after scanning again', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(spendMapProvider.notifier);
      notifier.debugInjectDependencies(
        reader: _FakeReader([unnamedDebit()]),
        sync: _NoopSync(),
      );

      await scan(container);
      expect(
          container.read(spendMapProvider).map!.txns.single.merchant, isNull);
      await notifier.recategorize(0, SpendCategory.fees);

      await scan(container);

      final txn = container.read(spendMapProvider).map!.txns.single;
      expect(txn.category, SpendCategory.fees);
      expect(txn.categorySource, CategorySource.manual);
    });

    test('correcting a payee files its later payments automatically', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final messages = <RawSms>[
        (
          id: null,
          sender: 'VMBANK',
          body: 'Rs 700 debited via UPI to LOCAL STORE.',
          date: DateTime(2026, 7, 5),
        ),
      ];
      final notifier = container.read(spendMapProvider.notifier);
      notifier.debugInjectDependencies(
        reader: _FakeReader(messages),
        sync: _NoopSync(),
      );

      await scan(container);
      expect(container.read(spendMapProvider).map!.txns.single.category,
          SpendCategory.other);
      await notifier.recategorize(0, SpendCategory.groceries);

      // A second, never-seen payment to the same payee arrives.
      messages.add((
        id: null,
        sender: 'VMBANK',
        body: 'Rs 320 debited via UPI to Local Store.',
        date: DateTime(2026, 7, 19),
      ));
      await scan(container);

      final txns = container.read(spendMapProvider).map!.txns;
      expect(txns.length, 2);
      expect(
        txns.every((t) => t.category == SpendCategory.groceries),
        isTrue,
      );
    });

    test('an insurance sub-type is accepted, an unknown category is not',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(spendMapProvider.notifier);
      notifier.debugInjectDependencies(
        reader: _FakeReader([unnamedDebit()]),
        sync: _NoopSync(),
      );
      await scan(container);

      await notifier.recategorize(0, SpendCategory.insuranceCar);
      expect(container.read(spendMapProvider).map!.txns.single.category,
          SpendCategory.insuranceCar);

      await notifier.recategorize(0, 'not-a-category');
      expect(container.read(spendMapProvider).map!.txns.single.category,
          SpendCategory.insuranceCar);
    });
  });
}

/// Sync stub that returns canned AI category guesses keyed by transaction index.
/// Answers every payee it is asked about with the same guess, and records what
/// it was asked. Item ids are grouping keys chosen by the provider, so a stub
/// that hard-coded them would be testing the key format rather than the merge.
class _StubCategorizer extends SpendMapService {
  _StubCategorizer(this.guess);
  final AiCategoryGuess guess;
  final List<CategorizeItem> received = [];

  @override
  Future<void> push(SpendMap map) async {}

  @override
  Future<Map<String, AiCategoryGuess>> categorize(
    List<CategorizeItem> items,
  ) async {
    received.addAll(items);
    return {for (final item in items) item.id: guess};
  }
}

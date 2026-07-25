import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arth/models/spend_map.dart';
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
    List<({String id, String text})> items,
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
      sync: _StubCategorizer({
        '0': const AiCategoryGuess(
          category: SpendCategory.entertainment,
          confidence: 'high',
          merchant: 'Quikpay',
        ),
      }),
    );

    await notifier.scan();
    final txn = container.read(spendMapProvider).map!.txns.single;
    expect(txn.category, SpendCategory.entertainment);
    expect(txn.merchant, 'Quikpay');
    expect(txn.categorySource, CategorySource.ai);
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
      sync: _StubCategorizer({
        '0': const AiCategoryGuess(
          category: SpendCategory.entertainment,
          confidence: 'low',
        ),
      }),
    );

    await notifier.scan();
    final txn = container.read(spendMapProvider).map!.txns.single;
    expect(txn.category, SpendCategory.other);
    expect(txn.categorySource, CategorySource.rules);
  });
}

/// Sync stub that returns canned AI category guesses keyed by transaction index.
class _StubCategorizer extends SpendMapService {
  _StubCategorizer(this.guesses);
  final Map<String, AiCategoryGuess> guesses;

  @override
  Future<void> push(SpendMap map) async {}

  @override
  Future<Map<String, AiCategoryGuess>> categorize(
    List<({String id, String text})> items,
  ) async =>
      guesses;
}

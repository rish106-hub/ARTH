import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arth/models/spend_map.dart';
import 'package:arth/providers/spend_map_provider.dart';
import 'package:arth/services/auth_service.dart';
import 'package:arth/services/gmail_service.dart';
import 'package:arth/services/sms_reader_service.dart';
import 'package:arth/services/spend_map_service.dart';

/// Fake reader returning the same messages we inject into the emulator inbox.
class _FakeReader extends SmsReaderService {
  _FakeReader(this.messages);
  final List<RawSms> messages;
  bool granted = true;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<List<RawSms>> readInbox({DateTime? since}) async => messages;
}

/// No-op sync so the test never touches the network.
class _NoopSync extends SpendMapService {
  @override
  Future<void> push(SpendMap map) async {}
}

class _FakeGmail extends GmailService {
  _FakeGmail(this.emails);
  final List<RawEmail> emails;
  @override
  Future<List<RawEmail>> fetchInvoices({
    required String accessToken,
    int maxResults = 40,
  }) async =>
      emails;
}

class _FakeAuth extends AuthService {
  _FakeAuth(this.token);
  final String? token;
  @override
  Future<String?> authorizeGmailReadonly() async => token;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 7, 22);
  List<RawSms> sampleMessages() => [
        (
          sender: 'VMHDFCBK',
          body:
              'Rs.54,500.00 credited to a/c XX1234 on 01-07-26 towards SALARY. Avbl bal Rs 61200.',
          date: DateTime(2026, 7, 1),
        ),
        (
          sender: 'VMHDFCBK',
          body: 'Rs 499 debited from a/c XX99 for UPI to SWIGGY on 05-07-26.',
          date: DateTime(2026, 7, 5),
        ),
        (
          sender: 'VMICICI',
          body: 'Rs 1,299 spent on ICICI Card at AMAZON on 08-07-26.',
          date: DateTime(2026, 7, 8),
        ),
        (
          sender: 'VMPAYTM',
          body: 'Rs 250 paid to UBER via UPI on 10-07-26.',
          date: DateTime(2026, 7, 10),
        ),
        (
          sender: 'VMBESCOM',
          body: 'Rs 1500 debited for BESCOM electricity bill on 12-07-26.',
          date: DateTime(2026, 7, 12),
        ),
        (
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

  test('connectGmail merges email invoices and dedupes against SMS', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(spendMapProvider.notifier);

    // Seed with SMS first.
    notifier.debugInjectDependencies(
      reader: _FakeReader(sampleMessages()),
      sync: _NoopSync(),
    );
    await notifier.scan();
    final smsSpend = container.read(spendMapProvider).map!.totalSpent;

    // Email invoices: one new (Flipkart) + one duplicate of the ₹1299 Amazon
    // SMS spend on the same day (should be deduped).
    final emails = <RawEmail>[
      (
        from: 'Flipkart <no-reply@flipkart.com>',
        subject: 'Your invoice',
        snippet: 'Order total Rs 2,000.',
        date: DateTime(2026, 7, 15),
      ),
      (
        from: 'Amazon <no-reply@amazon.in>',
        subject: 'Your invoice',
        snippet: 'Order total Rs 1,299.',
        date: DateTime(2026, 7, 8),
      ),
    ];
    notifier.debugInjectDependencies(
      gmail: _FakeGmail(emails),
      auth: _FakeAuth('fake-token'),
    );
    await notifier.connectGmail();

    final map = container.read(spendMapProvider).map!;
    // Only the ₹2000 Flipkart invoice is added; the ₹1299 duplicate is dropped.
    expect(map.totalSpent, smsSpend + 2000);
    expect(map.txns.where((t) => t.source == 'email').length, 1);
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
}

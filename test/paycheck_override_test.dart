import 'package:arth/models/paycheck.dart';
import 'package:arth/models/tax_document.dart';
import 'package:arth/providers/paycheck_override_provider.dart';
import 'package:arth/providers/paycheck_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TaxDocument payslip({
    List<Map<String, dynamic>> earnings = const [
      {'label': 'Basic', 'amount': 40000, 'classification': 'basic_pay'},
    ],
    List<Map<String, dynamic>> deductions = const [
      {'label': 'Income Tax', 'amount': 5000, 'classification': 'income_tax'},
    ],
  }) =>
      TaxDocument(
        id: 'payslip-1',
        fy: '2026-27',
        documentType: 'payslip',
        originalFilename: 'payslip.jpg',
        mimeType: 'image/jpeg',
        byteSize: 100,
        parseStatus: 'parsed',
        parseSummary: const {},
        reviewStatus: 'reviewed',
        confirmedFields: {
          'employeeName': 'Rishav',
          'employerName': 'Example Employer',
          'payPeriod': 'July 2026',
          'earnings': earnings,
          'deductions': deductions,
          'grossEarnings':
              earnings.fold<num>(0, (s, r) => s + (r['amount'] as num)),
          'totalDeductions':
              deductions.fold<num>(0, (s, r) => s + (r['amount'] as num)),
        },
        reviewedAt: DateTime(2026, 7, 22),
      );

  test('editing a parsed component updates gross/net without touching '
      'other components', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(paycheckProvider.notifier).syncDocuments([payslip()]);
    final basic = container
        .read(paycheckProvider)
        .components
        .firstWhere((c) => c.canonicalKey == 'basic_pay' || c.label == 'Basic');

    container.read(paycheckOverrideProvider.notifier).editComponent(
          basic.canonicalKey,
          'Basic pay',
          45000,
          PaycheckComponentKind.earning,
        );

    final paycheck = container.read(paycheckProvider);
    expect(paycheck.grossReceived, 45000);
    expect(paycheck.netCredited, 45000 - 5000);
    expect(
      paycheck.components
          .firstWhere((c) => c.canonicalKey == basic.canonicalKey)
          .label,
      'Basic pay',
    );
  });

  test('adding a manual component folds into gross and appears in items', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(paycheckProvider.notifier).syncDocuments([payslip()]);
    container.read(paycheckOverrideProvider.notifier).addComponent(
          'Freelance bonus',
          10000,
          PaycheckComponentKind.earning,
        );

    final paycheck = container.read(paycheckProvider);
    expect(paycheck.grossReceived, 40000 + 10000);
    expect(
      paycheck.components.any((c) => c.label == 'Freelance bonus'),
      isTrue,
    );
    expect(
      paycheck.items.any((i) => i.label == 'Freelance bonus'),
      isTrue,
    );
  });

  test('removing a parsed component hides it and excludes it from totals',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(paycheckProvider.notifier).syncDocuments([
      payslip(earnings: const [
        {'label': 'Basic', 'amount': 40000, 'classification': 'basic_pay'},
        {'label': 'HRA', 'amount': 8000, 'classification': 'hra'},
      ]),
    ]);
    final hra = container
        .read(paycheckProvider)
        .components
        .firstWhere((c) => c.label == 'HRA');

    container
        .read(paycheckOverrideProvider.notifier)
        .removeComponent(hra.canonicalKey, PaycheckComponentKind.earning);

    final paycheck = container.read(paycheckProvider);
    expect(paycheck.components.any((c) => c.label == 'HRA'), isFalse);
    expect(paycheck.grossReceived, 40000);
  });

  test('removing a manually-added component deletes it entirely (does not '
      'linger as a hidden override)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(paycheckProvider.notifier).syncDocuments([payslip()]);
    container
        .read(paycheckOverrideProvider.notifier)
        .addComponent('Side gig', 5000, PaycheckComponentKind.earning);
    final added = container
        .read(paycheckProvider)
        .components
        .firstWhere((c) => c.label == 'Side gig');

    container
        .read(paycheckOverrideProvider.notifier)
        .removeComponent(added.canonicalKey, PaycheckComponentKind.earning);

    expect(
      container.read(paycheckOverrideProvider).any(
            (o) => o.canonicalKey == added.canonicalKey,
          ),
      isFalse,
    );
    expect(container.read(paycheckProvider).grossReceived, 40000);
  });

  test('overrides survive a re-parse of the same document set', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final doc = payslip();
    container.read(paycheckProvider.notifier).syncDocuments([doc]);
    final basic = container
        .read(paycheckProvider)
        .components
        .firstWhere((c) => c.label == 'Basic');
    container.read(paycheckOverrideProvider.notifier).editComponent(
          basic.canonicalKey,
          'Basic pay (corrected)',
          42000,
          PaycheckComponentKind.earning,
        );

    // Re-sync (simulates a fresh document list arriving, e.g. after a re-scan).
    container.read(paycheckProvider.notifier).syncDocuments([doc]);

    final paycheck = container.read(paycheckProvider);
    expect(paycheck.grossReceived, 42000);
    expect(
      paycheck.components.first.label.contains('corrected'),
      isTrue,
    );
  });

  test('overrides apply even with zero documents (fully manual entry)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(paycheckOverrideProvider.notifier)
        .addComponent('Consulting income', 20000, PaycheckComponentKind.earning);
    container.read(paycheckOverrideProvider.notifier).addComponent(
          'Professional tax',
          200,
          PaycheckComponentKind.deduction,
        );

    final paycheck = container.read(paycheckProvider);
    expect(paycheck.grossReceived, 20000);
    expect(paycheck.otherDeductions, 200);
    expect(paycheck.netCredited, 20000 - 200);
  });
}

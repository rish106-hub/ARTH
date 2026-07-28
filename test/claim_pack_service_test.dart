import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:arth/features/recovery/models/recovery_models.dart';
import 'package:arth/features/recovery/services/claim_pack_service.dart';
import 'package:arth/models/paycheck.dart';
import 'package:arth/models/tax_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final claim = ClaimCase(
    id: 'claim-internet',
    paycheckItemId: 'internet',
    label: 'Internet reimbursement',
    detail: 'Offer promised reimbursement; receipt attached',
    amount: 1200,
    status: ClaimCaseStatus.review,
    createdAt: DateTime(2026, 7, 28),
    note: 'Please reimburse the July broadband bill.',
  );
  const document = TaxDocument(
    id: 'receipt-1',
    fy: '2026-27',
    documentType: 'receipt',
    originalFilename: 'broadband-july.txt',
    mimeType: 'text/plain',
    byteSize: 12,
    parseStatus: 'parsed',
    parseSummary: {},
  );
  const paycheck = PaycheckState(
    employeeName: 'Aarav',
    employer: 'Northstar Labs',
    role: 'Analyst',
    payPeriod: 'July 2026',
    promisedMonthly: 50000,
    grossReceived: 50000,
    netCredited: 46000,
    claimableNow: 1200,
    taxWithheld: 2000,
    otherDeductions: 2000,
    annualBenefits: 12000,
    usingSampleData: false,
    offerLetterAdded: true,
    inboxConnected: false,
    preparedClaims: {},
    items: [],
    components: [],
    sources: [],
    evidence: [],
  );

  test('requires user approval and at least one evidence file', () async {
    expect(
      () => const ClaimPackService().build(
        claim: claim,
        paycheck: paycheck,
        evidence: const [document],
        evidenceBytes: const {
          'receipt-1': [1, 2, 3],
        },
        userApproved: false,
      ),
      throwsStateError,
    );

    expect(
      () => const ClaimPackService().build(
        claim: claim,
        paycheck: paycheck,
        evidence: const [],
        evidenceBytes: const {},
        userApproved: true,
      ),
      throwsStateError,
    );
  });

  test('creates PDF and ZIP with unchanged evidence bytes', () async {
    final evidenceBytes = utf8.encode('receipt-data');
    final artifact = await const ClaimPackService().build(
      claim: claim,
      paycheck: paycheck,
      evidence: const [document],
      evidenceBytes: {'receipt-1': evidenceBytes},
      userApproved: true,
    );

    expect(ascii.decode(artifact.summaryPdf.take(4).toList()), '%PDF');
    expect(artifact.filename, 'ARTH-internet-reimbursement-claim-pack.zip');

    final archive = ZipDecoder().decodeBytes(artifact.bytes);
    expect(
      archive.files.map((file) => file.name),
      containsAll(['ARTH-claim-summary.pdf', 'broadband-july.txt']),
    );
    final receipt =
        archive.files.firstWhere((file) => file.name == 'broadband-july.txt');
    expect(receipt.readBytes(), evidenceBytes);
  });
}

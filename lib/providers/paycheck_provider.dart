import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/paycheck.dart';
import '../models/tax_document.dart';
import 'tax_document_provider.dart';
import 'user_profile_provider.dart';

class PaycheckNotifier extends Notifier<PaycheckState> {
  PaycheckState? _realState;

  @override
  PaycheckState build() {
    ref.listen<AsyncValue<List<TaxDocument>>>(
      taxDocumentProvider,
      (_, next) => next.whenData(
        (documents) => Future<void>.microtask(() => syncDocuments(documents)),
      ),
      fireImmediately: true,
    );
    ref.listen(
      userProfileProvider,
      (_, profile) => Future<void>.microtask(() {
        if (!state.usingSampleData && profile.employerName.trim().isNotEmpty) {
          state = state.copyWith(employer: profile.employerName.trim());
        }
      }),
      fireImmediately: true,
    );
    return emptyPaycheck;
  }

  void syncDocuments(List<TaxDocument> documents) {
    if (state.usingSampleData) return;
    final active = documents.where((document) => document.active).toList()
      ..sort((a, b) => _documentDate(b).compareTo(_documentDate(a)));
    final evidence = active.map(_evidenceFromDocument).toList(growable: false);
    final offerLetter = _latestConfirmed(active, 'offerLetter');
    final payslip = _latestConfirmed(active, 'payslip');

    final offer = offerLetter?.confirmedFields ?? const <String, dynamic>{};
    final pay = payslip?.confirmedFields ?? const <String, dynamic>{};
    final deductions = _rows(pay['deductions']);
    final earnings = _rows(pay['earnings']);
    final gross = _amount(pay['grossEarnings']) ?? _sumRows(earnings);
    final totalDeductions =
        _amount(pay['totalDeductions']) ?? _sumRows(deductions);
    final net = _amount(pay['netSalary']) ??
        (gross > 0 ? (gross - totalDeductions).clamp(0, gross).toInt() : 0);
    final incomeTax = deductions
        .where((row) => row['classification'] == 'income_tax')
        .fold<int>(0, (sum, row) => sum + (_amount(row['amount']) ?? 0));
    final annualFixed =
        _amount(offer['fixedAnnualPay']) ?? _amount(offer['annualCtc']) ?? 0;

    final items = <PaycheckItem>[
      ...earnings.map(
        (row) => PaycheckItem(
          id: 'earning-${_itemId(row['label'])}',
          label: row['label']?.toString() ?? 'Earning',
          detail: 'Recorded from confirmed payslip',
          amount: _amount(row['amount']) ?? 0,
          status: PaycheckItemStatus.matched,
        ),
      ),
      ...deductions.map(
        (row) => PaycheckItem(
          id: 'deduction-${_itemId(row['label'])}',
          label: row['label']?.toString() ?? 'Deduction',
          detail: 'Deducted in the confirmed payslip',
          amount: _amount(row['amount']) ?? 0,
          status: PaycheckItemStatus.deduction,
        ),
      ),
    ];

    state = emptyPaycheck.copyWith(
      employeeName: _text(pay['employeeName']) ?? state.employeeName,
      employer: _text(pay['employerName']) ??
          _text(offer['employerName']) ??
          ref.read(userProfileProvider).employerName.trim(),
      role: _text(offer['roleTitle']) ??
          (offerLetter == null
              ? 'Add an offer letter to compare pay'
              : state.role),
      payPeriod: _text(pay['payPeriod']) ??
          (payslip == null ? 'No payslip confirmed' : 'Latest payslip'),
      promisedMonthly: annualFixed > 0 ? (annualFixed / 12).round() : 0,
      grossReceived: gross,
      netCredited: net,
      taxWithheld: incomeTax,
      otherDeductions:
          (totalDeductions - incomeTax).clamp(0, totalDeductions).toInt(),
      offerLetterAdded: offerLetter != null ||
          active.any((document) =>
              document.documentType == 'offerLetter' && !document.isPayslip),
      items: items,
      sources: [
        if (offerLetter != null)
          const PaycheckSource(
            name: 'Offer letter',
            detail: 'Confirmed compensation promise',
            connected: true,
          ),
        if (payslip != null)
          const PaycheckSource(
            name: 'Latest payslip',
            detail: 'Confirmed monthly pay',
            connected: true,
          ),
      ],
      evidence: evidence,
      preparedClaims: state.preparedClaims,
    );
  }

  void useSampleData() {
    if (!state.usingSampleData) _realState = state;
    state = demoPaycheck;
  }

  void closeSampleData() {
    state = _realState ?? emptyPaycheck;
    _realState = null;
  }

  void clearUserData() {
    state = emptyPaycheck;
    _realState = null;
  }

  void markOfferLetterAdded() {
    state = state.copyWith(offerLetterAdded: true, usingSampleData: false);
  }

  void setInboxConnected(bool connected) {
    final updatedSources = state.sources
        .map(
          (source) => source.name == 'Gmail receipts'
              ? PaycheckSource(
                  name: source.name,
                  detail: source.detail,
                  connected: connected,
                  lastSeen: connected ? DateTime.now() : null,
                )
              : source,
        )
        .toList(growable: false);
    state = state.copyWith(
      inboxConnected: connected,
      sources: updatedSources,
    );
  }

  void markClaimPrepared(String id) {
    state = state.copyWith(preparedClaims: {...state.preparedClaims, id});
  }

  void addEvidence(String fileName) {
    final lower = fileName.toLowerCase();
    final receiptLike = lower.contains('receipt') ||
        lower.contains('bill') ||
        lower.contains('gym') ||
        lower.contains('invoice');
    final payslipLike = lower.contains('payslip') || lower.contains('salary');
    final kind = receiptLike
        ? PaycheckEvidenceKind.receipt
        : payslipLike
            ? PaycheckEvidenceKind.payslip
            : PaycheckEvidenceKind.document;

    final evidence = PaycheckEvidence(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      name: fileName,
      detail: 'Added manually. Review extracted fields before matching.',
      statusLabel: 'REVIEW',
      kind: kind,
      needsAction: true,
    );

    state = state.copyWith(
      usingSampleData: false,
      evidence: [evidence, ...state.evidence],
    );
  }

  TaxDocument? _latestConfirmed(
    List<TaxDocument> documents,
    String documentType,
  ) {
    for (final document in documents) {
      final typeMatches = documentType == 'payslip'
          ? document.isPayslip
          : document.documentType == documentType && !document.isPayslip;
      if (typeMatches &&
          document.parsed &&
          document.confirmedFields.isNotEmpty) {
        return document;
      }
    }
    return null;
  }

  DateTime _documentDate(TaxDocument document) =>
      document.reviewedAt ?? document.createdAt ?? DateTime(1970);

  PaycheckEvidence _evidenceFromDocument(TaxDocument document) {
    final kind = document.isPayslip
        ? PaycheckEvidenceKind.payslip
        : PaycheckEvidenceKind.document;
    final count = document.confirmedFields['earnings'] is List
        ? (document.confirmedFields['earnings'] as List).length
        : document.confirmedFields.length;
    return PaycheckEvidence(
      id: document.id,
      name: document.displayName,
      detail: document.parsed
          ? '$count details confirmed and saved'
          : document.needsConfirmation
              ? 'Open this file and check the extracted details'
              : 'Saved securely for manual review',
      statusLabel: document.parsed
          ? 'CONFIRMED'
          : document.needsConfirmation
              ? 'REVIEW'
              : 'SAVED',
      kind: kind,
      needsAction: document.needsConfirmation,
    );
  }

  List<Map<String, dynamic>> _rows(Object? value) =>
      (value as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);

  int _sumRows(List<Map<String, dynamic>> rows) => rows.fold<int>(
        0,
        (sum, row) => sum + (_amount(row['amount']) ?? 0),
      );

  int? _amount(Object? value) => value is num ? value.round() : null;

  String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  String _itemId(Object? value) => (value?.toString() ?? 'item')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

final paycheckProvider = NotifierProvider<PaycheckNotifier, PaycheckState>(
  PaycheckNotifier.new,
);

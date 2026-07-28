import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/reconciliation_engine.dart';
import '../models/paycheck.dart';
import '../models/tax_document.dart';
import 'paycheck_override_provider.dart';
import 'tax_document_provider.dart';
import 'user_profile_provider.dart';

class _ParsedSnapshot {
  const _ParsedSnapshot({
    this.offerFields = const {},
    this.payslipFields = const {},
    this.components = const [],
    this.evidence = const [],
    this.employeeName = 'Your pay profile',
    this.employer = '',
    this.role = 'Add an offer letter to compare pay',
    this.payPeriod = 'Not connected',
    this.offerLetterAdded = false,
  });

  final Map<String, dynamic> offerFields;
  final Map<String, dynamic> payslipFields;
  final List<PaycheckComponent> components;
  final List<PaycheckEvidence> evidence;
  final String employeeName;
  final String employer;
  final String role;
  final String payPeriod;
  final bool offerLetterAdded;
}

class PaycheckNotifier extends Notifier<PaycheckState> {
  PaycheckState? _realState;
  _ParsedSnapshot _parsed = const _ParsedSnapshot();
  SalarySmsSnapshot _salarySms = const SalarySmsSnapshot();
  Set<String> _preparedClaims = {};
  bool _inboxConnected = false;

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
          _parsed = _ParsedSnapshot(
            offerFields: _parsed.offerFields,
            payslipFields: _parsed.payslipFields,
            components: _parsed.components,
            evidence: _parsed.evidence,
            employeeName: _parsed.employeeName,
            employer: profile.employerName.trim(),
            role: _parsed.role,
            payPeriod: _parsed.payPeriod,
            offerLetterAdded: _parsed.offerLetterAdded,
          );
          if (!state.usingSampleData) state = _reconcile();
        }
      }),
      fireImmediately: true,
    );
    ref.listen(paycheckOverrideProvider, (_, __) {
      if (!state.usingSampleData) state = _reconcile();
    });
    return _reconcile();
  }

  /// Called by the spend-map provider when SMS salary credits change.
  void syncSalarySms(SalarySmsSnapshot salarySms) {
    if (state.usingSampleData || _salarySms == salarySms) return;
    _salarySms = salarySms;
    state = _reconcile();
  }

  PaycheckState _reconcile() {
    final mergedComponents = _mergeOverrides(_parsed.components);
    final output = ReconciliationEngine.reconcile(
      ReconciliationInput(
        offerFields: _parsed.offerFields,
        payslipFields: _parsed.payslipFields,
        components: mergedComponents,
        evidence: _parsed.evidence,
        salarySms: _salarySms,
        employeeName: _parsed.employeeName,
        employer: _parsed.employer,
        role: _parsed.role,
        payPeriod: _parsed.payPeriod,
        offerLetterAdded: _parsed.offerLetterAdded,
      ),
    );
    var paycheck = output.toPaycheckState(
      preparedClaims: _preparedClaims,
      inboxConnected: _inboxConnected,
    );
    if (_inboxConnected) {
      paycheck = paycheck.copyWith(
        sources: [
          ...paycheck.sources,
          const PaycheckSource(
            name: 'Gmail receipts',
            detail: 'Payslips and eligible bills',
            connected: true,
          ),
        ],
      );
    }
    return paycheck;
  }

  List<PaycheckComponent> _mergeOverrides(List<PaycheckComponent> base) {
    final overrides = ref.read(paycheckOverrideProvider);
    if (overrides.isEmpty) return base;

    final overrideByKey = {for (final o in overrides) o.canonicalKey: o};
    final merged = <PaycheckComponent>[];
    for (final component in base) {
      final override = overrideByKey[component.canonicalKey];
      if (override == null) {
        merged.add(component);
      } else if (!override.removed) {
        merged.add(PaycheckComponent(
          label: override.label,
          canonicalKey: component.canonicalKey,
          classification: component.classification,
          amount: override.amount,
          kind: component.kind,
        ));
      }
    }
    for (final override in overrides) {
      if (override.isManualAdd && !override.removed) {
        merged.add(PaycheckComponent(
          label: override.label,
          canonicalKey: override.canonicalKey,
          classification: 'other',
          amount: override.amount,
          kind: override.kind,
        ));
      }
    }
    return merged;
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
    final components = <PaycheckComponent>[
      ...earnings.map(
        (row) => PaycheckComponent(
          label: row['label']?.toString() ?? 'Earning',
          canonicalKey:
              row['canonicalKey']?.toString() ?? _itemId(row['label']),
          classification: row['classification']?.toString() ?? 'other',
          amount: _amount(row['amount']) ?? 0,
          kind: PaycheckComponentKind.earning,
        ),
      ),
      ...deductions.map(
        (row) => PaycheckComponent(
          label: row['label']?.toString() ?? 'Deduction',
          canonicalKey:
              row['canonicalKey']?.toString() ?? _itemId(row['label']),
          classification: row['classification']?.toString() ?? 'other',
          amount: _amount(row['amount']) ?? 0,
          kind: PaycheckComponentKind.deduction,
        ),
      ),
    ];
    final grossDeclared = _amount(pay['grossEarnings']);
    final earningsSum = components
        .where((c) => c.kind == PaycheckComponentKind.earning)
        .fold<int>(0, (sum, c) => sum + c.amount);
    if (grossDeclared != null &&
        grossDeclared > earningsSum &&
        earningsSum > 0) {
      components.add(
        PaycheckComponent(
          label: 'Other earnings',
          canonicalKey: 'other_earnings',
          classification: 'other',
          amount: grossDeclared - earningsSum,
          kind: PaycheckComponentKind.earning,
        ),
      );
    }

    _parsed = _ParsedSnapshot(
      offerFields: offer,
      payslipFields: pay,
      components: components,
      evidence: evidence,
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
      offerLetterAdded: offerLetter != null ||
          active.any((document) =>
              document.documentType == 'offerLetter' && !document.isPayslip),
    );
    state = _reconcile();
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
    _parsed = const _ParsedSnapshot();
    _salarySms = const SalarySmsSnapshot();
    _preparedClaims = {};
    _inboxConnected = false;
  }

  void markOfferLetterAdded() {
    state = state.copyWith(offerLetterAdded: true, usingSampleData: false);
  }

  void setInboxConnected(bool connected) {
    _inboxConnected = connected;
    state = _reconcile();
  }

  void markClaimPrepared(String id) {
    if (state.usingSampleData) {
      state = state.copyWith(preparedClaims: {...state.preparedClaims, id});
      return;
    }
    _preparedClaims = {..._preparedClaims, id};
    state = _reconcile();
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
    _parsed = _ParsedSnapshot(
      offerFields: _parsed.offerFields,
      payslipFields: _parsed.payslipFields,
      components: _parsed.components,
      evidence: [evidence, ..._parsed.evidence],
      employeeName: _parsed.employeeName,
      employer: _parsed.employer,
      role: _parsed.role,
      payPeriod: _parsed.payPeriod,
      offerLetterAdded: _parsed.offerLetterAdded,
    );
    state = _reconcile();
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
    final kind = evidenceKindForDocument(document);
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

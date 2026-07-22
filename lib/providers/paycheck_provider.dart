import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/paycheck.dart';

class PaycheckNotifier extends Notifier<PaycheckState> {
  PaycheckState? _realState;

  @override
  PaycheckState build() => emptyPaycheck;

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
}

final paycheckProvider = NotifierProvider<PaycheckNotifier, PaycheckState>(
  PaycheckNotifier.new,
);

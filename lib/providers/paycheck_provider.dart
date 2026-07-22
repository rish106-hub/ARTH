import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/paycheck.dart';

class PaycheckNotifier extends Notifier<PaycheckState> {
  @override
  PaycheckState build() => demoPaycheck;

  void useSampleData() {
    state = demoPaycheck;
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
}

final paycheckProvider = NotifierProvider<PaycheckNotifier, PaycheckState>(
  PaycheckNotifier.new,
);

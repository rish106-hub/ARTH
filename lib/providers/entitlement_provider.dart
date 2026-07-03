import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/entitlement.dart';

class EntitlementNotifier extends Notifier<Entitlement> {
  @override
  Entitlement build() => const Entitlement();

  void setPremiumDemo(bool enabled) {
    state = Entitlement(
      tier: enabled ? EntitlementTier.premiumDemo : EntitlementTier.free,
    );
  }
}

final entitlementProvider = NotifierProvider<EntitlementNotifier, Entitlement>(
  EntitlementNotifier.new,
);

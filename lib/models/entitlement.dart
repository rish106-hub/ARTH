enum EntitlementTier { free, premiumDemo }

class Entitlement {
  final EntitlementTier tier;

  const Entitlement({this.tier = EntitlementTier.free});

  bool get isPremiumDemo => tier == EntitlementTier.premiumDemo;

  String get label => isPremiumDemo ? 'Premium demo' : 'Free';
}

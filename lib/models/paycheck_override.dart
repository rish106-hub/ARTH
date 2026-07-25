import 'dart:convert';

import 'paycheck.dart';

/// A user edit layered on top of parsed paycheck data. [syncDocuments] rebuilds
/// `components` from scratch on every document change, so overrides are kept
/// separately and re-applied after each rebuild (see PaycheckNotifier) rather
/// than being written into the parsed state directly.
class PaycheckOverride {
  const PaycheckOverride({
    required this.canonicalKey,
    required this.label,
    required this.amount,
    required this.kind,
    this.removed = false,
    this.isManualAdd = false,
  });

  /// Matches a parsed [PaycheckComponent.canonicalKey], or a synthetic
  /// `manual-<timestamp>` key for a wholly user-added line item.
  final String canonicalKey;
  final String label;
  final int amount;
  final PaycheckComponentKind kind;

  /// True hides this component (only meaningful for a key that also exists
  /// in the parsed set — a manually-added component that's removed is simply
  /// deleted from the override list instead, see PaycheckOverrideNotifier).
  final bool removed;

  /// True when this line item has no parsed counterpart — it exists purely
  /// because the user added it.
  final bool isManualAdd;

  Map<String, dynamic> toJson() => {
        'canonicalKey': canonicalKey,
        'label': label,
        'amount': amount,
        'kind': kind.name,
        'removed': removed,
        'isManualAdd': isManualAdd,
      };

  factory PaycheckOverride.fromJson(Map<String, dynamic> json) =>
      PaycheckOverride(
        canonicalKey: json['canonicalKey']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        amount: (json['amount'] as num?)?.round() ?? 0,
        kind: json['kind'] == 'deduction'
            ? PaycheckComponentKind.deduction
            : PaycheckComponentKind.earning,
        removed: json['removed'] == true,
        isManualAdd: json['isManualAdd'] == true,
      );

  static String encodeList(List<PaycheckOverride> overrides) =>
      jsonEncode(overrides.map((o) => o.toJson()).toList());

  static List<PaycheckOverride> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(PaycheckOverride.fromJson)
          .where((o) => o.canonicalKey.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

import 'dart:convert';

/// A merchant → category memory, keyed on a normalised merchant name so
/// "SWIGGY", "Swiggy " and "swiggy" are one entry.
///
/// Two instances are stored per user, because a scan rebuilds every transaction
/// from the SMS inbox and would otherwise lose both kinds of knowledge:
///
///  - the user's own corrections, which must survive and take precedence;
///  - payees the paid AI pass has already resolved, so widening the scan window
///    from one month to twelve re-uses those answers instead of paying for them
///    again.
class MerchantCategoryRules {
  const MerchantCategoryRules._(this._byMerchant);

  const MerchantCategoryRules.empty() : _byMerchant = const {};

  final Map<String, String> _byMerchant;

  /// Upper bound on stored rules. Oldest entries are dropped first: a merchant
  /// the user has not corrected in hundreds of distinct payees is the least
  /// valuable one to keep, and this keeps the persisted blob small.
  static const maxRules = 400;

  /// Shortest usable key. Two characters is too little to identify a payee and
  /// would mis-file unrelated merchants.
  static const _minKeyLength = 3;

  static final RegExp _nonAlphanumeric = RegExp(r'[^a-z0-9]');

  /// Normalised lookup key for [merchant], or null when there is not enough of
  /// a name to key a rule on.
  static String? keyFor(String? merchant) {
    if (merchant == null) return null;
    final key = merchant.toLowerCase().replaceAll(_nonAlphanumeric, '');
    return key.length < _minKeyLength ? null : key;
  }

  bool get isEmpty => _byMerchant.isEmpty;
  int get length => _byMerchant.length;

  /// The category the user last chose for [merchant], or null when untaught.
  String? categoryFor(String? merchant) {
    final key = keyFor(merchant);
    return key == null ? null : _byMerchant[key];
  }

  /// Returns a copy with [merchant] mapped to [category]. Re-teaching a
  /// merchant moves it to the newest position so it survives trimming.
  MerchantCategoryRules withRule(String? merchant, String category) {
    final key = keyFor(merchant);
    if (key == null) return this;
    final next = Map<String, String>.from(_byMerchant)
      ..remove(key)
      ..[key] = category;
    while (next.length > maxRules) {
      next.remove(next.keys.first);
    }
    return MerchantCategoryRules._(next);
  }

  String toJsonString() => jsonEncode(_byMerchant);

  /// Tolerant of a corrupt or legacy blob — an unreadable rule set is treated
  /// as "nothing taught yet" rather than failing the scan that reads it.
  factory MerchantCategoryRules.fromJsonString(String? json) {
    if (json == null || json.isEmpty) {
      return const MerchantCategoryRules.empty();
    }
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return const MerchantCategoryRules.empty();
      final rules = <String, String>{};
      decoded.forEach((key, value) {
        final normalised = keyFor(key?.toString());
        final category = value?.toString();
        if (normalised != null && category != null && category.isNotEmpty) {
          rules[normalised] = category;
        }
      });
      return MerchantCategoryRules._(rules);
    } catch (_) {
      return const MerchantCategoryRules.empty();
    }
  }
}

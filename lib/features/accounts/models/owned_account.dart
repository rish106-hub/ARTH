import 'dart:convert';

import '../../../models/spend_map.dart';

/// Whether the user has told us anything about an account we found in their SMS.
enum AccountOwnership {
  /// Found in SMS, looks like theirs, not yet confirmed. Treated as owned for
  /// correlation, because the inference is conservative and being wrong here
  /// only means a transfer stays visible as spend until they say otherwise.
  inferred,

  /// The user confirmed it is theirs.
  confirmed,

  /// The user said it is not theirs — a shared account, a family member's, a
  /// payee they transfer to often. Never treated as an internal endpoint.
  rejected,
}

/// An account or card seen in the user's SMS.
///
/// Knowing which endpoints belong to the user is what turns a pile of legs into
/// a transaction: money leaving one owned account and arriving at another is a
/// transfer, not spending, regardless of how many hops it took or whether the
/// banks quoted a shared reference.
class OwnedAccount {
  const OwnedAccount({
    required this.id,
    required this.institution,
    required this.tail,
    required this.kind,
    this.ownership = AccountOwnership.inferred,
    this.label,
    this.sightings = 1,
  });

  /// Upper bound, so a corrupt inbox cannot grow the synced payload without
  /// limit. Well beyond the number of accounts a person actually holds.
  static const maxPerUser = 40;

  /// `TxnEndpoint.id` — `<institution>:<kind>:<tail>`.
  final String id;
  final String? institution;
  final String tail;
  final InstrumentKind kind;
  final AccountOwnership ownership;

  /// User-supplied name ("Salary account", "Wife's card"). Null until they
  /// bother, which most never will.
  final String? label;

  /// How many messages named this account as their subject. Drives ordering on
  /// the confirmation screen so the accounts that matter appear first.
  final int sightings;

  bool get isOwned => ownership != AccountOwnership.rejected;
  bool get needsConfirmation => ownership == AccountOwnership.inferred;

  /// Falls back to something readable when unlabelled: "HDFCBK ••1234".
  String get displayLabel {
    final own = label?.trim();
    if (own != null && own.isNotEmpty) return own;
    final where = institution ?? 'Account';
    return '$where ••$tail';
  }

  String get kindLabel => switch (kind) {
        InstrumentKind.creditCard => 'Credit card',
        InstrumentKind.bankAccount => 'Bank account',
        InstrumentKind.wallet => 'Wallet',
        InstrumentKind.unknown => 'Account',
      };

  OwnedAccount copyWith({
    AccountOwnership? ownership,
    String? label,
    int? sightings,
  }) =>
      OwnedAccount(
        id: id,
        institution: institution,
        tail: tail,
        kind: kind,
        ownership: ownership ?? this.ownership,
        label: label ?? this.label,
        sightings: sightings ?? this.sightings,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (institution != null) 'institution': institution,
        'tail': tail,
        'kind': kind.name,
        'ownership': ownership.name,
        if (label != null) 'label': label,
        'sightings': sightings,
      };

  static OwnedAccount? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final tail = json['tail']?.toString();
    if (id == null || id.isEmpty || tail == null || tail.isEmpty) return null;
    return OwnedAccount(
      id: id,
      institution: json['institution']?.toString(),
      tail: tail,
      kind: InstrumentKind.fromName(json['kind']?.toString()),
      ownership: switch (json['ownership']?.toString()) {
        'confirmed' => AccountOwnership.confirmed,
        'rejected' => AccountOwnership.rejected,
        _ => AccountOwnership.inferred,
      },
      label: json['label']?.toString(),
      sightings: (json['sightings'] as num?)?.toInt() ?? 1,
    );
  }
}

/// The user's account registry, keyed by endpoint id.
class AccountRegistry {
  const AccountRegistry({this.accounts = const {}});

  const AccountRegistry.empty() : accounts = const {};

  final Map<String, OwnedAccount> accounts;

  bool get isEmpty => accounts.isEmpty;
  int get length => accounts.length;

  /// Accounts to put in front of the user, most-seen first. Only ever the ones
  /// still unconfirmed, so the screen empties out as they answer.
  List<OwnedAccount> get pendingConfirmation {
    final pending = accounts.values
        .where((account) => account.needsConfirmation)
        .toList()
      ..sort((a, b) => b.sightings.compareTo(a.sightings));
    return pending;
  }

  List<OwnedAccount> get confirmed => accounts.values
      .where((account) => account.ownership == AccountOwnership.confirmed)
      .toList(growable: false);

  /// Whether [endpoint] is one of the user's own. Unknown endpoints are not
  /// owned: correlation must not assume, or it would net off real spending.
  bool owns(TxnEndpoint? endpoint) {
    final id = endpoint?.id;
    if (id == null) return false;
    return accounts[id]?.isOwned ?? false;
  }

  AccountRegistry withAccount(OwnedAccount account) => AccountRegistry(
        accounts: {...accounts, account.id: account},
      );

  AccountRegistry withOwnership(String id, AccountOwnership ownership) {
    final existing = accounts[id];
    if (existing == null) return this;
    return withAccount(existing.copyWith(ownership: ownership));
  }

  AccountRegistry withLabel(String id, String label) {
    final existing = accounts[id];
    if (existing == null) return this;
    return withAccount(existing.copyWith(label: label));
  }

  Map<String, dynamic> toJson() => {
        'accounts': accounts.values.map((account) => account.toJson()).toList(),
      };

  String toJsonString() => jsonEncode(toJson());

  /// Tolerant of a corrupt or legacy blob: an unreadable registry is treated as
  /// empty rather than failing the scan that reads it.
  factory AccountRegistry.fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return const AccountRegistry.empty();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const AccountRegistry.empty();
      final list = decoded['accounts'];
      if (list is! List) return const AccountRegistry.empty();
      final accounts = <String, OwnedAccount>{};
      for (final entry in list) {
        if (entry is! Map) continue;
        final account = OwnedAccount.fromJson(Map<String, dynamic>.from(entry));
        if (account != null) accounts[account.id] = account;
      }
      return AccountRegistry(accounts: accounts);
    } catch (_) {
      return const AccountRegistry.empty();
    }
  }
}

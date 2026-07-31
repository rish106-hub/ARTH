import '../../../models/spend_map.dart';
import '../models/owned_account.dart';

/// Learns which accounts belong to the user from the shape of their SMS, without
/// asking them anything.
///
/// The rule is deliberately conservative, because the two errors are not
/// symmetric. Wrongly treating a stranger's account as the user's would net a
/// real payment off their spending and hide it — a number that is silently too
/// low. Wrongly leaving the user's own account out only means a transfer keeps
/// showing as spend, which they can see and correct. So: only claim an account
/// when the messages say it is the subject, never the destination.
class AccountInference {
  const AccountInference();

  /// A tail seen once could be anything — a one-off payee, a typo, an OTP
  /// fragment. Two independent messages naming it as their subject is the point
  /// at which it is worth showing the user.
  static const minSightings = 2;

  /// Folds [txns] into [existing], preserving every answer the user has already
  /// given. Confirmed and rejected accounts keep their ownership; only sighting
  /// counts move.
  AccountRegistry learn(
    Iterable<FinanceTxn> txns,
    AccountRegistry existing,
  ) {
    // A source endpoint is the account the message is ABOUT. A counterparty is
    // where money went, which is usually somebody else, so counterparties are
    // never candidates on their own.
    final sightings = <String, int>{};
    final endpoints = <String, TxnEndpoint>{};
    for (final txn in txns) {
      final endpoint = txn.source;
      final id = endpoint?.id;
      if (endpoint == null || id == null) continue;
      sightings[id] = (sightings[id] ?? 0) + 1;
      endpoints[id] = endpoint;
    }

    var registry = existing;
    for (final entry in sightings.entries) {
      final id = entry.key;
      final seen = entry.value;
      final known = registry.accounts[id];

      if (known != null) {
        // Never overwrite an answer the user gave; only refresh the count.
        registry = registry.withAccount(known.copyWith(sightings: seen));
        continue;
      }
      if (seen < minSightings) continue;
      if (registry.length >= OwnedAccount.maxPerUser) continue;

      final endpoint = endpoints[id]!;
      registry = registry.withAccount(OwnedAccount(
        id: id,
        institution: endpoint.institution,
        tail: endpoint.tail!,
        kind: endpoint.kind,
        sightings: seen,
      ));
    }
    return registry;
  }

  /// Whether both ends of a movement are accounts the user holds, which makes it
  /// internal regardless of what the message text says.
  bool isInternalPair(
    FinanceTxn debit,
    FinanceTxn credit,
    AccountRegistry registry,
  ) =>
      registry.owns(debit.source) && registry.owns(credit.source);
}

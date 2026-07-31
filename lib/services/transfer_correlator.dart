import '../models/spend_map.dart';

/// Whether an endpoint belongs to the user. Supplied as a predicate rather than
/// by importing the account registry, so this service stays independent of the
/// feature that owns that state.
typedef EndpointOwnership = bool Function(TxnEndpoint? endpoint);

/// Recognises the several SMS a single movement of money produces, and marks
/// them as internal so none of them is counted as spending or income.
///
/// Two operations are easy to confuse, and conflating them was the original bug:
///
///  * **Dedup** — one leg alerted twice, by the bank header and again by a UPI
///    app. Same reference, *same* direction. Handled in the parser.
///  * **Correlate** — different legs of one movement. Same reference in
///    *opposite* directions, or one leg's destination account being another
///    leg's subject account. Handled here.
///
/// Paying a credit card bill from a different bank is three legs: bank A out,
/// bank B in, bank B out to the card. Chained together they are one payment,
/// and the user spent nothing by moving their own money around.
class TransferCorrelator {
  const TransferCorrelator();

  /// How far apart the legs of one movement may be. IMPS and UPI settle in
  /// seconds, but NEFT batches overnight and a card payment can post the
  /// following morning, so a day either side is not generous.
  static const window = Duration(hours: 36);

  /// Marks every leg that only moves the user's own money between their own
  /// accounts, and stamps each correlated set with a shared
  /// [FinanceTxn.transferGroupId].
  ///
  /// Only certainties are applied: a shared reference across opposite
  /// directions, or a named destination account matching another leg's subject
  /// account where both are the user's. Guessing from equal amounts on the same
  /// day is deliberately not done here — it would hide a genuine expense that
  /// happened to coincide with a genuine credit, and a silently missing expense
  /// is the one error the user cannot see.
  List<FinanceTxn> correlate(
    List<FinanceTxn> txns, {
    EndpointOwnership owns = _ownsNothing,
  }) {
    if (txns.length < 2) return txns;

    final groups = _DisjointSet(txns.length);
    _linkBySharedReference(txns, groups);
    _linkByEndpoint(txns, groups, owns);
    _linkPassThrough(txns, groups, owns);

    final internal = <int>{};
    final labelByRoot = <int, String>{};
    for (final members in groups.clusters()) {
      if (members.length < 2) continue;
      // A cluster is only a transfer if money both left and arrived. Two debits
      // sharing nothing but an amount are two payments.
      final hasDebit =
          members.any((i) => txns[i].direction == TxnDirection.debit);
      final hasCredit =
          members.any((i) => txns[i].direction == TxnDirection.credit);
      final anyRepayment = members.any((i) => txns[i].isInternalTransfer);
      if (!(hasDebit && hasCredit) && !anyRepayment) continue;

      internal.addAll(members);
      labelByRoot[groups.find(members.first)] = _groupId(txns, members);
    }

    if (internal.isEmpty) return txns;
    return [
      for (var i = 0; i < txns.length; i++)
        internal.contains(i)
            ? txns[i].copyWith(
                isInternalTransfer: true,
                isSalary: false,
                transferGroupId: labelByRoot[groups.find(i)],
              )
            : txns[i],
    ];
  }

  static bool _ownsNothing(TxnEndpoint? endpoint) => false;

  /// Rule 1 — one reference quoted by both sides. The strongest signal there is:
  /// a UTR identifies a single movement, so seeing it as both a debit and a
  /// credit means those are its two ends.
  void _linkBySharedReference(List<FinanceTxn> txns, _DisjointSet groups) {
    final byRef = <String, List<int>>{};
    for (var i = 0; i < txns.length; i++) {
      final ref = txns[i].refNo;
      if (ref == null || ref.isEmpty) continue;
      (byRef[ref] ??= <int>[]).add(i);
    }
    for (final indices in byRef.values) {
      for (final index in indices.skip(1)) {
        groups.union(indices.first, index);
      }
    }
  }

  /// Rule 2 — one leg says where the money went, another says it arrived there.
  ///
  /// This is what the reference-only rule could not do. Banks frequently omit
  /// the UTR on one side, and before this those transfers were counted as spend
  /// on one account and income on the other.
  void _linkByEndpoint(
    List<FinanceTxn> txns,
    _DisjointSet groups,
    EndpointOwnership owns,
  ) {
    for (var i = 0; i < txns.length; i++) {
      final outgoing = txns[i];
      final destination = outgoing.counterparty?.tail;
      if (outgoing.direction != TxnDirection.debit) continue;
      if (destination == null || destination.isEmpty) continue;
      // The paying account must be the user's, or this is an ordinary payment
      // to somebody else who happens to bank where the user does.
      if (!owns(outgoing.source)) continue;

      for (var j = 0; j < txns.length; j++) {
        if (i == j) continue;
        final incoming = txns[j];
        if (incoming.direction != TxnDirection.credit) continue;
        if (incoming.source?.tail != destination) continue;
        if (!owns(incoming.source)) continue;
        if (incoming.amount != outgoing.amount) continue;
        if (incoming.date.difference(outgoing.date).abs() > window) continue;
        groups.union(i, j);
      }
    }
  }

  /// Rule 3 — money that landed in an account and left it again on its way
  /// somewhere else.
  ///
  /// The middle hop of a card payment funded from another bank: the account is
  /// credited, then debited for the same amount towards the card. Deliberately
  /// narrow — it only links a debit ALREADY known to be a card repayment, on the
  /// user's own account, for the same amount, inside the window. Without those
  /// guards a salary credit followed by a same-size rent payment would be
  /// mistaken for a pass-through and the rent would vanish.
  void _linkPassThrough(
    List<FinanceTxn> txns,
    _DisjointSet groups,
    EndpointOwnership owns,
  ) {
    for (var i = 0; i < txns.length; i++) {
      final outgoing = txns[i];
      if (outgoing.direction != TxnDirection.debit) continue;
      if (!outgoing.isInternalTransfer) continue;
      final account = outgoing.source?.tail;
      if (account == null || !owns(outgoing.source)) continue;

      for (var j = 0; j < txns.length; j++) {
        if (i == j) continue;
        final incoming = txns[j];
        if (incoming.direction != TxnDirection.credit) continue;
        if (incoming.source?.tail != account) continue;
        if (incoming.amount != outgoing.amount) continue;
        if (outgoing.date.difference(incoming.date).abs() > window) continue;
        groups.union(i, j);
      }
    }
  }

  /// Stable id for a correlated set, derived from the movement itself so it is
  /// the same across re-scans: amount, day, and the reference when there is one.
  static String _groupId(List<FinanceTxn> txns, List<int> members) {
    final sorted = [...members]
      ..sort((a, b) => txns[a].date.compareTo(txns[b].date));
    final first = txns[sorted.first];
    final ref = txns.map((t) => t.refNo).firstWhere(
          (ref) => ref != null && ref.isNotEmpty,
          orElse: () => null,
        );
    if (ref != null) return 'ref:$ref';
    return 'sig:${first.amount}|'
        '${first.date.year}-${first.date.month}-${first.date.day}';
  }
}

/// Union-find, so legs chain transitively: bank A links to bank B, bank B links
/// to the card, and all three end up in one group without needing to compare A
/// against the card directly.
class _DisjointSet {
  _DisjointSet(int size) : _parent = List<int>.generate(size, (i) => i);

  final List<int> _parent;

  int find(int node) {
    var root = node;
    while (_parent[root] != root) {
      root = _parent[root];
    }
    // Path compression, so repeated lookups over a long chain stay cheap.
    var current = node;
    while (_parent[current] != root) {
      final next = _parent[current];
      _parent[current] = root;
      current = next;
    }
    return root;
  }

  void union(int a, int b) {
    final rootA = find(a);
    final rootB = find(b);
    if (rootA != rootB) _parent[rootB] = rootA;
  }

  Iterable<List<int>> clusters() {
    final byRoot = <int, List<int>>{};
    for (var i = 0; i < _parent.length; i++) {
      (byRoot[find(i)] ??= <int>[]).add(i);
    }
    return byRoot.values;
  }
}

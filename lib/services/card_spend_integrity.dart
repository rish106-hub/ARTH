import '../models/spend_map.dart';

/// Keeps a credit card's spending visible even when the issuer never itemises it.
///
/// Card purchases are the expense and the monthly bill is internal movement —
/// counting both would count the same money twice. That is right for the large
/// majority of cards, which alert on every purchase within seconds.
///
/// It is wrong for the minority that do not. For those, excluding the bill makes
/// the card's spending vanish completely: the user sees a card they clearly use
/// and a spend figure that ignores it, with nothing on screen to explain the
/// gap. Across millions of users that minority is a lot of people, and none of
/// them can be asked a setup question about it.
///
/// So: per card, per month, if a bill was paid and no purchase ever arrived,
/// count the bill instead. Marked [FinanceTxn.isLowDetailCardBill] so the UI can
/// say the amount is real but the breakdown is not available.
class CardSpendIntegrity {
  const CardSpendIntegrity();

  List<FinanceTxn> apply(List<FinanceTxn> txns) {
    // Only legs the card itself reported can be attributed to a card. The
    // bank-side leg of a bill payment names the card in prose, not as an
    // endpoint, so it is not a candidate here — and using it would double count
    // against the card's own acknowledgement.
    final purchaseMonths = <String>{};
    final billsByCardMonth = <String, List<int>>{};

    for (var i = 0; i < txns.length; i++) {
      final txn = txns[i];
      final card = txn.source;
      if (card?.kind != InstrumentKind.creditCard) continue;
      if (card?.tail == null) continue;
      if (txn.direction != TxnDirection.debit) continue;

      final key = '${card!.tail}|${txn.date.year}-${txn.date.month}';
      if (txn.isInternalTransfer) {
        (billsByCardMonth[key] ??= <int>[]).add(i);
      } else {
        purchaseMonths.add(key);
      }
    }

    final promote = <int>{};
    billsByCardMonth.forEach((key, bills) {
      if (purchaseMonths.contains(key)) return; // itemised, nothing to do
      // Several bills in one month means a part payment followed by the rest.
      // Counting only the largest would under-report, so all of them count —
      // together they are what actually left the user's pocket.
      promote.addAll(bills);
    });

    if (promote.isEmpty) return txns;
    return [
      for (var i = 0; i < txns.length; i++)
        promote.contains(i)
            ? txns[i].copyWith(
                isInternalTransfer: false,
                isLowDetailCardBill: true,
              )
            : txns[i],
    ];
  }
}

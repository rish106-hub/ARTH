import '../models/spend_map.dart';
import 'auth_service.dart';
import 'server_api_service.dart';

/// Best-effort backend sync for the spend map. The spend map is computed and
/// persisted locally first (see SpendMapNotifier); this only mirrors a summary
/// to the server when signed in. All failures are swallowed by callers — the
/// feature must work fully offline / before the backend route is deployed.
class SpendMapService {
  SpendMapService({ServerApiService? api, AuthService? auth})
      : _api = api ?? ServerApiService(),
        _auth = auth ?? AuthService();

  final ServerApiService _api;
  final AuthService _auth;

  Future<void> push(SpendMap map) async {
    final token = await _auth.getValidAccessToken();
    if (token == null) return;
    // This analytics route receives an aggregate summary. Full durable-state
    // backup is handled separately by DurableUserStateService.
    final salaryDates = map.txns
        .where((transaction) =>
            transaction.isSalary &&
            transaction.direction == TxnDirection.credit)
        .map((transaction) => transaction.date)
        .toList()
      ..sort((a, b) => b.compareTo(a));
    final scanCoversSixtyDays =
        map.windowEnd.difference(map.windowStart).inDays >= 60;
    await _api.postJson(
      '/spend-map',
      bearerToken: token,
      body: {
        // UTC so the ISO string carries a 'Z' offset the backend accepts.
        'windowStart': map.windowStart.toUtc().toIso8601String(),
        'windowEnd': map.windowEnd.toUtc().toIso8601String(),
        'generatedAt': map.generatedAt.toUtc().toIso8601String(),
        // Observed SMS/payslip figures only. Manual edits use durable state.
        'monthlyIncome': map.observedPrimaryMonthlyIncome,
        if (salaryDates.isNotEmpty) 'salaryCreditDay': salaryDates.first.day,
        if (salaryDates.isEmpty && scanCoversSixtyDays)
          'clearSalaryCreditDay': true,
        'incomeSource': map.primaryIncomeIsManual
            ? 'manual'
            : map.incomeIsDetected
                ? 'detected'
                : (map.observedPrimaryMonthlyIncome > 0 ? 'fallback' : 'none'),
        'monthlySpend': map.observedMonthlySpend,
        'monthlyEssentialSpend': map.monthlyEssentialSpend,
        'realisticMonthlySavings': map.observedRealisticMonthlySavings,
        'spendByCategory': map.spendByCategory,
        'monthlyTrend': map.monthlyTrend
            .map(
              (point) => {
                'month': point.month.toUtc().toIso8601String(),
                'spent': point.spent,
                'income': point.income,
              },
            )
            .toList(growable: false),
      },
    );
  }

  /// Hybrid categorization fallback. Sends one item per DISTINCT payee the
  /// on-device rules could not categorize and returns the resulting
  /// category/merchant guesses keyed by the caller's id.
  ///
  /// `text` is already redacted by the caller. `sender` is the bank's DLT header
  /// (`VM-HDFCBK`) and `amountBand` a coarse size band rather than the figure —
  /// both are signals the classifier needs to tell apart businesses that share a
  /// brand name, and neither identifies a person.
  ///
  /// Returns an empty map when signed out, when the backend or model is
  /// unavailable, when the shared spend cap is exhausted, or on any error —
  /// callers keep their on-device categories.
  Future<Map<String, AiCategoryGuess>> categorize(
    List<CategorizeItem> items,
  ) async {
    if (items.isEmpty) return const {};
    final token = await _auth.getValidAccessToken();
    if (token == null) return const {};
    try {
      final response = await _api.postJson(
        '/spend-map/categorize',
        bearerToken: token,
        body: {
          'items': items
              .map((it) => {
                    'id': it.id,
                    'text': it.text,
                    if (it.merchant != null) 'merchant': it.merchant,
                    if (it.sender != null) 'sender': it.sender,
                    if (it.amountBand != null) 'amountBand': it.amountBand,
                  })
              .toList(growable: false),
        },
      );
      final results = response['results'];
      if (results is! List) return const {};
      final out = <String, AiCategoryGuess>{};
      for (final raw in results) {
        if (raw is! Map) continue;
        final id = raw['id']?.toString();
        final category = raw['category']?.toString();
        if (id == null || category == null) continue;
        out[id] = AiCategoryGuess(
          category: category,
          merchant: raw['merchant']?.toString(),
          confidence: raw['confidence']?.toString() ?? 'low',
        );
      }
      return out;
    } catch (_) {
      return const {};
    }
  }
}

/// One distinct payee sent for classification. `id` is the caller's grouping
/// key, so the answer applies to every transaction with that payee.
typedef CategorizeItem = ({
  String id,
  String text,
  String? merchant,
  String? sender,
  String? amountBand,
});

/// An AI-suggested category for one transaction.
class AiCategoryGuess {
  const AiCategoryGuess({
    required this.category,
    required this.confidence,
    this.merchant,
  });

  final String category;
  final String? merchant;
  final String confidence; // high | medium | low
}

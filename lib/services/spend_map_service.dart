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
    // Sync an aggregate summary only — never raw message bodies.
    final salaryDates = map.txns
        .where((transaction) =>
            transaction.isSalary &&
            transaction.direction == TxnDirection.credit)
        .map((transaction) => transaction.date)
        .toList()
      ..sort((a, b) => b.compareTo(a));
    await _api.postJson(
      '/spend-map',
      bearerToken: token,
      body: {
        // UTC so the ISO string carries a 'Z' offset the backend accepts.
        'windowStart': map.windowStart.toUtc().toIso8601String(),
        'windowEnd': map.windowEnd.toUtc().toIso8601String(),
        'generatedAt': map.generatedAt.toUtc().toIso8601String(),
        // Observed SMS/payslip figures only — manual user edits stay on-device.
        'monthlyIncome': map.observedPrimaryMonthlyIncome,
        if (salaryDates.isNotEmpty) 'salaryCreditDay': salaryDates.first.day,
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

  /// Hybrid categorization fallback. Sends only the transactions the on-device
  /// rules could not categorize (as `{id, text}`, text already redacted by the
  /// caller) and returns the AI's category/merchant guesses keyed by id.
  ///
  /// Returns an empty map when signed out, when the backend/Gemini is
  /// unavailable, or on any error — callers keep their on-device categories.
  Future<Map<String, AiCategoryGuess>> categorize(
    List<({String id, String text})> items,
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
              .map((it) => {'id': it.id, 'text': it.text})
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

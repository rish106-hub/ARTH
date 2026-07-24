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
    await _api.postJson(
      '/spend-map',
      bearerToken: token,
      body: {
        'windowStart': map.windowStart.toIso8601String(),
        'windowEnd': map.windowEnd.toIso8601String(),
        'generatedAt': map.generatedAt.toIso8601String(),
        'monthlyIncome': map.monthlyIncome,
        'incomeSource': map.incomeIsDetected
            ? 'detected'
            : (map.monthlyIncome > 0 ? 'fallback' : 'none'),
        'monthlySpend': map.monthlySpend,
        'monthlyEssentialSpend': map.monthlyEssentialSpend,
        'realisticMonthlySavings': map.realisticMonthlySavings,
        'spendByCategory': map.spendByCategory,
        'monthlyTrend': map.monthlyTrend
            .map(
              (point) => {
                'month': point.month.toIso8601String(),
                'spent': point.spent,
                'income': point.income,
              },
            )
            .toList(growable: false),
      },
    );
  }
}

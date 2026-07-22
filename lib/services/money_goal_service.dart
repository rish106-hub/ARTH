import '../models/money_goal.dart';
import 'auth_service.dart';
import 'server_api_service.dart';

class MoneyGoalService {
  MoneyGoalService({ServerApiService? api, AuthService? auth})
      : _api = api ?? ServerApiService(),
        _auth = auth ?? AuthService();

  final ServerApiService _api;
  final AuthService _auth;

  Future<List<MoneyGoal>> fetchGoals() async {
    final token = await _auth.getValidAccessToken();
    if (token == null) return const [];
    final response = await _api.getJson('/money-goals', bearerToken: token);
    final goals = response['goals'] as List<dynamic>? ?? const [];
    return goals
        .whereType<Map<String, dynamic>>()
        .map(MoneyGoal.fromJson)
        .toList(growable: false);
  }

  Future<MoneyGoal> saveGoal(MoneyGoal goal) async {
    final token = await _auth.getValidAccessToken();
    if (token == null) throw StateError('not signed in');
    final response = goal.id.isEmpty
        ? await _api.postJson(
            '/money-goals',
            bearerToken: token,
            body: goal.toJson(),
          )
        : await _api.putJson(
            '/money-goals/${goal.id}',
            bearerToken: token,
            body: goal.toJson(),
          );
    return MoneyGoal.fromJson(response['goal'] as Map<String, dynamic>);
  }

  Future<void> deleteGoal(String id) async {
    final token = await _auth.getValidAccessToken();
    if (token == null) throw StateError('not signed in');
    await _api.delete('/money-goals/$id', bearerToken: token);
  }
}

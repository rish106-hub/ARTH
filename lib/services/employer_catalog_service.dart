import 'auth_service.dart';
import 'server_api_service.dart';

class EmployerCatalogService {
  EmployerCatalogService({ServerApiService? api, AuthService? auth})
      : _api = api ?? ServerApiService(),
        _auth = auth ?? AuthService();

  final ServerApiService _api;
  final AuthService _auth;

  Future<List<String>> search(String query) async {
    final response = await _api.getJson(
      '/employers?q=${Uri.encodeQueryComponent(query.trim())}',
    );
    return (response['employers'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<String> submit(String name) async {
    final token = await _auth.getValidAccessToken();
    if (token == null) throw StateError('not signed in');
    final response = await _api.postJson(
      '/employers',
      bearerToken: token,
      body: {'name': name.trim()},
    );
    return response['employer']?.toString() ?? name.trim();
  }
}

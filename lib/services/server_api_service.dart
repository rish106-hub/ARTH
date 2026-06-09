import 'dart:convert';
import 'dart:io';

class ServerApiException implements Exception {
  final int statusCode;
  final String message;

  const ServerApiException(this.statusCode, this.message);

  @override
  String toString() => 'ServerApiException($statusCode): $message';
}

class ServerApiService {
  static const String _defaultBaseUrl = 'https://arth-production-aaca.up.railway.app/v1';

  final HttpClient _client;
  final String _baseUrl;

  ServerApiService({
    HttpClient? client,
    String? baseUrl,
  })  : _client = client ?? HttpClient(),
        _baseUrl =
            baseUrl ?? const String.fromEnvironment('ARTH_API_BASE_URL', defaultValue: _defaultBaseUrl);

  Future<Map<String, dynamic>> getJson(
    String path, {
    String? bearerToken,
  }) async {
    final response = await _send(
      'GET',
      path,
      bearerToken: bearerToken,
    );
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    String? bearerToken,
  }) async {
    final response = await _send(
      'POST',
      path,
      body: body,
      bearerToken: bearerToken,
    );
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> putJson(
    String path, {
    Map<String, dynamic>? body,
    String? bearerToken,
  }) async {
    final response = await _send(
      'PUT',
      path,
      body: body,
      bearerToken: bearerToken,
    );
    return _decodeMap(response);
  }

  Future<void> postNoContent(
    String path, {
    Map<String, dynamic>? body,
    String? bearerToken,
  }) async {
    await _send(
      'POST',
      path,
      body: body,
      bearerToken: bearerToken,
    );
  }

  Future<void> delete(
    String path, {
    String? bearerToken,
  }) async {
    await _send('DELETE', path, bearerToken: bearerToken);
  }

  Future<String> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? bearerToken,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final request = await _client.openUrl(method, uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    if (bearerToken != null && bearerToken.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
    }
    if (body != null) {
      request.write(jsonEncode(body));
    }

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ServerApiException(
        response.statusCode,
        _extractMessage(responseBody),
      );
    }
    return responseBody;
  }

  Map<String, dynamic> _decodeMap(String raw) {
    if (raw.trim().isEmpty) return <String, dynamic>{};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  String _extractMessage(String raw) {
    if (raw.trim().isEmpty) return 'Request failed';
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded['message'] as String? ?? raw;
    } catch (_) {
      return raw;
    }
  }
}

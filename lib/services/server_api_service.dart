import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class ServerApiException implements Exception {
  final int statusCode;
  final String? code;
  final String message;
  final bool retryable;

  const ServerApiException(
    this.statusCode,
    this.message, {
    this.code,
    this.retryable = false,
  });

  @override
  String toString() => 'ServerApiException($statusCode): $message';
}

class ServerApiService {
  static const String _defaultBaseUrl =
      'https://arth-backend-production.up.railway.app/v1';
  static const Duration _requestTimeout = Duration(seconds: 15);
  static const Duration _documentUploadTimeout = Duration(minutes: 10);

  final HttpClient _client;
  final String _baseUrl;

  ServerApiService({HttpClient? client, String? baseUrl})
      : _client = client ?? HttpClient(),
        _baseUrl = baseUrl ??
            const String.fromEnvironment(
              'ARTH_API_BASE_URL',
              defaultValue: _defaultBaseUrl,
            ) {
    _client.connectionTimeout = _requestTimeout;
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    String? bearerToken,
  }) async {
    final response = await _send('GET', path, bearerToken: bearerToken);
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    String? bearerToken,
    bool retryTransient = false,
  }) async {
    final response = await _send(
      'POST',
      path,
      body: body,
      bearerToken: bearerToken,
      retryTransient: retryTransient,
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

  Future<Map<String, dynamic>> patchJson(
    String path, {
    Map<String, dynamic>? body,
    String? bearerToken,
  }) async {
    final response = await _send(
      'PATCH',
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
    await _send('POST', path, body: body, bearerToken: bearerToken);
  }

  Future<void> delete(String path, {String? bearerToken}) async {
    await _send('DELETE', path, bearerToken: bearerToken);
  }

  Future<Map<String, dynamic>> uploadMultipart(
    String path, {
    required String bearerToken,
    required Map<String, String> fields,
    required String fieldName,
    required String filename,
    required String contentType,
    required List<int> bytes,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final boundary = 'arth-${DateTime.now().microsecondsSinceEpoch}';
    final body = BytesBuilder(copy: false);

    void writeAscii(String value) => body.add(ascii.encode(value));

    for (final entry in fields.entries) {
      writeAscii('--$boundary\r\n');
      writeAscii(
        'content-disposition: form-data; name="${entry.key}"\r\n\r\n',
      );
      body.add(utf8.encode(entry.value));
      writeAscii('\r\n');
    }

    writeAscii('--$boundary\r\n');
    writeAscii(
      'content-disposition: form-data; name="$fieldName"; filename="$filename"\r\n',
    );
    writeAscii('content-type: $contentType\r\n\r\n');
    body.add(bytes);
    writeAscii('\r\n--$boundary--\r\n');
    final bodyBytes = body.takeBytes();

    try {
      final request =
          await _client.openUrl('POST', uri).timeout(_documentUploadTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers
          .set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response = await request.close().timeout(_documentUploadTimeout);
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_documentUploadTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final details = _extractErrorDetails(responseBody);
        throw ServerApiException(
          response.statusCode,
          details.message,
          code: details.code,
          retryable: details.retryable || response.statusCode >= 500,
        );
      }
      return _decodeMap(responseBody);
    } on TimeoutException {
      throw const ServerApiException(
        0,
        'Document parsing took too long. Please try the upload again.',
        code: 'document_upload_timeout',
        retryable: true,
      );
    } on SocketException {
      throw const ServerApiException(
        0,
        'Cannot reach ARTH. Please try again.',
        code: 'network_unreachable',
        retryable: true,
      );
    } on HandshakeException {
      throw const ServerApiException(
        0,
        'Could not establish a secure connection to ARTH. Please try again.',
        code: 'secure_connection_failed',
        retryable: true,
      );
    } on HttpException {
      throw const ServerApiException(
        0,
        'The upload connection closed unexpectedly. Please try again.',
        code: 'upload_connection_closed',
        retryable: true,
      );
    }
  }

  Future<String> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? bearerToken,
    bool retryTransient = false,
  }) async {
    final maxAttempts = retryTransient ? 2 : 1;
    for (var attempt = 0; attempt < maxAttempts; attempt += 1) {
      try {
        return await _sendOnce(
          method,
          path,
          body: body,
          bearerToken: bearerToken,
        );
      } on ServerApiException catch (error) {
        if (attempt + 1 >= maxAttempts || !error.retryable) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
    }
    throw const ServerApiException(0, 'Network request failed');
  }

  Future<String> _sendOnce(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? bearerToken,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    late final HttpClientRequest request;
    try {
      request = await _client.openUrl(method, uri).timeout(_requestTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (bearerToken != null && bearerToken.isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $bearerToken',
        );
      }
      if (body != null) {
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(_requestTimeout);
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final details = _extractErrorDetails(responseBody);
        throw ServerApiException(
          response.statusCode,
          details.message,
          code: details.code,
          retryable: details.retryable || response.statusCode >= 500,
        );
      }
      return responseBody;
    } on TimeoutException {
      throw const ServerApiException(
        0,
        'Network request timed out',
        code: 'network_timeout',
        retryable: true,
      );
    } on SocketException {
      throw const ServerApiException(
        0,
        'Cannot reach ARTH',
        code: 'network_unreachable',
        retryable: true,
      );
    }
  }

  Map<String, dynamic> _decodeMap(String raw) {
    if (raw.trim().isEmpty) return <String, dynamic>{};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  _ApiErrorDetails _extractErrorDetails(String raw) {
    if (raw.trim().isEmpty) {
      return const _ApiErrorDetails(message: 'Request failed');
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return _ApiErrorDetails(
        message: decoded['message'] as String? ?? raw,
        code: decoded['code'] as String?,
        retryable: decoded['retryable'] == true,
      );
    } catch (_) {
      return _ApiErrorDetails(message: raw);
    }
  }
}

class _ApiErrorDetails {
  final String message;
  final String? code;
  final bool retryable;

  const _ApiErrorDetails({
    required this.message,
    this.code,
    this.retryable = false,
  });
}

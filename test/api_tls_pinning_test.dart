import 'package:arth/services/api_tls_pinning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production host requires a pinned leaf certificate', () {
    final uri = Uri.https(ApiTlsPinning.productionHost, '/v1/health');
    expect(ApiTlsPinning.requiresPin(uri), isTrue);
  });

  test('localhost and loopback skip pinning', () {
    expect(ApiTlsPinning.requiresPin(Uri.http('localhost', '/v1/health')),
        isFalse);
    expect(ApiTlsPinning.requiresPin(Uri.http('127.0.0.1', '/v1/health')),
        isFalse);
    expect(
        ApiTlsPinning.requiresPin(Uri.http('10.0.2.2', '/v1/health')), isFalse);
  });
}

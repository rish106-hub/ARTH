import 'dart:io';

import 'package:crypto/crypto.dart';

/// TLS pinning for the production ARTH API host.
///
/// Pins the leaf certificate SHA-256 fingerprint. Add a backup pin before the
/// current certificate expires, then remove the old pin after rotation.
class ApiTlsPinning {
  ApiTlsPinning._();

  static const productionHost = 'arth-backend-production.up.railway.app';

  /// Lowercase hex SHA-256 fingerprints of permitted leaf certificates.
  static const productionLeafPins = <String>{
    'e7a672949860b929a790f82dd2150d1a3fc08c5a823a6d0fc7f3a63b959d0511',
  };

  static const _disabled = bool.fromEnvironment(
    'ARTH_DISABLE_TLS_PINNING',
    defaultValue: false,
  );

  static bool requiresPin(Uri uri) {
    if (_disabled || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2') {
      return false;
    }
    return host == productionHost;
  }

  static bool matchesPinnedLeaf(X509Certificate cert) {
    final digest = sha256.convert(cert.der).toString();
    return productionLeafPins.contains(digest);
  }

  static void configure(HttpClient client) {
    client.connectionFactory = (uri, proxyHost, proxyPort) {
      if (uri.scheme == 'http') {
        return Socket.startConnect(uri.host, uri.port);
      }
      if (!requiresPin(uri)) {
        return SecureSocket.startConnect(uri.host, uri.port);
      }
      return _pinnedConnect(uri);
    };
  }

  static Future<ConnectionTask<Socket>> _pinnedConnect(Uri uri) async {
    final socket = await SecureSocket.connect(uri.host, uri.port);
    final cert = socket.peerCertificate;
    if (cert == null || !matchesPinnedLeaf(cert)) {
      socket.destroy();
      throw HandshakeException(
        'TLS certificate pin mismatch for ${uri.host}',
      );
    }
    return ConnectionTask.fromSocket(
      Future<Socket>.value(socket),
      socket.destroy,
    );
  }
}

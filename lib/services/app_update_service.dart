import 'package:flutter/services.dart';

class AppUpdateException implements Exception {
  final String code;
  final String message;

  const AppUpdateException(this.code, this.message);
}

class AppUpdateService {
  static const _channel = MethodChannel('com.arth.taxgap/app_updates');

  const AppUpdateService();

  Future<void> checkForUpdates() async {
    try {
      await _channel.invokeMethod<void>('checkForUpdates');
    } on PlatformException catch (error) {
      throw AppUpdateException(
        error.code,
        error.message ?? 'Could not check for updates.',
      );
    }
  }
}

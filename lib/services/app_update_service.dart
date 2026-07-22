import 'package:flutter/services.dart';

class AppUpdateException implements Exception {
  final String code;
  final String message;

  const AppUpdateException(this.code, this.message);
}

class AppUpdateInfo {
  final bool isAvailable;
  final int currentVersionCode;
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String sha256;
  final String releaseNotes;

  const AppUpdateInfo({
    required this.isAvailable,
    required this.currentVersionCode,
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.sha256,
    required this.releaseNotes,
  });

  factory AppUpdateInfo.fromMap(Map<Object?, Object?> map) {
    return AppUpdateInfo(
      isAvailable: map['status'] == 'available',
      currentVersionCode: (map['currentVersionCode'] as num?)?.toInt() ?? 0,
      versionCode: (map['versionCode'] as num?)?.toInt() ?? 0,
      versionName: map['versionName'] as String? ?? '',
      apkUrl: map['apkUrl'] as String? ?? '',
      sha256: map['sha256'] as String? ?? '',
      releaseNotes: map['releaseNotes'] as String? ?? '',
    );
  }
}

class AppUpdateService {
  static const _channel = MethodChannel('com.arth.taxgap/app_updates');

  const AppUpdateService();

  Future<AppUpdateInfo> checkForUpdates() async {
    try {
      final response = await _channel.invokeMethod<Map<Object?, Object?>>(
        'checkForUpdates',
      );
      if (response == null) {
        throw const AppUpdateException(
          'INVALID_UPDATE',
          'The update server returned an empty response.',
        );
      }
      return AppUpdateInfo.fromMap(response);
    } on PlatformException catch (error) {
      throw AppUpdateException(
        error.code,
        error.message ?? 'Could not check for updates.',
      );
    }
  }

  Future<void> downloadAndInstall(AppUpdateInfo update) async {
    try {
      await _channel.invokeMethod<Map<Object?, Object?>>(
        'downloadAndInstallUpdate',
        {
          'versionCode': update.versionCode,
          'apkUrl': update.apkUrl,
          'sha256': update.sha256,
        },
      );
    } on PlatformException catch (error) {
      throw AppUpdateException(
        error.code,
        error.message ?? 'Could not install the update.',
      );
    }
  }
}

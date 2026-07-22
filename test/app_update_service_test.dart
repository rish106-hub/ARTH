import 'package:arth/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a verified update manifest response', () {
    final update = AppUpdateInfo.fromMap({
      'status': 'available',
      'currentVersionCode': 10001,
      'versionCode': 10002,
      'versionName': '1.0.2',
      'apkUrl': 'https://github.com/example/app.apk',
      'sha256': 'a' * 64,
      'releaseNotes': 'Reliability fixes.',
    });

    expect(update.isAvailable, isTrue);
    expect(update.currentVersionCode, 10001);
    expect(update.versionCode, 10002);
    expect(update.versionName, '1.0.2');
    expect(update.releaseNotes, 'Reliability fixes.');
  });

  test('marks the current release as up to date', () {
    final update = AppUpdateInfo.fromMap({
      'status': 'current',
      'currentVersionCode': 10002,
      'versionCode': 10002,
      'versionName': '1.0.2',
      'apkUrl': 'https://github.com/example/app.apk',
      'sha256': 'b' * 64,
      'releaseNotes': '',
    });

    expect(update.isAvailable, isFalse);
  });
}

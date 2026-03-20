// ─────────────────────────────────────────────────────────────────────────────
// ARTH Firebase Options — project: arth-tax-gap
//
// To regenerate after adding iOS or other platforms:
//   dart pub global activate flutterfire_cli
//   flutterfire configure --project=arth-tax-gap
// ─────────────────────────────────────────────────────────────────────────────

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web not supported');
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions not configured for $defaultTargetPlatform. '
          'Run: flutterfire configure --project=arth-tax-gap',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBmRSGRPrny9mnJtLxupQ1sdS2pBOg-CSU',
    appId: '1:101289118169:android:c77fee1e94aa0c29f2b1c8',
    messagingSenderId: '101289118169',
    projectId: 'arth-tax-gap',
    storageBucket: 'arth-tax-gap.firebasestorage.app',
    // Web OAuth client (used by Google Sign-In on Android)
    androidClientId: '101289118169-j0io6jjcdf947ss7bdfpjovk4dacfr4d.apps.googleusercontent.com',
  );
}

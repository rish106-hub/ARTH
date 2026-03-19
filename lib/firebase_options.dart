// ─────────────────────────────────────────────────────────────────────────────
// ARTH Firebase Options
//
// Generated values from Firebase project: collprep-51b6d
// Android app: com.arth.taxgap (ARTH)
//
// To regenerate (e.g. after adding iOS):
//   dart pub global activate flutterfire_cli
//   flutterfire configure --project=collprep-51b6d
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
          'Run: flutterfire configure --project=collprep-51b6d',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC40edMSuds_ucp3caWurPrqNEQPNgPqkU',
    appId: '1:237352355014:android:3ee36e965c0fa0969583c7',
    messagingSenderId: '237352355014',
    projectId: 'collprep-51b6d',
    storageBucket: 'collprep-51b6d.firebasestorage.app',
  );
}

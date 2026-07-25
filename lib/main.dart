import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'firebase_options.dart';
import 'services/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Immersive status bar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Local-notification display + background handler registration. Per-user
    // token sync (permission request + backend registration) happens once
    // signed in, via authProvider (see push_notification_service.dart).
    await pushNotificationService.init(onOpenRoute: appRouter.go);
  } catch (e) {
    if (kDebugMode) debugPrint('[main] Firebase init skipped: $e');
  }

  runApp(const ProviderScope(child: ArthApp()));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    pushNotificationService.openPendingNotification();
  });
}

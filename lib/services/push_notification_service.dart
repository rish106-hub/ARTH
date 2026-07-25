import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'server_api_service.dart';

/// Must be a top-level (or static) function: the platform invokes this in a
/// separate background isolate when a data/notification message arrives while
/// the app is backgrounded or terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

String? notificationRouteForData(Map<String, dynamic> data) {
  return switch (data['screen']) {
    'spend-map' => '/spend-map',
    _ => null,
  };
}

final pushNotificationService = PushNotificationService();

/// Wraps FCM token lifecycle + local display of foreground pushes. Kept free
/// of Riverpod so it can be constructed once in main() before the widget tree
/// (and its providers) exist.
class PushNotificationService {
  PushNotificationService({ServerApiService? api})
      : _api = api ?? ServerApiService();

  final ServerApiService _api;
  final _localNotifications = FlutterLocalNotificationsPlugin();
  static const _channel = AndroidNotificationChannel(
    'arth_default',
    'ARTH alerts',
    description: 'Spend alerts, reminders, and account notifications.',
    importance: Importance.high,
  );

  String? _lastRegisteredToken;
  String? _activeBearerToken;
  StreamSubscription<String>? _tokenRefreshSubscription;
  void Function(String route)? _onOpenRoute;
  String? _pendingRoute;
  bool _initialized = false;

  /// Initializes local-notification display and background handling. Safe to
  /// call once at startup regardless of sign-in state; does not request
  /// permission or register a token (that happens per-user, see [syncToken]).
  Future<void> init({
    required void Function(String route) onOpenRoute,
  }) async {
    _onOpenRoute = onOpenRoute;
    if (_initialized) return;
    _initialized = true;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        final route = response.payload;
        if (route != null && route.startsWith('/')) _openRoute(route);
      },
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Foreground messages don't auto-display on Android; show them via the
    // local-notifications channel so the user sees alerts while the app is open.
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final route = notificationRouteForData(message.data);
      if (route != null) _openRoute(route);
    });
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    _pendingRoute = initialMessage == null
        ? null
        : notificationRouteForData(initialMessage.data);
  }

  void _openRoute(String route) {
    final onOpenRoute = _onOpenRoute;
    if (onOpenRoute == null) {
      _pendingRoute = route;
      return;
    }
    onOpenRoute(route);
  }

  void openPendingNotification() {
    final route = _pendingRoute;
    _pendingRoute = null;
    if (route != null) _openRoute(route);
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      payload: notificationRouteForData(message.data),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  /// Requests notification permission (no-ops if already granted/denied) and
  /// registers the current FCM token with the backend for [bearerToken]'s
  /// user. Call after sign-in and on token refresh. Best-effort: swallows all
  /// errors so a push-registration failure never blocks sign-in.
  Future<void> syncToken(String bearerToken) async {
    try {
      _activeBearerToken = bearerToken;
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _registerToken(token, bearerToken);

      _tokenRefreshSubscription ??=
          FirebaseMessaging.instance.onTokenRefresh.listen((refreshed) {
        final activeBearerToken = _activeBearerToken;
        if (activeBearerToken != null) {
          unawaited(_registerToken(refreshed, activeBearerToken));
        }
      });
    } catch (error) {
      if (kDebugMode) debugPrint('[push] syncToken failed: $error');
    }
  }

  Future<void> _registerToken(String token, String bearerToken) async {
    if (token == _lastRegisteredToken) return;
    try {
      await _api.postJson(
        '/devices',
        bearerToken: bearerToken,
        body: {
          'fcmToken': token,
          'platform':
              defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        },
      );
      _lastRegisteredToken = token;
    } catch (error) {
      if (kDebugMode) debugPrint('[push] token registration failed: $error');
    }
  }

  /// Unregisters this device's token, e.g. right before sign-out. Best-effort.
  Future<void> unregister(String bearerToken) async {
    _activeBearerToken = null;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _api.delete(
        '/devices',
        body: {'fcmToken': token},
        bearerToken: bearerToken,
      );
      _lastRegisteredToken = null;
    } catch (error) {
      if (kDebugMode) debugPrint('[push] unregister failed: $error');
    }
  }
}

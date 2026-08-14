import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/analytics_service.dart';

/// Single analytics entry point for the whole app.
///
/// Overridden in tests with a recording sink, so instrumentation can be
/// asserted without a Firebase app:
///
/// ```dart
/// ProviderScope(overrides: [
///   analyticsProvider.overrideWithValue(AnalyticsService(sink: recorder)),
/// ])
/// ```
final analyticsProvider = Provider<AnalyticsService>(
  (ref) => const AnalyticsService(),
);

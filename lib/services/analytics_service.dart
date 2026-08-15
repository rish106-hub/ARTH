import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Where product events go.
///
/// Swapped in tests so instrumentation can be asserted without a Firebase app.
abstract interface class AnalyticsSink {
  Future<void> send(String name, Map<String, Object> parameters);
}

/// Sends to Firebase Analytics, and does nothing when Firebase is unavailable.
///
/// Analytics must never be the reason a user action fails, so every failure is
/// swallowed and the app carries on reporting nothing.
class FirebaseAnalyticsSink implements AnalyticsSink {
  const FirebaseAnalyticsSink();

  @override
  Future<void> send(String name, Map<String, Object> parameters) async {
    if (Firebase.apps.isEmpty) return;
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: name,
        parameters: parameters,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Analytics] dropped $name: $e');
    }
  }
}

/// Collects events, and drops them. Useful in tests and for a local build that
/// should not report.
class NoopAnalyticsSink implements AnalyticsSink {
  const NoopAnalyticsSink();

  @override
  Future<void> send(String name, Map<String, Object> parameters) async {}
}

/// Product events for the Tier-1 measurement plan.
///
/// **Privacy contract.** No method here accepts a rupee amount, a merchant
/// name, a date, a free-text label, or an identifier. Counts go through
/// [countBucket] so an event describes scale without describing the user, and
/// every other parameter is a fixed enum or a boolean. That is enforced by the
/// method signatures rather than by review: there is no way to pass a raw value
/// in. Keep it that way — the whole reason this is safe to enable by default is
/// that it cannot carry financial data off the device.
class AnalyticsService {
  const AnalyticsService({AnalyticsSink sink = const FirebaseAnalyticsSink()})
      : _sink = sink;

  final AnalyticsSink _sink;

  // ── Workday Cost Lens ────────────────────────────────────────────────────

  /// How many candidates the lens surfaced. Answers whether the >=3-transaction
  /// threshold leaves anyone with nothing to act on.
  Future<void> workCostCandidatesShown(int count) => _sink.send(
        'work_cost_candidates_shown',
        {'count_bucket': countBucket(count)},
      );

  Future<void> workCostTagConfirmed(
    WorkCostAnalyticsKind kind, {
    required bool hasAlternativeCost,
  }) =>
      _sink.send('work_cost_tag_confirmed', {
        'work_kind': kind.eventValue,
        'has_alternative': _flag(hasAlternativeCost),
      });

  Future<void> workCostTagRemoved() => _sink.send('work_cost_tag_removed', {});

  Future<void> workCostPatternDismissed() =>
      _sink.send('work_cost_pattern_dismissed', {});

  /// The user committed to spending less on one tagged repeat cost.
  ///
  /// This is the event that separates reading the lens from acting on it, so it
  /// carries only what kind of cost was chosen — never the saving on offer.
  Future<void> workCostExperimentStarted(WorkCostAnalyticsKind kind) => _sink
      .send('work_cost_experiment_started', {'work_kind': kind.eventValue});

  /// The user judged a running experiment. [kept] false means they stopped it.
  ///
  /// Paired with [workCostExperimentStarted], this is what tells us whether the
  /// lens changes behaviour or is merely read. How long it ran is bucketed,
  /// since the exact figure would place the user on a calendar.
  Future<void> workCostExperimentDecided(
    WorkCostAnalyticsKind kind, {
    required bool kept,
    required int daysRunning,
  }) =>
      _sink.send('work_cost_experiment_decided', {
        'work_kind': kind.eventValue,
        'outcome': kept ? 'kept' : 'stopped',
        'ran_for': experimentAgeBucket(daysRunning),
      });

  // ── Monthly commitments ──────────────────────────────────────────────────

  Future<void> commitmentSaved({
    required bool isNew,
    required bool isManual,
  }) =>
      _sink.send('commitment_saved', {
        'is_new': _flag(isNew),
        'source': isManual ? 'manual' : 'detected',
      });

  Future<void> commitmentRemoved() => _sink.send('commitment_removed', {});

  // ── Decision Sandbox ─────────────────────────────────────────────────────

  /// [goalFinishChangeMonths] is null when no valid money goal is selected, in
  /// which case the scenario had no projection to shift.
  Future<void> decisionScenarioSaved({
    required DecisionAnalyticsKind kind,
    required bool isNew,
    required int? goalFinishChangeMonths,
  }) =>
      _sink.send('decision_scenario_saved', {
        'decision_kind': kind.eventValue,
        'is_new': _flag(isNew),
        'goal_shift': goalShiftBucket(goalFinishChangeMonths),
      });

  // ── SMS scan ─────────────────────────────────────────────────────────────

  Future<void> smsScanStarted(String periodLabel) =>
      _sink.send('sms_scan_started', {'period': periodLabel});

  Future<void> smsScanCompleted({
    required String periodLabel,
    required int transactionCount,
  }) =>
      _sink.send('sms_scan_completed', {
        'period': periodLabel,
        'count_bucket': countBucket(transactionCount),
      });

  Future<void> smsScanFailed(String periodLabel) =>
      _sink.send('sms_scan_failed', {'period': periodLabel});

  static String _flag(bool value) => value ? 'yes' : 'no';
}

/// Buckets a count so the event describes scale, not the individual.
@visibleForTesting
String countBucket(int count) {
  if (count <= 0) return 'none';
  if (count < 5) return '1_4';
  if (count < 20) return '5_19';
  if (count < 50) return '20_49';
  if (count < 200) return '50_199';
  return '200_plus';
}

/// How long an experiment ran, in ranges rather than days.
///
/// A day count plus an event timestamp would reconstruct the start date, which
/// the privacy contract keeps off the wire, so the buckets are deliberately
/// coarse. They still answer the question that matters: whether people quit
/// within days or gave the change a real month.
@visibleForTesting
String experimentAgeBucket(int days) {
  if (days <= 0) return 'same_day';
  if (days < 7) return 'under_week';
  if (days < 28) return 'under_month';
  return 'month_plus';
}

/// Direction and rough size of a money-goal date shift, never the exact months.
///
/// `no_goal` and `unchanged` are kept apart on purpose: the first says the user
/// never picked a goal, the second says the decision genuinely did not move it.
@visibleForTesting
String goalShiftBucket(int? months) {
  if (months == null) return 'no_goal';
  if (months == 0) return 'unchanged';
  final magnitude = months.abs() < 3 ? 'small' : 'large';
  return months < 0 ? 'earlier_$magnitude' : 'later_$magnitude';
}

/// Mirrors `WorkCostKind` without importing the feature, so the shared service
/// stays independent of feature internals.
enum WorkCostAnalyticsKind {
  commute,
  officeMeals,
  coffeeAndSnacks,
  workTools,
  workSocial,
  other;

  String get eventValue => switch (this) {
        WorkCostAnalyticsKind.commute => 'commute',
        WorkCostAnalyticsKind.officeMeals => 'office_meals',
        WorkCostAnalyticsKind.coffeeAndSnacks => 'coffee_and_snacks',
        WorkCostAnalyticsKind.workTools => 'work_tools',
        WorkCostAnalyticsKind.workSocial => 'work_social',
        WorkCostAnalyticsKind.other => 'other',
      };
}

/// Mirrors `DecisionKind`, for the same reason as [WorkCostAnalyticsKind].
enum DecisionAnalyticsKind {
  moveForWork,
  buyVehicle,
  changeJobs;

  String get eventValue => switch (this) {
        DecisionAnalyticsKind.moveForWork => 'move_for_work',
        DecisionAnalyticsKind.buyVehicle => 'buy_vehicle',
        DecisionAnalyticsKind.changeJobs => 'change_jobs',
      };
}

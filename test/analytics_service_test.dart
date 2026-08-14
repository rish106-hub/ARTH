import 'package:arth/services/analytics_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingSink implements AnalyticsSink {
  final events = <(String, Map<String, Object>)>[];

  @override
  Future<void> send(String name, Map<String, Object> parameters) async {
    events.add((name, parameters));
  }
}

void main() {
  late _RecordingSink sink;
  late AnalyticsService analytics;

  setUp(() {
    sink = _RecordingSink();
    analytics = AnalyticsService(sink: sink);
  });

  group('countBucket', () {
    test('describes scale without the exact number', () {
      expect(countBucket(0), 'none');
      expect(countBucket(-3), 'none');
      expect(countBucket(1), '1_4');
      expect(countBucket(4), '1_4');
      expect(countBucket(5), '5_19');
      expect(countBucket(19), '5_19');
      expect(countBucket(20), '20_49');
      expect(countBucket(49), '20_49');
      expect(countBucket(50), '50_199');
      expect(countBucket(199), '50_199');
      expect(countBucket(200), '200_plus');
      expect(countBucket(98123), '200_plus');
    });
  });

  group('goalShiftBucket', () {
    test('keeps "no goal chosen" apart from "goal did not move"', () {
      expect(goalShiftBucket(null), 'no_goal');
      expect(goalShiftBucket(0), 'unchanged');
    });

    test('records direction and rough size, never the month count', () {
      expect(goalShiftBucket(-1), 'earlier_small');
      expect(goalShiftBucket(-2), 'earlier_small');
      expect(goalShiftBucket(-3), 'earlier_large');
      expect(goalShiftBucket(-40), 'earlier_large');
      expect(goalShiftBucket(1), 'later_small');
      expect(goalShiftBucket(3), 'later_large');
    });
  });

  group('events', () {
    test('work cost tag carries the kind and whether a comparison was set',
        () async {
      await analytics.workCostTagConfirmed(
        WorkCostAnalyticsKind.officeMeals,
        hasAlternativeCost: true,
      );

      expect(sink.events.single.$1, 'work_cost_tag_confirmed');
      expect(sink.events.single.$2, {
        'work_kind': 'office_meals',
        'has_alternative': 'yes',
      });
    });

    test('commitment save distinguishes a new one from an edit', () async {
      await analytics.commitmentSaved(isNew: false, isManual: true);

      expect(sink.events.single.$2, {'is_new': 'no', 'source': 'manual'});
    });

    test('decision scenario reports the goal shift as a bucket', () async {
      await analytics.decisionScenarioSaved(
        kind: DecisionAnalyticsKind.buyVehicle,
        isNew: true,
        goalFinishChangeMonths: 7,
      );

      expect(sink.events.single.$1, 'decision_scenario_saved');
      expect(sink.events.single.$2, {
        'decision_kind': 'buy_vehicle',
        'is_new': 'yes',
        'goal_shift': 'later_large',
      });
    });

    test('scan completion buckets the transaction count', () async {
      await analytics.smsScanCompleted(
        periodLabel: 'sixMonths',
        transactionCount: 412,
      );

      expect(sink.events.single.$2, {
        'period': 'sixMonths',
        'count_bucket': '200_plus',
      });
    });
  });

  group('privacy contract', () {
    /// The service is safe to enable by default only because no method can
    /// carry a rupee amount, a merchant, a date or an id. Anything numeric that
    /// does get in must have been bucketed into a label first.
    test('no event parameter is a raw number', () async {
      await analytics.workCostCandidatesShown(37);
      await analytics.workCostTagConfirmed(
        WorkCostAnalyticsKind.commute,
        hasAlternativeCost: false,
      );
      await analytics.workCostTagRemoved();
      await analytics.workCostPatternDismissed();
      await analytics.commitmentSaved(isNew: true, isManual: true);
      await analytics.commitmentRemoved();
      await analytics.decisionScenarioSaved(
        kind: DecisionAnalyticsKind.changeJobs,
        isNew: true,
        goalFinishChangeMonths: 14,
      );
      await analytics.smsScanStarted('oneMonth');
      await analytics.smsScanCompleted(
        periodLabel: 'oneMonth',
        transactionCount: 88,
      );
      await analytics.smsScanFailed('oneMonth');

      expect(sink.events, hasLength(10));
      for (final (name, parameters) in sink.events) {
        for (final entry in parameters.entries) {
          expect(
            entry.value,
            isA<String>(),
            reason: '$name.${entry.key} must be a bucketed or enumerated '
                'label, never a raw value',
          );
          expect(
            int.tryParse(entry.value as String),
            isNull,
            reason: '$name.${entry.key} parses as a bare number, which is how '
                'an amount or a count leaks',
          );
        }
      }
    });

    test('event and parameter names stay inside Firebase limits', () async {
      await analytics.workCostCandidatesShown(3);
      await analytics.decisionScenarioSaved(
        kind: DecisionAnalyticsKind.moveForWork,
        isNew: false,
        goalFinishChangeMonths: null,
      );

      for (final (name, parameters) in sink.events) {
        expect(name.length, lessThanOrEqualTo(40));
        expect(name, matches(RegExp(r'^[a-z][a-z0-9_]*$')));
        expect(parameters.length, lessThanOrEqualTo(25));
        for (final key in parameters.keys) {
          expect(key.length, lessThanOrEqualTo(40));
          expect((parameters[key] as String).length, lessThanOrEqualTo(100));
        }
      }
    });
  });

  test('the noop sink drops everything', () async {
    const quiet = AnalyticsService(sink: NoopAnalyticsSink());
    await quiet.workCostTagRemoved();
    // Nothing to assert beyond it not throwing: the point is that a build with
    // no reporting configured behaves exactly like one with it.
  });
}

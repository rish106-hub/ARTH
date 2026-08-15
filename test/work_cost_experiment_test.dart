import 'dart:convert';

import 'package:arth/features/work_costs/models/work_cost_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The "one less each workweek" suggestion is only measurable if the user's
/// commitment survives a restart, so these tests guard the state, not the copy.
void main() {
  final started = DateTime(2026, 8, 1, 9);

  WorkCostState stateWith(WorkCostExperiment experiment) => const WorkCostState(
        tags: {
          'work_cost_food_canteen': WorkCostTag(
            candidateId: 'work_cost_food_canteen',
            kind: WorkCostKind.officeMeals,
          ),
        },
      ).withExperiment(experiment);

  WorkCostExperiment running() => WorkCostExperiment(
        candidateId: 'work_cost_food_canteen',
        status: WorkCostExperimentStatus.running,
        monthlyTarget: 1300,
        startedAt: started,
      );

  group('WorkCostExperiment', () {
    test('runs until decided, then freezes its length', () {
      final experiment = running();

      expect(experiment.status.isDecided, isFalse);
      expect(experiment.daysRunning(started.add(const Duration(days: 5))), 5);

      final kept = experiment.decide(
        WorkCostExperimentStatus.kept,
        started.add(const Duration(days: 30)),
      );

      expect(kept.status.isDecided, isTrue);
      expect(kept.daysRunning(started.add(const Duration(days: 400))), 30);
    });

    test('keeps the target promised at the start', () {
      final stopped = running().decide(
        WorkCostExperimentStatus.stopped,
        started.add(const Duration(days: 2)),
      );

      expect(stopped.monthlyTarget, 1300);
    });

    test('survives a save and load', () {
      final decided = running().decide(
        WorkCostExperimentStatus.kept,
        started.add(const Duration(days: 12)),
      );
      final restored = WorkCostState.fromJson(
        jsonDecode(jsonEncode(stateWith(decided).toJson()))
            as Map<String, dynamic>,
      );

      final experiment = restored.experiments['work_cost_food_canteen']!;
      expect(experiment.status, WorkCostExperimentStatus.kept);
      expect(experiment.monthlyTarget, 1300);
      expect(experiment.startedAt, started);
      expect(experiment.daysRunning(DateTime(2027)), 12);
    });

    test('drops stored state with no candidate or no start date', () {
      expect(WorkCostExperiment.fromJson(const {'status': 'kept'}), isNull);
      expect(
        WorkCostExperiment.fromJson({
          'candidateId': 'work_cost_food_canteen',
          'startedAt': 'not-a-date',
        }),
        isNull,
      );
    });

    test('treats an unreadable status as still running', () {
      final experiment = WorkCostExperiment.fromJson({
        'candidateId': 'work_cost_food_canteen',
        'status': 'abandoned_by_a_future_version',
        'startedAt': started.toIso8601String(),
      });

      expect(experiment!.status, WorkCostExperimentStatus.running);
    });
  });

  group('WorkCostState', () {
    test('removing the work tag removes the experiment with it', () {
      final state = stateWith(running()).withoutTag('work_cost_food_canteen');

      expect(state.tags, isEmpty);
      expect(state.experiments, isEmpty);
    });

    test('one candidate holds one experiment', () {
      final state = stateWith(running()).withExperiment(
        running().decide(
          WorkCostExperimentStatus.stopped,
          started.add(const Duration(days: 1)),
        ),
      );

      expect(state.experiments, hasLength(1));
      expect(
        state.experiments['work_cost_food_canteen']!.status,
        WorkCostExperimentStatus.stopped,
      );
    });

    test('tagging and dismissing leave existing experiments alone', () {
      final tagged = stateWith(running()).withTag(const WorkCostTag(
        candidateId: 'work_cost_travel_metro',
        kind: WorkCostKind.commute,
      ));

      expect(tagged.experiments, hasLength(1));
      expect(
          tagged.dismiss('work_cost_travel_metro').experiments, hasLength(1));
    });
  });
}

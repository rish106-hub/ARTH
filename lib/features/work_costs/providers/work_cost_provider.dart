import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/analytics_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/analytics_service.dart';
import '../../../services/secure_storage_service.dart';
import '../../../services/user_scoped_storage.dart';
import '../models/work_cost_models.dart';

class WorkCostNotifier extends Notifier<WorkCostState> {
  final _storage = const SecureStorageService();
  late String _uid;

  @override
  WorkCostState build() {
    _uid = ref.watch(authProvider)?.uid ?? 'guest';
    Future.microtask(() => _load(_uid));
    return const WorkCostState();
  }

  Future<void> setTag(
    String candidateId,
    WorkCostKind kind, {
    int? alternativeUnitCost,
  }) async {
    state = state.withTag(WorkCostTag(
      candidateId: candidateId,
      kind: kind,
      alternativeUnitCost: alternativeUnitCost,
    ));
    await _persist();
    await ref.read(analyticsProvider).workCostTagConfirmed(
          _analyticsKind(kind),
          hasAlternativeCost: alternativeUnitCost != null,
        );
  }

  Future<void> removeTag(String candidateId) async {
    // Report the running experiment as stopped before the tag takes it with it:
    // it ended without being kept, and a start with no end is a hole in the
    // measurement.
    final abandoned = state.experiments[candidateId];
    final kind = state.tags[candidateId]?.kind;
    state = state.withoutTag(candidateId);
    await _persist();
    final analytics = ref.read(analyticsProvider);
    if (abandoned != null && !abandoned.status.isDecided && kind != null) {
      await analytics.workCostExperimentDecided(
        _analyticsKind(kind),
        kept: false,
        daysRunning: abandoned.daysRunning(DateTime.now()),
      );
    }
    await analytics.workCostTagRemoved();
  }

  /// Commits the user to the "one less each workweek" suggestion.
  ///
  /// [monthlyTarget] is the saving shown at the moment of committing, stored so
  /// the promise stays fixed even if their spending moves afterwards.
  Future<void> startExperiment(String candidateId, int monthlyTarget) async {
    final kind = state.tags[candidateId]?.kind;
    // An experiment belongs to a confirmed work cost. Without a tag there is
    // nothing to be spending less on.
    if (kind == null) return;
    state = state.withExperiment(
      WorkCostExperiment(
        candidateId: candidateId,
        status: WorkCostExperimentStatus.running,
        monthlyTarget: monthlyTarget,
        startedAt: DateTime.now(),
      ),
    );
    await _persist();
    await ref.read(analyticsProvider).workCostExperimentStarted(
          _analyticsKind(kind),
        );
  }

  /// Records whether the change stuck. [kept] false means the user stopped.
  Future<void> decideExperiment(String candidateId,
      {required bool kept}) async {
    final running = state.experiments[candidateId];
    final kind = state.tags[candidateId]?.kind;
    if (running == null || running.status.isDecided || kind == null) return;
    final now = DateTime.now();
    state = state.withExperiment(
      running.decide(
        kept ? WorkCostExperimentStatus.kept : WorkCostExperimentStatus.stopped,
        now,
      ),
    );
    await _persist();
    await ref.read(analyticsProvider).workCostExperimentDecided(
          _analyticsKind(kind),
          kept: kept,
          daysRunning: running.daysRunning(now),
        );
  }

  Future<void> dismiss(String candidateId) async {
    state = state.dismiss(candidateId);
    await _persist();
    await ref.read(analyticsProvider).workCostPatternDismissed();
  }

  /// Maps to the analytics enum so the shared service never imports a feature.
  static WorkCostAnalyticsKind _analyticsKind(WorkCostKind kind) =>
      switch (kind) {
        WorkCostKind.commute => WorkCostAnalyticsKind.commute,
        WorkCostKind.officeMeals => WorkCostAnalyticsKind.officeMeals,
        WorkCostKind.coffeeAndSnacks => WorkCostAnalyticsKind.coffeeAndSnacks,
        WorkCostKind.workTools => WorkCostAnalyticsKind.workTools,
        WorkCostKind.workSocial => WorkCostAnalyticsKind.workSocial,
        WorkCostKind.other => WorkCostAnalyticsKind.other,
      };

  Future<void> _load(String uid) async {
    final raw = await _storage.read(UserScopedStorageKeys.workCosts(uid));
    if (raw == null || !ref.mounted || uid != _uid) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      state = WorkCostState.fromJson(json);
    } catch (_) {
      // Invalid local state is ignored. The next user edit replaces it.
    }
  }

  Future<void> _persist() => _storage.write(
        UserScopedStorageKeys.workCosts(_uid),
        jsonEncode(state.toJson()),
      );
}

final workCostProvider = NotifierProvider<WorkCostNotifier, WorkCostState>(
  WorkCostNotifier.new,
);

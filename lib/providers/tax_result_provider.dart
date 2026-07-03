import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tax_result.dart';
import '../models/gap_card.dart';
import '../engine/tax_engine.dart';
import '../engine/gap_finder.dart';
import '../services/backend_sync_service.dart';
import 'user_profile_provider.dart';
import 'tax_year_provider.dart';

// Async provider that loads triggers from JSON and computes gaps
final taxResultProvider = FutureProvider<TaxResult>((ref) async {
  final complete = await ref.watch(completedTaxProfileProvider.future);
  if (!complete) {
    throw StateError('tax profile incomplete');
  }
  final profile = ref.watch(userProfileProvider);
  final ruleSet = await ref.watch(activeTaxRuleSetProvider.future);
  final triggers = await GapFinder.loadTriggers();
  final gaps = GapFinder.findGaps(profile, triggers);
  final result = TaxEngine.calculate(profile, gaps, ruleSet: ruleSet);
  await BackendSyncService().syncTaxResult(result);
  return result;
});

// Mutable gap state for "mark done" functionality
class GapStateNotifier extends Notifier<Map<String, bool>> {
  Timer? _syncDebounce;
  bool _hydrating = false;

  @override
  Map<String, bool> build() {
    _loadRemote();
    ref.onDispose(() => _syncDebounce?.cancel());
    return {};
  }

  Future<void> _loadRemote() async {
    if (_hydrating) return;
    _hydrating = true;
    try {
      final remote = await BackendSyncService().fetchDoneGaps();
      if (remote.isNotEmpty) {
        state = {for (final gapId in remote) gapId: true};
      }
    } catch (_) {
      // Local-first fallback when backend is unavailable.
    } finally {
      _hydrating = false;
    }
  }

  void _scheduleSync() {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 500), () async {
      final doneIds = state.entries
          .where((entry) => entry.value)
          .map((entry) => entry.key)
          .toSet();
      try {
        await BackendSyncService().syncDoneGaps(doneIds);
        await BackendSyncService().trackEvent(
          name: 'checklist_updated',
          metadata: {'doneGapIds': doneIds.toList()},
        );
      } catch (_) {
        // Keep local state even if server sync is temporarily unavailable.
      }
    });
  }

  void markDone(String gapId) {
    state = {...state, gapId: true};
    _scheduleSync();
  }

  void markUndone(String gapId) {
    state = {...state, gapId: false};
    _scheduleSync();
  }

  void toggle(String gapId) {
    final current = state[gapId] ?? false;
    state = {...state, gapId: !current};
    _scheduleSync();
  }

  bool isDone(String gapId) => state[gapId] ?? false;

  int doneCount(List<GapCard> gaps) => gaps.where((g) => isDone(g.id)).length;

  int remainingAmount(List<GapCard> gaps) =>
      gaps.where((g) => !isDone(g.id)).fold(0, (sum, g) => sum + g.gapAmount);
}

final gapStateProvider = NotifierProvider<GapStateNotifier, Map<String, bool>>(
  GapStateNotifier.new,
);

// Convenience: active gaps (not done)
final activeGapsProvider = Provider<AsyncValue<List<GapCard>>>((ref) {
  final result = ref.watch(taxResultProvider);
  final doneMap = ref.watch(gapStateProvider);
  return result.whenData(
    (r) => r.gaps.where((g) => !(doneMap[g.id] ?? false)).toList(),
  );
});

// Tax savings rate at the user's income level
final marginalRateProvider = Provider<double>((ref) {
  final profile = ref.watch(userProfileProvider);
  return TaxEngine.marginalRateOldRegime(profile.annualCTC.toDouble());
});

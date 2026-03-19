import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tax_result.dart';
import '../models/gap_card.dart';
import '../engine/tax_engine.dart';
import '../engine/gap_finder.dart';
import 'user_profile_provider.dart';

// Async provider that loads triggers from JSON and computes gaps
final taxResultProvider = FutureProvider<TaxResult>((ref) async {
  final profile = ref.watch(userProfileProvider);
  final triggers = await GapFinder.loadTriggers();
  final gaps = GapFinder.findGaps(profile, triggers);
  return TaxEngine.calculate(profile, gaps);
});

// Mutable gap state for "mark done" functionality
class GapStateNotifier extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => {};

  void markDone(String gapId) {
    state = {...state, gapId: true};
  }

  void markUndone(String gapId) {
    state = {...state, gapId: false};
  }

  void toggle(String gapId) {
    final current = state[gapId] ?? false;
    state = {...state, gapId: !current};
  }

  bool isDone(String gapId) => state[gapId] ?? false;

  int doneCount(List<GapCard> gaps) => gaps.where((g) => isDone(g.id)).length;

  int remainingAmount(List<GapCard> gaps) => gaps
      .where((g) => !isDone(g.id))
      .fold(0, (sum, g) => sum + g.gapAmount);
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

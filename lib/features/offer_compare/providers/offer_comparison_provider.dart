import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/offer_comparison_models.dart';
import '../services/offer_comparison_service.dart';

/// Where the candidate is in the flow.
enum OfferCompareStage {
  /// Choosing which stored offer letters to compare.
  pickingOffers,

  /// Answering the questions this comparison selected.
  answering,

  /// Reading the verdict and the negotiation play.
  reading,
}

class OfferCompareState {
  const OfferCompareState({
    this.comparison,
    this.selectedDocumentIds = const [],
    this.draftAnswers = const {},
    this.isBusy = false,
    this.errorMessage,
    this.adviceUnavailable = false,
  });

  final OfferComparison? comparison;

  /// In pick order, because that becomes the display order of the offers.
  final List<String> selectedDocumentIds;
  final Map<String, String> draftAnswers;
  final bool isBusy;
  final String? errorMessage;

  /// The answers were saved but no advice came back. Distinct from an error: the
  /// candidate has lost nothing and can retry.
  final bool adviceUnavailable;

  OfferCompareStage get stage {
    final current = comparison;
    if (current == null) return OfferCompareStage.pickingOffers;
    if (current.advice != null) return OfferCompareStage.reading;
    return OfferCompareStage.answering;
  }

  bool get canSubmitAnswers {
    final questions = comparison?.questions ?? const <OfferQuestion>[];
    if (questions.isEmpty) return false;
    return questions.every((question) {
      final answer = draftAnswers[question.id];
      return answer != null && answer.trim().isNotEmpty;
    });
  }

  OfferCompareState copyWith({
    OfferComparison? comparison,
    List<String>? selectedDocumentIds,
    Map<String, String>? draftAnswers,
    bool? isBusy,
    String? errorMessage,
    bool clearError = false,
    bool? adviceUnavailable,
  }) {
    return OfferCompareState(
      comparison: comparison ?? this.comparison,
      selectedDocumentIds: selectedDocumentIds ?? this.selectedDocumentIds,
      draftAnswers: draftAnswers ?? this.draftAnswers,
      isBusy: isBusy ?? this.isBusy,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      adviceUnavailable: adviceUnavailable ?? this.adviceUnavailable,
    );
  }
}

final offerComparisonServiceProvider = Provider<OfferComparisonService>(
  (ref) => OfferComparisonService(),
);

class OfferCompareNotifier extends Notifier<OfferCompareState> {
  @override
  OfferCompareState build() => const OfferCompareState();

  /// Toggles an offer letter in or out of the comparison. Selection order is kept,
  /// so removing and re-adding a letter moves it to the end rather than back to
  /// where it was — which is what the candidate just asked for.
  void toggleOffer(String documentId) {
    final selected = [...state.selectedDocumentIds];
    if (!selected.remove(documentId)) {
      selected.add(documentId);
    }
    state = state.copyWith(selectedDocumentIds: selected, clearError: true);
  }

  void answer(String questionId, String value) {
    state = state.copyWith(
      draftAnswers: {...state.draftAnswers, questionId: value},
      clearError: true,
    );
  }

  Future<void> start() async {
    if (state.selectedDocumentIds.isEmpty || state.isBusy) return;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final comparison = await ref
          .read(offerComparisonServiceProvider)
          .startComparison(state.selectedDocumentIds);
      state = state.copyWith(
        comparison: comparison,
        draftAnswers: const {},
        adviceUnavailable: false,
        isBusy: false,
      );
    } catch (error) {
      state = state.copyWith(isBusy: false, errorMessage: _message(error));
    }
  }

  Future<void> submitAnswers() async {
    final comparison = state.comparison;
    if (comparison == null || state.isBusy || !state.canSubmitAnswers) return;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final result = await ref
          .read(offerComparisonServiceProvider)
          .submitAnswers(comparison.id, state.draftAnswers);
      state = state.copyWith(
        comparison: result.comparison,
        adviceUnavailable: result.adviceUnavailable,
        isBusy: false,
      );
    } catch (error) {
      state = state.copyWith(isBusy: false, errorMessage: _message(error));
    }
  }

  /// Back to the offer picker, keeping nothing. A new comparison is cheap; a
  /// half-cleared one is confusing.
  void reset() {
    state = const OfferCompareState();
  }

  String _message(Object error) {
    final text = error.toString();
    // The API client already produces a readable message; the type prefix is
    // noise on a screen.
    final separator = text.indexOf('): ');
    return separator == -1 ? text : text.substring(separator + 3);
  }
}

final offerCompareProvider =
    NotifierProvider<OfferCompareNotifier, OfferCompareState>(
  OfferCompareNotifier.new,
);

import 'package:flutter_test/flutter_test.dart';

import 'package:arth/features/offer_compare/models/offer_comparison_models.dart';
import 'package:arth/features/offer_compare/providers/offer_comparison_provider.dart';

Map<String, dynamic> offerJson({
  required String id,
  int position = 0,
  String? employerName = 'Zeta',
  int? guaranteed = 1000000,
  int atRisk = 0,
  int? atRiskShare,
  int oneTime = 0,
  int? ctc,
  List<Map<String, dynamic>> unknowns = const [],
  List<String> warnings = const [],
  String currency = 'INR',
}) {
  return {
    'documentId': id,
    'position': position,
    'employerName': employerName,
    'roleTitle': 'Analyst',
    'currency': currency,
    'guaranteedAnnualPay': guaranteed,
    'atRiskAnnualPay': atRisk,
    'atRiskShareBasisPoints': atRiskShare,
    'oneTimePay': oneTime,
    'employerContributions': 0,
    'annualCtc': ctc,
    'unknowns': unknowns,
    'warnings': warnings,
  };
}

Map<String, dynamic> comparisonJson({
  List<Map<String, dynamic>>? offers,
  List<String> ranked = const ['a'],
  String axis = 'guaranteed_pay',
  bool ctcMismatch = false,
  List<Map<String, dynamic>> questions = const [],
  List<Map<String, dynamic>> answers = const [],
  Map<String, dynamic>? advice,
  List<String> currencies = const ['INR'],
}) {
  return {
    'id': '11111111-1111-4111-8111-111111111111',
    'status': advice == null ? 'questions_pending' : 'advised',
    'offers': offers ?? [offerJson(id: 'a')],
    'rankedDocumentIds': ranked,
    'decidingAxis': axis,
    'guaranteedPayGap': 250000,
    'largestCtcIsNotBestGuaranteed': ctcMismatch,
    'currencies': currencies,
    'questions': questions,
    'answers': answers,
    'advice': advice,
  };
}

void main() {
  group('offer comparison parsing', () {
    test('reads the pay decomposition and the ranking as decided', () {
      final comparison = OfferComparison.fromJson(comparisonJson(
        offers: [
          offerJson(
            id: 'zeta',
            employerName: 'Zeta',
            guaranteed: 1000000,
            atRisk: 500000,
            atRiskShare: 3333,
            ctc: 1500000,
          ),
          offerJson(
            id: 'orbit',
            position: 1,
            employerName: 'Orbit',
            guaranteed: 1250000,
            atRisk: 150000,
            atRiskShare: 1071,
            ctc: 1400000,
          ),
        ],
        ranked: ['orbit', 'zeta'],
        ctcMismatch: true,
      ));

      expect(comparison.winner?.displayName, 'Orbit');
      expect(comparison.largestCtcIsNotBestGuaranteed, isTrue);
      expect(comparison.decidingAxis, OfferDecidingAxis.guaranteedPay);
      expect(comparison.offerById('zeta')?.atRiskAnnualPay, 500000);
    });

    test('keeps a missing guaranteed figure missing rather than zero', () {
      final comparison = OfferComparison.fromJson(comparisonJson(
        offers: [offerJson(id: 'a', guaranteed: null)],
        ranked: const [],
        axis: 'incomparable',
      ));

      // Zero would read on screen as "this job pays nothing".
      expect(comparison.offers.single.guaranteedAnnualPay, isNull);
      expect(comparison.winner, isNull);
    });

    test('names an offer with no employer by its position', () {
      final offer = NormalizedOffer.fromJson(
        offerJson(id: 'a', position: 1, employerName: null),
      );

      expect(offer.displayName, 'Offer B');
    });

    test('reads an unknown component and its reason', () {
      final offer = NormalizedOffer.fromJson(offerJson(
        id: 'a',
        unknowns: [
          {
            'label': 'Retention pay',
            'annualAmount': null,
            'reason': 'no_payout_schedule',
          },
        ],
      ));

      expect(offer.unknowns.single.reason, OfferUnknownReason.noPayoutSchedule);
      expect(offer.unknowns.single.reason.label, 'No payout date stated');
    });

    test('reads the verdict, the caveat, and the negotiation target', () {
      final comparison = OfferComparison.fromJson(comparisonJson(
        advice: {
          'verdict': {
            'headline': 'Orbit, on more guaranteed pay.',
            'reasoning':
                'Zeta has the larger CTC but a third of it is at risk.',
            'caveat': 'Neither letter states the posting city.',
          },
          'negotiation': {
            'targetDocumentId': 'a',
            'component': 'fixed_pay',
            'ask': 'Ask for more fixed pay.',
            'script': ['Zeta has offered more on paper.'],
            'walkAway': 'I will take it as it stands.',
          },
        },
      ));

      expect(comparison.advice?.verdict.caveat,
          'Neither letter states the posting city.');
      expect(comparison.advice?.negotiation.componentLabel, 'Fixed pay');
    });
  });

  group('offer compare flow state', () {
    test('shows the picker until a comparison exists', () {
      expect(const OfferCompareState().stage, OfferCompareStage.pickingOffers);
    });

    test('shows the questions until advice arrives, then the verdict', () {
      final unanswered = OfferCompareState(
        comparison: OfferComparison.fromJson(comparisonJson(
          questions: [
            {'id': 'role_fit', 'prompt': 'Which role?', 'options': []},
          ],
        )),
      );
      final advised = OfferCompareState(
        comparison: OfferComparison.fromJson(comparisonJson(
          advice: {
            'verdict': {'headline': 'h', 'reasoning': 'r', 'caveat': 'c'},
            'negotiation': {
              'targetDocumentId': 'a',
              'component': 'fixed_pay',
              'ask': 'ask',
              'script': ['line'],
              'walkAway': 'walk',
            },
          },
        )),
      );

      expect(unanswered.stage, OfferCompareStage.answering);
      expect(advised.stage, OfferCompareStage.reading);
    });

    test('will not submit until every question has a non-blank answer', () {
      final comparison = OfferComparison.fromJson(comparisonJson(
        questions: [
          {'id': 'role_fit', 'prompt': 'Which role?', 'options': []},
          {'id': 'leverage', 'prompt': 'Who knows?', 'options': []},
        ],
      ));

      expect(
        OfferCompareState(comparison: comparison).canSubmitAnswers,
        isFalse,
      );
      expect(
        OfferCompareState(
          comparison: comparison,
          draftAnswers: const {'role_fit': 'a', 'leverage': '   '},
        ).canSubmitAnswers,
        // Whitespace is not an answer, and submitting it would brief the advice
        // call with an empty premise.
        isFalse,
      );
      expect(
        OfferCompareState(
          comparison: comparison,
          draftAnswers: const {'role_fit': 'a', 'leverage': 'Both know'},
        ).canSubmitAnswers,
        isTrue,
      );
    });

    test('clears the error when an answer changes', () {
      const state = OfferCompareState(errorMessage: 'Network unreachable');

      expect(state.copyWith(clearError: true).errorMessage, isNull);
    });
  });
}

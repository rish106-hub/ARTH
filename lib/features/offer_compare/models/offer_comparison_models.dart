// Models for comparing several job offers.
//
// These mirror the backend's offer comparison response. Nothing here recomputes
// a figure the backend decided: the ranking and the pay decomposition arrive
// already settled, and this layer only reads them.

/// Why a component of an offer could not be counted.
enum OfferUnknownReason {
  lowConfidence,
  unclassified,
  noPayoutSchedule;

  static OfferUnknownReason fromJson(String value) => switch (value) {
        'low_confidence' => OfferUnknownReason.lowConfidence,
        'no_payout_schedule' => OfferUnknownReason.noPayoutSchedule,
        _ => OfferUnknownReason.unclassified,
      };

  String get label => switch (this) {
        OfferUnknownReason.lowConfidence => 'Could not be read confidently',
        OfferUnknownReason.unclassified => 'Not a recognised kind of pay',
        OfferUnknownReason.noPayoutSchedule => 'No payout date stated',
      };
}

class OfferUnknown {
  const OfferUnknown({
    required this.label,
    required this.annualAmount,
    required this.reason,
  });

  final String label;
  final int? annualAmount;
  final OfferUnknownReason reason;

  static OfferUnknown fromJson(Map<String, dynamic> json) => OfferUnknown(
        label: json['label'] as String? ?? '',
        annualAmount: (json['annualAmount'] as num?)?.round(),
        reason: OfferUnknownReason.fromJson(json['reason'] as String? ?? ''),
      );
}

/// What one offer letter actually promises, split into what arrives regardless
/// of performance and what does not.
class NormalizedOffer {
  const NormalizedOffer({
    required this.documentId,
    required this.position,
    required this.employerName,
    required this.roleTitle,
    required this.currency,
    required this.guaranteedAnnualPay,
    required this.atRiskAnnualPay,
    required this.atRiskShareBasisPoints,
    required this.oneTimePay,
    required this.employerContributions,
    required this.annualCtc,
    required this.unknowns,
    required this.warnings,
  });

  final String documentId;
  final int position;
  final String? employerName;
  final String? roleTitle;
  final String currency;

  /// Null, never zero, when the letter states nothing that could be classified.
  /// A zero would read as "this job pays nothing".
  final int? guaranteedAnnualPay;
  final int atRiskAnnualPay;
  final int? atRiskShareBasisPoints;
  final int oneTimePay;
  final int employerContributions;
  final int? annualCtc;
  final List<OfferUnknown> unknowns;
  final List<String> warnings;

  /// A name to show. Falls back to the letter position so a card is never blank.
  String get displayName => employerName?.trim().isNotEmpty == true
      ? employerName!.trim()
      : 'Offer ${String.fromCharCode(65 + position)}';

  static NormalizedOffer fromJson(Map<String, dynamic> json) => NormalizedOffer(
        documentId: json['documentId'] as String,
        position: (json['position'] as num?)?.toInt() ?? 0,
        employerName: json['employerName'] as String?,
        roleTitle: json['roleTitle'] as String?,
        currency: json['currency'] as String? ?? 'INR',
        guaranteedAnnualPay: (json['guaranteedAnnualPay'] as num?)?.round(),
        atRiskAnnualPay: (json['atRiskAnnualPay'] as num?)?.round() ?? 0,
        atRiskShareBasisPoints:
            (json['atRiskShareBasisPoints'] as num?)?.round(),
        oneTimePay: (json['oneTimePay'] as num?)?.round() ?? 0,
        employerContributions:
            (json['employerContributions'] as num?)?.round() ?? 0,
        annualCtc: (json['annualCtc'] as num?)?.round(),
        unknowns: (json['unknowns'] as List<dynamic>? ?? const [])
            .map((item) => OfferUnknown.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
        warnings: (json['warnings'] as List<dynamic>? ?? const [])
            .map((item) => item as String)
            .toList(growable: false),
      );
}

/// What settled the ranking, or why nothing could.
enum OfferDecidingAxis {
  guaranteedPay,
  tied,
  incomparable;

  static OfferDecidingAxis fromJson(String value) => switch (value) {
        'guaranteed_pay' => OfferDecidingAxis.guaranteedPay,
        'tied' => OfferDecidingAxis.tied,
        _ => OfferDecidingAxis.incomparable,
      };
}

class OfferQuestion {
  const OfferQuestion({
    required this.id,
    required this.prompt,
    required this.options,
  });

  final String id;
  final String prompt;
  final List<OfferQuestionOption> options;

  /// No options means the answer is typed rather than chosen.
  bool get isFreeText => options.isEmpty;

  static OfferQuestion fromJson(Map<String, dynamic> json) => OfferQuestion(
        id: json['id'] as String,
        prompt: json['prompt'] as String? ?? '',
        options: (json['options'] as List<dynamic>? ?? const [])
            .map((item) =>
                OfferQuestionOption.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class OfferQuestionOption {
  const OfferQuestionOption({required this.value, required this.label});

  final String value;
  final String label;

  static OfferQuestionOption fromJson(Map<String, dynamic> json) =>
      OfferQuestionOption(
        value: json['value'] as String,
        label: json['label'] as String? ?? '',
      );
}

class OfferVerdict {
  const OfferVerdict({
    required this.headline,
    required this.reasoning,
    required this.caveat,
  });

  final String headline;
  final String reasoning;
  final String caveat;

  static OfferVerdict fromJson(Map<String, dynamic> json) => OfferVerdict(
        headline: json['headline'] as String? ?? '',
        reasoning: json['reasoning'] as String? ?? '',
        caveat: json['caveat'] as String? ?? '',
      );
}

class OfferNegotiation {
  const OfferNegotiation({
    required this.targetDocumentId,
    required this.component,
    required this.ask,
    required this.script,
    required this.walkAway,
  });

  final String targetDocumentId;
  final String component;
  final String ask;
  final List<String> script;
  final String walkAway;

  String get componentLabel => switch (component) {
        'fixed_pay' => 'Fixed pay',
        'variable_pay' => 'Variable pay',
        'joining_bonus' => 'Joining bonus',
        'equity' => 'Equity',
        'title' => 'Title',
        'start_date' => 'Start date',
        _ => 'Nothing worth pushing',
      };

  static OfferNegotiation fromJson(Map<String, dynamic> json) =>
      OfferNegotiation(
        targetDocumentId: json['targetDocumentId'] as String? ?? '',
        component: json['component'] as String? ?? 'nothing_to_gain',
        ask: json['ask'] as String? ?? '',
        script: (json['script'] as List<dynamic>? ?? const [])
            .map((item) => item as String)
            .toList(growable: false),
        walkAway: json['walkAway'] as String? ?? '',
      );
}

class OfferAdvice {
  const OfferAdvice({required this.verdict, required this.negotiation});

  final OfferVerdict verdict;
  final OfferNegotiation negotiation;

  static OfferAdvice fromJson(Map<String, dynamic> json) => OfferAdvice(
        verdict: OfferVerdict.fromJson(json['verdict'] as Map<String, dynamic>),
        negotiation: OfferNegotiation.fromJson(
            json['negotiation'] as Map<String, dynamic>),
      );
}

/// One comparison session: the offers, the questions put to this candidate, the
/// answers so far, and the advice once it exists.
class OfferComparison {
  const OfferComparison({
    required this.id,
    required this.status,
    required this.offers,
    required this.rankedDocumentIds,
    required this.decidingAxis,
    required this.guaranteedPayGap,
    required this.largestCtcIsNotBestGuaranteed,
    required this.currencies,
    required this.questions,
    required this.answers,
    required this.advice,
  });

  final String id;
  final String status;
  final List<NormalizedOffer> offers;

  /// Best first. Excludes any offer that could not be compared on money, rather
  /// than ranking it last.
  final List<String> rankedDocumentIds;
  final OfferDecidingAxis decidingAxis;
  final int? guaranteedPayGap;

  /// The headline finding when true: the biggest CTC is not the best offer.
  final bool largestCtcIsNotBestGuaranteed;
  final List<String> currencies;
  final List<OfferQuestion> questions;
  final Map<String, String> answers;
  final OfferAdvice? advice;

  NormalizedOffer? get winner => rankedDocumentIds.isEmpty
      ? null
      : offers
          .where((offer) => offer.documentId == rankedDocumentIds.first)
          .firstOrNull;

  NormalizedOffer? offerById(String documentId) =>
      offers.where((offer) => offer.documentId == documentId).firstOrNull;

  bool get isAnswered =>
      answers.length >= questions.length && questions.isNotEmpty;

  static OfferComparison fromJson(Map<String, dynamic> json) => OfferComparison(
        id: json['id'] as String,
        status: json['status'] as String? ?? 'questions_pending',
        offers: (json['offers'] as List<dynamic>? ?? const [])
            .map((item) =>
                NormalizedOffer.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
        rankedDocumentIds:
            (json['rankedDocumentIds'] as List<dynamic>? ?? const [])
                .map((item) => item as String)
                .toList(growable: false),
        decidingAxis:
            OfferDecidingAxis.fromJson(json['decidingAxis'] as String? ?? ''),
        guaranteedPayGap: (json['guaranteedPayGap'] as num?)?.round(),
        largestCtcIsNotBestGuaranteed:
            json['largestCtcIsNotBestGuaranteed'] as bool? ?? false,
        currencies: (json['currencies'] as List<dynamic>? ?? const [])
            .map((item) => item as String)
            .toList(growable: false),
        questions: (json['questions'] as List<dynamic>? ?? const [])
            .map((item) => OfferQuestion.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
        answers: {
          for (final answer in json['answers'] as List<dynamic>? ?? const [])
            (answer as Map<String, dynamic>)['id'] as String:
                answer['answer'] as String,
        },
        advice: json['advice'] == null
            ? null
            : OfferAdvice.fromJson(json['advice'] as Map<String, dynamic>),
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

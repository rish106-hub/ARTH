import type { OfferLetterInterpretation } from './geminiInterpreter.js';

/// Normalizes several offer letters onto one axis set and ranks them.
///
/// Pure: no network, no database, no model. This is deliberate and it is what
/// makes the feature auditable — the verdict is decided here, in code a reader
/// can follow, and the model that later writes the wording is given no number of
/// its own to produce.
///
/// Take-home pay is not computed here. The tax engine lives in the app
/// (lib/engine/tax_engine.dart), and duplicating slab logic in the backend to
/// avoid one extra hop would be two tax engines to keep in step. This engine
/// decomposes the promise; the app layers take-home on top of it.

/// Whole currency units. Offer letters are written in whole rupees, and money in
/// this codebase never travels as a float.
type Money = number;

/// Below this gap in guaranteed pay, two offers are called a tie rather than
/// ranked. Ranking a 0.5% difference as a winner would dress up noise as a
/// finding, and the honest answer at that point is that money is not the
/// deciding axis.
const TIE_BASIS_POINTS = 200;

/// How far the components may sum away from a printed total before the printed
/// total is reported as disputed. Small gaps are rounding and unlisted minor
/// heads; a large gap means one of the two numbers is not what the reader thinks.
const COMPONENT_DISAGREEMENT_BASIS_POINTS = 500;

export type UnknownReason =
  /// The extractor was unsure it read this component correctly.
  | 'low_confidence'
  /// A component with an amount that fits no pay category.
  | 'unclassified'
  /// An amount with no stated frequency, so it cannot be annualized.
  | 'no_payout_schedule';

export type OfferUnknown = {
  label: string;
  annualAmount: Money | null;
  reason: UnknownReason;
};

export type NormalizedOffer = {
  documentId: string;
  position: number;
  employerName: string | null;
  roleTitle: string | null;
  currency: string;
  /// Pay that arrives regardless of performance: fixed pay plus allowances.
  /// Null, never zero, when the letter states nothing that can be classified —
  /// a zero here would rank a silent letter last as though it paid nothing.
  guaranteedAnnualPay: Money | null;
  /// Variable, bonus, and commission: promised, but conditional.
  atRiskAnnualPay: Money;
  /// At-risk pay as a share of recurring pay. One-time money is excluded from
  /// the denominator on purpose: the question this answers is what share of an
  /// ongoing month is conditional, and a joining bonus flatters that.
  atRiskShareBasisPoints: number | null;
  /// Joining bonus, relocation, retention — real money, but paid once. Kept
  /// apart because it inflates year-one CTC and is gone by year two.
  oneTimePay: Money;
  /// PF and similar. Counted, but never as take-home.
  employerContributions: Money;
  /// As printed. Not recomputed, so a reader can reconcile against the letter.
  annualCtc: Money | null;
  /// Components that could not be placed. Each becomes a candidate question
  /// rather than an assumption.
  unknowns: OfferUnknown[];
  /// Extraction warnings, plus anything this engine found inconsistent.
  warnings: string[];
};

export type DecidingAxis =
  /// One offer pays materially more guaranteed money.
  | 'guaranteed_pay'
  /// Guaranteed pay is within the tie threshold, so money does not decide it.
  | 'tied'
  /// Not enough was extracted from at least one letter to compare on money.
  | 'incomparable';

export type OfferComparison = {
  offers: NormalizedOffer[];
  /// Best first, by guaranteed annual pay. Offers with no comparable guaranteed
  /// figure are excluded rather than ranked last.
  rankedDocumentIds: string[];
  decidingAxis: DecidingAxis;
  /// Best guaranteed pay minus the runner-up's. Null when nothing can be ranked.
  guaranteedPayGap: Money | null;
  /// True when the offer with the largest CTC is not the one with the largest
  /// guaranteed pay. The single most useful thing this engine can notice: it is
  /// how a candidate ends up choosing the worse offer while believing the
  /// numbers backed them up.
  largestCtcIsNotBestGuaranteed: boolean;
  /// Currencies seen across the offers. More than one means the money axis
  /// cannot be compared at all without a rate the product does not have.
  currencies: string[];
};

export type OfferInput = {
  documentId: string;
  position: number;
  interpretation: OfferLetterInterpretation;
};

function roundMoney(value: number | null | undefined): Money | null {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    return null;
  }
  return Math.round(value);
}

function basisPoints(part: Money, whole: Money): number | null {
  if (whole <= 0) return null;
  return Math.round((part / whole) * 10_000);
}

function relativeGapBasisPoints(left: Money, right: Money): number | null {
  const larger = Math.max(left, right);
  if (larger <= 0) return null;
  return Math.round((Math.abs(left - right) / larger) * 10_000);
}

/// Annual value of one printed component, or null when it cannot be annualized.
///
/// A stated frequency is required. Guessing that an unlabelled amount is monthly
/// would turn one number into twelve, which is the single most expensive mistake
/// available in this file.
function annualizeComponent(
  component: OfferLetterInterpretation['components'][number],
): Money | null {
  const amount = roundMoney(component.annualAmount);
  if (amount === null) return null;
  // The extractor is asked for annual amounts, so a stated frequency describes
  // how the money arrives, not a multiplier still to apply.
  return component.frequency === 'unknown' ? null : amount;
}

export function normalizeOffer(input: OfferInput): NormalizedOffer {
  const source = input.interpretation;
  const warnings = [...source.warnings];
  const unknowns: OfferUnknown[] = [];

  let componentGuaranteed = 0;
  let componentAtRisk = 0;
  let oneTimePay = 0;
  let employerContributions = 0;
  let sawGuaranteedComponent = false;

  for (const component of source.components) {
    const annual = annualizeComponent(component);

    if (component.confidence === 'low') {
      unknowns.push({
        label: component.label,
        annualAmount: annual,
        reason: 'low_confidence',
      });
    }

    if (annual === null) {
      // An amount with no usable frequency is worth asking about; a component
      // with no amount at all is just a named benefit and needs no question.
      if (roundMoney(component.annualAmount) !== null) {
        unknowns.push({
          label: component.label,
          annualAmount: null,
          reason: 'no_payout_schedule',
        });
      }
      continue;
    }

    if (component.frequency === 'one_time') {
      oneTimePay += annual;
      continue;
    }

    switch (component.classification) {
      case 'fixed_pay':
      case 'allowance':
        componentGuaranteed += annual;
        sawGuaranteedComponent = true;
        break;
      case 'variable_pay':
        componentAtRisk += annual;
        break;
      case 'employer_contribution':
        employerContributions += annual;
        break;
      case 'reimbursement':
      case 'deduction':
        // Neither is pay: one returns money already spent, the other takes money
        // away. Counting either as income is how a CTC figure gets padded.
        break;
      case 'other':
        unknowns.push({
          label: component.label,
          annualAmount: annual,
          reason: 'unclassified',
        });
        break;
    }
  }

  const printedFixed = roundMoney(source.fixedAnnualPay);
  const printedVariable = roundMoney(source.variableAnnualPay);
  const joiningBonus = roundMoney(source.joiningBonus);
  if (joiningBonus !== null) oneTimePay += joiningBonus;

  // Printed totals win over component sums. The letter is the promise; the
  // components are this engine's reading of it. Where they disagree materially,
  // the disagreement is reported rather than resolved.
  const guaranteedAnnualPay = printedFixed
    ?? (sawGuaranteedComponent ? componentGuaranteed : null);
  const atRiskAnnualPay = printedVariable ?? componentAtRisk;

  if (printedFixed !== null && sawGuaranteedComponent) {
    const gap = relativeGapBasisPoints(printedFixed, componentGuaranteed);
    if (gap !== null && gap > COMPONENT_DISAGREEMENT_BASIS_POINTS) {
      warnings.push(
        `Stated fixed pay and the listed components differ by ${(gap / 100).toFixed(1)}%. Check which figure the letter means.`,
      );
    }
  }

  const recurringPay = (guaranteedAnnualPay ?? 0) + atRiskAnnualPay;

  return {
    documentId: input.documentId,
    position: input.position,
    employerName: source.employerName,
    roleTitle: source.roleTitle,
    currency: source.currency,
    guaranteedAnnualPay,
    atRiskAnnualPay,
    atRiskShareBasisPoints: guaranteedAnnualPay === null
      ? null
      : basisPoints(atRiskAnnualPay, recurringPay),
    oneTimePay,
    employerContributions,
    annualCtc: roundMoney(source.annualCtc),
    unknowns,
    warnings,
  };
}

export function compareOffers(inputs: OfferInput[]): OfferComparison {
  const offers = inputs
    .map(normalizeOffer)
    .sort((left, right) => left.position - right.position);

  const currencies = [...new Set(offers.map((offer) => offer.currency))].sort();

  const comparable = offers.filter(
    (offer): offer is NormalizedOffer & { guaranteedAnnualPay: Money } =>
      offer.guaranteedAnnualPay !== null,
  );
  // Mixing currencies would mean ranking rupees against dollars, which needs a
  // rate this product does not hold and must not invent.
  const rankable = currencies.length === 1 ? comparable : [];
  const ranked = [...rankable].sort(
    (left, right) => right.guaranteedAnnualPay - left.guaranteedAnnualPay,
  );

  const gap = ranked.length >= 2
    ? ranked[0].guaranteedAnnualPay - ranked[1].guaranteedAnnualPay
    : null;
  const gapBasisPoints = ranked.length >= 2
    ? relativeGapBasisPoints(
        ranked[0].guaranteedAnnualPay,
        ranked[1].guaranteedAnnualPay,
      )
    : null;

  const decidingAxis: DecidingAxis = ranked.length < 2
    ? 'incomparable'
    : gapBasisPoints !== null && gapBasisPoints <= TIE_BASIS_POINTS
      ? 'tied'
      : 'guaranteed_pay';

  const withCtc = rankable.filter((offer) => offer.annualCtc !== null);
  const largestCtc = withCtc.length >= 2
    ? [...withCtc].sort((left, right) => (right.annualCtc ?? 0) - (left.annualCtc ?? 0))[0]
    : null;
  const largestCtcIsNotBestGuaranteed = largestCtc !== null
    && ranked.length >= 2
    && largestCtc.documentId !== ranked[0].documentId;

  return {
    offers,
    rankedDocumentIds: ranked.map((offer) => offer.documentId),
    decidingAxis,
    guaranteedPayGap: gap,
    largestCtcIsNotBestGuaranteed,
    currencies,
  };
}

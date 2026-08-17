import type { NormalizedOffer, OfferComparison } from './offerComparisonEngine.js';

/// Chooses which questions to put to one candidate, and fills them with that
/// candidate's own numbers.
///
/// Pure: no network, no database, no model. Selection is deterministic on
/// purpose. A model asked to invent five questions produces a competent generic
/// quiz; what actually helps is asking only the questions whose answer would
/// change the ranking this engine already computed, worded with the figures from
/// these letters. That is also why this step costs nothing to run.

/// Five is the product promise, and it is also about as many questions as
/// someone deciding between job offers will answer carefully.
export const MAX_QUESTIONS = 5;

/// How far two offers' at-risk shares must diverge before the question of
/// surviving a zero payout is worth one of the five slots. Below this the offers
/// carry much the same risk and the answer changes nothing.
const VARIABLE_SHARE_DIVERGENCE_BASIS_POINTS = 800;

export type QuestionId =
  | 'variable_risk'
  | 'role_fit'
  | 'leverage'
  | 'tenure'
  | 'unverified_component'
  | 'location'
  | 'anchor';

export type QuestionOption = {
  value: string;
  label: string;
};

export type SelectedQuestion = {
  id: QuestionId;
  prompt: string;
  /// Empty for a free-text answer.
  options: QuestionOption[];
  /// Why this question earned a slot. Not shown to the candidate; it makes the
  /// selection reviewable, and it is what the advice step is told so it can
  /// explain the verdict in the same terms.
  because: string;
};

/// Indian-format money, because "₹18.5L" is how the offers themselves read and
/// "1850000" is not. Falls back to a grouped figure with the currency code when
/// the letters are not in rupees, rather than mislabelling a foreign amount.
export function formatOfferMoney(amount: number, currency: string): string {
  const normalized = currency.trim().toUpperCase();
  if (normalized !== 'INR' && normalized !== '₹') {
    return `${normalized} ${amount.toLocaleString('en-US')}`;
  }
  if (amount >= 10_000_000) {
    return `₹${trimZero(amount / 10_000_000)}Cr`;
  }
  if (amount >= 100_000) {
    return `₹${trimZero(amount / 100_000)}L`;
  }
  return `₹${amount.toLocaleString('en-IN')}`;
}

function trimZero(value: number): string {
  return value.toFixed(1).replace(/\.0$/, '');
}

function percent(basisPoints: number): string {
  return `${trimZero(basisPoints / 100)}%`;
}

function offerName(offer: NormalizedOffer): string {
  return offer.employerName?.trim()
    || offer.roleTitle?.trim()
    || `Offer ${String.fromCharCode(65 + offer.position)}`;
}

function roleLabel(offer: NormalizedOffer): string {
  const employer = offer.employerName?.trim();
  const role = offer.roleTitle?.trim();
  if (employer && role) return `${role} at ${employer}`;
  return role || employer || `Offer ${String.fromCharCode(65 + offer.position)}`;
}

type Candidate = SelectedQuestion & { priority: number };

/// The at-risk-pay question, when the offers actually differ on that risk.
function variableRiskQuestion(comparison: OfferComparison): Candidate | null {
  const shares = comparison.offers
    .filter((offer) => offer.atRiskShareBasisPoints !== null)
    .map((offer) => ({ offer, share: offer.atRiskShareBasisPoints as number }));
  if (shares.length < 2) return null;

  const sorted = [...shares].sort((left, right) => right.share - left.share);
  const spread = sorted[0].share - sorted[sorted.length - 1].share;
  if (spread < VARIABLE_SHARE_DIVERGENCE_BASIS_POINTS) return null;

  const riskiest = sorted[0];
  if (riskiest.offer.atRiskAnnualPay <= 0) return null;
  const amount = formatOfferMoney(
    riskiest.offer.atRiskAnnualPay,
    riskiest.offer.currency,
  );

  return {
    priority: 1,
    id: 'variable_risk',
    prompt: `If ${offerName(riskiest.offer)}'s ${amount} variable pay (${percent(riskiest.share)} of ongoing pay) paid nothing this year, could you still cover rent and any EMIs?`,
    options: [
      { value: 'comfortably', label: 'Comfortably' },
      { value: 'tight', label: 'Tight, but survivable' },
      { value: 'no', label: 'No' },
    ],
    because: `At-risk pay differs by ${percent(spread)} across these offers, so how much of it the candidate can afford to lose changes which offer pays more in practice.`,
  };
}

/// The only non-financial axis, and the decider outright when money ties.
function roleFitQuestion(comparison: OfferComparison): Candidate | null {
  if (comparison.offers.length < 2) return null;
  const tied = comparison.decidingAxis !== 'guaranteed_pay';

  return {
    // When guaranteed pay cannot separate the offers, this is not a tie-breaker,
    // it is the decision.
    priority: tied ? 0 : 3,
    id: 'role_fit',
    prompt: 'Set the money aside. Which of these is closer to the work you want to be doing in two years?',
    options: [
      ...comparison.offers.map((offer) => ({
        value: offer.documentId,
        label: roleLabel(offer),
      })),
      { value: 'neither', label: 'Neither' },
    ],
    because: tied
      ? 'Guaranteed pay does not separate these offers, so this answer decides it rather than breaking a tie.'
      : 'The one axis no offer letter can be read for, and the one candidates most often regret ignoring.',
  };
}

/// Whether there is any leverage to negotiate with. Without this the negotiation
/// output is generic advice.
function leverageQuestion(comparison: OfferComparison): Candidate | null {
  if (comparison.offers.length < 2) return null;
  const names = comparison.offers.map(offerName).join(', ');

  return {
    priority: 2,
    id: 'leverage',
    prompt: `Which of these employers already knows you are holding another offer, and has any of them given you a deadline? (${names})`,
    options: [],
    because: 'Competing offers only become leverage once an employer knows they exist, and a deadline decides the order to push in.',
  };
}

/// What makes money paid once real, or a trap.
function tenureQuestion(comparison: OfferComparison): Candidate | null {
  const withOneTime = comparison.offers.filter((offer) => offer.oneTimePay > 0);
  if (!withOneTime.length) return null;

  const largest = [...withOneTime].sort(
    (left, right) => right.oneTimePay - left.oneTimePay,
  )[0];
  const amount = formatOfferMoney(largest.oneTimePay, largest.currency);

  return {
    priority: 4,
    id: 'tenure',
    prompt: 'Honestly, how long do you expect to stay in this job?',
    options: [
      { value: 'under_year', label: 'Under a year' },
      { value: 'one_to_two', label: '1 to 2 years' },
      { value: 'three_plus', label: '3 years or more' },
    ],
    because: `${offerName(largest)} pays ${amount} once. A clawback or a vesting cliff would make that a loan rather than pay, and only the intended tenure decides which it is.`,
  };
}

/// Turns an extraction weakness into a useful prompt instead of a silent guess.
function unverifiedComponentQuestion(
  comparison: OfferComparison,
): Candidate | null {
  for (const reason of ['no_payout_schedule', 'unclassified', 'low_confidence'] as const) {
    for (const offer of comparison.offers) {
      const unknown = offer.unknowns.find((item) => item.reason === reason);
      if (!unknown) continue;
      const amount = unknown.annualAmount === null
        ? ''
        : ` ${formatOfferMoney(unknown.annualAmount, offer.currency)}`;
      return {
        priority: 5,
        id: 'unverified_component',
        prompt: `${offerName(offer)} lists "${unknown.label}"${amount} without enough detail to count it. Do you have that commitment in writing, with a payout date?`,
        options: [
          { value: 'in_writing', label: 'Yes, in writing' },
          { value: 'verbal', label: 'Only verbally' },
          { value: 'no', label: 'No' },
        ],
        because: `"${unknown.label}" could not be placed (${reason.replace(/_/g, ' ')}), so counting it either way would be a guess about real money.`,
      };
    }
  }
  return null;
}

/// Cost of living, which no offer letter states and which can invert the ranking.
function locationQuestion(comparison: OfferComparison): Candidate | null {
  if (comparison.offers.length < 2) return null;

  return {
    priority: 6,
    id: 'location',
    prompt: 'Which city would you be living in for each offer, and would you be paying rent yourself?',
    options: [],
    because: 'Offer letters do not reliably state the posting, and the same pay is a different life in Bengaluru than in Indore. Nothing in the letters can answer this.',
  };
}

/// The anchor and the urgency a negotiation ask needs.
function anchorQuestion(): Candidate {
  return {
    priority: 7,
    id: 'anchor',
    prompt: 'What is your current or last fixed pay, and how long is your notice period?',
    options: [],
    because: 'A negotiation ask needs an anchor to move from, and the notice period sets how much time there is to use.',
  };
}

/// The five questions for this candidate, best first.
///
/// Every question here is one whose answer could change the verdict or the
/// negotiation. Questions that cannot fire — no at-risk pay to lose, no one-time
/// money to claw back, nothing left unread in the letters — are not asked, so the
/// set differs from candidate to candidate by construction.
export function selectQuestions(comparison: OfferComparison): SelectedQuestion[] {
  const candidates = [
    variableRiskQuestion(comparison),
    roleFitQuestion(comparison),
    leverageQuestion(comparison),
    tenureQuestion(comparison),
    unverifiedComponentQuestion(comparison),
    locationQuestion(comparison),
    anchorQuestion(),
  ].filter((candidate): candidate is Candidate => candidate !== null);

  return candidates
    .sort((left, right) => left.priority - right.priority)
    .slice(0, MAX_QUESTIONS)
    .map(({ priority: _priority, ...question }) => question);
}

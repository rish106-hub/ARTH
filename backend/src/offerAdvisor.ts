import { createHash } from 'node:crypto';
import { z } from 'zod';

import {
  generateStructuredJson,
  untrustedTextPart,
  type SpendGuard,
} from './geminiStructuredCall.js';
import type { NormalizedOffer, OfferComparison } from './offerComparisonEngine.js';
import {
  formatBasisPointsAsPercent,
  formatOfferMoney,
} from './offerMoneyFormat.js';
import type { QuestionId } from './offerQuestionSelector.js';

/// Turns a decided comparison into words: a verdict the candidate can act on, and
/// a negotiation play.
///
/// The one paid step in this feature. It is given the comparison the engine
/// already decided and is asked to explain it — it is never asked which offer
/// wins. That is the difference between advice that can be audited and advice
/// that merely sounds right, and it is enforced by the schema below having no
/// field for the model to name a winner in.
///
/// The model may propose a number for the ask, because a negotiation target is a
/// recommendation rather than a claim about the letters. It may not introduce a
/// figure about the offers themselves, which is why every figure it could need is
/// handed to it pre-formatted, as a string it can quote.

const NEGOTIATION_COMPONENTS = [
  'fixed_pay',
  'variable_pay',
  'joining_bonus',
  'equity',
  'title',
  'start_date',
  'nothing_to_gain',
] as const;

const adviceSchema = z.object({
  verdict: z.object({
    /// One line. The offer's name and the figure that settled it.
    headline: z.string().min(1).max(240),
    /// Why that figure and not the headline CTC.
    reasoning: z.string().min(1).max(600),
    /// What this verdict does not know. Never empty: there is always something
    /// an offer letter does not say.
    caveat: z.string().min(1).max(400),
  }),
  negotiation: z.object({
    /// Which offer to push. Must be one of the document ids supplied.
    targetDocumentId: z.string().min(1).max(64),
    component: z.enum(NEGOTIATION_COMPONENTS),
    /// The ask in one sentence, including the number to ask for.
    ask: z.string().min(1).max(300),
    /// What to actually say, a line at a time.
    script: z.array(z.string().min(1).max(400)).min(1).max(6),
    /// The sentence that closes the conversation if the answer is no.
    walkAway: z.string().min(1).max(300),
  }),
});

export type OfferAdvice = z.infer<typeof adviceSchema>;

const responseSchema = {
  type: 'object',
  properties: {
    verdict: {
      type: 'object',
      properties: {
        headline: { type: 'string', description: 'At most 240 characters.' },
        reasoning: { type: 'string', description: 'At most 600 characters.' },
        caveat: { type: 'string', description: 'At most 400 characters.' },
      },
      required: ['headline', 'reasoning', 'caveat'],
    },
    negotiation: {
      type: 'object',
      properties: {
        targetDocumentId: {
          type: 'string',
          description: 'Exactly one of the offer ids given in the brief.',
        },
        component: { type: 'string', enum: [...NEGOTIATION_COMPONENTS] },
        ask: { type: 'string', description: 'At most 300 characters.' },
        script: {
          type: 'array',
          items: { type: 'string', description: 'At most 400 characters.' },
        },
        walkAway: { type: 'string', description: 'At most 300 characters.' },
      },
      required: ['targetDocumentId', 'component', 'ask', 'script', 'walkAway'],
    },
  },
  required: ['verdict', 'negotiation'],
};

export type AnsweredQuestion = {
  id: QuestionId;
  prompt: string;
  because: string;
  answer: string;
};

/// Advice is the only step that costs money, so an unchanged comparison with
/// unchanged answers reuses the cached result instead of paying again. Question
/// wording is excluded: it is derived from the comparison, so including it would
/// only add a way for the fingerprint to change without the inputs changing.
export function adviceFingerprint(
  comparison: OfferComparison,
  answers: AnsweredQuestion[],
): string {
  const material = JSON.stringify({
    offers: comparison.offers,
    ranked: comparison.rankedDocumentIds,
    axis: comparison.decidingAxis,
    answers: [...answers]
      .sort((left, right) => left.id.localeCompare(right.id))
      .map((answer) => [answer.id, answer.answer]),
  });
  return createHash('sha256').update(material).digest('hex');
}

function describeOffer(offer: NormalizedOffer): string {
  const name = offer.employerName?.trim() || `Offer ${offer.position + 1}`;
  const money = (amount: number) => formatOfferMoney(amount, offer.currency);
  const lines = [
    `- id: ${offer.documentId}`,
    `  employer: ${name}`,
    `  role: ${offer.roleTitle?.trim() || 'not stated'}`,
    `  guaranteed annual pay: ${
      offer.guaranteedAnnualPay === null ? 'not stated' : money(offer.guaranteedAnnualPay)
    }`,
    `  at-risk annual pay: ${money(offer.atRiskAnnualPay)}${
      offer.atRiskShareBasisPoints === null
        ? ''
        : ` (${formatBasisPointsAsPercent(offer.atRiskShareBasisPoints)} of ongoing pay)`
    }`,
    `  paid once: ${money(offer.oneTimePay)}`,
    `  employer contributions: ${money(offer.employerContributions)}`,
    `  stated CTC: ${offer.annualCtc === null ? 'not stated' : money(offer.annualCtc)}`,
  ];
  for (const unknown of offer.unknowns) {
    lines.push(
      `  could not count: ${unknown.label} (${unknown.reason.replace(/_/g, ' ')})`,
    );
  }
  for (const warning of offer.warnings) {
    lines.push(`  warning: ${warning}`);
  }
  return lines.join('\n');
}

/// The decided comparison, written out as quotable strings.
///
/// Every figure the model could need appears here already formatted, so restating
/// one is quoting rather than calculating.
function comparisonBrief(comparison: OfferComparison): string {
  const winner = comparison.rankedDocumentIds[0];
  const currency = comparison.offers[0]?.currency ?? 'INR';
  const axis = {
    guaranteed_pay: 'guaranteed annual pay',
    tied: 'nothing — guaranteed pay is within 2%, so money does not decide this',
    incomparable: 'nothing — at least one letter did not state enough to compare',
  }[comparison.decidingAxis];

  return [
    'OFFERS',
    comparison.offers.map(describeOffer).join('\n'),
    '',
    'ALREADY DECIDED (do not re-decide any of this)',
    `- ranking, best first: ${comparison.rankedDocumentIds.join(', ') || 'none rankable'}`,
    `- the offer that wins: ${winner ?? 'none'}`,
    `- what decided it: ${axis}`,
    `- gap in guaranteed pay: ${
      comparison.guaranteedPayGap === null
        ? 'not applicable'
        : formatOfferMoney(comparison.guaranteedPayGap, currency)
    }`,
    `- largest CTC is not the best offer: ${comparison.largestCtcIsNotBestGuaranteed}`,
  ].join('\n');
}

function answersBrief(answers: AnsweredQuestion[]): string {
  if (!answers.length) return 'ANSWERS\n- none given';
  return [
    'ANSWERS',
    ...answers.map((answer) => [
      `- question (${answer.id}): ${answer.prompt}`,
      `  asked because: ${answer.because}`,
      `  answer: ${answer.answer}`,
    ].join('\n')),
  ].join('\n');
}

const systemInstruction = [
  'You write compensation advice for one candidate choosing between job offers in India.',
  'The comparison has already been decided in code. Explain the decision you are given; never substitute your own ranking, and never name a different winner.',
  'Every figure about the offers is supplied to you already formatted. Quote those strings. Do not calculate, convert, or estimate any figure about the offers, and do not introduce a figure that is not in the brief.',
  'You may propose a number to ask for in a negotiation, because that is a recommendation rather than a claim about the letters.',
  'Never estimate tax or take-home pay. Never comment on a company\'s culture, stability, or reputation, and never predict promotions or future salary growth.',
  'Be specific and plain. No hedging, no encouragement, no restating the question.',
  'Write the negotiation ask on a single component, and prefer fixed pay over CTC, because fixed pay is the part that pays every month.',
  'If the answers show there is no leverage, say the honest thing: choose the component with the most room and say plainly what the candidate is trading away by asking.',
].join(' ');

const instruction = [
  'Write the verdict and the negotiation play from the brief below.',
  'The verdict headline names the winning offer and the one figure that settled it.',
  'The reasoning explains why that figure and not the headline CTC.',
  'The caveat states what this cannot know from the letters, and must not be empty.',
  'targetDocumentId must be exactly one of the ids listed under OFFERS.',
].join(' ');

export async function adviseOnOffers(input: {
  comparison: OfferComparison;
  answers: AnsweredQuestion[];
  spendGuard: SpendGuard;
}): Promise<OfferAdvice | null> {
  if (!input.comparison.offers.length) return null;

  const raw = await generateStructuredJson({
    label: 'offer-advice',
    systemInstruction,
    parts: [
      { text: instruction },
      { text: comparisonBrief(input.comparison) },
      // The answers are the candidate's own words, and offer names came out of an
      // uploaded document. Both are data, not instructions.
      untrustedTextPart(answersBrief(input.answers), 20_000),
    ],
    responseSchema,
    spendGuard: input.spendGuard,
  });
  if (raw === null) return null;

  const parsed = adviceSchema.safeParse(raw);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((issue) => ({
      path: issue.path.join('.'),
      code: issue.code,
    }));
    console.warn(`[offers] invalid advice output: ${JSON.stringify(issues)}`);
    return null;
  }

  // A model that cannot keep to the ids it was handed has not produced advice
  // worth showing. Rejecting is safer than repairing: silently retargeting the
  // negotiation would leave a script written for one employer addressed to
  // another.
  const known = new Set(input.comparison.offers.map((offer) => offer.documentId));
  if (!known.has(parsed.data.negotiation.targetDocumentId)) {
    console.warn('[offers] advice named an offer that is not in the comparison');
    return null;
  }

  return parsed.data;
}

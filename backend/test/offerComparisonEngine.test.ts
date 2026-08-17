import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import type { OfferLetterInterpretation } from '../src/geminiInterpreter.js';
import { compareOffers, normalizeOffer } from '../src/offerComparisonEngine.js';

type Component = OfferLetterInterpretation['components'][number];

function component(fields: Partial<Component>): Component {
  return {
    label: 'Component',
    annualAmount: null,
    frequency: 'annual',
    classification: 'fixed_pay',
    confidence: 'high',
    ...fields,
  };
}

function offerLetter(
  fields: Partial<OfferLetterInterpretation> = {},
): OfferLetterInterpretation {
  return {
    employerName: 'Example Technologies',
    roleTitle: 'Analyst',
    currency: 'INR',
    annualCtc: null,
    fixedAnnualPay: null,
    variableAnnualPay: null,
    joiningBonus: null,
    components: [],
    warnings: [],
    questionsForUser: [],
    ...fields,
  };
}

function input(documentId: string, position: number, fields: Partial<OfferLetterInterpretation>) {
  return { documentId, position, interpretation: offerLetter(fields) };
}

describe('offer normalization', () => {
  it('separates guaranteed pay, at-risk pay, and money paid once', () => {
    const offer = normalizeOffer(input('a', 0, {
      annualCtc: 1_800_000,
      fixedAnnualPay: 1_000_000,
      variableAnnualPay: 400_000,
      joiningBonus: 300_000,
    }));

    assert.equal(offer.guaranteedAnnualPay, 1_000_000);
    assert.equal(offer.atRiskAnnualPay, 400_000);
    assert.equal(offer.oneTimePay, 300_000);
    assert.equal(offer.annualCtc, 1_800_000);
    // 400k of 1.4M recurring pay. The joining bonus is deliberately outside the
    // denominator: it would otherwise make conditional pay look like a smaller
    // share of an ongoing month than it is.
    assert.equal(offer.atRiskShareBasisPoints, 2857);
  });

  it('counts allowances as guaranteed and sums components when no total is printed', () => {
    const offer = normalizeOffer(input('a', 0, {
      components: [
        component({ label: 'Basic', annualAmount: 600_000 }),
        component({ label: 'HRA', annualAmount: 240_000, classification: 'allowance' }),
        component({
          label: 'Performance bonus',
          annualAmount: 150_000,
          classification: 'variable_pay',
        }),
      ],
    }));

    assert.equal(offer.guaranteedAnnualPay, 840_000);
    assert.equal(offer.atRiskAnnualPay, 150_000);
  });

  it('never counts a reimbursement or a deduction as pay', () => {
    const offer = normalizeOffer(input('a', 0, {
      components: [
        component({ label: 'Basic', annualAmount: 600_000 }),
        component({
          label: 'Internet reimbursement',
          annualAmount: 24_000,
          classification: 'reimbursement',
        }),
        component({
          label: 'Employee PF',
          annualAmount: 21_600,
          classification: 'deduction',
        }),
        component({
          label: 'Employer PF',
          annualAmount: 21_600,
          classification: 'employer_contribution',
        }),
      ],
    }));

    // Reimbursement returns money already spent and a deduction takes money
    // away. Counting either as income is how a CTC figure gets padded.
    assert.equal(offer.guaranteedAnnualPay, 600_000);
    assert.equal(offer.employerContributions, 21_600);
  });

  it('reports no guaranteed figure rather than zero when nothing can be classified', () => {
    const offer = normalizeOffer(input('a', 0, {
      components: [component({ label: 'Health cover', annualAmount: null })],
    }));

    // Zero would rank a silent letter last as though it paid nothing.
    assert.equal(offer.guaranteedAnnualPay, null);
    assert.equal(offer.atRiskShareBasisPoints, null);
  });

  it('refuses to annualize an amount with no stated frequency, and asks instead', () => {
    const offer = normalizeOffer(input('a', 0, {
      fixedAnnualPay: 900_000,
      components: [
        component({
          label: 'Retention pay',
          annualAmount: 150_000,
          frequency: 'unknown',
        }),
      ],
    }));

    // Guessing that an unlabelled amount is monthly would turn one number into
    // twelve, so it stays out of the totals and becomes a question.
    assert.equal(offer.guaranteedAnnualPay, 900_000);
    assert.deepEqual(offer.unknowns, [{
      label: 'Retention pay',
      annualAmount: null,
      reason: 'no_payout_schedule',
    }]);
  });

  it('flags a low-confidence component and an unclassifiable one', () => {
    const offer = normalizeOffer(input('a', 0, {
      fixedAnnualPay: 900_000,
      components: [
        component({ label: 'Special pay', annualAmount: 60_000, confidence: 'low' }),
        component({
          label: 'Long service award',
          annualAmount: 25_000,
          classification: 'other',
        }),
      ],
    }));

    assert.deepEqual(offer.unknowns.map((unknown) => unknown.reason), [
      'low_confidence',
      'unclassified',
    ]);
  });

  it('reports a printed total that its own components contradict', () => {
    const offer = normalizeOffer(input('a', 0, {
      fixedAnnualPay: 1_000_000,
      components: [component({ label: 'Basic', annualAmount: 700_000 })],
    }));

    // The printed figure still wins — the letter is the promise. The reader is
    // told the two do not reconcile rather than having it resolved for them.
    assert.equal(offer.guaranteedAnnualPay, 1_000_000);
    assert.equal(offer.warnings.length, 1);
    assert.match(offer.warnings[0], /differ by 30\.0%/);
  });

  it('ignores a rounding-sized gap between the total and the components', () => {
    const offer = normalizeOffer(input('a', 0, {
      fixedAnnualPay: 1_000_000,
      components: [component({ label: 'Basic', annualAmount: 990_000 })],
    }));

    assert.deepEqual(offer.warnings, []);
  });
});

describe('offer ranking', () => {
  it('ranks on guaranteed pay, not on CTC, and says so when they disagree', () => {
    const comparison = compareOffers([
      input('big-ctc', 0, {
        annualCtc: 1_500_000,
        fixedAnnualPay: 1_000_000,
        variableAnnualPay: 500_000,
      }),
      input('big-fixed', 1, {
        annualCtc: 1_400_000,
        fixedAnnualPay: 1_250_000,
        variableAnnualPay: 150_000,
      }),
    ]);

    assert.deepEqual(comparison.rankedDocumentIds, ['big-fixed', 'big-ctc']);
    assert.equal(comparison.decidingAxis, 'guaranteed_pay');
    assert.equal(comparison.guaranteedPayGap, 250_000);
    // The whole point of the feature: the larger headline number is the worse
    // offer on money the candidate can actually rely on.
    assert.equal(comparison.largestCtcIsNotBestGuaranteed, true);
  });

  it('calls a sub-2% difference a tie instead of picking a winner', () => {
    const comparison = compareOffers([
      input('a', 0, { fixedAnnualPay: 1_000_000 }),
      input('b', 1, { fixedAnnualPay: 1_010_000 }),
    ]);

    // Ranking a 1% difference would dress up noise as a finding. The honest
    // answer is that money is not what decides this one.
    assert.equal(comparison.decidingAxis, 'tied');
    assert.equal(comparison.guaranteedPayGap, 10_000);
  });

  it('refuses to rank across currencies', () => {
    const comparison = compareOffers([
      input('rupees', 0, { currency: 'INR', fixedAnnualPay: 2_000_000 }),
      input('dollars', 1, { currency: 'USD', fixedAnnualPay: 90_000 }),
    ]);

    // Ranking these needs an exchange rate the product does not hold.
    assert.deepEqual(comparison.rankedDocumentIds, []);
    assert.equal(comparison.decidingAxis, 'incomparable');
    assert.deepEqual(comparison.currencies, ['INR', 'USD']);
  });

  it('excludes an offer with no comparable figure rather than ranking it last', () => {
    const comparison = compareOffers([
      input('known', 0, { fixedAnnualPay: 1_000_000 }),
      input('silent', 1, {}),
    ]);

    assert.deepEqual(comparison.rankedDocumentIds, ['known']);
    assert.equal(comparison.decidingAxis, 'incomparable');
    assert.equal(comparison.guaranteedPayGap, null);
  });

  it('keeps offers in their display order regardless of rank', () => {
    const comparison = compareOffers([
      input('second', 1, { fixedAnnualPay: 2_000_000 }),
      input('first', 0, { fixedAnnualPay: 1_000_000 }),
    ]);

    // "Offer A" has to mean the same thing on every screen, so display order is
    // the caller's position and never the ranking.
    assert.deepEqual(comparison.offers.map((offer) => offer.documentId), [
      'first',
      'second',
    ]);
    assert.deepEqual(comparison.rankedDocumentIds, ['second', 'first']);
  });
});

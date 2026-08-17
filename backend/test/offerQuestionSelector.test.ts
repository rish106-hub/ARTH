import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import type { OfferLetterInterpretation } from '../src/geminiInterpreter.js';
import { compareOffers } from '../src/offerComparisonEngine.js';
import { formatOfferMoney } from '../src/offerMoneyFormat.js';
import { MAX_QUESTIONS, selectQuestions } from '../src/offerQuestionSelector.js';

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

function input(
  documentId: string,
  position: number,
  fields: Partial<OfferLetterInterpretation>,
) {
  return { documentId, position, interpretation: offerLetter(fields) };
}

function idsFor(comparison: Parameters<typeof selectQuestions>[0]) {
  return selectQuestions(comparison).map((question) => question.id);
}

describe('offer money formatting', () => {
  it('writes rupees the way the offers themselves do', () => {
    assert.equal(formatOfferMoney(450_000, 'INR'), '₹4.5L');
    assert.equal(formatOfferMoney(1_000_000, 'INR'), '₹10L');
    assert.equal(formatOfferMoney(12_500_000, 'INR'), '₹1.3Cr');
    assert.equal(formatOfferMoney(45_000, 'INR'), '₹45,000');
  });

  it('does not dress a foreign amount up as rupees', () => {
    assert.equal(formatOfferMoney(90_000, 'USD'), 'USD 90,000');
  });
});

describe('question selection', () => {
  it('asks at most five, keeping the ones that move the verdict', () => {
    const comparison = compareOffers([
      input('risky', 0, {
        employerName: 'Zeta',
        fixedAnnualPay: 1_000_000,
        variableAnnualPay: 500_000,
        joiningBonus: 300_000,
        components: [{
          label: 'Retention pay',
          annualAmount: 150_000,
          frequency: 'unknown',
          classification: 'fixed_pay',
          confidence: 'high',
        }],
      }),
      input('steady', 1, {
        employerName: 'Orbit',
        fixedAnnualPay: 1_250_000,
        variableAnnualPay: 150_000,
      }),
    ]);

    const questions = selectQuestions(comparison);
    assert.equal(questions.length, MAX_QUESTIONS);
    // Location and the pay anchor are real questions, but they lose their slots
    // to five that can change the answer outright.
    assert.deepEqual(questions.map((question) => question.id), [
      'variable_risk',
      'leverage',
      'role_fit',
      'tenure',
      'unverified_component',
    ]);
    for (const question of questions) {
      assert.ok(question.because.length > 0, question.id);
    }
  });

  it('puts the candidate’s own numbers in the wording', () => {
    const comparison = compareOffers([
      input('risky', 0, {
        employerName: 'Zeta',
        fixedAnnualPay: 1_000_000,
        variableAnnualPay: 500_000,
      }),
      input('steady', 1, {
        employerName: 'Orbit',
        fixedAnnualPay: 1_250_000,
        variableAnnualPay: 150_000,
      }),
    ]);

    const risk = selectQuestions(comparison)
      .find((question) => question.id === 'variable_risk');
    // A generic "how do you feel about variable pay?" is answerable without
    // thinking. This one is not.
    assert.match(risk?.prompt ?? '', /Zeta/);
    assert.match(risk?.prompt ?? '', /₹5L/);
    assert.match(risk?.prompt ?? '', /33\.3% of ongoing pay/);
  });

  it('skips the at-risk question when both offers carry the same risk', () => {
    const comparison = compareOffers([
      input('a', 0, { fixedAnnualPay: 1_000_000, variableAnnualPay: 100_000 }),
      input('b', 1, { fixedAnnualPay: 1_200_000, variableAnnualPay: 120_000 }),
    ]);

    // Same share of pay at risk on both sides, so the answer changes nothing.
    assert.ok(!idsFor(comparison).includes('variable_risk'));
  });

  it('asks the role question first when money cannot separate the offers', () => {
    const comparison = compareOffers([
      input('a', 0, { fixedAnnualPay: 1_000_000 }),
      input('b', 1, { fixedAnnualPay: 1_010_000 }),
    ]);

    assert.equal(comparison.decidingAxis, 'tied');
    const questions = selectQuestions(comparison);
    // Not a tie-breaker at this point. It is the decision.
    assert.equal(questions[0].id, 'role_fit');
    assert.match(questions[0].because, /decides it rather than breaking a tie/);
  });

  it('asks about tenure only when there is money paid once to claw back', () => {
    const withBonus = compareOffers([
      input('a', 0, { fixedAnnualPay: 1_000_000, joiningBonus: 200_000 }),
      input('b', 1, { fixedAnnualPay: 1_400_000 }),
    ]);
    const withoutBonus = compareOffers([
      input('a', 0, { fixedAnnualPay: 1_000_000 }),
      input('b', 1, { fixedAnnualPay: 1_400_000 }),
    ]);

    assert.ok(idsFor(withBonus).includes('tenure'));
    assert.ok(!idsFor(withoutBonus).includes('tenure'));
    const tenure = selectQuestions(withBonus)
      .find((question) => question.id === 'tenure');
    assert.match(tenure?.because ?? '', /₹2L once/);
  });

  it('asks about an unread component rather than guessing at it', () => {
    const comparison = compareOffers([
      input('a', 0, {
        fixedAnnualPay: 1_000_000,
        components: [{
          label: 'Special allowance',
          annualAmount: 90_000,
          frequency: 'annual',
          classification: 'other',
          confidence: 'high',
        }],
      }),
      input('b', 1, { fixedAnnualPay: 1_400_000 }),
    ]);

    const question = selectQuestions(comparison)
      .find((item) => item.id === 'unverified_component');
    assert.match(question?.prompt ?? '', /Special allowance/);
    assert.match(question?.prompt ?? '', /₹90,000/);
  });

  it('drops the comparison questions when there is only one offer', () => {
    const comparison = compareOffers([
      input('only', 0, { fixedAnnualPay: 1_000_000, joiningBonus: 100_000 }),
    ]);

    const ids = idsFor(comparison);
    // Nothing to compare against, so a role choice, a leverage check and a
    // city-versus-city question would all be asking about a second offer that
    // does not exist. The negotiation questions still apply.
    assert.deepEqual(ids, ['tenure', 'anchor']);
  });

  it('falls back to the questions that always apply', () => {
    const comparison = compareOffers([
      input('a', 0, { fixedAnnualPay: 1_000_000 }),
      input('b', 1, { fixedAnnualPay: 1_400_000 }),
    ]);

    assert.deepEqual(idsFor(comparison), [
      'leverage',
      'role_fit',
      'location',
      'anchor',
    ]);
  });
});

# ARTH Multi-Offer Comparison Plan

## Goal

A candidate holding two or more job offers uploads every offer letter, answers at
most five questions, and gets two things back:

1. **A verdict.** One offer named, and the single number that decided it.
2. **A negotiation play.** Which employer to push, on which component, by how
   much, and the exact words to use.

The product claim is narrow on purpose: ARTH compares what the offer letters
actually say, and is explicit about what it cannot know. It does not predict
promotions, rate companies, or forecast equity value.

## What already exists

This feature is mostly assembly, not new machinery.

- `backend/src/geminiInterpreter.ts` — `interpretOfferLetter()` already extracts
  employer, role title, currency, annual CTC, fixed pay, variable pay, joining
  bonus, a per-component breakdown with confidence, warnings, and open questions.
- `backend/src/documentParser.ts` — upload parse pipeline, with Sarvam OCR
  fallback for scanned and regional-language documents.
- `tax_documents` — encrypted document storage. Its unique key is
  `(user_id, fy, document_type, sha256_fingerprint)`, so several `offerLetter`
  rows for one user already coexist. No schema change needed to hold N offers.
- `offerLetter` is already an accepted `document_type`.

Missing, and therefore the scope of this plan: comparison, questions, verdict,
negotiation.

## Two defects to fix first

Both are pre-existing, and both get worse the moment we invite five uploads
instead of one.

1. `interpretOfferLetter()` calls Gemini directly. It never consults
   `aiSpendLedger`, so offer extraction is unmetered and uncapped. Every other
   paid path in the backend is metered.
2. `MODEL_PRICES` in `backend/src/aiSpendLedger.ts` contains no Gemini entries.
   `FALLBACK_PRICE` is deliberately the most expensive model known
   (`gpt-5.5-pro`, $30/M input). Metering Gemini without adding its prices would
   throttle the feature immediately rather than overspend — safe, but unusable.

## Model policy

Gemini only, for this feature.

- Extraction: `GEMINI_MODEL` (default `gemini-3.6-flash`). One call per uploaded
  offer letter. Already implemented.
- Question selection: **zero LLM calls.** Deterministic, see below.
- Verdict and negotiation script: **one** Gemini call per comparison session,
  cached on a hash of the normalized offers plus the answers.

OpenAI stays where it is, on spend categorization. Sarvam stays as the OCR
fallback it already is. No new AI provider, no new API key.

Cost per user session: N extraction calls plus one advice call. For three offers
that is four calls of a few thousand tokens each.

## Comparison engine

`backend/src/offerComparisonEngine.ts` — pure functions, no network, no LLM.

Normalizes each offer onto one axis set so the numbers are actually comparable:

- **Guaranteed annual pay** — fixed pay, plus allowances paid regardless of
  performance.
- **At-risk annual pay** — variable, bonus, commission. Recorded with its share
  of CTC, because a 30% at-risk offer and a 5% at-risk offer are not the same
  product even at identical CTC.
- **One-time pay** — joining bonus, relocation, retention. Separated out because
  it flatters year-one CTC and vanishes in year two.
- **Employer contributions** — PF and gratuity accrual. Counted, but never as
  take-home.
- **Estimated monthly take-home** — reuses the existing tax engine. Never
  recalculated here.
- **Unknowns** — every component the extractor marked low confidence, or that
  has no stated payout schedule.

The engine ranks the offers. It is unit-testable without a network, and its
output is the input to everything downstream.

## The five questions

Design decision: questions are **selected deterministically, not invented by the
model.** The engine compares the offers first, finds where they tie or where the
paper cannot answer, and asks only the questions whose answer changes the
ranking. Real extracted numbers are slotted into the wording. That is what makes
the set personal to one candidate rather than a generic quiz.

`backend/src/offerQuestionSelector.ts` — pure. Bank of seven, capped at five,
ranked by how much the answer moves the verdict.

| # | Fires when | Question |
|---|---|---|
| Q1 | at-risk share differs by more than 8pp between offers | If **{employer}**'s ₹{atRisk} variable pay ({share}% of CTC) paid zero this year, could you still cover rent and EMIs? *Comfortably / Tight / No* |
| Q2 | a joining bonus, clawback, or equity cliff is present | Honestly, how long do you expect to stay? *Under a year / 1-2 years / 3+ years* |
| Q3 | always | Ignore the money. Which role's day-to-day work is closer to what you want to be doing in two years? *{roleA} / {roleB} / Neither* |
| Q4 | two or more offers are live | Which of these employers already knows you hold another offer, and has any of them given you a deadline? |
| Q5 | offer locations differ | Which city for each, and are you paying rent yourself? |
| Q6 | a slot remains free | Your current or last fixed CTC, and your notice period? |
| Q7 | any component was extracted at low confidence | **{employer}** lists "{component} ₹{amount}" with no stated payout date. Do you have that commitment in writing? |

Why these and not others:

- Q1 converts CTC into money the candidate can actually rely on. It is the most
  common way a bigger-looking offer is the worse offer.
- Q2 is what makes a joining bonus real or a trap. A clawback on an eighteen-month
  stay is a loan, not pay.
- Q3 is the only non-financial axis, and it is the one candidates regret ignoring.
  Kept unconditional for that reason.
- Q4 is the entire negotiation lever. Without it the negotiation output is
  generic advice.
- Q5 stops the tool from calling ₹18L in Bengaluru a win over ₹16L in Indore.
- Q6 supplies the anchor and the urgency a negotiation ask needs.
- Q7 turns an extraction weakness into a useful prompt instead of a silent
  guess.

Q1 through Q4 fire in almost every real session. Q5 to Q7 fill remaining slots.

## Verdict and negotiation

`backend/src/offerAdvisor.ts` — the single Gemini call.

Input: engine output plus the answers. Output is structured JSON, validated with
zod exactly as the existing interpreters are, and the same untrusted-input guard
is applied to any text originating from a document.

- **Verdict** — the chosen offer, the deciding number stated plainly, and the
  honest caveat. Example shape: *"Zeta, on ₹1.1L more guaranteed annual pay —
  not on its ₹3L larger CTC, which is 30% at risk."*
- **Negotiation play** — which employer to push, which component to ask on
  (fixed pay, not CTC), a specific number, the script, and the walk-away line.
  This runs even when the verdict is unambiguous, because that is where the
  money actually is.

The model phrases the decision. The engine makes it. No number in the output
originates from the model.

## Data model

`backend/sql/020_offer_comparisons.sql`

- `offer_comparisons` — one comparison session per user. Holds normalized engine
  output, the selected question set, the answers, and the cached advice.
- `offer_comparison_offers` — join rows to `tax_documents(id)`, so an offer
  letter is stored once and referenced, never duplicated.

Row-level security policies follow `019_tenant_rls.sql`. No offer letter content
is copied out of the encrypted vault.

## Routes

- `POST /offers/compare` — open a session over a set of vault document ids.
  Returns normalized comparison plus the selected questions.
- `POST /offers/compare/:id/answers` — submit answers, receive verdict and
  negotiation play.
- `GET /offers/compare/:id` — read a past session.

All three sit behind the existing auth wrapper and `dataRateLimit`.

## App

`lib/features/offer_compare/{models,engine,providers,screens}`, mirroring the
existing `lib/features/work_costs` layout. No feature imports another feature's
internals.

Screens:

1. Offers list — upload, see what was extracted, flag anything wrong.
2. Questions — one per card, at most five, answerable in under a minute.
3. Verdict and negotiation — the two outputs, with the caveat visible, not buried.

Entry point from the paycheck shell, alongside the existing work-costs entry.

## Tests

- `backend/test/offerComparisonEngine.test.ts` — normalization and ranking.
- `backend/test/offerQuestionSelector.test.ts` — which questions fire, and the
  five-question cap.
- `backend/test/aiSpendLedger.test.ts` — extend for Gemini pricing.
- `test/offer_compare_engine_test.dart` — app-side display logic.

Engine and selector are pure, so they test with no network and no API key.

## Sequence

1. Gemini prices in the spend ledger, and meter `interpretOfferLetter`.
2. `020_offer_comparisons.sql`.
3. Comparison engine plus tests.
4. Question selector plus tests.
5. Advisor call plus routes.
6. App feature module and screens.

Steps 1 to 4 need no API key to build or test.

## Out of scope

Company ratings, equity valuation, promotion or salary-growth forecasts, and any
claim about a company's culture or stability. ARTH compares what the letters say.

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

## Two defects found on the way in, both now fixed

Both were pre-existing, and both got worse the moment the product invited five
uploads instead of one.

1. `interpretOfferLetter()` called Gemini directly and never consulted
   `aiSpendLedger`, so offer extraction was unmetered and uncapped while every
   other paid path in the backend was metered.
2. `MODEL_PRICES` in `backend/src/aiSpendLedger.ts` held no Gemini entries, and
   `FALLBACK_PRICE` is deliberately the most expensive model known
   (`gpt-5.5-pro`, $30/M input). Metering Gemini without adding its prices would
   have refused every upload rather than overspent — safe, but unusable.

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
that is four calls of a few thousand tokens each, around $0.04 in total. See the
Spend section for how that lands against the cap.

## Comparison engine

`backend/src/offerComparisonEngine.ts` — pure functions, no network, no LLM.

Normalizes each offer onto one axis set so the numbers are actually comparable:

- **Guaranteed annual pay** — fixed pay, plus allowances paid regardless of
  performance.
- **At-risk annual pay** — variable, bonus, commission. Recorded with its share
  of *recurring* pay, because a 30% at-risk offer and a 5% at-risk offer are not
  the same product even at identical CTC. One-time money is left out of that
  denominator: it would otherwise make conditional pay look like a smaller share
  of an ongoing month than it is.
- **One-time pay** — joining bonus, relocation, retention. Separated out because
  it flatters year-one CTC and vanishes in year two.
- **Employer contributions** — PF and gratuity accrual. Counted, but never as
  take-home.
- **Unknowns** — every component the extractor marked low confidence, that fits
  no pay category, or that has no stated payout schedule and so cannot be
  annualized.

Take-home is deliberately *not* computed here. The tax engine lives in the app
(`lib/engine/tax_engine.dart`), and duplicating slab logic in the backend to save
a hop would leave two tax engines to keep in step. See the App section.

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
| Q1 | at-risk shares differ by more than 8pp across the offers | If **{employer}**'s ₹{atRisk} variable pay ({share}% of ongoing pay) paid nothing this year, could you still cover rent and any EMIs? *Comfortably / Tight, but survivable / No* |
| Q2 | a joining bonus, clawback, or equity cliff is present | Honestly, how long do you expect to stay? *Under a year / 1-2 years / 3+ years* |
| Q3 | two or more offers (asked **first** when guaranteed pay ties) | Set the money aside. Which of these is closer to the work you want to be doing in two years? *{roleA} / {roleB} / Neither* |
| Q4 | two or more offers are live | Which of these employers already knows you hold another offer, and has any of them given you a deadline? |
| Q5 | two or more offers — never by detection, see below | Which city would you be living in for each offer, and would you be paying rent yourself? |
| Q6 | a slot remains free | Your current or last fixed CTC, and your notice period? |
| Q7 | any component could not be counted | **{employer}** lists "{component} ₹{amount}" without enough detail to count it. Do you have that commitment in writing, with a payout date? |

Why these and not others:

- Q1 converts CTC into money the candidate can actually rely on. It is the most
  common way a bigger-looking offer is the worse offer.
- Q2 is what makes a joining bonus real or a trap. A clawback on an eighteen-month
  stay is a loan, not pay.
- Q3 is the only non-financial axis, and it is the one candidates regret ignoring.
  Kept unconditional for that reason.
- Q4 is the entire negotiation lever. Without it the negotiation output is
  generic advice.
- Q5 stops the tool from calling ₹18L in Bengaluru a win over ₹16L in Indore. It
  is always eligible and never detected: offer letters do not reliably state the
  posting and the extraction carries no location field, so claiming to detect a
  difference would have been a lie in code. Asking last is the honest version.
- Q6 supplies the anchor and the urgency a negotiation ask needs.
- Q7 turns an extraction weakness into a useful prompt instead of a silent
  guess.

Q1 through Q4 fire in almost every real session. Q5 to Q7 fill remaining slots.
Every selected question also records *why* it earned its slot; that rationale is
never sent to the app, but it is what briefs the advice call so the verdict is
explained in the terms it was decided on.

## Verdict and negotiation

`backend/src/offerAdvisor.ts` — the single Gemini call, over the metered call in
`backend/src/geminiStructuredCall.ts`.

That shared call was extracted from the document interpreter so the budget check,
the output ceiling, the usage accounting and the untrusted-input wrapper exist
once rather than three times. It reads `process.env` directly and imports no
config, which is what keeps the document parser testable with no environment set
— the backend CI job provides none.

Input: engine output plus the answers. Output is structured JSON, validated with
zod exactly as the existing interpreters are, and the same untrusted-input guard
is applied to any text originating from a document.

- **Verdict** — the deciding number stated plainly, and the honest caveat.
  Example shape: *"Zeta, on ₹1.1L more guaranteed annual pay — not on its ₹3L
  larger CTC, which is 30% at risk."* The response schema has **no field** for
  naming a winner, so the model cannot pick a different offer even if it
  disagrees.
- **Negotiation play** — which employer to push, which component to ask on
  (fixed pay, not CTC), a specific number, the script, and the walk-away line.
  This runs even when the verdict is unambiguous, because that is where the
  money actually is.

The model phrases the decision. The engine makes it. Every figure is handed over
pre-formatted so restating one is quoting rather than calculating. The one number
the model may originate is the negotiation ask, because a target to push for is a
recommendation rather than a claim about the letters. Advice naming an offer id
that is not in the comparison is rejected outright rather than retargeted: a
script written for one employer addressed to another is worse than nothing.

## Data model

`backend/sql/020_offer_comparisons.sql`

- `offer_comparisons` — one comparison session per user. Holds normalized engine
  output, the selected question set, the answers, and the cached advice.
- `offer_comparison_offers` — join rows to `tax_documents(id)`, so an offer
  letter is stored once and referenced, never duplicated.

Row-level security policies follow `019_tenant_rls.sql`. No offer letter content
is copied out of the encrypted vault.

## Routes

`backend/src/offerComparisonRoutes.ts`, registered from `routes.ts`. Its own
module because `routes.ts` already carries every other product area.

- `POST /offers/compare` — open a session over a set of vault document ids.
  Returns the normalized comparison plus the selected questions.
- `POST /offers/compare/:id/answers` — submit answers, receive verdict and
  negotiation play. Returns 503 carrying the session when advice is unavailable:
  the answers are saved either way, so an outage never costs the candidate five
  answers.
- `GET /offers/compare/:id` — read a past session.

All three sit behind the existing auth wrapper and `dataRateLimit`. The question
selection rationale is stripped from every response — it exists to make the
choice reviewable and to brief the advice call, not to be read by the candidate.

## App

`lib/features/offer_compare/{models,engine,providers,screens,services}`,
mirroring the existing `lib/features/work_costs` layout. No feature imports
another feature's internals.

One screen at `/offers/compare` with three stages, because this is one decision
made in one sitting:

1. Pick the offer letters, in the order they should appear.
2. Answer the questions, one per card, at most five.
3. Read the verdict and the negotiation play, with the caveat inside the verdict
   card rather than below it.

Take-home is the only figure the app computes, using the existing tax engine on a
deliberately bare basis: a full year of salary, no deductions claimed, cheaper
regime. Those assumptions sit behind a disclosure beside the figure, and live as
constants next to the calculation so the caveat cannot drift from the maths. Only
rupee offers are estimated.

Entry point is the profile screen, beside the existing work-costs entry.

## Tests

- `backend/test/offerComparisonEngine.test.ts` — normalization and ranking.
- `backend/test/offerQuestionSelector.test.ts` — which questions fire, and the
  five-question cap.
- `backend/test/offerAdvisor.test.ts` — that the model is never asked to pick a
  winner, that figures are handed over pre-formatted, that an injection attempt
  in an answer stays data, and that advice naming an unknown offer is rejected.
- `backend/test/cockroachSchema.test.ts` — the new migrations, in both dialects.
- `backend/test/aiSpendLedger.test.ts` — Gemini pricing.
- `backend/test/documentParser.test.ts` — the metered path, including refusal.
- `backend/test/security.test.ts` — the three routes end to end.
- `test/offer_compare_test.dart` — app-side parsing and flow state.

The engine and the selector are pure, so they test with no network and no API key.

## What is built

1. Gemini prices in the spend ledger, and `interpretOfferLetter` metered.
2. `020_offer_comparisons.sql` and its Cockroach counterpart.
3. Comparison engine.
4. Question selector.
5. Advisor call and the three routes.
6. App feature module, screen, and profile entry point.

Steps 1 to 4 need no API key to build or test.

## Spend

Two distinct numbers, and confusing them makes the cap look far tighter than it is.

The ledger **charges** what a call actually cost, from Gemini's reported usage. A
two-page offer letter runs about 3k input and 800 output tokens, so roughly
$0.011. The advice call is text only and lands in the same range.

The ledger separately **refuses to start** a call whose worst case would not fit
in what is left — every input token uncached, the whole output allowance spent.
For a document uploaded as bytes that worst case is about $0.15, because a PDF is
billed per page and its size cannot be measured before it is sent.

So the cap depletes at the actual rate and only stops issuing calls once the
remaining balance drops under one worst case. At the $3 default that is on the
order of 250 document interpretations, with the last $0.15 unusable by design.

`AI_ITEMS_PER_USER_PER_DAY` stays at 200. Each document and each advice call
counts as one item, so no single account can drain the shared cap in a day.

## Still needed to run it

- `GEMINI_API_KEY` set in the deployed backend. Without it the feature degrades to
  "advice unavailable" and the comparison still works.
- The migrations applied. `npm run migrate` picks them up by filename.

`AI_SPEND_CAP_USD` now defaults to $3, so a deploy that does not set it is already
workable.

## Out of scope

Company ratings, equity valuation, promotion or salary-growth forecasts, and any
claim about a company's culture or stability. ARTH compares what the letters say.

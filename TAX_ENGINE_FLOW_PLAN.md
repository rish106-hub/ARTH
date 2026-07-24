# Tax Engine + Question-Flow Overhaul — Plan

Goal: act like a tax consultant. Compute the **correct** liability under FY 2026-27 law (Income-tax Act 2025 / Finance Act 2026), and reach it with the **fewest** questions — prefilling from documents and already-known data, skipping anything the regime or prior answers make irrelevant.

Status: **plan only. No code changes. No push.** Grounded in 3 audits (law research, engine stress-test, flow/prefill audit).

---

## Part 0 — Law baseline (FY 2026-27, sourced)

- Governed by the **new Income-tax Act 2025** (in force 1 Apr 2026). 87A → **s.202** rebate; new regime is default, old regime = **opt-in s.202(4)**. Form 16 → Form 130.
- **Slabs/rebate/standard deduction unchanged** vs FY25-26. The bundled `fy_2026_27.json` values (new slabs 4/8/12/16/20/24L, rebate ₹60k@₹12L, SD ₹75k new / ₹50k old) **match the law** — no change needed there.
- **New regime disallows** 80C, 80CCD(1)/(1B), 80D, 80E, 80G, 80GG, 80TTA/TTB, HRA, 24(b), professional tax. **Allows** standard deduction ₹75k, **80CCD(2) @ 14%**, 80CCH (Agniveer).
- **HRA metro list expands 4 → 8 cities** for FY2026-27 (Rule 279): adds **Bengaluru, Hyderabad, Pune, Ahmedabad**. Old regime only.
- Verify-before-hardcode flags from research: 80TTA/TTB possible merger under new Act; draft allowance-cap hikes; surcharge special-rate 15% cap.

---

## Part A — Engine correctness fixes (`lib/engine/tax_engine.dart`)

Ranked by impact on the number.

| # | Bug | Location | Fix |
|---|-----|----------|-----|
| A1 | **Standard deduction granted to self-employed** in both regimes | `:77`, `:123` | Gate SD to `employmentType == salaried` (or pension). |
| A2 | **80CCD(2) capped at 10% in new regime** — should be **14%** | `_employerNpsDeduction` `:291-295` via `:80` | Cap = 14% (new) / 10% private (old) of basic+DA; pass regime in. |
| A3 | **87A marginal relief wrongly applied to old regime** | `:208-213` reuse `:301-318` | Marginal relief only for new-regime rebate; old regime = hard ₹12,500 @ ₹5L, no relief. |
| A4 | **No surcharge marginal relief** at 50L/1Cr/2Cr/5Cr | `_surcharge` `:320-328` | Add marginal relief at each threshold; add special-rate 15% cap hook. |
| A5 | **Let-out house-property interest dropped entirely** | `:140-145` | Add let-out branch: full interest vs rental income, ₹2L set-off cap. Needs rental-income input. |
| A6 | **80G missing 10%-of-adjusted-GTI qualifying limit** + no 100/50% category + no cash>₹2000 rule | `:174-178` | Model category → rate + limited/unlimited; apply 10%-GTI cap to limited category; flag cash>₹2000 ineligible. |
| A7 | **80CCH (Agniveer) absent** | — | Add, allowed in new regime. (Low frequency; optional.) |
| A8 | Metro HRA = 4 cities only | `s03:1095` `_metros` + engine `isMetroCity` | Expand to 8 for FY2026-27; ideally move metro list into the rule JSON per year. |
| A9 | 80CCD(1) 10%-salary-within-1.5L not modeled | `:147-155` | Optional: enforce the 10%-of-salary sub-cap on own-NPS inside 80C. |

Also: `_calculate80D` missing ₹5k preventive-checkup sub-limit and senior-no-policy medical route (within-cap, no overstatement — low priority).

---

## Part B — Flow redesign (doctor-style, `s03_questions_screen.dart`)

Principle: **triage before deep-dive.** Most users (income ≤ ₹12L → nil tax in new regime) need almost no deduction questions.

### B1. Regime/eligibility gate up front
After income is known, branch:
- **Taxable ≲ ₹12L** → new regime is a near-certain win (nil tax). Show the result, **skip Q05–Q11 entirely**, offer "check old regime anyway?" as opt-in.
- **> ₹12L** → gather old-regime deductions to run the real comparison.
- Ask **regime preference** as a first-class question (or "compute both" default). Deduction questions only render when old regime is in play.

### B2. Employment-type branch
- Self-employed skips HRA / professional-tax / salaried-SD assumptions; instead gets business-income (44ADA presumptive) questions. (A1 depends on this.)

### B3. Amounts, not booleans (feed the engine what it needs)
- **Q05 HRA** — capture **₹ actual HRA received** (prefill from payslip), not just yes/no.
- **Q09 health** — capture **₹ premium (self, parents)** + **preventive checkup**, not just who's covered. This alone unblocks 80D (today it's silently ₹0).
- Add capture for engine-read-but-never-asked fields: `savingsInterest` (80TTA), `fdInterest` (80TTB), `employerNpsContribution` (80CCD(2)), `donationDeductionRatePercent`/category.

### B4. Remove artificial clamps
- Q01 CTC 1–60L, Q04 rent 1–200K, **Q07 home-loan text re-clamp 0.25–5L** (can't enter 0 or true value), Q08 0–50K (keep — matches 80CCD(1B) cap), Q10 year 1–8 + interest ≥₹5K floor, Q11 0.5–100K. Replace with free rupee entry + soft guidance; keep only legally-real caps (80C ₹1.5L, 80CCD(1B) ₹50k) as *guidance*, not input locks.

### B5. Missing segments (gateway questions, then branch)
- **Other income** one-tap gateway: none / savings+FD interest / capital gains / rental / freelance-business → branch only if selected.
- **80CCD(2)** employer NPS (distinct from 80CCD(1B)).
- **Disability/illness**: 80DD (dependent), 80U (self), 80DDB — single "anyone with a disability/major illness?" gate.
- **EV loan** 80EEB (closed to new loans — ask only "existing EV loan pre-Mar 2023?").
- **Residential status** (Resident / RNOR / NRI) — affects taxability; one question.
- **Regime preference**, **multiple employers / job change** (uses existing `jobDurationMonths`).

### B6. Order/dependency
Income → residential status → regime intent → (if old regime) employment branch → HRA/rent → 80C/NPS/home-loan/health/education/donation → other income → age. Each gated so irrelevant branches never render.

---

## Part C — Prefill wiring (reduce friction to confirmations)

| # | Gap | Fix |
|---|-----|-----|
| C1 | **Form 16 never applied to profile** (most authoritative doc ignored) | New `form16_tax_prefill.dart` → map gross, Chapter VI-A, TDS, taxable onto `UserProfile`; register beside `payslipTaxPrefillProvider`; apply in `user_profile_provider`. |
| C2 | Offer-letter CTC doesn't auto-fill Q01 here | Apply `applyConfirmedOfferLetter` in this screen's build when no payslip. |
| C3 | Q06 80C / Q08 NPS / Q09 health prefilled **silently, no note** | Add source-note + convert to one-tap confirm ("₹X from your payslip — correct?"). |
| C4 | Q01 CTC / Q02 employer known from docs but still full-entry | Collapse to confirmation cards. |
| C5 | Proof doc types (`rentReceipts`, `investment80c`, `healthInsurance80d`, `homeLoanCertificate`, `donationReceipts`) parse to `metadata_ready` only | Extend backend parsing to structured fields so Q04/Q06/Q07/Q09/Q11 can pre-answer. (Larger; backend work.) |

---

## New model fields required (`user_profile.dart`)

- Donations: `donationCategory` (enum: pmCares100/govt100Limited/ngo50Limited/religious50Limited) → drives rate + qualifying-limit; keep `donationDeductionRatePercent` derived.
- `rentalIncome`, `letOutInterest` (A5).
- `employerNpsContribution` — already exists; just needs a question.
- `preventiveHealthCheckup`.
- `residentialStatus` enum.
- `regimePreference` enum (auto / new / old).
- `hasDisabilitySelf`/`disabilityPercent`, `hasDisabledDependent`, `criticalIllnessExpense` (80DD/U/DDB).
- Capital gains / business income (if B5 scope includes them).

---

## Sequencing (each a reviewable batch, no push) — decided: all batches in order

- **Batch 1 — Engine correctness — ✅ DONE.** A1 (SD salaried-only), A2 (80CCD(2) 14% new / 10% old), A3 (old-regime 87A no marginal relief), A4 (surcharge marginal relief at all thresholds), A8 (metro list 4→8 moved into per-year rule JSON + case-insensitive `isHraMetro`, city question reads it). 5 lock-in tests added; 81 tests pass; analyze clean. Files: `tax_engine.dart`, `tax_rule_set.dart`, `fy_2025_26.json`, `fy_2026_27.json`, `s03_questions_screen.dart`, `test/tax_rule_engine_test.dart`.
- **Batch 2 — 80D/80G depth — ✅ DONE.** Model: added `DonationCategory` enum (100/50% × limited/unlimited, with `rate`/`hasQualifyingLimit`), `donationInCash`, `preventiveHealthCheckup` fields (constructor/copyWith/toJson/fromJson). Engine: 80D now folds in preventive checkup (≤₹5k within the self cap); new `_calculate80G` applies category rate, the 10%-of-adjusted-GTI qualifying limit for limited categories, and the cash>₹2,000 ineligibility. UI: Q09 captures self/parents/preventive **premiums** (unblocks 80D, previously silently ₹0); Q11 captures **category + cash/digital** and de-clamps the amount, with a live cash>₹2k warning. 7 tests added. Files: `user_profile.dart`, `tax_engine.dart`, `s03_questions_screen.dart`, `test/tax_rule_engine_test.dart`.
- **Batch 3 — regime gate + employment branch + de-clamp — ✅ DONE.** Model: `RegimePreference` enum (auto/new/old) field. Flow: the fixed 12-step switch is now a **dynamic gated list** (`_QStep` enum + `_visibleSteps` + `_needsDeductionInputs`). A new **regime question** (auto default) sits after employment; when the new regime is a clear win (income ≤ rebate+SD band, or user picks New) all deduction steps are skipped — doctor-style. Self-employed skips HRA. Progress bar + chapter markers + journey visuals decoupled via a stable `visualIndex`. De-clamped Q01 CTC, Q04 rent, Q07 home-loan interest (was un-enterable below ₹25k / above ₹5L), Q10 education interest (₹5k floor removed) — sliders still bound their own position but the persisted value is the true amount. Kept legal caps (Q08 ₹50k 80CCD(1B), Q10 8-year 80E). Files: `user_profile.dart`, `s03_questions_screen.dart`, `test/tax_rule_engine_test.dart`.
- **Batch 4 — prefill wiring — ✅ DONE.** New `form16_tax_prefill.dart` (+ `form16TaxPrefillProvider`, `applyForm16Prefill`) maps a confirmed Form 16's gross salary + employer onto the profile — the authoritative annual doc that previously prefilled nothing. Applied in s03 build after payslip (so its true annual gross wins while payslip granularity survives). Offer-letter CTC/employer now auto-fills Q01 when neither payslip nor Form 16 exists. Source-note cards added to Q06 (80C) and Q08 (NPS), which were silently prefilled. 3 tests. Files: `form16_tax_prefill.dart`, `tax_document_provider.dart`, `user_profile_provider.dart`, `s03_questions_screen.dart`, `test/tax_rule_engine_test.dart`.
  - Deliberate limitation: Form 16 reports Chapter VI-A only as an aggregate, so it is NOT decomposed into per-section fields (would risk double-counting). Income + employer only; the totals are carried for display/reconciliation.
- Decision recorded: **other income = full modeling** (Batch 5), **metro list in JSON** (done in Batch 1).

### Original sequencing

1. **Batch 1 — Engine correctness** A1–A4, A8 (pure logic + tests; no UI). Highest correctness ROI, self-contained.
2. **Batch 2 — 80D/80G depth** A6 + B3 (health premium, donation category) + model fields. Unblocks the two most-broken deductions.
3. **Batch 3 — Regime/employment gate + de-clamp** B1, B2, B4. Biggest friction reduction.
4. **Batch 4 — Prefill wiring** C1–C4 (Form 16, confirmations).
5. **Batch 5 — Missing segments** B5, A5, A7 (other income, let-out, disability, EV, residential status).
6. **Batch 6 — Backend structured prefill** C5.

Each batch: implement → unit tests (extend `logic_audit_test.dart`, `tax_rule_engine_test.dart`) → `flutter analyze` → review. Then next audit round before the signed APK.

---

## Open decisions for you

1. **Scope of "other income"** — full capital-gains + business (44ADA) modeling, or gateway-only ("you have capital gains — see a CA") for now?
2. **Metro list** — move into rule JSON per year (clean, future-proof) or just expand the hardcoded `_metros` to 8?
3. **Sequencing** — start with Batch 1 (engine correctness) as recommended, or a different batch first?

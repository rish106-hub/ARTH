# Money Tools Audit — Expense-from-SMS + Savings Goals

Scope: `Spend map` (SMS expense) and `Money goal` (savings plan) under Money Tools.
Status: **findings only — no fixes applied.** Fix decisions to be made together.

Files in scope:
- `lib/models/spend_map.dart`
- `lib/services/finance_message_parser.dart`
- `lib/services/sms_reader_service.dart`
- `lib/providers/spend_map_provider.dart`
- `lib/services/spend_map_service.dart`
- `lib/screens/s33_spend_insights_screen.dart`
- `lib/models/money_goal.dart`
- `lib/providers/money_goal_provider.dart`
- `lib/services/money_goal_service.dart`
- `lib/screens/s32_money_goal_screen.dart`
- `lib/utils/money_format.dart`

Severity: **P0** breaks the core number the feature exists to show · **P1** wrong/misleading result in common cases · **P2** edge case / UX / polish.

---

## A. Monthly normalization (the income-vs-spend inconsistency)

### B1 — `monthsSpan` is derived from transaction extent, not the selected period  · **P0**
`spend_map_provider.dart:226-228` sets `windowStart = earliest txn`, `windowEnd = latest txn`. The scan `since` (period start) is used **only** when there are no txns (`:214`). So the "1/3/6/12 month" choice never reaches `monthsSpan`.
- `monthsSpan` (`spend_map.dart:169`) then reflects however far apart the parsed transactions happen to sit.
- **Symptom:** pick "3 months" but if txns only land in the last few days, `monthsSpan = 1` → every figure is treated as a single month (averages become totals). Pick "3 months" with txns spread over 3 → averages over 3. The denominator is data-dependent, not user-chosen.

### B2 — Income and spend can be divided by different effective month counts  · **P0**
`monthlyIncome = salaryCredited / monthsSpan` (`spend_map.dart:231`) and `monthlySpend = totalSpent / monthsSpan` (`:225`) share ONE `monthsSpan`, but salary credits and spends rarely cover the same set of months.
- If salary spans the full window while spends are concentrated (or vice-versa), one series is normalized against months it doesn't actually cover.
- **This is the reported bug:** income looks scaled to the period while spend looks like one month (or the reverse), and `realisticMonthlySavings` (`:239`) = income − spend inherits the mismatch, over- or under-stating savings.
- Fix direction (to discuss): normalize each series over the **actual selected period length**, or count months-with-activity per series, consistently for both.

### B3 — `monthsSpan` calendar math over-counts partial months  · **P1**
`spend_map.dart:170-174`: `diff = (y2-y1)*12 + m2 - m1; return diff < 1 ? 1 : diff + 1`. This counts calendar months **touched**, not elapsed. Jun 30 → Jul 1 (≈1 day) returns 2. Inflates the denominator → understates every monthly figure.

### B4 — `realisticMonthlySavings` / `savingsRate` mix income and spend from different sources  · **P1**
After the fallback change, `monthlyIncome` can come from a payslip (a clean monthly net figure) while `monthlySpend` is an SMS average over a partial window (B1–B3). Subtracting them (`:240`, `:246`) compares apples to oranges → savings headline can be wildly off.

### B5 — Per-month income in `monthlyTrend` is computed but never rendered, and ignores fallback  · **P2**
`spend_map.dart:monthlyTrend` fills `income` per point from salary credits only; `_MonthlyTrend` (`s33:484-517`) draws `point.spent` only. The income series is dead data, and where it *is* summed it ignores fallback income → inconsistent with the headline.

---

## B. SMS reading & scope (reported point #1: "text says UPI but I fetch all SMS")

### B6 — Copy says "bank & UPI SMS" but the reader ingests the entire inbox  · **P1 (privacy expectation)**
`sms_reader_service.dart:23-45` reads **all** inbox messages (no sender filter); the parser drops non-financial ones afterward. UI copy at `s33:32` and `s33:110` says "reads bank & UPI SMS." Personal SMS bodies are read into app memory even though they're discarded and never synced. Copy and behavior disagree.

### B7 — No sender allowlist  · **P1**
No filtering to transactional short-code senders (DLT IDs like `VM-HDFCBK`, `AD-SBIINB`). Everything is scanned. A sender allowlist would (a) match the privacy copy, (b) cut false positives, (c) speed up large inboxes.

### B8 — Full-inbox read with no `limit`  · **P2 (perf)**
`getInboxSms` (`sms_reader_service.dart:24`) pulls the whole inbox into memory before the date `break`. On phones with thousands of SMS and a 12-month scan this is heavy. Consider a bounded query / count filter.

### B9 — iOS silently unsupported  · **P2**
`another_telephony` is Android-only; on iOS `requestPermission` returns false → "SMS access needed" card, implying a permission problem rather than platform unavailability.

---

## C. Parsing accuracy (reported point: bank salary credits missed)

> Note: recurring-salary inference was added earlier this session; the items below are what remains.

### B10 — Recurring-salary inference can tag multiple credits in the same month → inflates monthly income  · **P1**
`finance_message_parser.dart` `inferRecurringSalary` buckets credits by amount (±₹500) across ≥2 months, but does not cap at one credit per month. If a same-size non-salary credit (or a split/bonus) lands in a month already containing salary, both get tagged, `salaryCredited` exceeds true monthly salary, and `salaryCredited / monthsSpan` inflates income — a concrete path to the "income looks ×N" symptom.

### B11 — Amount regex requires a currency prefix  · **P1**
`_amountRe` (`finance_message_parser.dart:13`) needs `rs`/`inr`/`₹` before the number. Misses `85000.00 credited`, `Rs85000` variants, and worded amounts (`Rs 1.5 Lakh` / `1.5L`). Some bank/salary SMS use these forms.

### B12 — No SMS de-duplication  · **P1**
Banks often send the same transaction twice (bank SMS + UPI-app SMS, or two sender IDs). Nothing dedupes by (amount, date, direction) → double-counted spend and income → inflated totals feeding every downstream number.

### B13 — "First verb wins" direction + substring skip words misfire  · **P2**
`finance_message_parser.dart:189-193` picks debit/credit by earliest matched verb; refund-of-a-debit or "reversed" text can flip direction. `_skipWords` (`:49`) match by substring, so `failed`/`declined` inside a merchant name can drop a legit txn. "reversed" not handled.

### B14 — Multiple income streams collapse to one  · **P2**
`inferRecurringSalary` keeps only the single strongest recurring group; a second recurring income (e.g., rent received) is ignored → income understated for users with more than one stream.

---

## D. Savings-goal planner

### B15 — Goal planner ignores spend-map / fallback income; uses paycheck net pay only  · **P1**
`s32:128-129` computes `projection` from `paycheckProvider.netCredited` alone. If no payslip is confirmed, `netPay = 0` → `availableMonthly = 0` → **every goal shows infeasible**, even though the spend map (now with fallback income) knows the user's income. The two Money-Tools screens use different income truths.

### B16 — "Use detected spend as essentials" double-counts discretionary spend  · **P1**
`_SpendMapHint` (`s32:425, 445`) offers `map.monthlySpend` as the **essentials** value, but the field label and helper text (`s32:237, 249`) say essentials = "rent, food, travel and bills … not your entire bank outflow." `monthlySpend` includes shopping/entertainment/etc. → essentials overstated → `availableMonthly` understated → goal wrongly flagged infeasible.

### B17 — Period picker changes selection but does not refresh data  · **P1 (UX)**
`spend_map_provider.dart:178-180` `selectPeriod` only stores the choice; it never rescans. Tapping 1/3/6/12-month chips (`s33:36-40`) updates the highlighted chip but the numbers don't change until the user separately taps "Rescan SMS". Looks broken/inconsistent.

### B18 — Horizon control is the job-duration selector, capped at 12 months, but the date picker allows 20 years  · **P2**
`s32:211` reuses `JobDurationSelector`/`kJobDurationOptions`; `_selectedHorizonMonths` clamps to 12 (`:87`). Pick a 5-year target via the date picker and the horizon selector silently misrepresents it as ≤12 months. Two controls, inconsistent ranges.

### B19 — `projectGoal` month math + past/near dates  · **P2**
`money_goal.dart:71-74` uses calendar-month diff, `clamp(1, 600)`. A target in the current month or the past collapses to 1 month → `requiredMonthly` = full remaining amount in one month. Also partial months rounded like B3.

### B20 — `current > target` reads as "feasible" with no signal  · **P2**
`money_goal.dart:75` clamps `remaining` to ≥0, so an already-met (or over-saved) goal shows `requiredMonthly = 0` and "feasible" with no "goal already reached" messaging.

### B21 — Single-goal assumption in the editor  · **P2**
`s32:123-127` loads only `goals.first` and the `_loadedId == null` guard prevents switching to a different saved goal. Ordering of `goals` isn't guaranteed. Fine for one goal; breaks with multiple.

---

## E. Sync / display

### B22 — Backend receives fallback-derived figures indistinguishably  · **P2**
`spend_map_service.dart:28-30` pushes `monthlyIncome` / `savings` that may now be payslip-fallback values, with no flag telling the server whether income was SMS-detected or inferred. Analytics can't tell real from estimated.

### B23 — "% of detected income" / "detected" copy shown for fallback income  · **P2**
`s33:550` labels the rate "% of detected income" and `_coachingLine` (`s33:687`) branches on `monthlyIncome <= 0`; with fallback income the number is from a payslip, not "detected" from SMS, so the wording misleads.

---

## Suggested fix ordering (for the joint session)

1. **B1–B4** (normalization) — one coherent model of "period → monthly average," applied to both income and spend. Fixes the reported inconsistency and the savings figure at once.
2. **B12, B10, B11** (parsing accuracy) — dedup first (biggest total-distortion), then income-inflation guardrails, then amount coverage.
3. **B15, B16, B17** (goal planner correctness + period UX) — share one income source, fix essentials semantics, make the period picker live.
4. **B6, B7** (privacy scope + copy) — sender allowlist + honest copy.
5. Remaining **P2s** as polish before the signed APK.

---

## Fix Log — round 1 (not yet pushed)

| ID | Status | What changed |
|----|--------|--------------|
| B1 | ✅ fixed | `_buildMap` sets window = selected period (`since`..now), not txn extent (`spend_map_provider.dart`). |
| B2 | ✅ fixed | Income and spend now averaged over the months **each series** actually covers (`_salaryMonths` / `_spendMonths` in `spend_map.dart`). Same per-month basis. |
| B3 | ✅ fixed | Denominator is now a distinct-month **count**, not calendar-span arithmetic — no partial-month over-count. |
| B4 | ✅ fixed | Falls out of B1–B3 + honest income-source labeling. |
| B5 | ✅ fixed | Trend card captioned "Spend per month"; income series retained for backend only. |
| B6 | ✅ fixed | Copy updated: "reads only bank & UPI transaction SMS … personal messages ignored." |
| B7 | ✅ fixed | Sender allowlist in `sms_reader_service.dart` — only lettered (header-ID) senders read; personal numbers skipped. |
| B8 | ◑ partial | Personal senders no longer enter memory (big cut); a hard SQL `limit` on the inbox query is still not set. |
| B9 | ✅ fixed | `SmsReaderService.isSupported` (Android-only); provider shows "available on Android only". |
| B10 | ✅ fixed | Recurring-salary inference caps at one credit per month per group. |
| B11 | ✅ fixed | Worded `lakh`/`crore` amounts parsed (`_wordedAmountRe`). |
| B12 | ✅ fixed | `_deduplicate` drops duplicate alerts (same amount+direction+day). |
| B13 | ✅ fixed | Skip words matched on word boundaries; `reversed`/`reversal` added. |
| B14 | ✅ fixed | All qualifying recurring groups tagged (multi-stream income). |
| B15 | ✅ fixed | Goal planner uses spend-map/fallback income when no confirmed net pay. |
| B16 | ✅ fixed | Essentials hint uses `monthlyEssentialSpend` (essential categories only). |
| B17 | ✅ fixed | `selectPeriod` re-scans when data exists; re-entrancy guard added. |
| B18 | ✅ fixed | Horizon no longer clamped to 12 months. |
| B19 | ◑ partial | Near/past-date clamp kept; date-picker `firstDate` blocks past dates for new goals. |
| B20 | ✅ fixed | `alreadyFunded` → "goal already funded" guidance. |
| B21 | ⏸ deferred | Multi-goal management needs a goal-list UI — out of scope for a bug-fix pass. |
| B22 | ✅ fixed | Sync pushes `incomeSource` (`detected`/`fallback`/`none`) + `monthlyEssentialSpend`. |
| B23 | ✅ fixed | Rate label reads "estimated income (from your payslip)" when not SMS-detected. |

Tests: 76 pass · `flutter analyze` clean. New coverage added for per-series averaging, dedup, worded amounts, one-per-month cap, multi-stream, essentials.

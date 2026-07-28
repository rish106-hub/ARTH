# ARTH — Feature Ideas

Feature ideas that fit ARTH's wedge (paycheck trust + private evidence), not generic "finance app" clutter.

---

## Core wedge — money recovered or protected

These directly support the north star: verified money recovered or protected per active user per month.

1. **Real claim pack export** — PDF/ZIP with offer line, payslip line, receipt, and a one-page summary the user can email HR. The UI hook exists; the deliverable is missing.

2. **Line-item reconciliation history** — Month-over-month diff (promised vs paid vs SMS credit), not just the latest payslip. "July underpaid by ₹1,200 on HRA" with a trend.

3. **Benefit utilization tracker** — For reimbursements/allowances in the offer letter: annual cap, claimed YTD, expiry ("₹8,400 wellness left, resets April").

4. **Payday checklist** — After salary SMS: "Credit received → matches payslip net? → any claimable items this cycle?" One screen, three checks.

5. **Employer-specific playbooks** — Curated rules for common Indian employers (variable pay timing, reimbursement windows). Starts as content + rules, not AI.

6. **Deadline nudges** — Claim-by dates, proof submission windows, tax investment cutoffs tied to *their* confirmed components, not generic tax spam.

---

## Spend map — make capture more complete

7. **Salary account picker** — User marks which bank SMS to trust for income; reduces noise from other accounts.

8. **"Missing spend" honesty panel** — Cash, cards without SMS, UPI from unlinked accounts — show estimated gap, not fake completeness.

9. **Recurring spend detection** — Rent, SIP, subscriptions from SMS patterns; feeds essentials for savings goal.

10. **Shared household mode (local-only)** — Second person's income as manual entry; split rent/essentials without merging accounts on server.

11. **Category budgets from trend** — "You averaged ₹12k on food (last 3 months); set a soft cap?" Uses period-aware averages.

---

## Bridge features — connect paycheck ↔ spend ↔ tax

These are high leverage because both sides of the product already exist.

12. **One income number everywhere** — User-edited monthly income flows to Home, spend map, and savings goal with a single source of truth and clear "edited vs detected" badge.

13. **Payslip → tax prefill (deeper)** — Confirmed HRA, 80C (PF from payslip), professional tax auto-fill tax diagnostic; less re-entry.

14. **"Tax impact of this paycheck"** — Show TDS on payslip vs expected for their regime; flag over/under deduction (review item, not filing).

15. **Reimbursement → 80C/allowance hints** — Only where legally relevant; deterministic, not chat.

---

## Trust, habit, and retention

16. **Monthly reconciliation ritual** — Push on payday + in-app "5-minute monthly close": confirm credit, scan new bills, mark claims.

17. **Evidence health score** — "Offer ✓, Payslip ✓, SMS ✓, 2 receipts pending review" — gamifies completeness without fake savings claims.

18. **Audit trail per figure** — Tap any rupee → "From July payslip line 4, confirmed 22 Jul" or "Your edit, 28 Jul".

19. **Compare to cohort (anonymous)** — "Users with similar CTC in Bangalore average 18% on rent" — only with enough aggregated backend data and strict privacy.

---

## Onboarding & distribution

20. **Hero-path onboarding** — Pick one loop at signup: "Track paycheck" vs "Map my spending"; current onboarding still skews offer-letter-only.

21. **WhatsApp/share summary** — Redacted one-card share: "This month: earned X, spent Y, 2 items to claim" — no PAN, no employer name unless user opts in.

22. **Play Store story for SMS** — In-app explainer + privacy card for why SMS is needed (required for policy and trust).

---

## What to avoid (fits ARTH guardrails)

- Investment recommendations, credit, lending
- Auto-filing ITR or representing the user
- Generic AI finance chat as a tab
- Bank linking before a regulated Account Aggregator partner is contracted
- Gmail read unless Google verification is complete

---

## Suggested priority (roadmap sketch)

| Tier | Feature | Why |
| --- | --- | --- |
| **Now** | Claim pack export | Closes the wedge; enables north star metric |
| **Now** | Payday checklist + income bridge | Connects SMS ↔ paycheck ↔ Home |
| **Next** | Benefit utilization + deadlines | Recurring claimable value |
| **Next** | Monthly reconciliation history | Habit + differentiation vs calculators |
| **Later** | Employer playbooks, cohort benchmarks | Scale and moat; needs data |

---

## Principle

Prioritize features that add **evidence, deadlines, or recovered money** — not another dashboard.

**Lead loop options for next quarter:**

- **Paycheck trust** — offer → payslip → claim → export
- **Spend clarity** — SMS scan → honest trends → savings goal
- **Tax downstream** — payslip-confirmed inputs → regime comparison (supporting, not headline)

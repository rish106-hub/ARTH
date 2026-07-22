# ARTH Paycheck Product Plan

## Product lock

**ICP:** Indian salaried workers in their first five earning years, starting with people in formal private-sector jobs who receive an offer letter, monthly payslip, and salary credit alert.

**Promise:** ARTH shows what your employer promised, what reached you, and what money still needs an action.

**North Star:** verified money recovered or protected per active user each month.

The first supporting metric is the percentage of monthly pay components automatically matched to a source. Engagement is not the goal. A useful month may require one visit and one claim.

## Why this wedge

Young employees often see CTC, fixed pay, variable pay, reimbursements, benefits, deductions, and net salary as unrelated numbers. Existing products usually explain tax, investments, or spending after the money arrives. ARTH starts from the employment promise and reconciles it against later evidence.

This is harder for a general chatbot to replace because the product value comes from a private, changing evidence graph, deterministic matching, deadlines, and longitudinal history. The moat is not financial advice or generated prose.

## MVP boundary

### In the product

- Import an offer letter or compensation annexure.
- Let the user confirm every extracted pay component.
- Match payslips, salary alerts, bills, and claim deadlines.
- Show promised, received, pending, and claimable money.
- Prepare a claim pack only after an explicit user action.
- Keep source permissions visible and revocable.

### Not in the product

- Holding or moving money.
- Executing investments or recommending securities.
- Filing taxes or representing the user before a tax authority.
- Lending, underwriting, or credit scoring.
- Quietly sending claims or emails on the user's behalf.
- Generic finance chat.

Tax remains a contained optional diagnostic. It preserves the original ARTH questions and tax-gap result, but it is not a primary tab, onboarding step, or headline promise.

## Information architecture

| Area | Job |
| --- | --- |
| Paycheck | One monthly answer: money ready to claim and reconciliation status |
| Promise | The confirmed employment contract and compensation components |
| Inbox | Source-backed events such as payslips, bills, and salary alerts |
| You | Permissions, deletion, profile, and small tools such as Plan your tax |

## Data model

The core object is a `PayComponent` with an amount, cadence, source, status, and optional deadline. Evidence is stored separately and linked to a component. A reconciliation result must always show which source produced it and whether it is confirmed, inferred, or missing.

AI can classify document sections and draft explanations. Deterministic rules calculate amounts, deadlines, differences, reconciliation status, and tax. The user must confirm uncertain extraction before it affects the dashboard.

The document-intelligence provider stays behind a vendor-neutral contract. Sarvam Doc AI is the preferred first candidate for Indian offer letters, payslips, invoices, and receipts because it exposes structured extraction and field confidence. Gemini 3.6 Flash is a possible fallback for difficult multimodal interpretation and plain-language explanations. Neither model can select tax inputs, change engine output, or submit a claim.

## Source rollout

1. **Prototype:** local sample data and user-selected offer-letter import.
2. **Private alpha:** encrypted document storage, payslip import, manual confirmation, and exported claim packs.
3. **Email pilot:** narrow read-only access for salary and reimbursement messages. Request the smallest possible scope and complete provider verification before release.
4. **Bank evidence:** work with an eligible Account Aggregator participant or regulated partner. Do not describe this as a direct integration until access is contracted and tested.
5. **SMS:** treat Android SMS access as optional. Play policy and device restrictions make it a weak foundation for distribution.

Every stage must work without giving ARTH payment authority.

## Privacy and trust rules

- Encrypt source documents at rest and in transit.
- Separate raw evidence from derived values.
- Record why every match was made.
- Let users remove a source and its retained data.
- Never train a shared model on private payroll data by default.
- Use short retention windows for raw inbox content.
- Make sample data impossible to confuse with live data.

## UI direction

The interface uses a payroll-paper palette, strong numeric hierarchy, and a reconciliation rail. It borrows interaction principles seen in Mobbin references from KakaoBank, Plata Card, Origin, and Monarch: grouped account cards, one dominant action, compact transaction rows, and progressive setup. The visual skin and component system are original to ARTH.

## Release gates

Before a real-user pilot:

- Test extraction on at least 50 redacted Indian offer letters across employers.
- Reach at least 95% precision on displayed monetary values after confirmation.
- Show a source and confidence state for every calculated number.
- Complete a deletion and permission-revocation test on Android.
- Have employment and privacy counsel review user-facing claims.
- Prove that a user can reach the first useful reconciliation in under three minutes.

## Product kill criteria

Stop or change the wedge if, after a focused pilot, fewer than 20% of target users have non-trivial variable pay, reimbursements, benefits, or payroll discrepancies worth tracking. A beautiful dashboard is not enough. The product needs recurring recoverable value.

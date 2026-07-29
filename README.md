# ARTH

ARTH is a paycheck-reconciliation and money-clarity app for salaried Indians in their first few earning years.

It starts with the employment promise, then matches later evidence such as payslips, salary credits, bank SMS, bills, and receipts. The goal is simple: show what was promised, what reached the user, where it went, what is still pending, and what can still be claimed.

This is not another budgeting app, investment recommender, or tax chatbot. ARTH is built around private payroll evidence, deterministic reconciliation, and user-confirmed records.

---

## 1. Product thesis

Young salaried employees in India receive compensation as a messy mix of CTC, fixed pay, variable pay, reimbursements, benefits, deductions, and net salary. Most finance products start *after* money reaches the bank account. ARTH starts earlier, at the offer letter, and follows the money all the way to where it is actually spent.

The product wedge is **paycheck trust**:

- Did the employer pay what was promised?
- Which benefits or reimbursements are still unclaimed?
- Which deductions need review?
- Where does the money actually go after it lands?
- Which documents support the answer?
- What can the user do without giving ARTH authority over their money?

**North Star:** verified money recovered or protected per active user each month.

### Supporting metrics

| Metric | Why it matters |
| --- | --- |
| Confirmed compensation components per user | Depth of the evidence graph; drives every downstream answer |
| Documents confirmed / documents uploaded | Extraction quality and review friction |
| SMS transactions auto-categorised without user edits | Parser + AI accuracy; every manual fix is a UX tax |
| Users with a detected salary credit | Whether reconciliation is grounded in real data vs estimates |
| Claimable money surfaced → claim packs prepared | Whether insight converts to recovered money |
| Monthly returning users after first reconciliation | Whether this is a habit or a one-time novelty |

---

## 2. Target user

Indian salaried workers in formal private-sector jobs who receive:

- an offer letter or compensation annexure
- monthly payslips
- salary credit alerts and bank/UPI transaction SMS
- reimbursement bills or benefit receipts
- tax documents such as Form 16, AIS/26AS, or deduction proofs

The early ICP is **not** every taxpayer in India. It is a narrower group: early-career employees who have enough payroll complexity for reconciliation to matter, but not enough finance support to catch every mismatch themselves.

---

## 3. Main surfaces

The app has four tabs:

| Tab | Purpose |
| --- | --- |
| **Home** | Current paycheck reconciliation — promised vs paid vs difference, and money requiring action |
| **Documents** | Offer letters, payslips, receipts, bills, and other evidence with review state |
| **Filing** | Contained tax diagnostic — regime comparison and ranked deduction gaps |
| **Profile** | Identity, permissions, deletion, money tools, and connections |

Two money tools live under Profile:

- **Expenses from SMS** — the spend map (see §5)
- **Savings goal** — a plan built from net pay and observed expenses

---

## 4. Core flow: paycheck reconciliation

1. Add an offer letter or compensation annexure.
2. Confirm the extracted compensation components.
3. Add payslips, salary alerts, bills, and receipts.
4. Review promised, received, pending, and claimable money.
5. Prepare claim evidence only after explicit approval.

### Editable breakdown

Parsers are never fully right. Every line item in **Gross earnings** and **Deductions** is user-editable: correct an amount, rename a label, add a category the parser missed, or remove one it invented.

Manual edits are stored as a **separate override layer** and re-applied on top of every fresh document parse, so a re-scan never silently wipes a correction. Overrides also work with zero documents, which makes fully manual entry possible.

Net pay stays *derived* (`gross − deductions`) rather than directly editable, so the calculation shown to the user can never contradict its own line items.

**Known gap:** Home shows `Difference: —` until an offer letter is confirmed, because there is no "promised" figure to compare against. Working as designed, but it reads as broken to a new user.

---

## 5. Expenses from SMS (spend map)

The newest pillar. ARTH reads **only** bank and UPI transaction SMS on the device to map where money actually goes.

**Scan windows:** 1 month, 3 months, 6 months, 12 months, YTD (3 months recommended as a useful recent baseline).

**Categories:** food, groceries, transport, shopping, bills, entertainment, health, rent, investment, cash, other.

### What it produces

- **Monthly balance** — signed income − spend. Shows a real overspend in red rather than flooring a shortfall to zero.
- **Where it goes** — category breakdown with a share chart and ranked bars.
- **Month by month** — spend plotted against income on a shared baseline.
- **Forecast** — projected month-end spend from the current run-rate, pace vs the user's own average, and biggest per-category movers.
- **Transactions** — every parsed transaction with date, time, contact, amount and category; tapping one shows the original SMS text and offers to open the messaging app.

### Categorisation: rules first, AI second

1. On-device regex + merchant keyword rules classify most transactions with no network call.
2. Only transactions the rules leave as `other` go to an AI pass (Gemini), carrying **minimal redacted text** — the merchant name alone where available; otherwise the SMS body with amounts and any 5+ digit run (account/card/phone numbers) stripped.
3. Low-confidence AI answers are discarded and the transaction stays `other`.
4. User corrections are marked `manual` and are never re-sent to the AI.

### Direction is interpreted, not taken literally

A message reading *"Payment of ₹15,000 received towards your SBI Credit Card"* contains the word *received*, but from the user's perspective it is money **leaving** their account to pay a card bill. ARTH reclassifies these as debits instead of counting them as income — while still treating a genuine *refund* credited to a card as a credit.

### Unclear-transaction review

Anything still uncategorised goes into a full-screen, one-card-at-a-time review: swipe to skip, tap a category to file it and advance. This replaced a flat wall of chips, because categorising several ambiguous SMS at once is where users disengage.

### Additional income

Immediately after SMS permission is granted, ARTH asks once whether the user has income beyond salary (freelance, rent, a side business). Entries are stored in device secure storage and the account's encrypted durable-state backup. They contribute to on-screen figures but are not added to the aggregate spend-map analytics payload.

---

## 6. Tax planning

Tax planning is a contained supporting tool. It does not control the main navigation or turn the product into a second finance dashboard.

The diagnostic covers annual income and employment type, city/rent/HRA, 80C, home-loan interest, NPS, health insurance, education-loan interest, donations and age group — ending in an old-versus-new-regime comparison with ranked deduction gaps and visible calculation assumptions.

The tax calculation is **deterministic and versioned**. No LLM calculates tax, chooses a regime, or invents a deduction.

---

## 7. Notifications

Push is live on Android via FCM. The backend signs its own OAuth JWT and calls the FCM HTTP v1 API directly.

- Device tokens are stored **AES-encrypted at rest**, keyed by a fingerprint hash for dedupe.
- One automatic trigger today: an **overspend alert** when observed monthly spend exceeds detected income.
- Tapping a notification deep-links into the relevant screen.
- Ad-hoc campaigns are sent from the Firebase Console rather than a bespoke admin panel.

---

## 8. Document intelligence boundary

Users upload offer letters, payslips, receipts, Form 16 files, and other tax documents. New evidence is marked for review — ARTH does not pretend a file has been verified until extracted fields are confirmed.

The production boundary is:

1. A document service extracts typed fields with confidence scores.
2. The user confirms uncertain fields.
3. Deterministic reconciliation and tax rules use **only confirmed values**.
4. An optional language model can explain a result, but cannot change a calculated number.

Images are downscaled and compressed on-device before upload (≤2400px JPEG), which keeps a phone photo of a payslip well under the upload ceiling and reduces OCR noise.

---

## 9. Privacy posture

This is the product, not a compliance footnote:

- SMS parsing happens **on-device**. Personal messages are ignored; only bank/UPI transaction patterns are read.
- Parsed transaction records, including the short SMS preview used in the UI, are encrypted and backed up to the authenticated account.
- Text sent for AI categorisation is minimised and redacted (merchant only where possible; amounts and long digit runs stripped).
- User-entered other income is included in the encrypted account backup.
- Documents are encrypted; PAN is encrypted and separately hashed.
- The user can review sources, retention and deletion, and can delete tax and paycheck data while keeping their login.

---

## 10. Guardrails

ARTH does not:

- hold or move money
- submit claims silently
- execute investments or recommend securities
- file an ITR or represent the user before a tax authority
- guarantee a deduction, refund, or financial outcome
- use an LLM as a tax calculator

These exclusions are product decisions, not temporary disclaimers. They keep ARTH away from regulated money movement, investment advice, and silent user representation.

---

## 11. Why this is defensible

ARTH is not defensible because it generates better prose. A general chatbot can explain CTC. It cannot maintain a private evidence graph, remember user-confirmed payroll components, match later documents, track deadlines, and show a source for every rupee without the user rebuilding context every time.

The moat is **workflow state**:

- confirmed compensation structure
- linked payroll evidence
- source-backed reconciliation
- deterministic, versioned rules
- user-controlled permissions and deletion
- longitudinal monthly history

AI can assist extraction and explanation. It cannot be the system of record.

---

## 12. Current build

- Flutter Android app — 28 screens, Riverpod state, GoRouter navigation
- Single design system (`PaycheckType` / `PaycheckColors`, Anek typeface) across every screen
- Fastify backend on Railway
- **CockroachDB**, running the flat schema in `DB_DIALECT=postgres` compatibility mode
- Email/password and Google auth, JWT access tokens with refresh-token rotation
- Encrypted document storage, encrypted PAN, encrypted device tokens
- Gemini for document interpretation and spend categorisation; Sarvam for OCR
- FCM push notifications
- Deterministic FY 2025-26 tax rule engine
- Signed APK releases through GitHub Releases

### Architecture

```text
lib/
  engine/       Versioned tax and reconciliation rules
  models/       Paycheck, spend map, evidence, tax-result, and account models
  providers/    Riverpod state and persistence boundaries
  screens/      Paycheck shell, spend map, and contained tax-planning flow
  services/     Auth, secure storage, SMS parsing, OCR, push, and sync
  theme/        PaycheckType / PaycheckColors design system
  widgets/      Shared ARTH UI primitives
```

```text
backend/
  src/          Fastify API, auth, document parsing, push, security, config
  sql/          Ordered database migrations (15)
  test/         Backend security, parser, and push tests
```

### API surface

Auth (`/auth/*`), account and PAN, documents (upload / confirm / download / patch), spend map (`/spend-map`, `/spend-map/categorize`), money goals, employers, devices (`/devices` register + unregister), and health/ping.

---

## 13. Release process

ARTH is distributed as a signed Android APK through GitHub Releases. Each public release includes the signed APK, a SHA-256 checksum, an update manifest used by the in-app update flow, and release notes for beta users.

The process is intentionally direct because the app is in a controlled beta. Users install from the release artifact, not from local builds.

### Quality bar

Before a signed APK is published, the project is expected to pass:

- Flutter analysis (clean, repo-wide)
- Flutter unit and widget tests (16 test files)
- backend type checks
- backend security, parser, and push tests (8 test files)
- signed APK verification
- checksum generation
- update-manifest generation

Security reporting and backend security details are documented in [SECURITY.md](./SECURITY.md). The internal release procedure is documented in [Direct APK releases](./docs/direct-apk-releases.md). Database design is documented in [database architecture](./docs/database-architecture.md).

---

## 14. Open product questions

An honest list of what is unresolved — not a roadmap commitment:

- **Onboarding predates the newest features.** The first-run flow does not mention SMS expenses or additional income, so a new user meets the most differentiated feature by accident.
- **Empty states read as bugs.** `Difference: —` before an offer letter is the clearest example.
- **Spend capture is incomplete by construction.** SMS-only means cash, some cards, and any bank that does not send parseable alerts are invisible. Figures are labelled as estimates, but the gap is real.
- **No dark mode.** Every colour is currently a static light-theme token.
- **iOS push is inert.** Requires an APNs key and an Apple Developer account.
- **Type scale is still two-tiered.** Colours are unified; heading sizes inherited from the older system have not been reconciled into one scale.
- **Notification strategy is one trigger deep.** Overspend alerts exist; bill reminders, deadline nudges and payday prompts do not.

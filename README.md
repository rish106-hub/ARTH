<p align="center">
  <img src="assets/icon/arth_mark.svg" width="88" alt="ARTH mark" />
</p>

<h1 align="center">ARTH</h1>

<p align="center"><strong>Know what work costs you. Catch what you are owed. Plan before a decision becomes expensive.</strong></p>

<p align="center">
  <a href="https://github.com/rish106-hub/ARTH/releases">Android releases</a> ·
  <a href="https://github.com/rish106-hub/ARTH/actions">Build status</a>
</p>

ARTH is an Android app for early-career salaried Indians. It turns private payroll documents and bank or UPI transaction SMS into a clear money workspace.

It starts with the offer and payslip, not a generic budget. Then it helps a user check pay, keep evidence ready, understand tracked spending, find repeat work costs, and test a major life choice before they commit to it.

> **Product status:** controlled Android beta. The Money workspace updates below are in active development on the current product branch. ARTH is not a bank, lender, broker, or ITR filing service.

![ARTH tax journey preview](assets/images/tax_journey.png)

## The problem

An early-career salary is not one number. It is a mix of CTC, fixed pay, variable pay, reimbursements, deductions, benefits, tax documents, rent, commute, food, subscriptions, and decisions that turn into monthly obligations.

Most tools begin after money lands in an account. They do not help a user answer:

- Did my payslip match what I was promised?
- Is there a reimbursement or benefit I have not claimed?
- What work-related cost keeps repeating?
- What does a move, vehicle, or job change do to my monthly room?
- Which document should I confirm before relying on a tax number?

ARTH is built for those decisions. It uses clear sources and deterministic calculations where correctness matters.

## Who it is for

The first user is a salaried Indian in a formal private-sector job who has some mix of:

- an offer letter or compensation annexure
- monthly payslips and salary-credit SMS
- UPI or bank transaction SMS
- receipts for reimbursements or benefits
- Form 16, AIS/26AS, or deduction proofs

This is deliberately not a product for every taxpayer or every personal-finance use case. It is for a person whose work creates both income and hidden recurring costs, but who does not have a finance team watching their paperwork.

## What ARTH helps a user do

| Job | What ARTH does | What it does not do |
| --- | --- | --- |
| Check pay | Matches confirmed offer, payslip, and salary evidence | Move money or make an employer claim automatically |
| Prepare recovery | Surfaces claims and assembles an evidence pack after approval | Submit claims silently |
| See spending | Parses bank and UPI transaction SMS on-device into a spend map | Claim it knows a live bank balance |
| Plan tax | Runs a deterministic FY 2025-26 comparison and shows gaps | File an ITR or choose a regime for the user |
| Reduce work costs | Lets users tag repeat costs and see their own arithmetic | Judge a merchant or shame spending |
| Test decisions | Models a move, vehicle, or job change as a private estimate | Give lending, credit, or investment advice |

## Product map

The beta has Home, Documents, Filing, and Profile. The product map below is the active information architecture now being built: Documents and Filing become one Plan workspace, while spend and life decisions move into Money.

| Surface | User question | Key tools |
| --- | --- | --- |
| **Home** | “What matters this month?” | tracked monthly position, spend pace, priority action, recovery status |
| **Money** | “Where is work and life costing me?” | SMS spend map, workday costs, commitments, savings goal, decision sandbox |
| **Plan** | “What evidence or tax task is next?” | documents, payslips, tax diagnostic, tax plan, recovery |
| **Profile** | “What data and permissions does ARTH use?” | account, privacy, permissions, connected tools, deletion |

### Core user loop

```text
Offer / payslip / SMS evidence
            ↓
Confirm the facts that matter
            ↓
Understand pay, repeat costs, and commitments
            ↓
Take one action or test one decision
            ↓
Keep the result and evidence ready next month
```

## Current product capabilities

### Paycheck and evidence

- Offer-letter and payslip parsing, with an editable override layer.
- Separate gross earnings, deductions, net pay, pending money, and claimable items.
- Claims and reimbursement packs are prepared only after explicit user approval.
- Document upload, OCR, review, confirmation, and encrypted storage.
- A monthly-close flow for bills, claims, and evidence health.

The rule is simple: a parsed document is not a verified fact. ARTH requires confirmation before a value affects reconciliation or tax calculations.

### SMS spend map

ARTH reads only bank and UPI transaction SMS on the device. It produces a reviewed spend map, categories, monthly trends, forecast pace, and coverage checks.

Categorisation is rules first. Only unresolved transactions may use a minimised, redacted AI classification pass. User corrections stay local and are never sent back for classification.

SMS coverage is incomplete by design. Cash, some cards, and missing notifications can be invisible. Therefore ARTH labels these figures as **tracked**, never as a bank balance or “safe to spend”.

### Workday Cost Lens · in active build

This is the new product wedge.

ARTH finds repeat, identifiable merchant patterns from tracked transactions. The user decides whether each one is a commute, office meal, coffee, work tool, work-social cost, or something else. ARTH does not guess that meaning.

For a confirmed pattern, it shows:

- tracked monthly cost and purchase count
- twelve-month cost if the pattern continues
- a small experiment, such as one fewer purchase per workweek
- the saving arithmetic from the user's median transaction amount

This keeps the feature grounded. It is not generic advice and it does not invent a better lifestyle for the user.

### Monthly Commitments · in active build

Confirmed repeat payments and manual commitments live in one view. It is for rent, EMIs, subscriptions, bills, family support, and other monthly obligations.

Only a confirmed repeat or a user-added item changes the total. Predictions never quietly become commitments.

### Decision Sandbox · in active build

The sandbox helps a user look before they leap. It starts with three decision templates:

1. Move for work
2. Buy a vehicle
3. Change jobs

Each scenario compares the change in tracked monthly room, recurring commitment change, one-off cost, and selected savings-goal timing. Scenarios can be saved, edited, duplicated, or deleted locally.

It is a planning estimate. It never says “you can afford this”, recommends a lender, or treats tracked spending as complete spending.

### Tax planning

Tax is a contained tool inside Plan. The diagnostic covers income, employment type, city and rent/HRA, 80C, home-loan interest, NPS, health insurance, education-loan interest, donations, and age group.

The comparison uses a versioned, deterministic rule engine for FY 2025-26. An LLM does not calculate tax, select a regime, or make a deduction claim.

## Trust and privacy

For this product, trust is part of the interface.

- SMS parsing happens on-device. Personal messages are ignored.
- AI categorisation receives the smallest useful input. Merchant-only text is preferred; long digit runs and amounts are redacted where body text is needed.
- Documents, PAN data, device tokens, and authenticated user data are encrypted at rest.
- User corrections remain an override layer. A re-scan cannot silently erase them.
- Users can inspect privacy settings and delete scoped local data.
- ARTH does not hold money, execute trades, issue credit, file returns, or submit claims without a user action.

## Design principles

- **One useful next action.** Home should help, not repeat a payroll table.
- **Show the source.** A number should tell the user whether it came from a payslip, SMS, or a manual input.
- **Keep the user in control.** Confirm before a record changes the answer.
- **Use plain math.** Show inputs and arithmetic for a cost or decision estimate.
- **Do not pretend coverage is complete.** Tracked money is not account balance.
- **Keep tax contained.** Tax matters, but it should not take over the product.

## What ARTH does not do

- Bank linking without an Account Aggregator flow
- Investment recommendations or execution
- Credit underwriting or lender recommendations
- Automatic employer claim submission
- Automatic ITR filing or representation before a tax authority
- A generic “ask anything” finance chatbot
- Guarantees of savings, refunds, deductions, or financial outcomes

## Technical shape

```text
Flutter Android app
  ├── Riverpod state and GoRouter navigation
  ├── on-device SMS extraction and review
  ├── secure local storage and encrypted sync
  ├── document capture, OCR, confirmation, and claim-pack export
  └── deterministic payroll, spending, recovery, and tax engines

Fastify backend
  ├── authentication and account state
  ├── encrypted document and device-token handling
  ├── document interpretation pipeline
  ├── spend-map sync and controlled AI classification
  ├── FCM push delivery
  └── CockroachDB / PostgreSQL-compatible migration path
```

The app uses Flutter and Dart. The backend uses Node.js, TypeScript, Fastify, and a CockroachDB-compatible PostgreSQL setup. Gemini and Sarvam can assist interpretation, but deterministic app logic remains the source of truth for money and tax calculations.

## Delivery and quality

ARTH is distributed as a signed Android APK through [GitHub Releases](https://github.com/rish106-hub/ARTH/releases). Releases include the APK, checksum, update manifest, and beta notes.

The required checks mirror CI:

```bash
# App, from repo root
flutter pub get
dart format --output=none --set-exit-if-changed lib/ test/ && flutter analyze --no-fatal-infos
flutter test

# Backend, from backend/
npm ci
npm run check
npm test
npm run build
```

## Brand assets

The ARTH mark and Android app icon are versioned in the repository:

- [`assets/icon/arth_mark.svg`](assets/icon/arth_mark.svg)
- [`assets/icon/icon_1024.png`](assets/icon/icon_1024.png)
- [`assets/icon/icon_foreground.png`](assets/icon/icon_foreground.png)

The product uses the Anek typeface and a restrained black, white, and muted-blue visual system. The goal is clarity under financial stress, not a busy finance dashboard.

## Roadmap boundary

ARTH is moving from a paycheck-reconciliation tool into a work-life money workspace. The direction is deliberate:

1. Help users recover or protect money they are already owed.
2. Help them see repeat costs created by work.
3. Help them test a costly decision before it becomes a commitment.

The product will not expand into lending, trading, or a generic personal-finance feed just to add more screens.

---

Built for salaried Indians who want clear facts before a money decision becomes permanent.

# ARTH

ARTH is a paycheck-reconciliation app for salaried Indians in their first few earning years.

It starts with the employment promise, then matches later evidence such as payslips, salary credits, bills, and receipts. The goal is simple: show what was promised, what reached the user, what is still pending, and what can still be claimed.

This is not another budgeting app, investment recommender, or tax chatbot. ARTH is built around private payroll evidence, deterministic reconciliation, and user-confirmed records.

## Product thesis

Young salaried employees in India often receive compensation as a messy mix of CTC, fixed pay, variable pay, reimbursements, benefits, deductions, and net salary. Most finance products start after money reaches the bank account. ARTH starts earlier, at the offer letter.

The product wedge is paycheck trust:

- Did the employer pay what was promised?
- Which benefits or reimbursements are still unclaimed?
- Which deductions need review?
- Which documents support the answer?
- What can the user do without giving ARTH authority over their money?

The North Star is verified money recovered or protected per active user each month.

## Target user

ARTH is built first for Indian salaried workers in formal private-sector jobs who receive:

- an offer letter or compensation annexure
- monthly payslips
- salary credit alerts
- reimbursement bills or benefit receipts
- tax documents such as Form 16, AIS/26AS, or deduction proofs

The early ICP is not every taxpayer in India. It is a narrower group: early-career employees who have enough payroll complexity for reconciliation to matter, but not enough finance support to catch every mismatch themselves.

## Product flow

1. Add an offer letter or compensation annexure.
2. Confirm the extracted compensation components.
3. Add payslips, salary alerts, bills, and receipts.
4. Review promised, received, pending, and claimable money.
5. Prepare claim evidence only after explicit approval.
6. Open **You → Small tools → Plan your tax** when a tax diagnostic is useful.
7. Finish the tax result and return directly to the Paycheck profile.

## Main areas

- **Paycheck:** the current reconciliation and money requiring action
- **Promise:** compensation components confirmed from the employment contract
- **Inbox:** offer letters, payslips, receipts, bills, and other evidence
- **You:** permissions, deletion, profile information, and small tools

## Why this is defensible

ARTH is not defensible because it has better generated prose. A general chatbot can explain CTC. It cannot maintain a private evidence graph, remember user-confirmed payroll components, match later documents, track deadlines, and show a source for every rupee without the user rebuilding context every time.

The moat is workflow state:

- confirmed compensation structure
- linked payroll evidence
- source-backed reconciliation
- deterministic rules
- user-controlled permissions and deletion
- longitudinal monthly history

AI can assist extraction and explanation. It cannot be the system of record.

## Tax planning

Tax planning is a contained supporting tool. It does not control the main navigation or turn the product into a second finance dashboard.

The tax tool preserves ARTH's original diagnostic:

- annual income and employment type
- city, rent, and HRA
- 80C investments
- home-loan interest
- NPS
- health insurance
- education-loan interest
- donations and age group
- old-versus-new-regime comparison
- ranked deduction gaps and visible calculation assumptions

The tax calculation is deterministic and uses versioned rules. No LLM calculates tax, chooses a regime, or invents a deduction.

## Document intelligence boundary

The current app lets users upload offer letters, payslips, receipts, Form 16 files, and other tax documents. New evidence is marked for review. ARTH does not pretend that a local file has been verified until extracted fields are confirmed.

The production boundary is:

1. A document service extracts typed fields with confidence scores.
2. The user confirms uncertain fields.
3. Deterministic reconciliation and tax rules use only confirmed values.
4. An optional language model can explain a result, but cannot change calculated numbers.

The backend already supports deterministic parsing for some document paths and model-assisted interpretation where configured. The client should continue to depend on a vendor-neutral extraction contract, not on one model-specific UI path.

## Guardrails

ARTH does not:

- hold or move money
- submit claims silently
- execute investments or recommend securities
- file an ITR or represent the user before a tax authority
- guarantee a deduction, refund, or financial outcome
- use an LLM as a tax calculator

These exclusions are product decisions, not temporary disclaimers. They keep ARTH away from regulated money movement, investment advice, and silent user representation.

## Current build

- Flutter Android app
- Riverpod state management
- GoRouter navigation
- Fastify backend
- email/password and Google auth paths
- JWT access tokens and refresh-token rotation
- encrypted document storage paths
- Neon-style SQL migrations
- signed APK release workflow through GitHub Releases
- deterministic FY 2025-26 tax rule engine

## Architecture

```text
lib/
  engine/       Versioned tax and reconciliation rules
  models/       Paycheck, evidence, tax-result, and account models
  providers/    Riverpod state and persistence boundaries
  screens/      Paycheck shell and contained tax-planning flow
  services/     Authentication, secure storage, sync, and future extraction APIs
  widgets/      Shared ARTH UI primitives
```

```text
backend/
  src/          Fastify API, auth, document parsing, security, config
  sql/          Ordered database migrations
  test/         Backend security and parser tests
```

## Release status

ARTH is distributed as a signed Android APK through GitHub Releases.

Each public release includes:

- the signed APK
- a SHA-256 checksum
- an update manifest used by the app update flow
- release notes for beta users

The release process is intentionally direct because the app is still in a controlled beta stage. Users install from the release artifact, not from local builds.

## Release quality bar

Before a signed APK is published, the project is expected to pass:

- Flutter analysis
- Flutter unit and widget tests
- backend type checks
- backend security and parser tests
- signed APK verification
- checksum generation
- update-manifest generation

Security reporting and backend security details are documented in [SECURITY.md](./SECURITY.md). The internal release procedure is documented in [Direct APK releases](./docs/direct-apk-releases.md).

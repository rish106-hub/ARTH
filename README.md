# ARTH

ARTH is a paycheck-reconciliation app for salaried Indians. It starts with the employment promise, matches later evidence, and shows money that has been received, is still pending, or can still be claimed.

Tax planning is a contained supporting tool. It does not control the main navigation or turn the product into a second finance dashboard.

## Product flow

1. Add an offer letter or compensation annexure.
2. Confirm the extracted compensation components.
3. Add payslips, salary alerts, bills, and receipts.
4. Review promised, received, pending, and claimable money.
5. Prepare claim evidence only after explicit approval.
6. Open **You → Small tools → Plan your tax** when a tax diagnostic is useful.
7. Finish the tax result and return directly to the Paycheck profile.

There is no budgeting, goal-planning, fixed-commitment, or “How are you getting paid?” flow in this branch.

## Main areas

- **Paycheck:** the current reconciliation and money requiring action
- **Promise:** compensation components confirmed from the employment contract
- **Inbox:** offer letters, payslips, receipts, bills, and other evidence
- **You:** permissions, deletion, profile information, and small tools

## Tax planning

The tax tool preserves the original ARTH diagnostic:

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

The current prototype allows users to select offer letters, receipts, payslips, and images. It marks new evidence for review and never pretends that a local file has already been verified.

The planned production boundary is:

1. A document service extracts typed fields with confidence scores.
2. The user confirms uncertain fields.
3. Deterministic reconciliation and tax rules use only confirmed values.
4. An optional language model can explain a result, but cannot change calculated numbers.

Sarvam Doc AI is the preferred first extraction candidate for Indian documents and receipts. Gemini 3.6 Flash is a possible fallback for difficult multimodal interpretation and plain-language explanations. The client should depend on a vendor-neutral extraction contract.

## Guardrails

ARTH does not:

- hold or move money
- submit claims silently
- execute investments or recommend securities
- file an ITR or represent the user before a tax authority
- guarantee a deduction, refund, or financial outcome
- use an LLM as a tax calculator

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

## Run locally

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Build an Android debug APK:

```bash
flutter build apk --debug
```

Beta users receive signed builds through public GitHub Releases. See
[Direct APK releases](./docs/direct-apk-releases.md) for the release and update
steps.

See [SECURITY.md](./SECURITY.md) for vulnerability reporting and backend security details.

# ARTH

ARTH is a tax-aware money planning app for salaried Indians whose compensation
and responsibilities have become harder to reason about than a simple monthly
budget.

## Product Proposition

ARTH turns compensation, real take-home, fixed commitments, planned investing,
liquid savings, and a primary goal into a working monthly money plan.

The product answers three questions:

1. What money reaches me?
2. What is already committed?
3. What can I still assign, and what decision matters next?

The initial user is a first-generation affluent salaried Indian earning roughly
₹25–50 lakh, often with variable pay, equity compensation, loans, dependants, or
major financial goals.

Tax is a supporting intelligence layer. It can improve the annual income view,
compare regimes, identify possible deductions, and prepare supporting evidence.
It is not the product's primary navigation or promise.

## Current Product

The main application has four areas:

- **Today:** usable monthly money and one prioritized decision
- **Income:** fixed pay, variable pay, equity compensation, take-home, and tax
- **Plan:** monthly allocation, liquid runway, primary goal, and scenarios
- **You:** account, assumptions, privacy, support, and data controls

The setup flow collects only explicit user inputs. ARTH does not derive monthly
take-home from CTC or silently treat compensation as spendable cash.

The current decision engine prioritizes:

1. Completing the money baseline
2. Excessive fixed commitments
3. Insufficient liquid runway
4. An underfunded primary goal
5. Tax mapping
6. Routine plan review

## Working Features

- Secure, user-scoped local money-plan persistence
- Compensation split across fixed, variable, and equity pay
- Monthly available-money calculation
- Commitment and planned-investing allocation view
- Liquid-savings runway calculation
- Primary-goal progress
- One-time purchase scenario
- Existing tax regime and deduction engine as a supporting module
- Document Vault for Form 16, AIS, and supporting proof
- Account, optional PAN vault, privacy controls, and data deletion

## Guardrails

ARTH does not:

- File an ITR or submit data to the Income Tax Department
- Guarantee a deduction, return, or financial outcome
- Recommend individual securities or investment products
- Move money or execute investments
- Infer bank balances or spending that the user did not provide
- Replace a CA, registered investment adviser, lawyer, or insurer

Tax and money outputs are deterministic estimates based on explicit inputs and
versioned rules. Assumptions must remain visible. Product-specific investment
advice requires the appropriate regulated structure and is outside this build.

## Architecture

```text
lib/
  engine/       Versioned tax and deduction calculations
  models/       Money plan, tax result, account, and document models
  providers/    Riverpod state and persistence boundaries
  screens/      Product and supporting module screens
  services/     Authentication, secure storage, sync, and document APIs
  widgets/      Shared UI primitives
```

The money baseline is represented by `MoneyPlan`. `MoneySnapshot` performs the
monthly allocation and runway calculations. `nextMoneyDecision` is a
deterministic policy. No LLM chooses or ranks financial actions.

## Run Locally

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Build an Android debug APK with:

```bash
flutter build apk --debug
```

## Security

Local financial inputs use OS keychain or keystore-backed secure storage.
Authentication tokens and user-scoped state are cleared on sign-out. The
Profile screen can delete the money baseline and existing tax data.

See [SECURITY.md](./SECURITY.md) for vulnerability reporting and backend
security details.

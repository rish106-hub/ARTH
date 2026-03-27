# ARTH

ARTH is a Flutter Android app for Indian taxpayers that identifies likely missed deductions, compares old vs new tax regimes, and turns the result into action cards, a progress tracker, and a shareable summary.

> Not a rupee less. Not a rupee more.

## What The App Does

- Captures a lightweight tax profile through onboarding
- Computes old-regime and new-regime tax estimates for FY 2025-26
- Finds likely deduction gaps through a rule-based trigger engine
- Shows deduction cards with deadlines and action steps
- Tracks completion progress locally
- Generates a shareable tax-gap card

This is a tax-gap discovery product, not an ITR filing platform and not a substitute for professional tax advice.

## Current Product Status

Verified in this repository as of 2026-03-27:

- `flutter test`: passing
- `flutter build apk --debug`: passing
- Logic audit sweep: passing across `12,960,000` generated profile permutations
- Narrow-screen UI audit: passing across major app screens on `320x740`

Artifacts generated during the audit:

- [AUDIT_LOG.md](./AUDIT_LOG.md)
- [LOGIC_AUDIT_RESULTS.md](./LOGIC_AUDIT_RESULTS.md)

## Tech Stack

| Layer | Stack |
| --- | --- |
| App | Flutter |
| Language | Dart |
| State | Riverpod |
| Navigation | go_router |
| Local persistence | shared_preferences |
| Backend integration | Firebase Core, Auth, Firestore, Remote Config |
| Sharing | screenshot, share_plus |
| UI motion | flutter_animate, lottie |

## Product Flow

1. Splash and account entry
2. Welcome and guided onboarding
3. Tax-profile questionnaire
4. Gap reveal
5. Old vs new regime comparison
6. Deduction cards and detail views
7. Action plan
8. Progress tracker
9. Share card
10. Settings

Primary entry points:

- [lib/main.dart](./lib/main.dart)
- [lib/app.dart](./lib/app.dart)
- [lib/engine/tax_engine.dart](./lib/engine/tax_engine.dart)
- [lib/engine/gap_finder.dart](./lib/engine/gap_finder.dart)

## Project Structure

```text
lib/
├── engine/       Tax and gap logic
├── models/       Core data models
├── providers/    Riverpod state and derived state
├── screens/      Product screens (s00-s12)
├── services/     Local persistence and cloud sync helpers
├── theme/        Colors, typography, component theme
└── widgets/      Reusable UI building blocks

assets/
├── images/
├── lottie/
└── tax_data.json

firebase/
├── firestore.rules
└── firestore.indexes.json

database/
└── schema.sql
```

## Design System

The app uses a dark-first premium fintech visual language.

- Background: charcoal and near-black surfaces
- Primary accent: gold
- Supporting accents: teal, amber, red, green
- Typography: Inter + Space Grotesk

Theme definitions live in [lib/theme/app_theme.dart](./lib/theme/app_theme.dart).

## Tax Logic Coverage

The app currently models FY 2025-26 logic around:

- Standard deduction
- Old vs new regime slab comparison
- 87A rebate handling
- 80C
- 80CCD(1B) NPS
- 80D insurance prompts
- 80GG rent without HRA
- 24(b) home-loan interest
- 80E education-loan interest
- 80TTA / 80TTB informational prompts
- 80CCD(2) employer NPS routing prompt

Source files:

- [lib/engine/tax_engine.dart](./lib/engine/tax_engine.dart)
- [lib/engine/gap_finder.dart](./lib/engine/gap_finder.dart)
- [assets/tax_data.json](./assets/tax_data.json)

## Important Accuracy Notes

The engine is stable under the audited sweep, but some parts are still approximation-driven because the app does not collect all required rupee-level inputs.

Known limitations:

- HRA and salary-structure modeling are estimated from profile-level inputs
- 80GG uses estimated adjusted total income logic
- Donation treatment is simplified
- Health insurance tax payable is conservative because premium amounts are not collected
- 80TTA and 80TTB are surfaced as informational opportunity prompts, not exact modeled interest deductions
- 80CCD(2) is surfaced as an employer-routing opportunity, not a self-claimable user input

If exact tax filing accuracy is required, the onboarding model must be expanded to collect more detailed salary and deduction data.

## Firebase And Cloud Status

Implemented:

- Firebase initialization
- Anonymous-auth-backed sync support
- Firestore account/profile sync helpers
- Remote Config helper

Current repo caveats:

- The app now degrades safely when Firebase is unavailable
- Done-gap sync exists at the service layer but is not fully wired into the active UI state flow
- Budget alert has a screen and flag plumbing, but the active navigation path is limited
- Google Sign-In is not implemented in the current `lib/services/` code even though earlier README copy claimed it

## Local Setup

### Prerequisites

- Flutter stable
- Android SDK
- Java 17

### Install

```bash
git clone https://github.com/rish106-hub/ARTH.git
cd ARTH
flutter pub get
```

### Run

```bash
flutter run
```

## Firebase Setup

This repository already includes:

- [lib/firebase_options.dart](./lib/firebase_options.dart)
- `android/app/google-services.json`

If you want to point the app to a different Firebase project:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

Deploy Firestore rules with:

```bash
firebase deploy --only firestore:rules
```

## Testing

Run the full test suite:

```bash
flutter test
```

Run the targeted audits:

```bash
flutter test test/logic_audit_test.dart
flutter test test/ui_audit_test.dart
```

## Build Outputs

Debug APK:

```bash
flutter build apk --debug
```

Output:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

Release bundle:

```bash
flutter build appbundle --release
```

## CI/CD

GitHub workflows present in this repo:

- [ci.yml](./.github/workflows/ci.yml): format, analyze, test, build debug APK
- [release.yml](./.github/workflows/release.yml): build release AAB and upload to Play Store internal track on version tags

Release workflow expects these GitHub secrets:

- `GOOGLE_SERVICES_JSON`
- `KEYSTORE_BASE64`
- `KEYSTORE_STORE_PASSWORD`
- `KEYSTORE_KEY_PASSWORD`
- `KEYSTORE_KEY_ALIAS`
- `PLAY_STORE_SERVICE_ACCOUNT_JSON`

## Release Readiness Checklist

- [ ] Confirm Finance Act assumptions for the target filing year
- [ ] Expand onboarding if exact rupee-level tax computation is required
- [ ] Complete wiring for cross-device done-gap sync
- [ ] Decide whether Budget Alert should stay active and route users into it
- [ ] Implement or remove dormant dependencies/features such as analytics, messaging, and Google Sign-In
- [ ] Resolve remaining informational lints from `flutter analyze`
- [ ] Verify release signing and Play Console configuration
- [ ] Run emulator and physical-device QA on multiple screen sizes

## Repository Notes

This repo is Android-focused today. iOS/macOS release setup is not complete in the current workspace state.

## License

No license file is currently present in this repository.

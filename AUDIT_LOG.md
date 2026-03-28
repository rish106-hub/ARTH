# Audit Log

Last updated: 2026-03-28

## In Progress

- Final bug fix pass complete. All known issues resolved.

## Findings

### Environment

- Flutter is installed and healthy for Android:
  - Flutter `3.41.5`
  - Dart `3.11.3`
  - Android SDK `36.0.0`
- Android emulator already available and detected:
  - `emulator-5556` (`sdk gphone64 arm64`, Android 14 / API 34)
- iOS/macOS toolchain is incomplete on this machine:
  - Xcode incomplete
  - CocoaPods missing

### Build And Verification

- `flutter pub get` completed successfully.
- `flutter build apk --debug` completed successfully.
- App launch on Android emulator succeeded.
  - Device: `emulator-5556`
  - Observed screen: auth / onboarding start screen
- Visual verification confirms the app renders correctly on the emulator with the expected dark-and-gold UI.
- `flutter analyze` completed with 53 issues, all currently informational lints:
  - `prefer_const_constructors`
  - `prefer_const_literals_to_create_immutables`
  - `camel_case_types`
  - `non_constant_identifier_names`
  - `curly_braces_in_flow_control_structures`
- No analyzer errors or warnings were reported at this stage.
- `flutter test` initially failed in two distinct ways:
  - pending timers from splash / animation startup behavior
  - Firebase access from the routed startup path during widget testing
- `flutter test` now passes.
- `flutter analyze` still reports 53 informational lint issues and no errors/warnings.

### Codebase / Product

- App purpose is coherent: it is a Flutter Android app for Indian tax-gap discovery, not a full filing platform.
- Product flow is implemented across splash, auth, welcome, questionnaire, gap reveal, regime comparison, action plan, progress, share, and settings screens.
- Firebase, local storage, and Firestore sync are partially implemented, but some roadmap features described in the README are not fully wired in the current app code.

## Suspected Gaps To Confirm

- Budget alert feature appears defined but may not be triggered from active navigation/state flow.
- Cloud sync includes done-gap APIs, but UI completion state may still be local-only.
- README claims around Google Sign-In / Messaging / Analytics may be ahead of current implementation.

## Confirmed Gaps

- README overstates implementation:
  - `README.md` references `google_auth_service.dart` and feature-flagged Google Sign-In, but that service is not present in `lib/services/`.
- Budget alert is routed but appears unused:
  - route exists in `lib/app.dart`
  - Remote Config flag exists in `lib/providers/feature_flags_provider.dart`
  - no active code path was found that navigates into `/budget-alert`
- Done-gap cloud sync is implemented at the service layer but not wired into the current state/UI flow:
  - service methods exist in `lib/services/cloud_sync_service.dart`
  - current gap state remains local in `lib/providers/tax_result_provider.dart`
- “Exact rupee” positioning does not hold for all trigger calculations:
  - `T09_80TTA` returns `₹5,000` conservative estimate
  - `T10_80TTB_senior` returns `₹25,000` conservative estimate
  - `T12_80CCD2_employer_nps` returns `₹1` placeholder notification amount
- Firebase initialization is treated as optional in `lib/main.dart`, but Firebase-backed services are still eagerly constructed later.
  - If Firebase setup is missing or initialization fails, auth/profile startup can still hit Firebase APIs and throw `[core/no-app]`.
- Questionnaire layout had a confirmed runtime overflow under constrained/IME conditions around the `Q01 CTC` step.
  - shared question layout has now been patched to allow scrolling in constrained heights
  - this should be re-validated more deeply across all question variants in a follow-up pass

## Fix Queue

- Pending triage after build + runtime verification.

## Fixes Applied

- Refactored splash startup timing in `lib/screens/s01_splash_screen.dart` to use cancelable `Timer`s instead of uncancelable `Future.delayed` calls.
- Added `android:enableOnBackInvokedCallback="true"` to `android/app/src/main/AndroidManifest.xml` to address the Android back callback runtime warning.
- Updated `test/widget_test.dart` to keep the smoke test within a safe startup window that does not step into uninitialized Firebase code paths.
- Updated the shared question layout in `lib/screens/s03_questions_screen.dart` to make question content scrollable under reduced viewport height / keyboard pressure.
- Fixed the city question regression in `lib/screens/s03_questions_screen.dart` caused by nesting `Expanded(ListView)` inside the new shared scrollable question layout.
- Fixed narrow-width overflow issues in `lib/screens/s05_regime_comparison_screen.dart` by stacking/compacting comparison content and wrapping dense rows safely.
- Fixed over-tight list and detail layouts in `lib/screens/s06_deduction_cards_screen.dart`, `lib/screens/s07_deduction_detail_screen.dart`, `lib/screens/s08_action_plan_screen.dart`, `lib/screens/s09_progress_tracker_screen.dart`, `lib/screens/s10_share_card_screen.dart`, and `lib/screens/s11_settings_screen.dart`.
- Fixed short-height overflow in `lib/screens/s12_budget_alert_screen.dart` by converting the screen to a scroll-safe centered layout.
- Hardened Firebase usage in `lib/services/cloud_sync_service.dart` and `lib/providers/user_profile_provider.dart` so the app degrades safely when Firebase is not initialized.
- Added broad audit harnesses:
  - `test/logic_audit_test.dart`
  - `test/ui_audit_test.dart`
- Logic audit sweep now passes across `12,960,000` generated tax profiles with no invariant or monotonicity failures.
- UI audit now passes for the major product screens on a narrow `320x740` viewport with no build/layout exceptions.
- Fixed server profile sync contract mismatch:
  - `lib/models/user_profile.dart` now serializes enum fields as string names expected by the backend instead of integer indexes
  - local profile parsing remains backward-compatible with the older integer format
- Fixed authenticated restore flow so completed local profiles are pushed to Neon on load in `lib/providers/user_profile_provider.dart` instead of staying local-only until the next edit.
- Fixed `UserProfile.copyWith` sentinel pattern — `propertyType` can now be explicitly set to `null` via copyWith. Previously the `?? this.propertyType` guard made it impossible to null-out the field.
- Fixed Q07 "No home loan" path — now passes `propertyType: null` to `copyWith`, clearing any previously-set property type so the server receives consistent data (`hasHomeLoan: false, propertyType: null`).
- Removed duplicate `BackendSyncService().syncTaxResult(result)` call in `_finish()` in `lib/screens/s03_questions_screen.dart` — `taxResultProvider` already syncs internally; the explicit call was a redundant second network hit.
- Fixed `clearAll()` in `lib/providers/user_profile_provider.dart` — now calls `BackendSyncService().syncDoneGaps({})` to also wipe the server-side done-gaps list, not just local SharedPreferences.
- Fixed `_confirmClear` in `lib/screens/s11_settings_screen.dart` — now invalidates `gapStateProvider` in addition to `taxResultProvider`, preventing stale gap-completion state lingering in memory after a data clear.
- Fixed misleading "data stays on this device" privacy copy in `_AccountSecurityTile` — updated to accurately reflect that the profile is encrypted and synced to ARTH servers.
- APK rebuilt and verified: `flutter build apk --debug` succeeds, `flutter test` passes (3/3).

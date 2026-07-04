# ARTH UI, UX, And Logic Audit

Date: 2026-07-04  
Scope: Flutter app, backend sync/auth surface, tax computation logic, document/PAN flows, tests, build health.  
Branch inspected: `codex/accuracy-coach-sheet-fix`

## Executive Verdict

ARTH is now a credible demo-grade tax readiness app, not a toy. It has a clear product wedge, browse-first navigation, profile/PAN/document flows, year-labelled tax rules, a deterministic Form 16 parser, and useful tests.

It is not yet production-trust ready. The biggest risks are not visual polish. The biggest risks are silent backend writes, overconfident savings math, incomplete law-certification tests, and a few session/navigation paths that can make users feel the app is unstable.

For a non-technical user: the app looks close, but before real users rely on it, we must make sure every tax number is explainable, every sync happens only when intended, and every failure has a calm recovery path.

## What Is Working Well

- Product story is much stronger: ARTH is positioned as a privacy-first tax readiness cockpit, not a fake filing clone.
- Bottom navigation and browse-first flow solve the earlier forced-onboarding problem.
- Profile now supports account identity, optional PAN vault, support, privacy, and delete-data paths.
- PAN is optional and profile-only, which is the right consent posture.
- Document upload exists with deterministic parsing, and the parser explicitly avoids LLM use.
- Backend tests pass for auth, security harness, PAN isolation, document isolation, parser fixtures, rate limits, and env validation.
- Flutter tests pass, including UI audit coverage for narrow screens.
- APK builds successfully.

Verified commands:

- `flutter analyze --no-fatal-infos`: passed, with info-level cleanup items.
- `flutter test`: passed, 33 tests.
- `flutter build apk --debug`: passed.
- `cd backend && npm run check && npm test`: passed, 19 backend tests.

## P0 Findings

### P0.1 Tax result provider writes to backend while screens read it

Evidence: `lib/providers/tax_result_provider.dart:12-23`

The provider computes tax result and immediately calls `BackendSyncService().syncTaxResult(result)`. Providers are read by many screens and can recompute on invalidation, route changes, and app lifecycle changes.

Why this matters:

- Just viewing Home, Dossier, Result, Actions, or Progress can trigger backend writes.
- This can create repeated sync queue logs and duplicate network writes.
- If auth is changing during sign-out/sign-in, stale results can be queued or retried.
- Users may see "server problem" even when they only opened a screen.

Fix:

- Make `taxResultProvider` pure: compute and return result only.
- Move server persistence to explicit moments: diagnostic completion, accuracy input save, tax year switch confirmation, and manual refresh.
- Add a result hash/profile hash so the same result is not repeatedly saved.
- Add a regression test proving reading result 5 times causes 0 backend writes.

### P0.2 Estimated tax benefit can be misleading

Evidence:

- `lib/engine/tax_engine.dart:28-35`
- `lib/engine/tax_engine.dart:358-374`
- `lib/engine/gap_finder.dart:81-105`

The app sums all gaps into `totalGapAmount`, then estimates tax benefit by applying that full amount as extra old-regime deductions. Some gaps are informational or assumption-based, such as:

- 80TTA: shows Rs 5,000 for every below-60 user even if interest income is unknown.
- 80TTB: shows Rs 25,000 for every senior even if interest income is unknown.
- 80CCD(2): returns Rs 1 only to force an HR action card.
- Education loan can show a default Rs 25,000 when no actual interest was entered.

Why this matters:

- The app may inflate "deduction opportunity."
- The "estimated tax benefit" can appear more certain than the inputs justify.
- This is the easiest way to lose trust, because a user may compare the result to a CA or ClearTax and see a mismatch.

Fix:

- Split gaps into three categories:
  - `confirmedDeductionOpportunity`
  - `assumptionBasedOpportunity`
  - `informationalActions`
- Estimate tax benefit only from confirmed and legally additional deductions.
- Keep 80TTA/80TTB/80CCD(2) as checklist guidance unless exact values exist.
- Add UI copy: "This does not change your estimate until you add the amount."

### P0.3 Tax law correctness is not yet certified enough

Evidence:

- Rule assets exist in `assets/tax_rules/fy_2025_26.json` and `assets/tax_rules/fy_2026_27.json`.
- Tests check important boundaries, but not enough official-calculator parity.
- Surcharge is simplified in `lib/engine/tax_engine.dart:313-326`.
- Rebate marginal relief is implemented generically in `lib/engine/tax_engine.dart:294-311`.

Current status:

- The app defaults to `FY2026-27 Planning / AY2027-28`.
- Finance Bill PDF from India Budget is reachable.
- Two Income Tax Department source URLs in assets returned 403 from this environment, so this audit cannot certify them live.

Why this matters:

- Tax is high-trust. "Looks right" is not enough.
- Surcharge, marginal relief, old/new regime comparison, and high-income scenarios must be exact.

Fix:

- Create official-source golden cases for both tax years.
- Compare against Income Tax Department calculator outputs or CA-reviewed fixtures.
- Cover incomes: Rs 2.5L, 3L, 4L, 5L, 7L, 8L, 10L, 12L, 12.75L, 16L, 20L, 24L, 50L, 1Cr, 2Cr, 5Cr.
- Add golden cases for HRA, 80GG, 80C, 80D, NPS, 80E, 24(b), 80TTA, 80TTB, 80G, surcharge, and marginal relief.
- Display "planning estimate" vs "filing estimate" everywhere a result appears.

### P0.4 Accuracy Coach can show unsaved tax changes after save failure

Evidence: `lib/screens/s20_accuracy_coach_screen.dart:208-214`

The sheet updates `userProfileProvider` first, then calls `save()`. If save fails, the in-memory profile remains changed. CodeRabbit also flagged this.

Why this matters:

- User sees a changed tax result even if the save failed.
- Backend/local state can drift.

Fix:

- Save previous profile.
- Apply optimistic update.
- On save failure, rollback provider state.
- Invalidate `taxResultProvider` only after successful save.

### P0.5 Sign-up lacks transient retry used by sign-in

Evidence: `lib/services/auth_service.dart:19-29` and `lib/services/auth_service.dart:31-40`

Sign-in uses `retryTransient: true`; sign-up does not.

Why this matters:

- This matches the earlier user-visible behavior: first tap shows "server problem", second tap succeeds.

Fix:

- Add transient retry to sign-up.
- Map transient backend errors to "Almost there, retrying..." rather than a scary server failure.
- Add test for first-attempt 503, second-attempt success.

## P1 Findings

### P1.1 Sync queue can enqueue unauthenticated failures

Evidence: `lib/services/backend_sync_service.dart:183-206` and `_shouldQueue` logic.

`StateError('no auth token')` is treated as queueable because it is not a `ServerApiException`.

Fix:

- Do not queue auth-missing errors.
- Scope queue keys by user id, not one global `arth_sync_queue`.
- Include `uid` in pending op metadata and drop mismatched ops on login.

### P1.2 Router has no central auth/completion guard

Evidence: `lib/app.dart:30-93`

Splash controls initial routing, but routes themselves are open. Screens handle incomplete state individually.

Fix:

- Add GoRouter redirect rules based on auth state and diagnostic completion.
- Keep browse-first public authenticated routes: Home, Profile, Help, AIS Guide.
- Protect completed-diagnostic routes from direct access unless profile exists.

### P1.3 Marginal-rate helper is old-regime-only

Evidence: `lib/providers/tax_result_provider.dart:109-113`

The display helper always uses old-regime marginal rate based on annual CTC.

Fix:

- Derive marginal rate from active rule set, active/better regime, and taxable income.
- If new regime wins, do not show old-regime savings rates as if they are guaranteed.

### P1.4 Large screens are becoming regression hot spots

Large files:

- `lib/screens/s03_questions_screen.dart`: 2249 lines.
- `lib/screens/s11_settings_screen.dart`: 1203 lines.
- `backend/src/routes.ts`: 1173 lines.
- `lib/screens/s14_profile_screen.dart`: 1070 lines.
- `lib/screens/s05_regime_comparison_screen.dart`: 739 lines.

Why this matters:

- Every future change becomes slower and riskier.
- UI bugs like overflow and navigation mistakes hide in large widgets.

Fix:

- Split screens into route shell, view model, sections, and small widgets.
- Retire or delete legacy `s11_settings_screen.dart` if `/settings` now aliases Profile.
- Split backend routes into auth, profile, account, documents, tax results, and events modules.

### P1.5 Document upload UX needs stronger trust rails

Evidence:

- `lib/services/tax_document_service.dart`
- `backend/src/documentParser.ts`

The backend is appropriately conservative, but the UI must make limitations clearer.

Fix:

- Before upload, show: supported types, encryption/storage summary, delete behavior, parser limitations.
- After upload, show exact status:
  - Stored only
  - Parsed, review needed
  - Unsupported scanned/password PDF
  - Failed
- Never imply ARTH has filed, verified, or government-matched anything.

## P2 Findings

### P2.1 UI is feature-rich but can feel dense

The app has many modules now: Home, Actions, Progress, Profile, Documents, AIS Guide, Filing Assistant, Accuracy Coach, Simulator, Calendar, Tax Story, Dossier.

Fix:

- Home should show one primary action, one secondary action, and three compact status cards.
- Move secondary modules below the fold.
- Keep "Tax OS" feeling, but reduce choice overload.

### P2.2 Performance needs profile-mode validation, not debug-only judgment

Observed debug launch skipped frames on device. Debug builds exaggerate lag, but user feedback says UI feels laggy.

Fix:

- Run profile build on low-end and common Android sizes.
- Measure first meaningful paint, scroll jank, and heavy blur areas.
- Keep `MotionPolicy` and `SurfacePolicy`, but audit all repeated glass/blur cards in scroll views.

### P2.3 Accessibility coverage needs expansion

Current UI tests cover narrow width, but not enough high text scale and low-end motion paths.

Fix:

- Add widget tests for 1.3x and 1.5x text scale.
- Check tap targets for PAN, documents, bottom nav, dialogs, and sheets.
- Avoid truncated labels like "Easy(auto-claimed e..." by enforcing flexible wrapping.

### P2.4 Toolchain warning should be scheduled

`flutter build apk --debug` warns that Android Gradle Plugin 8.9.1 and Kotlin 2.1.0 support will soon be dropped.

Fix:

- Upgrade AGP to 8.11.1 or later.
- Upgrade Kotlin to 2.2.20 or later.
- Run full Android build after upgrade.

## Screen-by-Screen UX Audit

### Auth

Good:

- Premium account framing is appropriate.
- Sign-in retry exists.

Risks:

- Sign-up needs the same transient retry.
- Error copy should distinguish weak password, duplicate email, network offline, rate limit, and server unavailable.

Priority fix:

- First tap must succeed or show a calm retry state.

### Splash

Good:

- Routes signed-in users to Home/Discover or completed flow.

Risks:

- Splash-only routing is not enough for deep route correctness.

Priority fix:

- Add router guards.

### Home / Discover

Good:

- The product now feels like a Tax OS cockpit.
- Readiness, documents, next best action, and support are the right anchors.

Risks:

- Too many modules can dilute the "next thing to do."
- If `taxResultProvider` writes on read, Home can trigger server noise.

Priority fix:

- Make result provider pure, then simplify Home's top section.

### Questions / Diagnostic

Good:

- Diagnostic captures a useful base profile.

Risks:

- Very large screen file.
- Back/edit flows are historically fragile.
- Advanced exactness fields live outside core diagnostic, so users may believe the first result is exact.

Priority fix:

- Keep diagnostic lightweight, but always point to Accuracy Coach when result confidence is not high.

### Results / Regime / Dossier

Good:

- Rule labels, confidence, assumptions, and trace are moving in the right direction.

Risks:

- Deduction opportunity vs actual tax benefit still needs stronger separation.
- Marginal rate display may mislead when new regime wins.

Priority fix:

- Show "what changed your tax" vs "what is only a reminder."

### Actions / Progress

Good:

- Turns tax into tasks.

Risks:

- Informational actions can look like monetary savings.
- Done-gap sync relies on backend writes and queue behavior.

Priority fix:

- Add action types: `money`, `document`, `education`, `hr_conversation`.

### Documents

Good:

- Right strategic direction.
- Deterministic parser and confirm-before-use posture are correct.

Risks:

- Users may expect all PDFs/scans/password PDFs to parse.
- Upload consent/storage details need more explicit copy.

Priority fix:

- Add upload preflight and parser status education.

### Profile

Good:

- Correct place for optional PAN, DP/name/phone, privacy, support, deletion.

Risks:

- Profile is large and could become a dumping ground.
- PAN one-account-one-PAN policy must be visible and enforced by backend.

Priority fix:

- Split Profile into Account, Tax Identity, Privacy, Support, App Controls.

### Help Center

Good:

- Email/phone support is appropriate for V1.

Risks:

- No issue id or diagnostic context for support.

Priority fix:

- Prefill email with app version, screen name, tax year, and device class only. Never include PAN, token, raw income, or document names.

## Logic And Tax Accuracy Audit

### Current Strengths

- Rule sets are versioned.
- Active default is FY2026-27 Planning.
- Result carries rule label, assessment year, assumptions, trace, and confidence.
- Fuzz-style logic audit exists and emits a report.
- Boundary tests exist for rebate and super-senior slabs.

### Current Weaknesses

- Some "gaps" are prompts, not confirmed deductions.
- Estimated tax benefit uses total gap amount too broadly.
- Surcharge and marginal relief need official parity fixtures.
- The same rule numbers appear in both FY2025-26 and FY2026-27 assets; this may be correct or may be placeholder reuse, but it must be reviewed.
- The app cannot yet claim every human permutation is verified. It can claim deterministic tests plus expanding golden coverage.

### Required Accuracy Upgrade

1. Freeze tax rules as versioned data.
2. Create official-source golden fixtures.
3. Add CA-reviewed edge cases.
4. Add invariant fuzz tests.
5. Add UI labels showing exactness/confidence.
6. Separate confirmed values from assumptions.
7. Never auto-mutate profile from documents without user confirmation.

## Backend, Sync, And Auth Audit

### Current Strengths

- Backend test suite passes.
- Health/security tests exist.
- PAN encryption/isolation is tested.
- Document owner isolation and delete-data wiping are tested.
- Auth refresh and sign-out flows exist.

### Current Weaknesses

- App-side sign-up retry is missing.
- Tax result sync is coupled to result rendering.
- Queue is global and may queue auth-missing failures.
- Frontend error mapping can still collapse to generic server problem.

### Required Reliability Upgrade

1. Make reads pure.
2. Make writes explicit.
3. Make queue user-scoped.
4. Drop unauthenticated queued writes.
5. Add consistent frontend error mapping.
6. Add auth/session regression test for sign-out then login as another user.

## Professional Readiness Score

These are subjective scores for product readiness, not test metrics.

- Product proposition: 8/10
- UI direction: 7/10
- UX clarity: 6.5/10
- Performance confidence: 5.5/10 until profile-mode testing
- Backend security foundation: 7.5/10
- Sync reliability: 5.5/10 because of render-triggered writes
- Tax accuracy confidence: 5.5/10 until official golden parity exists
- Demo/interviewer value: 8/10
- Production user trust: 5.5/10 today

## Priority Roadmap

### Next 48 Hours

1. Make `taxResultProvider` pure.
2. Add explicit result save flow after diagnostic completion and accuracy changes.
3. Add sign-up transient retry.
4. Fix Accuracy Coach rollback on save failure.
5. Make 80TTA/80TTB/80CCD(2) non-monetary guidance unless exact input exists.
6. Run APK on device and verify sign-up, diagnostic completion, sign-out, re-login.

### Next 1 Week

1. Add user-scoped sync queue.
2. Add GoRouter auth/completion guards.
3. Add official/CA-reviewed golden tax fixtures.
4. Refactor Home/Profile/Questions into smaller widgets.
5. Add upload preflight and parser status UX.
6. Add profile-mode performance test pass.

### Next 2-3 Weeks

1. Build confidence-led result explanation.
2. Add Tax Story as a polished summary, not a filing claim.
3. Build Filing Pack as premium demo.
4. Add support context and issue email prefill.
5. Add export/delete privacy language across Profile and Documents.
6. Upgrade Android Gradle Plugin and Kotlin.

## Non-Technical Bottom Line

ARTH should not compete by saying "we file faster." It should compete by saying:

"Before filing, ARTH tells you what is missing, what is risky, what documents you need, what tax year you are looking at, and how confident the estimate is."

To earn trust, the app must stop doing hidden sync work, stop mixing reminders with real savings, and make every number explainable.


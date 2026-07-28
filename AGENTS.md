<!--
Codex reads AGENTS.md. Claude Code reads CLAUDE.md (a symlink to this file).
One file, no drift. Do not create a second real CLAUDE.md.
-->

# Repo context

**What this is:** ARTH — Flutter mobile app + Node/TypeScript backend.
**Stack:** Flutter 3.44 (Dart), Firebase, Node backend (`backend/`), CockroachDB/Neon.
**Base branch:** main

## Before you start
Read `~/brain/projects/ARTH.md` for history and open threads.
Read `~/brain/stack.md` for machine constraints (M3, 8GB). Do not re-derive either.

## Commands, exactly these
These mirror `.github/workflows/ci.yml`. The pre-push gate runs the same ones,
so do not change them without changing CI too.

App (Flutter, run from repo root):
- Deps:  `flutter pub get`
- Lint:  `dart format --output=none --set-exit-if-changed lib/ test/ && flutter analyze --no-fatal-infos`
- Test:  `flutter test`
- Build: `flutter build apk --debug --flavor production`  (heavy, CI only — do not run in the pre-push gate on 8GB)
- Run:   physical device over wireless adb, not the emulator (8GB machine)

Backend (run from `backend/`):
- Deps:  `npm ci`
- Lint:  `npm run check`
- Test:  `npm test`
- Build: `npm run build`

## Branch model
`feat/<domain>/<short-desc>`, one domain per branch, e.g. `feat/tax/sms-parser`.
One product area per branch so it reviews and hands off independently. Never mix two domains.

## Conventions
- Industry-standard naming. This code gets handed to a club team, so clarity beats cleverness.
- Modular boundaries per feature. Feature code does not import another feature's internals.
- No dead code left behind. No commented-out blocks.

## Working rules for agents
1. Before editing, state in one sentence what you are changing and why.
2. Do not read the whole repo. Read what the task names.
3. Do not add a dependency without asking.
4. Do not weaken a test or lint rule to make a check pass.
5. Run the lint and test commands above before you claim done.
6. Output at most 5 review findings, ranked. Skip style notes entirely.
7. No 15-page reports. One screen or justify the length.

## Do not touch
- `.github/workflows/` without saying so explicitly
- secrets, `android/app/google-services.json`, `android/app/*.jks`, `.env*`, `local.properties`

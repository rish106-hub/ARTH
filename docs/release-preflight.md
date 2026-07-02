# ARTH Release Preflight

Run this checklist before creating a production release tag.

## Required gates

- [ ] GitHub CI is green on `main`.
- [ ] Backend check is green: secret scan, typecheck, tests, build, and npm audit.
- [ ] Flutter check is green: format, analyze, tests, and debug APK build.
- [ ] Dependabot security alerts are zero or explicitly accepted with owner sign-off.
- [ ] Code scanning alerts are zero or explicitly accepted with owner sign-off.
- [ ] GitHub secret scanning has no unresolved leaked secrets.
- [ ] Railway production env checklist in `backend/README.md` is complete.
- [ ] Neon restore point exists and restore path has been tested outside production.
- [ ] Play Store release secrets exist in GitHub Actions production environment.
- [ ] Release notes in `distribution/whatsnew/` match the shipped behavior.

## Commands

```bash
cd backend
npm ci
npm run scan:secrets
npm run check
npm test
npm run build
npm audit --audit-level=low

cd ..
dart format --set-exit-if-changed lib/ test/
flutter analyze --no-fatal-infos
flutter test --coverage
```

## Release tag

Create a SemVer tag only after every gate passes:

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

The release workflow validates required secrets before writing files or building
the Android App Bundle.

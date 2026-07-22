# Direct APK releases

ARTH beta builds are published through public GitHub Releases. This route does
not need Firebase App Distribution or a Google Play developer account.

## Publish an update

1. Update `version` in `pubspec.yaml`. Both the version name and build number
   must increase.
2. Push the tested code to `main` and wait for CI to pass.
3. Open **Actions > Direct APK Release > Run workflow** in GitHub.
4. Enter the same version name and build number, plus short release notes.
5. Share the APK from the new GitHub Release.

The workflow signs the APK with the existing release key. It also publishes a
checksum and `arth-update.json`, which the app reads from the latest release.
Never replace or lose the signing key. Android rejects an update signed by a
different key.

## User update flow

The user opens **You > Check for updates**. The first direct update requires
enabling **Allow from this source** for ARTH. Android then shows its own install
confirmation for every update. Updating keeps the app's local data as long as
the package name and signing key remain unchanged.

## Limits

- Android does not permit a normal app to silently install its own APK.
- Direct APK users do not receive automatic Play Store updates.
- GitHub Releases must remain public because the app does not carry a GitHub
  access token.
- Publish each version once. GitHub release tags and Android version codes must
  be unique and increasing.

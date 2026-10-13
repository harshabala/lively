# Releasing and notarization checklist

This is a checklist for the maintainer. Nothing here is automated end to end, and
no release has been cut as part of the production-readiness work.

## Current state

`package.sh` builds `Lively.app` with an ad-hoc signature and the hardened runtime.
That is enough to run locally but Gatekeeper warns on downloaded copies; the README
documents the `xattr` workaround.

## Prerequisites (owner action)

- Apple Developer Program membership and a **Developer ID Application** certificate.
- An app-specific password or App Store Connect API key for `notarytool` (store with
  `xcrun notarytool store-credentials`; never commit them).
- Full Xcode (for `notarytool`, `stapler`).

## Steps

1. Update the version in `Info.plist` (the only place; `package.sh` reads it) and move
   CHANGELOG "Unreleased" entries under the new version.
2. `./scripts/check_hygiene.sh && ./test.sh` must pass; run the manual QA list below.
3. `./scripts/release.sh vX.Y.Z --dry-run` to build and zip without touching GitHub.
4. Sign for distribution (replace the ad-hoc step in `package.sh`):
   `codesign --force --deep --options runtime --timestamp --sign "Developer ID Application: NAME (TEAMID)" --entitlements entitlements.plist Lively.app`
5. Notarize: `ditto -c -k --keepParent Lively.app Lively.zip`, then
   `xcrun notarytool submit Lively.zip --keychain-profile <profile> --wait`.
6. Staple and verify: `xcrun stapler staple Lively.app`, `spctl -a -vv Lively.app`,
   `codesign --verify --deep --strict Lively.app`.
7. Re-zip / build the DMG (`scripts/make-dmg.sh`), compute SHA-256, tag, publish the
   GitHub Release, update `Casks/lively.rb` version and sha256.
8. Remove the "not notarized" notes from README once releases are notarized.

## Manual QA before every release

- Fresh install: welcome sheet, assign a video, relaunch, wallpaper restored.
- Corrupt/missing video falls back to the macOS wallpaper with a clear message.
- Unplug/replug a display; switch Spaces; sleep/wake; lock/unlock; screen saver.
- On battery: playback pauses at the threshold; resumes on AC.
- Login item toggle; Reset Data; Download Logs contains no personal paths.
- VoiceOver: every control in the popover is reachable and labelled; Reduce Motion on.

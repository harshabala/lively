# Changelog

All notable changes to Lively are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Logs export now produces a redacted diagnostics report (versions, display count, settings, recent log, home paths replaced by `~`).
- The app notices when the previous run ended unexpectedly and records it in the log and report.
- Preferences carry a schema version for future migrations.
- `scripts/release.sh --dry-run`, `scripts/check_hygiene.sh`, SwiftLint config, Dependabot for Actions, and documentation (architecture, contributing, security, privacy, releasing, sandbox readiness, performance).
- The packaged `Info.plist` now takes its version from the repo `Info.plist`.

### Fixed

- **Per-Space and per-display assignments were being deleted.** Switching Spaces, unplugging a monitor, or launching without it wiped the clips assigned to the Spaces/displays not currently visible. They now persist.
- **Update check is opt-in, as documented.** Earlier builds turned it on at first launch. Existing installs are switched off once; turn it back on in Settings if you want it.
- Library imports now get the same H.264/HEVC check as display cards; damaged or truncated files are rejected with a clear message everywhere.
- A file that fails to play (corrupt, missing, ejected drive) no longer leaves a black window over the desktop; Lively falls back to your macOS wallpaper and retries when a drive mounts, after wake, or when you re-choose the file.
- Reset Data now also restores preferences to defaults (as its alert promised), refreshes the Library, and new assignments/imports save correctly afterwards.
- One malformed entry in the saved config no longer discards every assignment; an unreadable config is kept as `config_v2.corrupt.json` instead of being overwritten.
- Moved or renamed videos update the stored path when their bookmark is refreshed.
- The popover no longer leaks a global mouse monitor each time it closes itself.
- Update check: session is invalidated after each request, hard 12 s timeout, correct handling of pre-release tags and junk responses.

### Changed

- Wallpapers stop decoding while displays or the Mac sleep, the screen is locked, the screen saver runs, another user is active, or the wallpaper is fully covered, and resume automatically.

### Tests / CI

- New suites for update checking (stubbed network), video validation with generated H.264 and Motion-JPEG clips, config persistence/migration, preferences, Reset Data, and system suspension.
- New CI workflow runs build, tests, and packaging on every push and pull request.
- Performance harness: `os_signpost` intervals, `scripts/perf/measure.sh`, generated fixtures. No runtime behaviour change unless `LIVELY_PERF_MODE` is set.
- Measure isolation: `LIVELY_APPLICATION_SUPPORT` and `LIVELY_CONFIG_FILE` redirect Application Support. Setting `HOME` does not move `userDomainMask` on current macOS.

## [1.2.0] - 2026-07-14

### Added

- **User Wallpaper Library** — add your own MP4/MOV/M4V files once; apply to a target display or all displays
- **Settings redesign** — System Settings-style sidebar (General, Playback, Screen Setup, Logs, About) with fixed popover size
- **Screen Setup map** — live multi-display layout with wallpaper thumbnail previews
- **Playback preferences** — quality, loop behavior, hardware decoding, max resolution
- **Battery pause threshold** — slider (25–100%); always force-pause at ≤25% on battery
- **Appearance** — Light, Dark, or System theme for the menu-bar UI
- **Update banner** — optional GitHub Releases check; shows “Update available” with View (no auto-install)
- **ViewState** — builds UI with Command Line Tools (no SwiftUIMacros / full Xcode required for packaging)
- **First-run onboarding** — welcome sheet, dismissible Displays tip, sticky “Playing on this display”, Spaces coach
- **Screen Recording deep link** — empty/detecting states open System Settings privacy pane
- **Broken bookmark recovery** — “File missing — Reselect” when a video was moved or deleted
- **DMG installer** — `scripts/make-dmg.sh` builds a drag-to-Applications disk image
- **Branded app icon** — menu bar, About, README, and `.icns` packaging

### Changed

- Top nav uses underline selection; sidebar uses filled-pill selection (distinct languages)
- Semantic system colors for neutrals; accent reserved for active/interactive controls
- Display cards labeled **Display N** + hardware name (no redundant page “Displays” heading)
- Reset Data is its own General card; Pause/Quit share capsule chrome
- Logs table with Level / Message / Time, copy + download, internal scroll only
- Path redaction in logs; GitHub update URLs allowlisted to `https://github.com`

### Fixed

- System blue focus rect on primary tabs suppressed; soft brand focus rings elsewhere
- Security-scoped bookmark stop loops no longer mutate while iterating keys
- Playback prefs soft-apply where possible (full reload only for loop mode)

### Tests

- Battery policy unit tests
- Library / wallpaper manager tests

## [1.1.1] - 2026-07-11

### Fixed

- Instant wallpaper removal without broken confirmation dialogs in popovers
- Per-thumbnail clear controls and clearer “click to change” affordance

## [1.0.0] - 2026-07-06

First public release. Lively is open source under the MIT License.

### Added

- **Per-Space, per-display video wallpapers** — assign different looping videos to each macOS Space on each monitor
- **Menu-bar utility** — runs as a background (`LSUIElement`) process with no Dock icon
- **Hardware-accelerated playback** — H.264 and HEVC via AVFoundation `AVPlayerLayer` behind the desktop
- **Codec validation** — rejects VP9, AV1, and unsupported codecs at assignment time with clear errors
- **Light / Dark appearance mode** — separate videos for macOS light and dark appearance on the same Space
- **Security-scoped bookmarks** — wallpaper assignments persist across reboots without broad filesystem access
- **Launch at Login** — `SMAppService` registration (macOS 13+)
- **Global pause / resume** — pause all wallpapers from the settings header
- **Per-display controls** — fill/fit scale, mute, volume, remove wallpaper
- **Drag-and-drop and file picker** — assign `.mp4`, `.mov`, `.m4v` files from Finder
- **In-app log viewer** — view and copy troubleshooting logs
- **Fully offline** — no network entitlement, analytics, or telemetry
- **Accessible UI** — Reduce Motion support, VoiceOver labels, 32pt hit targets, error announcements
- **Mist Reef design system** — native SwiftUI tokens via `LivelyBrand`

### Technical

- Native Swift 6.2 package with zero third-party dependencies
- `LivelyCore` library + `LivelyApp` executable
- Unit tests for `ConfigStore` and codec validation
- `package.sh` for local `.app` bundle assembly and ad-hoc signing

### Known limitations

- H.264 and HEVC only — re-encode other codecs before use
- Unsandboxed — required for desktop-layer video; not Mac App Store ready as-is
- No automatic download/install of updates — optional check shows a banner and opens GitHub Releases
- No playlists, schedules, or cross-Mac sync
- Distribution builds require Developer ID signing and notarization for Gatekeeper outside your machine

[1.2.0]: https://github.com/harshabala/Lively/releases/tag/v1.2.0
[1.1.1]: https://github.com/harshabala/Lively/releases/tag/v1.1.1
[1.0.0]: https://github.com/harshabala/Lively/releases/tag/v1.0.0
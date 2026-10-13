# Production readiness

Audit of Lively against a ten-dimension rubric. Scores are 0-10 and are
deliberately conservative: a 10 means "verifiably complete", and anything that
could not be run in the audit environment is marked as unverified rather than
assumed to work.

Audit environment: Command Line Tools only (no Xcode), Swift 6.4 toolchain,
macOS 27 SDK. `xcodebuild`, XCTest, SwiftLint and GitHub Actions were not
available, so none of those were exercised.

## Baseline (2026-10-12, master at b0a64aa)

| # | Dimension | Score | Evidence |
|---|-----------|-------|----------|
| 1 | Build and run reproducible | 6 | `swift build` and `package.sh` work on CLT. Version string is duplicated in `Info.plist` and a heredoc inside `package.sh` (the repo `Info.plist` is not used). No pinned toolchain note beyond CI. |
| 2 | Tests | 6 | 13 Swift Testing suites cover config store, persistence, preferences, battery policy, suspension, update checker, video validation. No playlist feature exists (README: "No playlists yet"). No schema-version or diagnostics tests. |
| 3 | Static quality | 2 | No SwiftLint or formatter config, no lint step anywhere. |
| 4 | Security | 5 | Hardened runtime and ad-hoc signing in `package.sh`; no secrets found. Not sandboxed by design but no written threat model, no sandbox-readiness analysis, no `SECURITY.md`. |
| 5 | Reliability | 7 | Handles bad or missing video, moved files, sleep/wake, lock, screen saver, display hot-plug (`SpaceMonitor`), thermal state, corrupt config backup, one-time preference migration. Preferences have no schema version. No record of unclean exits. |
| 6 | Config and packaging | 4 | `CHANGELOG.md`, `scripts/release.sh`, Homebrew cask exist. No release process document, no notarization checklist, version not single-sourced, `release.sh` publishes straight to a GitHub Release with no dry-run. |
| 7 | CI | 5 | `ci.yml` builds, tests, packages and verifies the bundle; `release.yml` exists. No lint, no hygiene check, no dependency updates for actions, not runnable right now (account billing). |
| 8 | Docs | 4 | `README.md` and a short `AGENTS.md`. Missing `ARCHITECTURE.md`, `CONTRIBUTING.md`, `SECURITY.md`, `PRIVACY.md`. Stale planning files (`HANDOFF.md`, `docs/lively_*.md`). |
| 9 | UX, accessibility, performance | 6 | VoiceOver labels present (68 modifiers), Reduce Motion respected in the settings UI, wallpapers pause on battery, sleep, lock, occlusion and thermal pressure. No documented resource budget; wallpaper does not react to the system Reduce Motion setting. |
| 10 | Operability | 4 | In-memory log view with copy, plus `os.Logger`. No diagnostics export, no crash or unclean-exit detection, no support guidance. |

Repo hygiene findings: Finder-style duplicate files (`* 2.*`) sit untracked in
the working tree of the original clone; no personal paths or secrets are
tracked. One stale branch, `harsha/quirky-nightingale-e0cd4b` (1 commit), is
left untouched.

## After (2026-10-13, branch prod/10-of-10-20261012)

| # | Dimension | Before | After | What changed / why not 10 |
|---|-----------|--------|-------|---------------------------|
| 1 | Build and run reproducible | 6 | 8 | Version single-sourced from `Info.plist`; `package.sh` verified (plist lint, codesign verify). Not 10: no pinned Xcode locally, never built under full Xcode here. |
| 2 | Tests | 6 | 8 | 87 tests in 18 suites pass via `./test.sh`; added diagnostics, redaction, run-marker and preferences-schema tests. Not 10: no coverage of AVFoundation/window code; XCTest/Xcode run not done. |
| 3 | Static quality | 2 | 6 | `.swiftlint.yml`, `.editorconfig`, `scripts/check_hygiene.sh` (run, passes). SwiftLint itself was not installed, so the config is unverified against the code. |
| 4 | Security and privacy | 5 | 8 | `SECURITY.md`, `PRIVACY.md`, `docs/SANDBOX_READINESS.md`; hygiene script scans for secrets and personal paths. Not 10: not sandboxed (by design), not notarized, no dependencies to audit. |
| 5 | Reliability | 7 | 8 | Preferences schema version + migration tests; unclean-exit detection. Config file still has no schema version (decoding is lossy and backed up, so left unchanged for backward compatibility). |
| 6 | Config and packaging | 4 | 7 | `docs/RELEASING.md` with notarization checklist, `release.sh --dry-run`, Dependabot. Not 10: no Developer ID signing or notarization (owner). |
| 7 | CI | 5 | 7 | Added hygiene + SwiftLint job. Workflows could not run (account billing) and `actionlint` was unavailable; YAML syntax was checked only. |
| 8 | Docs | 4 | 9 | README links, ARCHITECTURE, CONTRIBUTING, SECURITY, PRIVACY, RELEASING, SANDBOX_READINESS, PERFORMANCE, AGENTS. Stale planning files (`HANDOFF.md`, `docs/lively_*.md`) remain; owner may archive. |
| 9 | UX, accessibility, performance | 6 | 6 | Budget documented, but nothing measured and no UI change was verifiable without Xcode. Wallpaper video does not yet honour system Reduce Motion (documented gap). |
| 10 | Operability | 4 | 7 | Redacted diagnostics export (copy/download), unclean-exit detection, run marker. Not 10: no crash reporter, no persistent on-disk log. |

### Verified

- `swift build` succeeds; `./test.sh`: 87 tests, 18 suites pass; `./scripts/check_hygiene.sh` passes.
- `package.sh` output has a valid plist, version 1.2.0 from `Info.plist`, and passes `codesign --verify --deep --strict`.

### Not verified (needs Xcode / hardware / accounts)

- SwiftUI/AppKit behaviour of the new Logs export and the run marker at launch (compiled, not run).
- SwiftLint output, GitHub Actions runs, XCTest under Xcode, real multi-display, sleep/wake and battery behaviour, CPU/GPU numbers.

### Blocked on owner

- Apple Developer ID certificate, notarization credentials and the first notarized release.
- Full Xcode run of the app and tests; real-hardware QA from `docs/RELEASING.md`.
- GitHub billing so CI can run; enabling private vulnerability reporting for `SECURITY.md`.
- Decision on archiving stale planning docs, and on the wallpaper Reduce Motion behaviour.
- Branch `harsha/quirky-nightingale-e0cd4b` (1 commit) left untouched.

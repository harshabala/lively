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

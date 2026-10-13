# AGENTS.md

Lively: native macOS 14+ menu bar app for looping video wallpapers (Swift 6, no third-party deps).

- Layout: `Sources/Lively` (LivelyCore: Core, Logic, UI), `Sources/LivelyApp/main.swift`, `Tests/LivelyTests`.
- Build/test: `swift build`, `swift test`. Package app: `./package.sh`; DMG: `./scripts/make-dmg.sh`.
- Design/brand: see `DESIGN.md`, `PRODUCT.md`, `brand.md`. Use `LivelyBrand` tokens, not inline literals.
- Privacy: offline by default; the only network call is the opt-in GitHub update check. Keep it that way.
- Not sandboxed by design (draws below desktop icons). Do not commit secrets, signing material, or personal paths.
- Tests: `./test.sh` works with Command Line Tools only; `./scripts/check_hygiene.sh` before committing. Put new logic in `Sources/Lively/Logic` with tests.
- Version lives only in `Info.plist`. Preference changes need a schema-version migration in `AppPreferences.migrate`.
- Never log file paths or names. Diagnostics must go through `DiagnosticsRedactor`.
- More: `ARCHITECTURE.md`, `CONTRIBUTING.md`, `SECURITY.md`, `docs/RELEASING.md`.

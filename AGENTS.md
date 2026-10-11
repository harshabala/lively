# AGENTS.md

Lively: native macOS 14+ menu bar app for looping video wallpapers (Swift 6, no third-party deps).

- Layout: `Sources/Lively` (LivelyCore: Core, Logic, UI), `Sources/LivelyApp/main.swift`, `Tests/LivelyTests`.
- Build/test: `swift build`, `swift test`. Package app: `./package.sh`; DMG: `./scripts/make-dmg.sh`.
- Design/brand: see `DESIGN.md`, `PRODUCT.md`, `brand.md`. Use `LivelyBrand` tokens, not inline literals.
- Privacy: offline by default; the only network call is the opt-in GitHub update check. Keep it that way.
- Not sandboxed by design (draws below desktop icons). Do not commit secrets, signing material, or personal paths.

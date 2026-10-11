# Product Review Roadmap Implementation

**Date:** 2026-07-14  
**Branch:** master (user-approved in-session)  
**Skip:** Apple Developer ID, notarization, Sparkle paid-signing path, playlists/schedules, App Store sandbox strategy

## Global Constraints

- Native SwiftUI/AppKit, macOS 14+, zero third-party deps (no Sparkle unless pure URL open)
- Respect `accessibilityReduceMotion`
- UserDefaults for first-run flags via `AppPreferences` or `AppMetrics`
- Local commits OK; push only when user asks
- Icon source: `<local-path> app icon.png` → `icon.png` + `AppIcon.icns`
- Installer: DMG with Applications folder drag-drop (no notarization)

## Tasks

### T1 — App icon everywhere
Generate multi-res `AppIcon.icns`, update `icon.png`, README image, About uses application icon, menu-bar status item prefers app icon (template) with SF Symbol fallback.

### T2 — First-run tip + System Settings deep link
Displays tip strip (dismiss forever). Empty/detecting states: Open System Settings for Screen Recording.

### T3 — Sticky playing + Spaces coach
After assign: card shows sticky “Playing on this display” until dismissed/next change. One-time Spaces coach after first activation.

### T4 — Welcome sheet
First launch: welcome panel → primary “Choose a video…” opens picker for first display.

### T5 — About first-launch help
Quarantine command + menu-bar location + Gatekeeper right-click Open.

### T6 — Broken bookmark recovery
When resolve fails / file missing on card: “File missing — Reselect” CTA.

### T7 — Custom focus chrome
Replace bare `focusEffectDisabled` where possible with subtle brand focus ring; keep tabs free of system blue rect.

### T8 — Apply to all displays
Library + optional after assign: apply same video to every connected display.

### T9 — DMG installer
`scripts/make-dmg.sh`: create DMG with Lively.app + Applications symlink, background instruction for drag-to-Applications.

### T10 — Docs
README + CHANGELOG: user-managed library, install DMG path, icon, onboarding; remove curated-library claims if stale.

### T11 — Warm quality tip
Optional footnote after assign when quality is High: power saver hint (footnote only).

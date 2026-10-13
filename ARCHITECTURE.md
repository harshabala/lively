# Architecture

Lively is a menu-bar (`LSUIElement`) macOS app written in Swift with SwiftUI,
AppKit and AVFoundation. It has no third-party dependencies.

## Targets (Package.swift)

| Target | Path | Role |
|--------|------|------|
| `LivelyCore` | `Sources/Lively` | All app logic and UI, as a library so it can be unit tested. |
| `LivelyApp` | `Sources/LivelyApp/main.swift` | Thin entry point: `NSStatusItem`, popover, lifecycle, run marker. |
| `LivelyTests` | `Tests/LivelyTests` | Swift Testing suites for `LivelyCore`. |

## Layers inside `LivelyCore`

- `Logic/` - pure or mostly pure state and policy. Most unit-tested code lives here.
  - `ConfigStore`: per-Space wallpaper assignments, security-scoped bookmarks,
    atomic debounced persistence to `~/Library/Application Support/Lively/config_v2.json`,
    entry-by-entry lossy decoding, corrupt-file backup.
  - `AppPreferences`: UserDefaults-backed settings with a schema version and migrations.
  - `PlaybackPolicy`: `SystemSuspension` (sleep, lock, screen saver, session switch)
    and the per-display decode decision.
  - `SpaceMonitor`: identifies display + Space pairs.
  - `VideoValidator`, `WallpaperLibraryManager`, `UpdateChecker` (opt-in), `LivelyLogger`,
    `Diagnostics` (redacted support report, unclean-exit marker).
- `Core/` - AppKit/AVFoundation glue. `WallpaperWindow` is a borderless window at
  desktop level; `WallpaperController` owns one player per display, reacts to
  Space, display, power, thermal and system-state notifications, and applies the
  pause policy.
- `UI/` - SwiftUI views hosted in the popover. `ViewState` replaces the `@State`
  macro so the package builds with Command Line Tools only.

## Data flow

```
SpaceMonitor --(spaces)--> WallpaperController --(play/pause)--> WallpaperWindow/AVPlayer
ConfigStore  --(bookmark -> URL)-----^                 ^
AppPreferences / battery / thermal / system suspension -+
```

## Persistence and migration

- Assignments: JSON dictionary keyed by `displayID:desktopImageURL`. Each entry is
  decoded independently; an unreadable file is moved to `config_v2.corrupt.json`.
- Preferences: UserDefaults keys under `prefs.`; `prefs.schemaVersion` tracks
  migrations (`AppPreferences.migrate`). Add a step and a test when a key changes meaning.
- Run marker: `running.marker` exists only while the app runs; if found at launch
  the previous run ended unexpectedly and this is logged and included in diagnostics.

## Why not sandboxed

Drawing below desktop icons needs a window at desktop level, which the App Sandbox
does not allow. See `docs/SANDBOX_READINESS.md`.

# Lively Performance Master Plan

Goal: the lightest possible live-wallpaper app on macOS. Minimal RAM, near-zero idle CPU, minimal battery impact.
Audience: an autonomous coding agent. Execute phases in order. Every phase ends with a measurement and a commit.

## 0. Decision: do NOT rewrite in Rust

Lively is already native Swift/AppKit: ~7.8k LOC, zero third-party dependencies, SPM, macOS 14+.
The real cost centres are not the language:

1. Video decode, which is done by the Apple Silicon media engine through AVFoundation. Rust cannot beat it.
2. WindowServer compositing of the wallpaper window, which is OS-owned.
3. SwiftUI/Combine/popover memory that stays resident while the app sits in the menu bar.
4. Wake-ups (timers, polling, notification fan-out) that keep the CPU out of deep idle.

A Rust rewrite would add FFI to AVFoundation/AppKit, cost months, and reduce nothing in 1 and 2.
Rust or C is only justified for a hot path that a profile proves is ours. None is expected.
Strategy: measure, remove wake-ups, free memory when invisible, shrink the video workload, shrink the binary.

## 1. Current state (audited 2026-10-13)

- Local `master` is in sync with `origin/master` (harshabala/lively) at `2d83093` "Production readiness pass (#7)".
- Open PR: Dependabot `actions/checkout 4 -> 7`. Review CI, then merge. Not performance-related.
- Untracked Finder/iCloud duplicates ("... 2.md", "... 2.png", including `.impeccable/critique/...2.md`). Delete or gitignore them. Check `diff` against the originals first.
- Stack: `LivelyCore` library (Sources/Lively), `LivelyApp` executable (main.swift, AppDelegate, NSStatusItem, NSPopover with NSHostingController(SettingsContainerView)).
- Big files: `ScreenCardView.swift` 942 lines, `WallpaperController.swift` 850, `PreferencesView.swift` 563, `ConfigStore.swift` 425, `LibraryView.swift` 422.
- `docs/PERFORMANCE.md` says its targets were never measured on hardware. This plan fixes that first.

### What is already good (keep)
- Pauses on display sleep, system sleep, lock, screen saver, fast-user-switch (`SystemSuspension`).
- Pauses when the wallpaper window is fully occluded (`didChangeOcclusionState`).
- Battery floor 25%, user threshold, thermal throttling, quality and resolution caps, `preferredPeakBitRate`.
- ConfigStore persistence is debounced (300 ms).
- `automaticallyWaitsToMinimizeStalling = false`, `preventsDisplaySleepDuringVideoPlayback = false`.

### Inefficiencies found in code (verify each with a profile before and after)
| # | Where | Issue | Fix (phase) |
|---|-------|-------|-------------|
| A | `WallpaperController.setupBatteryMonitor` | 20 s repeating `Timer` plus a `Task` hop forever, even while idle or paused. Constant wake-ups. | Event-driven `IOPSNotificationCreateRunLoopSource`; no timer (P2) |
| B | `WallpaperSession.pause()` | Pausing only calls `player.pause()`. The AVPlayer, item, decoded frames and buffers stay resident for hours while suspended or battery-paused. | Tear down the player after a short grace period; rebuild on resume from a poster frame (P3) |
| C | `NSHostingController` in main.swift | The SwiftUI settings tree (LibraryView, ScreenCardView, thumbnails, Combine subscriptions) is built at launch and kept alive for the app's life. | Create the popover content lazily on first open; destroy on close (P3) |
| D | `LogStore` | Up to 1000 `LogEntry` objects held in a `@Published` array on the main actor, mirroring `os.Logger`. Every log line fires objectWillChange. | Drop the in-memory mirror; read from `OSLogStore` on demand, or use a ring buffer that is not `@Published` while the log view is closed (P3) |
| E | `configStore.$configs` sink | Every config change triggers `retryFailedPlayback()` and `spaceMonitor.refresh()` (rebuilds all `ScreenSpace` values, re-queries `desktopImageURL`). | Diff first; refresh only when the affected spaceKey changed (P2) |
| F | `SpaceMonitor.handleSpaceChange` | Polls up to 10 x 50 ms on each Space switch. | Fine functionally. Cap work, skip when no display has a wallpaper assigned (P2) |
| G | Loop via `seek(to: .zero)` | Seek on item end causes a decoder flush, a stutter and a CPU spike every loop. | `AVPlayerLooper`/`AVQueuePlayer`, or an `AVAssetReader` + `AVSampleBufferDisplayLayer` pipeline if profiling shows it wins (P4) |
| H | Muted wallpapers | A muted `AVPlayer` still decodes the audio track. | Disable audio tracks on the item (`AVPlayerItemTrack.isEnabled = false`) or strip audio at import (P4) |
| I | Same file on 2+ displays | One `AVPlayer` and one decode per display. | Share a single `AVPlayer` across several `AVPlayerLayer`s for identical URL and settings (P4) |
| J | Source video can be 4K/60 fps | Only a bit-rate and max-height hint is applied. The decoder still works on the full stream. | Import-time transcode to a "Lively-optimised" HEVC at display-native size, 30 fps cap (P4). Biggest battery lever. |
| K | Reduce Motion gap noted in PERFORMANCE.md | Wallpaper ignores the accessibility setting. | Show poster frame and stop decoding when Reduce Motion is on (P4) |
| L | `AppMetrics` | A `DateFormatter` allocated for a once-a-day string. | Use `Date.FormatStyle` or compare `Calendar.startOfDay`. Trivial (P5) |
| M | `UpdateChecker` | Network call on every launch. | Throttle to once per 24 h, `URLSession` ephemeral, no retained session (P5) |
| N | Binary | Default release flags. | `-Osize`, WMO, dead-strip, strip symbols, no unused frameworks (P6) |

## 2. Budgets (the definition of done)

Measure on Apple silicon, release build, 1080p HEVC 30 fps looping wallpaper on one external or built-in display, AC power, idle desktop.

| Metric | Budget | Tool |
|---|---|---|
| Resident memory, wallpaper playing, popover closed | <= 60 MB (stretch 40 MB) | `footprint -p`, Instruments Allocations |
| Resident memory, paused or suspended | <= 25 MB | `footprint` |
| Resident memory, no wallpaper assigned | <= 20 MB | `footprint` |
| App CPU, playing 1080p30 HEVC | <= 1.5% of one core (stretch 1%) | `top -pid`, Activity Monitor |
| App CPU, paused or idle, 10 min average | 0.0% | `top`, `sample` |
| Wake-ups per second, idle | <= 1 (target 0) | `powermetrics --samplers tasks`, Activity Monitor "Idle Wake Ups" |
| Energy Impact, playing | <= 3 (stretch 2) | Activity Monitor, Instruments Energy Log |
| Energy Impact, paused | ~0 | Activity Monitor |
| Time from pause trigger to decoder stopped | <= 100 ms | os_signpost |
| Time from resume to first frame | <= 300 ms | os_signpost |
| Cold-launch to menu-bar ready | <= 250 ms | os_signpost |
| Release binary size (unstripped .app executable) | track and do not regress; stretch <= 2 MB | `ls -l`, `bloaty` |

Budgets are targets. If a budget is physically impossible, record the measured floor and the reason in `docs/PERFORMANCE.md`. Do not fudge numbers.

## 3. Phases

### P0. Hygiene and baseline (do first, about half a day)
1. Delete or ignore the "... 2" duplicates after confirming they are byte-identical or stale.
2. Merge the Dependabot PR if CI is green.
3. Create `scripts/perf/` with:
   - `measure.sh`: builds release, launches with a fixture wallpaper, samples `top` for N minutes, runs `footprint`, `powermetrics` (needs sudo, document it), writes `perf/results/<date>-<commit>.json`.
   - A fixture set in `perf/fixtures/` (small generated clips: 1080p30 HEVC, 4K60 HEVC, 1080p30 H.264, with and without audio). Generate with `ffmpeg` or `avconvert`; do not commit large binaries (use Git LFS or generate on demand).
4. Add `os_signpost` intervals (`OSSignposter`) around: launch, synchronize, player build, pause, resume. Keep them; they are free when not profiled.
5. Record the BASELINE in `docs/PERFORMANCE.md` as a table. Every later phase compares to it. No optimisation without a before and after number.

Exit: baseline table committed. CI still green.

### P1. Instruments pass (read-only, about half a day)
Run Time Profiler, Allocations, Energy Log, System Trace (wake-ups) for: idle, playing, paused, popover open and closed, Space switching, display hot-plug. Write findings to `docs/perf-findings.md`. Confirm or refute rows A to N above and add anything new. Re-rank by measured impact. Do not skip. The table above is a hypothesis from reading code.

### P2. Kill wake-ups (target: idle wake-ups to ~0)
- A: replace the 20 s timer with `IOPSNotificationCreateRunLoopSource` (fires only on power-source change). Also observe `NSProcessInfoPowerStateDidChange` (already done) and `ProcessInfo.thermalStateDidChangeNotification` (already done). Initial read once at launch. Keep a pure function `batteryPauseDecision` and its tests.
- E: in the `configStore.$configs` sink, compute which spaceKeys changed; call `spaceMonitor.refresh()` only if a current space's config changed. Add `removeDuplicates`.
- F: skip the poll loop when no screen has an assigned wallpaper.
- Audit every `Timer`, `Task.sleep`, `asyncAfter`, `Combine.publish(every:)`, and `NotificationCenter` observer. Each must have a documented reason. Remove observers that are not needed while paused (for example the occlusion observer).
- Coalesce rapid-fire notifications (display reconfiguration storms) with a single trailing 100 ms debounce.
- Add a test that no repeating timer exists after `WallpaperController.init` (inject a scheduler or assert `powerSourceTimer == nil`).

Exit: `powermetrics` shows idle wake-ups under budget; paused CPU 0.0%.

### P3. Memory: free everything that is not visible
- B: "Cold pause". When suspension or pause lasts longer than a grace period (suggest 10 s for lock, sleep and screen saver; 0 s for battery and thermal pauses), call `tearDownPlayer()` and keep only the window with a static poster frame (`CALayer.contents` as a `CGImage` at display pixel size; store the JPEG or HEIC poster in Caches). On resume, rebuild the player. Must not flash black: keep the poster visible until the first decoded frame arrives (`AVPlayerLayer.isReadyForDisplay`).
- Optional: when occluded for more than N seconds, apply the same cold pause.
- C: make the popover content lazy. `NSPopover.contentViewController` is set on first show, and set to `nil` in `popoverDidClose` (after a short delay) so SwiftUI state, thumbnails and Combine sinks are released. Verify with Allocations that memory drops after closing.
- D: LogStore. Remove the `@Published` 1000-entry array. Options in order of preference: (1) read `OSLogStore(scope: .currentProcessIdentifier)` when the log view opens; (2) a plain non-observable ring buffer of 200 entries, published only while the log view is visible.
- Thumbnails: `VideoThumbnailView` and `LibraryView` must use `AVAssetImageGenerator` with `maximumSize` set to the displayed pixel size, cache to disk in Caches, keep an `NSCache` with a small count/cost limit, and evict on `popoverDidClose`.
- Make `ScreenCardView` (942 lines) cheaper: split into small views with equatable inputs, avoid `@EnvironmentObject` fan-out so one `@Published` change does not re-render every card. This is also a maintainability win.
- Replace `@Published` + `ObservableObject` on hot controllers with `@Observable` (macOS 14 supports it) to cut invalidation. Do this only where P1 shows view-update cost.

Exit: footprint paused <= 25 MB, popover-closed <= budget, no growth after 50 open/close cycles of the popover (leak check with the memory-leak workflow).

### P4. Decode workload: the biggest battery lever
- J: Import pipeline "Optimise for Lively": on import (and optionally on first play), transcode to a cached HEVC file:
  - Resolution = display native pixel size, never larger (use the max across assigned displays, or one rung per display).
  - 30 fps cap (24 fps offered as "Eco"), constant frame rate.
  - Strip audio if the wallpaper is muted (the default).
  - Bitrate target about 4 to 8 Mbps for 1080p; GOP and keyframe interval short enough for cheap looping.
  - Use `AVAssetExportSession` with a preset or `AVAssetWriter` for control. Run it as a background `Process`-free task with `QualityOfService.utility`, cancellable, with progress. Keep the original untouched; cache under `~/Library/Caches` or the app container.
  - Skip transcoding if the source already meets the spec (reuse `VideoValidator`).
- G: seamless loop without seek-flush: `AVPlayerLooper` with `AVQueuePlayer` as first step. Measure CPU spikes at loop boundaries. Only if still visible, evaluate `AVAssetReader` + `AVSampleBufferDisplayLayer` (more control, more code; adopt only with a measured win).
- H: if the item is muted, disable the audio `AVPlayerItemTrack`s so no audio decode or render graph exists.
- I: share one `AVPlayer` across displays that show the same URL and settings; lay out multiple `AVPlayerLayer`s on it.
- K: respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`: show the poster frame, no decode. Add an observer for `accessibilityDisplayOptionsDidChangeNotification`. Update docs and tests.
- Low Power Mode: when `ProcessInfo.isLowPowerModeEnabled`, default to 24 fps or poster-only (user-configurable, default on).
- Smart "static after idle": optional setting to freeze on the poster frame after N minutes without user input on battery. Use `CGEventSource.secondsSinceLastEventType`, polled only when a decision is pending (no always-on timer; use a single one-shot timer re-armed on state changes).
- Never use software decode paths. Remove the "hardware decoding off" option unless there is a hard reason to keep it; if kept, document the energy cost.

Exit: playing CPU and Energy Impact meet budget on the 1080p30 fixture; the 4K60 fixture after transcode behaves like the 1080p30 one.

### P5. Small leaks of cycles
- L: replace `DateFormatter` in `AppMetrics`.
- M: throttle `UpdateChecker` to once per 24 h, using an ephemeral session, off the main actor, and never at launch. Defer 30 s after launch at `.background` QoS.
- Use `OSAllocatedUnfairLock` or actors consistently; remove stray `DispatchQueue.main.asyncAfter` where a state change is the correct trigger (`main.swift` initial popover open).
- Launch path: construct `UpdateChecker`, `LogStore`, `AppMetrics`, `Diagnostics` lazily. Do not touch the UI layer until the user clicks the status item (unless "Start Minimized" is off).
- Set QoS everywhere: UI `.userInteractive`, persistence `.utility`, transcoding `.utility`, update check `.background`.
- Use `NSStatusItem` image as a template `NSImage` created once.
- Ensure `Info.plist` has `LSUIElement` = YES (already accessory policy), no unused entitlements.

### P6. Build and binary size
- Release settings: `-Osize` (benchmark against `-O`; keep the faster one if the size gap is under 5%), `-whole-module-optimization`, `-Xlinker -dead_strip`, strip symbols, `-Xfrontend -enable-lto` or `-lto=llvm-thin` if supported by the toolchain. Evaluate Swift 6 embedded-style flags only if they build; do not chase them.
- Dependency audit: confirm no SwiftUI or Combine usage outside the settings UI. Consider replacing Combine in `LivelyCore` logic with plain `NotificationCenter` observers and closures; this shrinks the runtime footprint and removes allocation churn.
- Consider an AppKit-only settings window for the hottest screens only if P3 shows SwiftUI is still the dominant resident cost after lazy-load. Otherwise leave SwiftUI.
- Prelink and launch time: check `DYLD_PRINT_STATISTICS`-style output or `xctrace` App Launch template; remove any `+load` or heavy static initialisers.
- Keep `scripts/make-dmg.sh` and notarisation flow intact.

### P7. Regression guard (so it stays fast)
- `scripts/perf/measure.sh` runs in a manually triggered GitHub Action on a macOS runner (hardware numbers on hosted runners are noisy; use as trend, not gate). Local runs on real Apple silicon are the gate.
- Add unit tests for: cold-pause state machine (suspension reasons x grace timers), no-repeating-timers invariant, battery decision table, Reduce Motion path, lazy popover lifecycle (no hosting controller retained when closed).
- Add `docs/PERFORMANCE.md` as the single source of truth: budgets, latest measured numbers, how to reproduce.
- Add a PR checklist item: "Does this add a timer, observer, or retained view? Justify."

## 4. Rules for the executing agent
- One phase per branch and PR (`perf/p2-wakeups`, etc.). Small commits. All existing tests must pass (`swift test`). Add tests for any new logic.
- Every PR description must include BEFORE and AFTER numbers from `measure.sh`. No numbers means no merge.
- Do not change user-visible behaviour or config formats (security-scoped bookmarks, spaceKey format, `ConfigStore` schema). Migrations need tests.
- Do not add third-party dependencies.
- Do not remove the safety pauses (sleep, lock, thermal, battery floor).
- No black flashes: a wallpaper window may only be shown with content (poster or video frame).
- If a hypothesis in section 1 is disproved by profiling, say so in `docs/perf-findings.md` and skip the item.
- Stop and ask the owner before: changing minimum macOS version, removing a user-facing setting, or any rewrite of a module larger than ~300 lines.

## 5. Expected payoff (ranked by P1 — see `docs/perf-findings.md`)
1. P4 / H disable audio tracks when muted: muted AAC fixture was 13.7% CPU / 47 MB vs 4.4% / 21 MB silent.
2. P4 / J cap or transcode to 1080p30 (not 5K-native): 4K60 was ~8.6% CPU and 466 MB IOSurface virtual.
3. P3 / B cold pause: paused keeps CoreMedia threads and ~82 MB IOSurface virtual.
4. P2 / A, E, F wake-ups: 20 s timer confirmed; idle `top` already 0.0%; energy needs sudo.
5. P3 / C lazy popover, then P4 G/K, then P5/P6.

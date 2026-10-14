# Lively Open Perf Items Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the P1-ranked wins: mute audio tracks (H), 1080p decode cap (J), cold pause (B), then kill idle wake-ups (A, E, F).

**Architecture:** Pure policy types in `Sources/Lively/Logic` with tests. `WallpaperSession` / `WallpaperController` / `SpaceMonitor` call those policies. No AVFoundation in unit tests except where an existing generated clip is already used.

**Tech Stack:** Swift 6, AppKit, AVFoundation, IOKit.ps, Swift Testing, `./test.sh` (Command Line Tools).

**Spec:** `docs/PERFORMANCE_MASTER_PLAN.md` (phases P2–P4) and `docs/perf-findings.md` (P1 ranking). Budgets live in `docs/PERFORMANCE.md`.

## Global Constraints

- macOS 14+, Swift 6, zero third-party dependencies.
- Do not change ConfigStore schema, security-scoped bookmarks, or `spaceKey` format.
- Do not remove safety pauses (sleep, lock, screen saver, thermal, battery floor).
- Never show a black wallpaper window: poster or decoded frame only.
- Do not remove a user-facing setting. Max Resolution keeps Match Source / 1080p / 4K.
- Do not raise the minimum macOS version.
- Do not rewrite a module over ~300 lines; extract new Logic types instead.
- Never log file paths or names; use `DiagnosticsRedactor` / existing loggers.
- New logic lives in `Sources/Lively/Logic` with tests in `Tests/LivelyTests`.
- Every commit: `./test.sh` must pass (97+ tests). Conventional commits (`feat`, `fix`, `test`, `docs`).
- `powerSourceTimer` must be gone after Task 4. Keep `batteryPauseDecision` and its tests.
- Import-time transcode of videos is out of scope (deferred; >300 lines).

## Review Focus

- Muted wallpaper with an AAC track must not start AudioToolbox I/O.
- Match Source must not request a 5K decode; 4K setting still allows 2160p.
- Pause longer than grace must leave a visible poster, never an empty layer.
- Resume after cold pause must rebuild the player without a black flash.
- Config edits for an inactive Space must not call `spaceMonitor.refresh()`.

---

### Task 1: Disable audio tracks when muted (H)

**Files:**
- Create: `Sources/Lively/Logic/AudioTrackPolicy.swift`
- Create: `Tests/LivelyTests/AudioTrackPolicyTests.swift`
- Modify: `Sources/Lively/Core/WallpaperController.swift` (`WallpaperSession.loadVideo` and the `.readyToPlay` branch)
- Modify: `CHANGELOG.md` Unreleased / Changed

**Interfaces:**
- Consumes: `muted: Bool` already passed into `loadVideo`
- Produces: `enum AudioTrackPolicy { static func isEnabled(isAudioMedia: Bool, muted: Bool) -> Bool }`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import LivelyCore

struct AudioTrackPolicyTests {
    @Test func mutedDisablesAudioOnly() {
        #expect(!AudioTrackPolicy.isEnabled(isAudioMedia: true, muted: true))
        #expect(AudioTrackPolicy.isEnabled(isAudioMedia: false, muted: true))
    }

    @Test func unmutedLeavesAudioEnabled() {
        #expect(AudioTrackPolicy.isEnabled(isAudioMedia: true, muted: false))
        #expect(AudioTrackPolicy.isEnabled(isAudioMedia: false, muted: false))
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL (type missing)**

Run: `./test.sh` (or `swift test --filter AudioTrackPolicyTests` if the toolchain allows). Expected: compile error `AudioTrackPolicy` not found.

- [ ] **Step 3: Implement policy + apply on readyToPlay**

```swift
import Foundation

/// Whether an `AVPlayerItemTrack` should stay enabled.
/// Muted wallpapers still built an AudioToolbox graph in P1 (13.7% CPU).
public enum AudioTrackPolicy {
    public static func isEnabled(isAudioMedia: Bool, muted: Bool) -> Bool {
        if isAudioMedia && muted { return false }
        return true
    }
}
```

In `WallpaperSession.loadVideo`, after the item is `.readyToPlay` (tracks are populated then, not at `AVPlayerItem(url:)`), loop `item.tracks` and set `track.isEnabled = AudioTrackPolicy.isEnabled(isAudioMedia: track.assetTrack?.mediaType == .audio, muted: muted)`. Capture `muted` in the sink. Keep `newPlayer.isMuted = muted`.

- [ ] **Step 4: Run `./test.sh` — expect PASS including the new tests**

- [ ] **Step 5: Commit**

```bash
git add Sources/Lively/Logic/AudioTrackPolicy.swift Tests/LivelyTests/AudioTrackPolicyTests.swift Sources/Lively/Core/WallpaperController.swift CHANGELOG.md
git commit -m "feat(perf): Disable audio tracks on muted wallpapers"
```

---

### Task 2: Cap Match Source decode at 1080p (J)

**Files:**
- Create: `Sources/Lively/Logic/VideoDecodeBudget.swift`
- Create: `Tests/LivelyTests/VideoDecodeBudgetTests.swift`
- Modify: `Sources/Lively/Core/WallpaperController.swift` (`applyPreferences`)
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: `AppPreferences.MaxResolution.preferredMaxHeight`
- Produces: `enum VideoDecodeBudget { static func preferredMaximumResolution(maxResolution: AppPreferences.MaxResolution) -> CGSize }`

Ruling already made: import transcode is deferred. Match Source is **not** removed. Decode hint for Match Source is 1920×1080 (not `.zero`, not 5K). Explicit 4K still returns 3840×2160. Hardware-decoding-off path stays 1920×1080.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import CoreGraphics
@testable import LivelyCore

struct VideoDecodeBudgetTests {
    @Test func matchSourceCapsAt1080() {
        let size = VideoDecodeBudget.preferredMaximumResolution(maxResolution: .matchSource)
        #expect(size == CGSize(width: 1920, height: 1080))
    }

    @Test func p1080Is1080() {
        #expect(VideoDecodeBudget.preferredMaximumResolution(maxResolution: .p1080)
            == CGSize(width: 1920, height: 1080))
    }

    @Test func p4kIs2160() {
        #expect(VideoDecodeBudget.preferredMaximumResolution(maxResolution: .p4k)
            == CGSize(width: 3840, height: 2160))
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

- [ ] **Step 3: Implement and wire `applyPreferences`**

```swift
import CoreGraphics

public enum VideoDecodeBudget {
    public static func preferredMaximumResolution(
        maxResolution: AppPreferences.MaxResolution
    ) -> CGSize {
        let h = maxResolution.preferredMaxHeight
        if h > 0 {
            return CGSize(width: h * 16 / 9, height: h)
        }
        return CGSize(width: 1920, height: 1080)
    }
}
```

Replace the `preferredMaximumResolution` assignment in `applyPreferences(to:prefs:)` so:
- `!prefs.hardwareDecoding` still forces 1920×1080
- else `player.currentItem?.preferredMaximumResolution = VideoDecodeBudget.preferredMaximumResolution(maxResolution: prefs.maxResolution)`
- delete the `.zero` branch

Do not change `MaxResolution.preferredMaxHeight` (Match Source stays 0 for the preference enum).

- [ ] **Step 4: `./test.sh` PASS**

- [ ] **Step 5: Commit** `feat(perf): Cap Match Source decode at 1080p`

---

### Task 3: Cold pause with poster frame (B)

**Files:**
- Create: `Sources/Lively/Logic/ColdPausePolicy.swift`
- Create: `Tests/LivelyTests/ColdPausePolicyTests.swift`
- Modify: `Sources/Lively/Core/WallpaperController.swift` (`WallpaperSession.pause` / `resume` / `updatePlaybackRate` / `tearDownPlayer`; `WallpaperController.applyPlaybackState`)
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: `SystemSuspensionReason`, `shouldHaltPlayback`
- Produces:
  - `enum ColdPauseTrigger: Equatable { case userPause, batteryOrThermal, lockSleepOrSaver }`
  - `enum ColdPausePolicy { static func grace(for trigger: ColdPauseTrigger) -> Duration; static func shouldTearDown(elapsed: Duration, grace: Duration) -> Bool }`
  - grace: lock/sleep/saver/userPause = 10 seconds; batteryOrThermal = 0 seconds

Never order the window out during cold pause. Capture a poster (`AVAssetImageGenerator` at `player.currentTime()`, `appliesPreferredTrackTransform = true`, `maximumSize` = layer bounds in pixels) onto `playerLayer.contents` **before** `tearDownPlayer()`. On resume, keep `contents` until `isReady && AVPlayerLayer.isReadyForDisplay` (or `isReady` if `isReadyForDisplay` is not yet true), then clear `contents` so the video layer takes over. If poster capture fails, keep the existing player paused (do not tear down into a blank layer).

Use a one-shot `Task.sleep` or `DispatchWorkItem` per session, cancelled on resume. Do not add a repeating timer.

- [ ] **Step 1: Write failing policy tests**

```swift
import Testing
@testable import LivelyCore

struct ColdPausePolicyTests {
    @Test func lockSleepSaverAndUserPauseWaitTenSeconds() {
        let ten = Duration.seconds(10)
        #expect(ColdPausePolicy.grace(for: .lockSleepOrSaver) == ten)
        #expect(ColdPausePolicy.grace(for: .userPause) == ten)
        #expect(!ColdPausePolicy.shouldTearDown(elapsed: .seconds(9), grace: ten))
        #expect(ColdPausePolicy.shouldTearDown(elapsed: ten, grace: ten))
    }

    @Test func batteryAndThermalTearDownImmediately() {
        #expect(ColdPausePolicy.grace(for: .batteryOrThermal) == .seconds(0))
        #expect(ColdPausePolicy.shouldTearDown(elapsed: .seconds(0), grace: .seconds(0)))
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

- [ ] **Step 3: Implement policy + session cold pause**

Map controller halt reasons to `ColdPauseTrigger`: `isBatteryPaused || isThrottled` → `.batteryOrThermal`; `isSystemSuspended` → `.lockSleepOrSaver`; else user `isPaused` → `.userPause`.

Call `session.beginColdPause(trigger:)` from `applyPlaybackState` when `shouldHaltPlayback`, and `session.cancelColdPauseAndResume()` when it lifts. `beginColdPause` must `player.pause()` immediately (existing pause), then after grace capture poster + `tearDownPlayer()` while leaving the window on-screen.

- [ ] **Step 4: `./test.sh` PASS** (existing `resumeAfterPauseDoesNotCrash` must still pass)

- [ ] **Step 5: Commit** `feat(perf): Tear down paused players after a poster grace`

---

### Task 4: Replace 20 s battery timer (A)

**Files:**
- Create: `Sources/Lively/Logic/PowerSourceMonitor.swift` (move enum out of WallpaperController)
- Create: `Tests/LivelyTests/PowerSourceMonitorTests.swift` (and extend `BatteryPolicyTests` if needed)
- Modify: `Sources/Lively/Core/WallpaperController.swift` (`setupBatteryMonitor`, remove `powerSourceTimer`)
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: existing `PowerSourceMonitor.snapshot()` and `batteryPauseDecision`
- Produces: `PowerSourceMonitor` in Logic with `snapshot()` plus `start(_ onChange: @escaping () -> Void) -> Stop` where Stop invalidates the run-loop source. Use `IOPSNotificationCreateRunLoopSource`. Keep `NSProcessInfoPowerStateDidChange`. No `Timer`.

- [ ] **Step 1: Write a failing test that the controller has no repeating power timer**

Make `WallpaperController.repeatingPowerSourceTimer` an internal (testable) `Timer?` that stays nil. After `WallpaperController(...)`, `#expect(controller.repeatingPowerSourceTimer == nil)`.

If moving `PowerSourceMonitor` breaks `@testable` imports, keep the type `public`.

- [ ] **Step 2: Run tests — expect FAIL** (`repeatingPowerSourceTimer` missing or non-nil)

- [ ] **Step 3: Move snapshot, add IOPS notification source, delete `Timer.scheduledTimer(withTimeInterval: 20)`**

Call `snapshot()` once at init (already done). `start` must be stopped in `tearDown()`. Do not change `batteryPauseDecision`.

- [ ] **Step 4: `./test.sh` PASS** including Battery pause policy suite

- [ ] **Step 5: Commit** `feat(perf): Observe power-source changes instead of polling`

---

### Task 5: Diff configs and skip empty Space polls (E, F)

**Files:**
- Create: `Sources/Lively/Logic/ConfigChangeDiff.swift`
- Create: `Tests/LivelyTests/ConfigChangeDiffTests.swift`
- Modify: `Sources/Lively/Core/WallpaperController.swift` (`bind` `$configs` sink)
- Modify: `Sources/Lively/Logic/SpaceMonitor.swift` (`handleSpaceChange`)
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: `[String: SpaceConfig]`, current `spaceKey`s from `screenSpaces`
- Produces:
  - `enum ConfigChangeDiff { static func currentSpaceKeysChanged(from: Set<String>, to: Set<String>, currentSpaceKeys: Set<String>) -> Bool }`
  - `SpaceMonitor.hasAssignedWallpaper: () -> Bool` default `{ true }`; controller sets it to `{ !configStore.configs.isEmpty }` (assignments exist at all). When false, `handleSpaceChange` calls `refresh()` once and returns without the 10×50 ms loop.

- [ ] **Step 1: Failing tests**

```swift
struct ConfigChangeDiffTests {
    @Test func refreshOnlyWhenAVisibleSpaceKeyChanged() {
        let current: Set<String> = ["1:a"]
        #expect(ConfigChangeDiff.currentSpaceKeysChanged(
            from: ["1:a", "2:b"], to: ["1:a", "2:c"], currentSpaceKeys: current) == false)
        #expect(ConfigChangeDiff.currentSpaceKeysChanged(
            from: ["1:a"], to: ["1:z"], currentSpaceKeys: current) == true)
    }

    @Test func identicalKeysAreANoOp() {
        #expect(!ConfigChangeDiff.currentSpaceKeysChanged(
            from: ["1:a"], to: ["1:a"], currentSpaceKeys: ["1:a"]))
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

- [ ] **Step 3: Implement diff; `$configs` sink uses it before `spaceMonitor.refresh()`. Still call `retryFailedPlayback()` when the changed keys intersect current spaces or when a current key's config object identity/URL changed. If only inactive keys change, skip `refresh()`. Add `removeDuplicates` on the keys set if cheap.

`SpaceMonitor.hasAssignedWallpaper` — controller assigns in `init`/`bind`. `handleSpaceChange`: if `!hasAssignedWallpaper()` then `refresh()` once and return.

- [ ] **Step 4: `./test.sh` PASS** including `inactiveSpaceAssignmentsSurviveControllerSync`

- [ ] **Step 5: Commit** `feat(perf): Skip Space refresh unless a visible assignment changed`

---

### Task 6: Record P2–P4 numbers in PERFORMANCE.md

**Files:**
- Modify: `docs/PERFORMANCE.md`, `docs/perf-findings.md`
- Test: none (docs). Run `./test.sh` once anyway.

**Interfaces:** Consumes measure.json if the implementer can run `LIVELY_PERF_SKIP_BUILD=1 scripts/perf/measure.sh` after `./package.sh`. If disk or a running Lively blocks measure, leave cells as `—` and write the exact command. Never invent numbers.

- [ ] **Step 1:** Package once, measure idle 30 / playing 30 / paused 30 with the silent fixture, then playing 30 with `1080p30-hevc-audio.mp4`. Confirm user `config_v2.json` checksum is unchanged.
- [ ] **Step 2:** Fill a BEFORE (P1 table) / AFTER table in `PERFORMANCE.md`. Update H/B/A verdicts in `perf-findings.md`.
- [ ] **Step 3:** Commit `docs(perf): Record open-item before/after measurements`

# Perf findings

Hypothesis table (A–N) lives in `docs/PERFORMANCE_MASTER_PLAN.md` §1. This
file is the ranked, measured list. Do not start P2 until the ranking below
is the source of truth.

## How P1 was measured (2026-10-14)

Host: Apple M1, macOS 27.0.1, one built-in 5K display (5120×2880, also
listed as 2560×1600 scaled). Release `.app` from `./package.sh` (CLT).
Isolated Application Support (`LIVELY_APPLICATION_SUPPORT` /
`LIVELY_CONFIG_FILE`). Popover closed. User `config_v2.json` checksum
unchanged (`2558921003 1531`).

Tools that **did** run: `top`, `footprint`, `sample(1)`, `heap -sH` (first
120 lines), `vmmap --summary`. JSON under `perf/results/20261014T05*`.

Tools that **did not** run:

| Tool | Why | Exact command |
|---|---|---|
| Instruments Time Profiler / Allocations / Energy Log / System Trace | `xctrace` needs full Xcode; `xcode-select -p` is Command Line Tools | `xctrace record --template 'Time Profiler' --time-limit 30s --output /tmp/lively-time.trace --attach <pid>` |
| `powermetrics` | needs sudo | `sudo powermetrics --samplers tasks --show-process-energy --show-process-wait-times -i 1000 -n 30 --process-name Lively` |
| `os_signpost` durations | unified log (`/usr/bin/log show --predicate 'subsystem == "com.lively.app"'`) was empty without a trace session | same `xctrace` Time Profiler / `os_signpost` template |
| Popover open, Space switch, display hot-plug | no UI automation; one display | do by hand with the commands above attached |

Do not fill Energy Impact or idle-wake-ups from imagination. They stay `—`.

## Fixture comparison (playing, 30 s `top` after settle)

| Fixture | CPU avg (last five) | `footprint` | Threads | Notes |
|---|---|---|---|---|
| Idle (no wallpaper), 45 s | 0.0 (all 9 samples) | 15 MB | 9 → 3 | CFRunLoop wait |
| 1080p30 HEVC silent | 4.367 (5.1–5.6) | 21 MB | 24–28 | budget clip |
| 1080p30 HEVC **audio**, muted | 13.7 (14.8–17.7) | 47 MB (peak 49) | 31–43 | AudioToolbox IOProc |
| 4K60 HEVC silent | 7.033 (7.8–8.9) | 26 MB (peak 28) | 21–25 | IOSurface 466 MB virtual |
| 1080p30 H.264 silent | 4.217 (4.7–5.5) | 21 MB | 20–29 | same ballpark as HEVC |
| Paused (1080p30 HEVC) | 0.017 | 19 MB (peak 21) | 8–13 | CoreMedia threads still there |

Idle 45 s `sample(1)` (25 s): one `__NSFireTimer` → Lively timer thunk
(hypothesis A). Playing silent `sample`: AVPlayer / CoreMedia, almost no
AudioToolbox. Playing audio `sample`: `AQMEIO_HAL::IOProc`,
`AudioConverterFillComplexBuffer`, `AudioUnitRender`. Paused `sample`:
`figThreadMain` on `coremedia.imagequeue` / `videomediaconverter` /
`videomentor`. `vmmap`: idle has no IOSurface region; paused keeps ~82 MB
IOSurface virtual; 4K playing maps 466 MB IOSurface virtual.

## A–N verdicts

| # | Verdict | Evidence | Next phase |
|---|---|---|---|
| **H** | **Confirmed, largest playing delta** | Muted audio fixture 13.7% CPU / 47 MB vs silent 4.4% / 21 MB. `player.isMuted = true` still builds the audio graph. `WallpaperSession.loadVideo` never disables `AVPlayerItemTrack`s. | P4 |
| **J** | **Confirmed** | 4K60 silent 7.0% avg (~8.6% steady) / 26 MB vs 1080p30 4.4% / 21 MB. IOSurface virtual 466 MB vs 79 MB. This 5K panel would make a naive “display-native” transcode *larger* than 4K; cap to `maxResolution` / 1080p, not 5120×2880. | P4 |
| **B** | **Confirmed** | `pause()` only `player.pause()`. Paused keeps Fig queues, ~82 MB IOSurface virtual, +4 MB phys vs idle (19 vs 15). | P3 |
| Decode floor | **Measured** | 1080p30 HEVC silent steady ~5.2% of one core, all in AVFoundation. Budget is 1.5%. Rust will not move this. Shrinking the stream (H, J) or the loop (G) is the lever. | P4 |
| **A** | **Confirmed, idle CPU already 0.0%** | `Timer.scheduledTimer(20)` in `setupBatteryMonitor`. 25 s idle sample captured one `__NSFireTimer`. `top` idle 0.0% for 45 s. Wake-ups / energy still unknown without sudo. | P2 |
| **C** | **Confirmed in code; RAM not dominant** | `NSHostingController` assigned at launch (`main.swift`). SwiftUI/AttributeGraph mapped while idle. Heap top-120 is CFString/dictionaries, not view graphs. Popover-open delta not measured. | P3 |
| **G** | **Code confirmed; spike size unknown** | `seek(to: .zero)` on item end, 2 s fixture. 5 s `top` samples stay ~5% with no visible loop spike (averaging hides it). | P4 after H/J |
| **K** | **Confirmed in code** | Wallpaper path never reads `NSWorkspace.accessibilityDisplayShouldReduceMotion`. UI chrome does. | P4 |
| **E** | **Confirmed in code, not profiled** | `configStore.$configs` always `retryFailedPlayback()` + `spaceMonitor.refresh()`. | P2 |
| **F** | **Confirmed in code, not profiled** | Space change polls 10×50 ms even with no assignment. | P2 |
| **I** | **Untested** | One display. | P4 if a second display exists |
| **D** | **Confirmed in code, not in heap top** | `LogStore` `@Published` cap 1000. Not a top allocator at idle. | P3, after B/C |
| **L** | **Confirmed in code, trivial** | `DateFormatter` in `AppMetrics`, once a day. Not on-CPU in samples. | P5 |
| **M** | **Partial** | Ephemeral `URLSession` already; still launch-time if opted in. Default is off; perf harness skips it. | P5 |
| **N** | **Confirmed** | Executable 4,366,496 bytes. `package.sh` is `swift build -c release` with no `-Osize` / strip. | P6 |

## Ranked next work

1. **P4 / H** — when muted, disable audio `AVPlayerItemTrack`s (or strip on import). Biggest measured CPU and RAM win on files that have a soundtrack. Default wallpaper is muted.
2. **P4 / J** — transcode or cap to 1080p30 (honour `maxResolution`). 4K60 is already ~1.6× the 1080p30 CPU and a much larger IOSurface. Do not transcode up to 5K.
3. **P3 / B** — cold pause: tear down the player after a grace period, poster frame in the layer, no black flash. Confirmed retained CoreMedia + IOSurface while paused.
4. **P2 / A, E, F** — drop the 20 s timer and the always-on config/space refresh. Idle CPU is already 0.0%; this is for wake-ups and energy, which still need `sudo powermetrics`.
5. **P3 / C** — lazy popover. Launch already builds SwiftUI; idle 15 MB is inside the 20 MB budget, so this is smaller than B.
6. **P4 / G, K** — looper and Reduce Motion after H/J.
7. **P5 / P6** — L, M, N.

P2 remains the next *named phase* in the master plan. Measured impact says **H before A** if the goal is playing CPU and battery. Wait for an explicit go-ahead before either.

## P0 (previous branch)

- Finder/iCloud `* 2.*` duplicates removed.
- Dependabot `actions/checkout` 4 → 7 merged on `master` as #8.
- Signposts: `launch`, `synchronize`, `playerBuild`, `pause`, `resume`.
- Isolation: `HOME` does not move `userDomainMask`. Harness sets
  `LIVELY_APPLICATION_SUPPORT`, `LIVELY_CONFIG_FILE`, throwaway
  `com.lively.app.perf` UserDefaults.
- Canonical idle/playing/paused budget table: `docs/PERFORMANCE.md`.

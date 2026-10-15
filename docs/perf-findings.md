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

## How P2–P4 open items were measured (2026-10-15)

Same host and isolated harness as P1. Git `42df2f9`. Duration 30 s.
User `config_v2.json` checksum still `2558921003 1531` before and after.
JSON: `perf/results/20261015T042057Z-42df2f9-idle.json`,
`20261015T042152Z-42df2f9-playing.json` (silent),
`20261015T042238Z-42df2f9-paused.json`,
`20261015T042328Z-42df2f9-playing.json` (muted audio).
`powermetrics` / `xctrace` still did not run (`sudo -n` missing; CLT).

| Run | CPU avg (steady) | `footprint` | Threads | Notes |
|---|---|---|---|---|
| Idle 30 s | 0.0 (all 6 samples) | 14 MB (peak 15) | 9 → 3 | CFRunLoop wait; no `__NSFireTimer` in 10 s `sample` |
| 1080p30 HEVC silent | 3.733 (4.3–4.7) | 21 MB | 25–28 | decode floor, AVPlayer / CoreMedia |
| 1080p30 HEVC **audio**, muted | 3.667 (4.1–4.5) | 22 MB (peak 24) | 23–26 | no `AQMEIO` / `AudioUnitRender` |
| Paused (1080p30 HEVC) | 0.200 (1.2 then 0.0×4) | 18 MB (peak 21) | 11 → 20 → 4 | teardown spike; then idle-like |

Idle 10 s `sample`: main + `NSEventThread` only. Playing silent `sample`:
AVPlayer / CoreMedia, no AudioToolbox IOProc. Playing muted-audio `sample`:
same — **no** `AQMEIO_HAL::IOProc` (P1 had it). Paused `sample` after grace:
`com.apple.coremedia.imagequeue.coreanimation.common` still present; no
`videomediaconverter` / `videomentor`. `vmmap`: paused IOSurface virtual
15.9 MB (P1 ~82 MB); playing silent 75.8 MB; muted-audio 79.0 MB.

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
| **H** | **Measured drop** | P1 muted audio 13.7% CPU / 47 MB vs silent 4.4% / 21 MB. After disabling muted `AVPlayerItemTrack`s: 3.667% (4.1–4.5) / 22 MB, matching silent 3.733% (4.3–4.7) / 21 MB. 10 s `sample` has no `AQMEIO_HAL::IOProc` / `AudioUnitRender`. | done (P4) |
| **J** | **Confirmed; 4K not remeasured** | P1: 4K60 silent 7.0% / 26 MB vs 1080p30 4.4% / 21 MB. Match Source decode is now capped at 1080p in code. This after-set did not rerun the 4K60 fixture, so no new J number. | P4 |
| **B** | **Measured drop in retained decode, not idle-parity RAM** | After cold pause: threads 11 → 4, IOSurface virtual ~82 MB → 15.9 MB, no CoreMedia Memory Pool in `footprint`. Phys 18 MB vs idle 14 MB (still +4 MB; P1 was 19 vs 15). CPU 0.200 avg from one 1.2% teardown sample; last four `top` rows 0.0. `sample` still has `coremedia.imagequeue`. | done (P3) |
| Decode floor | **Measured** | 1080p30 HEVC silent steady 4.3–4.7% of one core (JSON avg 3.733 including the first 0.0), all in AVFoundation. Budget is 1.5%. H removed the audio tax; the silent floor remains. | P4 |
| **A** | **Timer gone; idle CPU still 0.0; wake-ups unmeasured** | P1: 25 s idle `sample` captured one `__NSFireTimer` from `Timer.scheduledTimer(20)`. After: 10 s idle `sample` has 0 `__NSFireTimer` (main + `NSEventThread` only). `top` idle 0.0 for 30 s (already 0.0 at P1). Wake-ups / energy still `—` without sudo. | done (P2); energy unproven |
| **C** | **Confirmed in code; RAM not dominant** | `NSHostingController` assigned at launch (`main.swift`). SwiftUI/AttributeGraph mapped while idle. Heap top-120 is CFString/dictionaries, not view graphs. Popover-open delta not measured. | P3 |
| **G** | **Code confirmed; spike size unknown** | `seek(to: .zero)` on item end, 2 s fixture. 5 s `top` samples stay ~5% with no visible loop spike (averaging hides it). | P4 after H/J |
| **K** | **Confirmed in code** | Wallpaper path never reads `NSWorkspace.accessibilityDisplayShouldReduceMotion`. UI chrome does. | P4 |
| **E** | **Code landed; idle CPU already 0.0; wake-ups unmeasured** | Config edits for inactive Spaces no longer `spaceMonitor.refresh()`. Idle 10 s `sample` shows no extra on-CPU work (already CFRunLoop wait). Not a measured CPU drop (P1 idle was 0.0). Wake-ups still `—`. | done (P2); energy unproven |
| **F** | **Code landed; idle CPU already 0.0; wake-ups unmeasured** | Space switches skip the wallpaper-URL poll when nothing is assigned. Idle harness does not switch Spaces, so this after-set has no F delta. Wake-ups still `—`. | done (P2); energy unproven |
| **I** | **Untested** | One display. | P4 if a second display exists |
| **D** | **Confirmed in code, not in heap top** | `LogStore` `@Published` cap 1000. Not a top allocator at idle. | P3, after B/C |
| **L** | **Confirmed in code, trivial** | `DateFormatter` in `AppMetrics`, once a day. Not on-CPU in samples. | P5 |
| **M** | **Partial** | Ephemeral `URLSession` already; still launch-time if opted in. Default is off; perf harness skips it. | P5 |
| **N** | **Confirmed** | Executable 4,366,496 bytes. `package.sh` is `swift build -c release` with no `-Osize` / strip. | P6 |

## Ranked next work

H, B, A, E, F landed on `perf/open-items` (`42df2f9`). After-set (2026-10-15):
H is the measured playing win (muted audio 13.7%/47 MB → 3.667%/22 MB). B
dropped paused IOSurface virtual and threads; paused phys is still +4 MB
vs idle. A/E/F removed idle work in code; idle CPU was already 0.0 and
wake-ups are still `—`.

1. **P4 / J** — remeasure 4K60 after the 1080p Match Source cap; honour
   `maxResolution`. Do not transcode up to 5K. No new 4K number in this after-set.
2. **Decode floor** — 1080p30 HEVC silent still ~4.5% of one core vs 1.5%
   budget. Shrinking the stream (J) or the loop (G) is the remaining lever.
3. **P3 / C** — lazy popover. Idle 14 MB is inside the 20 MB budget.
4. **P4 / G, K** — looper and Reduce Motion.
5. **P5 / P6** — L, M, N.
6. **Wake-ups / energy** — still need `sudo powermetrics` / `xctrace` Energy
   Log. Do not claim an idle-energy win for A/E/F until that runs.

## P0 (previous branch)

- Finder/iCloud `* 2.*` duplicates removed.
- Dependabot `actions/checkout` 4 → 7 merged on `master` as #8.
- Signposts: `launch`, `synchronize`, `playerBuild`, `pause`, `resume`.
- Isolation: `HOME` does not move `userDomainMask`. Harness sets
  `LIVELY_APPLICATION_SUPPORT`, `LIVELY_CONFIG_FILE`, throwaway
  `com.lively.app.perf` UserDefaults.
- Canonical idle/playing/paused budget table: `docs/PERFORMANCE.md`.

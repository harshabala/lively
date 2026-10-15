# CPU, GPU and battery budget

Policy lives in `docs/PERFORMANCE_MASTER_PLAN.md`. How to reproduce:
`scripts/perf/README.md`. Later phases compare to the P0 baseline below.
Do not invent numbers; a cell is `—` when that sampler did not run.

## Targets (budgets)

Measure on Apple silicon, release `.app`, 1080p HEVC 30 fps looping wallpaper
on one display, AC power, idle desktop, popover closed.

| Metric | Budget | Tool |
|---|---|---|
| Resident memory, wallpaper playing, popover closed | <= 60 MB (stretch 40 MB) | `footprint -p`, Instruments Allocations |
| Resident memory, paused or suspended | <= 25 MB | `footprint` |
| Resident memory, no wallpaper assigned | <= 20 MB | `footprint` |
| App CPU, playing 1080p30 HEVC | <= 1.5% of one core (stretch 1%) | `top -pid`, Activity Monitor |
| App CPU, paused or idle, 10 min average | 0.0% | `top`, `sample` |
| Wake-ups per second, idle | <= 1 (target 0) | `powermetrics --samplers tasks`, Activity Monitor Idle Wake Ups |
| Energy Impact, playing | <= 3 (stretch 2) | Activity Monitor, Instruments Energy Log |
| Energy Impact, paused | ~0 | Activity Monitor |
| Time from pause trigger to decoder stopped | <= 100 ms | os_signpost `pause` |
| Time from resume to first frame | <= 300 ms | os_signpost `resume` / `playerBuild` |
| Cold-launch to menu-bar ready | <= 250 ms | os_signpost `launch` |
| Release binary size (unstripped `.app` executable) | track; stretch <= 2 MB | `ls -l` |

If a budget is physically impossible, record the measured floor and why.

## Safety pauses (do not remove)

Playback stops when displays or the Mac sleep, the screen is locked, the
screen saver runs, the user session is inactive, the wallpaper window is
fully occluded, battery is at or below 25% (forced) or the user threshold
(default 35% when "Pause on Battery" is on), or thermal state is serious
or critical.

User controls: Playback Quality (peak bit rate cap), Max Resolution,
hardware decoding.

Known gap: the wallpaper video itself does not yet react to Reduce Motion
(P4 / hypothesis K).

## P0 baseline

Recorded 2026-10-13 on this machine. Host: Apple M1, macOS 27.0.1.
Release `.app` from `./package.sh` (Command Line Tools) after the
Application Support isolation fix. Popover closed (`startMinimized`
default). Fixture: `perf/fixtures/1080p30-hevc-silent.mp4` (2 s loop).
Sample window 30 s after a 5–8 s settle. Git parent at measure time:
`0b93d3b`; the packaged binary also included Application Support
isolation (`LIVELY_APPLICATION_SUPPORT`, `LIVELY_CONFIG_FILE`, perf
UserDefaults suite). JSON:
`perf/results/20261013T141319Z-0b93d3b-idle.json` and the matching
playing / paused files (gitignored).

Isolation: setting `HOME` does **not** redirect
`FileManager.SearchPathDomainMask.userDomainMask`. The harness must set
`LIVELY_APPLICATION_SUPPORT` and `LIVELY_CONFIG_FILE`. Proof on this
run: user `config_v2.json` checksum `2558921003 1531` was unchanged.

Discard earlier tables from this day. The 20 s `85e332a` run and the
60 s `0b93d3b` run used `HOME` only; the 60 s idle sample was actually
playing a user wallpaper (~3% CPU, AVPlayer in `sample(1)`).

`footprint` values are `phys_footprint` (mebibytes = bytes / 1024²).
`top` %CPU is macOS one-core percent (can exceed 100% on many cores).

| Metric | Idle (no wallpaper) | Playing 1080p30 HEVC | Paused | Budget |
|---|---|---|---|---|
| `footprint` resident | 14 MB (peak 15) | 21 MB (peak 22) | 20 MB (peak 21) | 20 / 60 / 25 MB |
| `top` CPU % | 0.0 (all 6 samples) | 4.783 avg; last five 5.5, 5.7, 6.1, 5.5, 5.9 | 0.133 avg; samples 0.0, 0.3, 0.0, 0.5, 0.0, 0.0 | 0.0 / 1.5 / 0.0 |
| Threads (`top` #TH) | 9 → 3 | 25–27 | 8–10 | — |
| Idle wake-ups / s | — | — | — | <= 1 idle |
| Energy Impact | — | — | — | 0 / 3 / 0 |
| Release executable | 4,366,496 bytes (4.16 MiB) | same | same | track; stretch 2 MB |

`sample(1)` on the same PIDs: idle is CFRunLoop waiting (CoreMedia
linked, not on-CPU); playing is AVPlayer / CoreMedia decode; paused
still has `figThreadMain` waiting on Fig semaphores.

RAM is inside the idle/playing/paused budgets. Playing CPU is **above**
the 1.5% budget once decode is up (~5.7% of one core on this 30 s
window). Paused RAM stays ~6 MB above idle with CoreMedia threads still
resident — P1 confirmed this as hypothesis B.

## P1 fixture comparison (2026-10-14)

Same host and isolated harness as P0. `sample` / `heap` / `vmmap` added.
Popover closed. One 5K built-in display. JSON prefix `20261014T05`.

| Run | CPU avg (steady) | `footprint` | vs 1080p30 HEVC silent |
|---|---|---|---|
| Idle 45 s | 0.0 | 15 MB | — |
| 1080p30 HEVC silent | 4.367 (5.1–5.6) | 21 MB | baseline |
| 1080p30 HEVC audio, muted | 13.7 (14.8–17.7) | 47 MB | +9.3% CPU, +26 MB |
| 4K60 HEVC silent | 7.033 (7.8–8.9) | 26 MB | +2.7% CPU, +5 MB |
| 1080p30 H.264 silent | 4.217 (4.7–5.5) | 21 MB | ~same as HEVC |
| Paused 1080p30 HEVC | 0.017 | 19 MB | +4 MB vs idle |

1080p30 HEVC silent already misses the 1.5% playing budget (~5.2% of one
core in AVFoundation). A muted audio track triples that. Ranking and
A–N verdicts: `docs/perf-findings.md`.

## Open items P2–P4 (2026-10-15)

Same host and isolated harness as P1. Git `42df2f9` (`perf/open-items`
after H / J / B / A / E / F). Release `.app` from `./package.sh` (CLT).
Popover closed. One 5K built-in display. Sample window 30 s after a 5–8 s
settle. User `config_v2.json` checksum `2558921003 1531` before and after
(unchanged). `sudo -n` still unavailable; `xctrace` still needs full
Xcode (`xcode-select -p` is Command Line Tools). Idle wake-ups and Energy
Impact stay `—`.

JSON (gitignored):

- idle: `perf/results/20261015T042057Z-42df2f9-idle.json`
- playing silent: `perf/results/20261015T042152Z-42df2f9-playing.json`
- paused: `perf/results/20261015T042238Z-42df2f9-paused.json`
- playing muted-audio: `perf/results/20261015T042328Z-42df2f9-playing.json`
  (fixture `1080p30-hevc-audio.mp4`)

BEFORE copies the P1 rows that this after-set repeats. P1 idle was 45 s;
this after set is 30 s. The P1 table above is not replaced.

### BEFORE (P1, 2026-10-14)

| Run | CPU avg (steady) | `footprint` |
|---|---|---|
| Idle 45 s | 0.0 | 15 MB |
| 1080p30 HEVC silent | 4.367 (5.1–5.6) | 21 MB |
| 1080p30 HEVC audio, muted | 13.7 (14.8–17.7) | 47 MB |
| Paused 1080p30 HEVC | 0.017 | 19 MB |

### AFTER (`42df2f9`, 2026-10-15)

`top` %CPU is the JSON `cpu_pct_avg` (all 6 samples). The range is the
last five samples after the first 0.0 settle row. `footprint` is
`phys_footprint` (mebibytes).

| Run | CPU avg (steady) | `footprint` | vs P1 |
|---|---|---|---|
| Idle 30 s | 0.0 (all 6 samples) | 14 MB (peak 15) | same 0.0 CPU; −1 MB |
| 1080p30 HEVC silent | 3.733 (4.3–4.7) | 21 MB | −0.6% CPU, same RAM (decode floor) |
| 1080p30 HEVC audio, muted | 3.667 (4.1–4.5) | 22 MB (peak 24) | −10.0% CPU, −25 MB |
| Paused 1080p30 HEVC | 0.200 (1.2 then 0.0×4) | 18 MB (peak 21) | CPU up (teardown sample); −1 MB |

Threads (`top` #TH): idle 9 → 3; playing silent 25–28; playing muted-audio
23–26; paused 11 → 20 (grace teardown) → 4.

Muted-audio now matches silent playing (hypothesis H). Silent playing is
still ~4.5% of one core, above the 1.5% budget. Paused RAM is still +4 MB
vs idle (18 vs 14) but IOSurface virtual dropped (P1 ~82 MB → 15.9 MB) and
steady paused CPU after teardown is 0.0. Verdicts: `docs/perf-findings.md`.

Release executable: 4,420,368 bytes (4.22 MiB).

### Not measured here (need the operator)

`sudo -n` was not available, so `powermetrics` and Energy Impact are
blank on purpose.

```bash
# Idle wake-ups and process energy, 30 s, while Lively is in the mode you care about:
sudo powermetrics --samplers tasks --show-process-energy \
  --show-process-wait-times -i 1000 -n 30 --process-name Lively

# Energy Log (Instruments)
xctrace record --template 'Energy Log' --time-limit 30s \
  --output /tmp/lively-energy.trace \
  --launch -- /private/tmp/LivelyOutput/Lively.app/Contents/MacOS/Lively

# Signpost intervals (launch / synchronize / playerBuild / pause / resume)
xctrace record --template 'Time Profiler' --time-limit 30s \
  --output /tmp/lively-time.trace \
  --launch -- /private/tmp/LivelyOutput/Lively.app/Contents/MacOS/Lively
```

Or Activity Monitor: select Lively → Energy tab (Energy Impact, Idle
Wake Ups) while the harness is running (`LIVELY_PERF_SKIP_BUILD=1
scripts/perf/measure.sh playing 60`).

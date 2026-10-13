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
Release `.app` from `./package.sh` (Command Line Tools). Isolated `HOME`.
Popover closed (`startMinimized` default). Fixture:
`perf/fixtures/1080p30-hevc-silent.mp4` (2 s loop). Sample window 20 s
after a 5–8 s settle. Parent commit at measure time: `85e332a` plus this
P0 tree.

`footprint` values are `phys_footprint` (mebibytes = bytes / 1024²).
`top` %CPU is macOS one-core percent (can exceed 100% on many cores).

| Metric | Idle (no wallpaper) | Playing 1080p30 HEVC | Paused | Budget |
|---|---|---|---|---|
| `footprint` resident | 13 MB (peak 14) | 18 MB (peak 18) | 17 MB (peak 18) | 20 / 60 / 25 MB |
| `top` CPU % | 0.0 (all 4 samples) | 2.325 avg; last three samples 3.0, 3.1, 3.2 | 0.0 | 0.0 / 1.5 / 0.0 |
| Threads (`top` #TH) | 3–8 | 18–19 | (see raw) | — |
| Idle wake-ups / s | — | — | — | <= 1 idle |
| Energy Impact | — | — | — | 0 / 3 / 0 |
| Release executable | 4,364,304 bytes (4.16 MiB) | same | same | track; stretch 2 MB |

RAM is already inside the idle/playing/paused budgets. Playing CPU is
**above** the 1.5% budget on this 20 s window (~3% once decode is up).
Paused RAM stays ~4 MB above idle and still shows a CoreMedia memory pool,
which is consistent with hypothesis B (player left resident) — P1 must
confirm with Allocations.

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

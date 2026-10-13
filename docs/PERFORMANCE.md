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
resident — a **hint** for hypothesis B, not a P1 confirmation. Paused
CPU is not a clean 0.0 on this window.

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

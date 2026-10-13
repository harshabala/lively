# Performance measurement

P0 harness for `docs/PERFORMANCE_MASTER_PLAN.md`. Numbers come from a real
Apple silicon Mac. Do not paste invented values into `docs/PERFORMANCE.md`.

## Fixtures

```bash
scripts/perf/generate-fixtures.sh
```

Writes short clips under `perf/fixtures/` (gitignored):

| File | Purpose |
|------|---------|
| `1080p30-hevc-silent.mp4` | Default playing/paused budget clip |
| `1080p30-hevc-audio.mp4` | Audio-track decode hypothesis (H) |
| `1080p30-h264-silent.mp4` | Software-vs-hardware comparison |
| `4k60-hevc-silent.mp4` | Transcode-to-native hypothesis (J) |

## Measure

Quit any running Lively first. The script refuses to start if `Lively` is
already in the process list, so it never kills your daily instance.

```bash
scripts/perf/measure.sh idle 30
scripts/perf/measure.sh playing 30
scripts/perf/measure.sh paused 30
```

Each run packages a release `.app` (skip with `LIVELY_PERF_SKIP_BUILD=1`),
launches it with an isolated `HOME`, samples `top` and `footprint`, and writes
`perf/results/<date>-<commit>-<mode>.json`. Playing and paused assign the 1080p30
HEVC fixture to every visible Space via `LIVELY_PERF_*` env vars; they will
cover the desktop until the script stops the process.

### powermetrics (sudo)

```bash
sudo powermetrics --samplers tasks --show-process-energy \
  --show-process-wait-times -i 1000 -n 30 --process-name Lively
```

If `sudo -n` is not allowed, `measure.sh` records `powermetrics_error` and
leaves `idle_wakeups_per_s` and energy null.

### Energy Impact

Activity Monitor → Energy tab, or Instruments Energy Log:

```bash
xctrace record --template 'Energy Log' --time-limit 30s \
  --launch -- /private/tmp/LivelyOutput/Lively.app/Contents/MacOS/Lively
```

### Signposts

Release builds emit `os_signpost` intervals (`com.lively.app` / `Performance`):
`launch`, `synchronize`, `playerBuild`, `pause`, `resume`. Time Profiler or
the `os_signpost` Instruments template can attach to them.

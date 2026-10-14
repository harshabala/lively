#!/bin/bash
# Measure Lively resource use. Writes perf/results/<date>-<commit>-<mode>.json
#
# Usage:
#   scripts/perf/measure.sh [idle|playing|paused] [duration_seconds]
#
# Environment:
#   LIVELY_PERF_SKIP_BUILD=1   reuse an existing packaged app
#   LIVELY_OUTPUT_DIR          package.sh output (default /private/tmp/LivelyOutput)
#   LIVELY_PERF_FIXTURE        override clip for playing/paused
#   LIVELY_PERF_HOME           isolated HOME (default a temp dir)
#
# Does not touch ~/Library/Application Support/Lively. HOME is not enough:
# userDomainMask still points at the real Library. The launch also sets
# LIVELY_APPLICATION_SUPPORT and LIVELY_CONFIG_FILE.
#
# powermetrics needs sudo. If sudo is not available the JSON records
# powermetrics_error and the other samplers still run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

MODE="${1:-idle}"
DURATION="${2:-30}"
case "$MODE" in
  idle|playing|paused) ;;
  *)
    echo "usage: $0 [idle|playing|paused] [duration_seconds]" >&2
    exit 2
    ;;
esac
if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [[ "$DURATION" -lt 5 ]]; then
  echo "duration must be an integer >= 5" >&2
  exit 2
fi

COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RESULTS="$ROOT/perf/results"
mkdir -p "$RESULTS"
RAW_DIR="$RESULTS/${STAMP}-${COMMIT}-${MODE}"
mkdir -p "$RAW_DIR"

if pgrep -x Lively >/dev/null 2>&1; then
  echo "measure: a Lively process is already running. Quit it first so this" >&2
  echo "script does not attach to (or kill) your daily instance." >&2
  exit 1
fi

if [[ "${LIVELY_PERF_SKIP_BUILD:-}" != "1" ]]; then
  echo "measure: packaging release app"
  ./package.sh
fi

APP="${LIVELY_OUTPUT_DIR:-/private/tmp/LivelyOutput}/Lively.app"
BIN="$APP/Contents/MacOS/Lively"
if [[ ! -x "$BIN" ]]; then
  echo "measure: missing $BIN — run ./package.sh" >&2
  exit 1
fi

FIXTURE="${LIVELY_PERF_FIXTURE:-}"
if [[ "$MODE" == "playing" || "$MODE" == "paused" ]]; then
  if [[ -z "$FIXTURE" ]]; then
    "$ROOT/scripts/perf/generate-fixtures.sh"
    FIXTURE="$ROOT/perf/fixtures/1080p30-hevc-silent.mp4"
  fi
  if [[ ! -f "$FIXTURE" ]]; then
    echo "measure: fixture not found: $FIXTURE" >&2
    exit 1
  fi
fi

PERF_HOME="${LIVELY_PERF_HOME:-$(mktemp -d /tmp/lively-perf-home.XXXXXX)}"
SUPPORT="${PERF_HOME}/Library/Application Support"
mkdir -p "$SUPPORT/Lively"

echo "measure: mode=$MODE duration=${DURATION}s home=$PERF_HOME"
echo "measure: launching $BIN"

# Launch the bundle executable so env vars inherit.
# `open` goes through LaunchServices and drops those variables.
# HOME is not enough: userDomainMask still points at the real Library.
export HOME="$PERF_HOME"
export LIVELY_APPLICATION_SUPPORT="$SUPPORT"
export LIVELY_CONFIG_FILE="$SUPPORT/Lively/config_v2.json"
export LIVELY_PERF_MODE="$MODE"
if [[ -n "$FIXTURE" ]]; then
  export LIVELY_PERF_FIXTURE="$FIXTURE"
fi

"$BIN" &
PID=$!
sleep 0.4
if ! kill -0 "$PID" 2>/dev/null; then
  echo "measure: Lively did not stay running (pid $PID)" >&2
  exit 1
fi
echo "measure: pid=$PID"

# Settle: player build / pause grace (1.5s) plus a couple of seconds of decode.
SETTLE=5
if [[ "$MODE" == "paused" ]]; then
  SETTLE=8
fi
sleep "$SETTLE"

TOP_SAMPLES=$(( DURATION / 5 ))
if [[ "$TOP_SAMPLES" -lt 3 ]]; then
  TOP_SAMPLES=3
fi

echo "measure: sampling top (${TOP_SAMPLES} x 5s)"
top -l "$TOP_SAMPLES" -s 5 -pid "$PID" -stats pid,cpu,mem,rsize,threads \
  > "$RAW_DIR/top.txt" 2>/dev/null || true

# sample(1) works with Command Line Tools. xctrace/Instruments need full Xcode.
SAMPLE_SECS=10
if [[ "$DURATION" -lt 15 ]]; then
  SAMPLE_SECS=5
elif [[ "$DURATION" -ge 40 ]]; then
  # Long enough to catch the 20 s battery Timer (hypothesis A).
  SAMPLE_SECS=25
fi
if command -v sample >/dev/null 2>&1; then
  echo "measure: sample ${SAMPLE_SECS}s of pid $PID"
  sample "$PID" "$SAMPLE_SECS" 1 -mayDie -file "$RAW_DIR/sample.txt" \
    >"$RAW_DIR/sample.err" 2>&1 || true
fi

echo "measure: footprint"
if footprint -p "$PID" > "$RAW_DIR/footprint.txt" 2>"$RAW_DIR/footprint.err"; then
  :
else
  echo "measure: footprint failed (see $RAW_DIR/footprint.err)"
fi

if command -v heap >/dev/null 2>&1; then
  echo "measure: heap (top by size)"
  heap -sH "$PID" 2>"$RAW_DIR/heap.err" | python3 -c '
import sys
lines = sys.stdin.readlines()
sys.stdout.writelines(lines[:120])
' > "$RAW_DIR/heap-top.txt" || true
fi
if command -v vmmap >/dev/null 2>&1; then
  echo "measure: vmmap --summary"
  vmmap --summary "$PID" > "$RAW_DIR/vmmap-summary.txt" 2>"$RAW_DIR/vmmap.err" || true
fi

POWERMETRICS_ERROR=""
if command -v powermetrics >/dev/null 2>&1; then
  if sudo -n true 2>/dev/null; then
    echo "measure: powermetrics (passwordless sudo)"
    sudo powermetrics --samplers tasks --show-process-energy \
      --show-process-wait-times -i 1000 -n 10 \
      --process-name Lively \
      > "$RAW_DIR/powermetrics.txt" 2>"$RAW_DIR/powermetrics.err" || \
      POWERMETRICS_ERROR="powermetrics failed; see powermetrics.err"
  else
    POWERMETRICS_ERROR="sudo required: sudo powermetrics --samplers tasks --show-process-energy --show-process-wait-times -i 1000 -n 30 --process-name Lively"
    echo "measure: skipping powermetrics ($POWERMETRICS_ERROR)"
  fi
else
  POWERMETRICS_ERROR="powermetrics not found"
fi

BINARY_BYTES="$(stat -f%z "$BIN" 2>/dev/null || wc -c < "$BIN" | tr -d ' ')"
CHIP="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
OS_VER="$(sw_vers -productVersion 2>/dev/null || echo unknown)"

JSON="$RESULTS/${STAMP}-${COMMIT}-${MODE}.json"
MEASURE_STAMP="$STAMP" MEASURE_COMMIT="$COMMIT" MEASURE_MODE="$MODE" \
MEASURE_DURATION="$DURATION" MEASURE_PID="$PID" MEASURE_CHIP="$CHIP" \
MEASURE_OS="$OS_VER" MEASURE_BIN="$BINARY_BYTES" \
MEASURE_POWER_ERR="$POWERMETRICS_ERROR" MEASURE_RAW="$RAW_DIR" MEASURE_JSON="$JSON" \
MEASURE_FIXTURE="${FIXTURE:-}" \
python3 <<'PY'
import json, os, re
from pathlib import Path

pid = os.environ["MEASURE_PID"]
raw_dir = Path(os.environ["MEASURE_RAW"])

def cpu_avg(text: str):
    vals = []
    for line in text.splitlines():
        parts = line.split()
        if parts and parts[0] == pid and len(parts) >= 2:
            try:
                vals.append(float(parts[1]))
            except ValueError:
                pass
    if not vals:
        return None
    return round(sum(vals) / len(vals), 3)

def size_to_bytes(num: str, unit: str) -> int:
    n = float(num)
    u = unit.upper().rstrip("s")
    mul = {"": 1, "B": 1, "KB": 1024, "MB": 1024**2, "GB": 1024**3}
    return int(n * mul.get(u, 1))

def parse_footprint(text: str):
    phys = peak = None
    m = re.search(r"phys_footprint:\s+([0-9.]+)\s*([A-Za-z]+)", text)
    if m:
        phys = size_to_bytes(m.group(1), m.group(2))
    m = re.search(r"phys_footprint_peak:\s+([0-9.]+)\s*([A-Za-z]+)", text)
    if m:
        peak = size_to_bytes(m.group(1), m.group(2))
    return phys, peak

top_text = (raw_dir / "top.txt").read_text(errors="replace") if (raw_dir / "top.txt").exists() else ""
fp_text = (raw_dir / "footprint.txt").read_text(errors="replace") if (raw_dir / "footprint.txt").exists() else ""
phys, peak = parse_footprint(fp_text)
err = os.environ.get("MEASURE_POWER_ERR") or None

payload = {
    "date": os.environ["MEASURE_STAMP"],
    "commit": os.environ["MEASURE_COMMIT"],
    "mode": os.environ["MEASURE_MODE"],
    "duration_seconds": int(os.environ["MEASURE_DURATION"]),
    "pid": int(pid),
    "chip": os.environ["MEASURE_CHIP"],
    "os": os.environ["MEASURE_OS"],
    "binary_bytes": int(os.environ["MEASURE_BIN"]),
    "cpu_pct_avg": cpu_avg(top_text),
    "footprint_bytes": phys,
    "footprint_peak_bytes": peak,
    "powermetrics_error": err,
    "energy_impact": None,
    "idle_wakeups_per_s": None,
    "raw_dir": str(raw_dir),
    "fixture": os.environ.get("MEASURE_FIXTURE") or None,
    "notes": [
        "Energy Impact is Activity Monitor / Instruments Energy Log; not sampled here.",
        "Idle wake-ups need powermetrics or Activity Monitor.",
        "Never invent numbers; fields are null when the sampler did not run.",
    ],
}
out = os.environ["MEASURE_JSON"]
with open(out, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2)
    fh.write("\n")
print("wrote", out)
PY

echo "measure: stopping pid $PID"
kill "$PID" 2>/dev/null || true
sleep 0.5
kill -9 "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

echo "measure: done"
cat "$JSON"

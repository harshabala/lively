# Perf findings

Hypothesis table (A–N) lives in `docs/PERFORMANCE_MASTER_PLAN.md` §1. P1
must confirm or refute each item with Instruments. Until then, treat the
table as unread code, not measured fact.

## P0 (this branch)

- Finder/iCloud `* 2.*` duplicates removed (byte-identical except
  `Lively-task-list-plan 2.md`, which was an older copy of the tracked file).
- Dependabot `actions/checkout` 4 → 7 merged on `master` as #8 (CI green).
- Signposts: `launch`, `synchronize`, `playerBuild`, `pause`, `resume`
  (`com.lively.app` / `Performance`).
- `scripts/perf/measure.sh` writes JSON under `perf/results/`. Null fields
  mean the sampler did not run. Do not fill them in by hand.
- Isolation: `HOME` does not move `userDomainMask`. Harness sets
  `LIVELY_APPLICATION_SUPPORT`, `LIVELY_CONFIG_FILE`, and a throwaway
  `com.lively.app.perf` UserDefaults suite. `sample(1)` is captured when
  present (CLT; no Xcode).
- Canonical baseline is the isolated 30 s run in `docs/PERFORMANCE.md`.
  Playing CPU (~5.7% once decode is up) misses the 1.5% budget. Paused
  footprint 20 MB vs idle 14 MB, with `figThreadMain` still waiting —
  treat as a **hint** for hypothesis B, not a P1 confirmation. Wake-ups
  and Energy Impact were not sampled (powermetrics needs sudo).
- Earlier same-day tables that used `HOME` only are invalid. One leaked
  run wrote the fixture into the real `config_v2.json`; isolation is now
  a P0 correctness requirement.

## P1 (not started)

See the P1 plan in the P0 pull request. Do not skip. Do not start P2 until
this file records a ranked, measured list.

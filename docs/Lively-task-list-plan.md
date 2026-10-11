# Lively — Agent task list & implementation plan

> **Give this entire file to one agent (or one session). Work only on this product until ship criteria are met.**

| Field | Value |
|-------|--------|
| **Product** | Lively |
| **Priority** | P2 — ship + craft proof |
| **GitHub** | https://github.com/harshabala/Lively |
| **Local clone (preferred)** | `~/Documents/Projects/Lively` |
| **If missing, clone to** | `~/Documents/Projects/Lively` via `gh repo clone harshabala/Lively` |
| **Default branch** | `master` |
| **Work branch** | `feat/flow-metrics-2026-07` (create from latest default if needed) |
| **Stack** | Swift Package macOS menu-bar video wallpaper app |
| **Task IDs** | LV-1, LV-2, LV-3 |
| **Fable plan status** | Fable plan FAILED — reconstructed below from task list |
| **Work already done** | None for this initiative |

## Agent instructions (start here)

1. **Read this whole file** before editing.
2. **cd** to the local clone path above. If the path does not exist, clone the GitHub repo there.
3. `git fetch origin && git checkout -B feat/flow-metrics-2026-07 origin/master` (or continue existing feature branch if present).
4. Implement tasks in the **recommended commit sequence** at the bottom of the plan section.
5. After each commit: run the **verify commands** listed below.
6. Create/update **`docs/TASKS.md`** with every task ID and status.
7. Complete the **README dual-section rewrite**.
8. Run design + code + security self-review on the diff; fix critical/high issues.
9. Push branch and open a PR against `master`. Do **not** force-push. Do **not** merge unless the user asked for auto-merge.
10. Do **not** touch other portfolio repos in this session.

## What “done” means for this product

All task IDs listed above are implemented **or** explicitly documented as infeasible with a narrow alternative. Metrics are local-first, activation is a named constant, scoreboard is user-visible with method + privacy copy, README is dual-section, `docs/TASKS.md` is accurate, tests/build green, PR open.


## Global constraints (apply to ALL work)

Source: `<local-path>` and `<local-path>`.

1. **Local-first metrics** — counters/estimates on device or extension storage only. Nothing leaves unless user explicitly exports or opts in. **No cloud analytics in v1.**
2. **One activation event** — named constant in code (e.g. `ACTIVATION_EVENT = '...'`).
3. **User-visible scoreboard** on the natural success screen (ParseKit token-savings pattern), with **method + caveat microcopy**. Honest estimates; never fake precision.
4. **Privacy line on every stats surface:** e.g. *"Stored only on this device. Never uploaded."* (wording may adapt slightly per product).
5. **Zero-AI default** where relevant — core loop works without API keys; AI is optional upgrade.
6. **README rewrite required** in every repo (see below).
7. **`docs/TASKS.md`** committed checklist; update checkboxes as you finish task IDs.
8. **Ship path:** branch `feat/flow-metrics-2026-07` → push → open PR → (if user requested auto-merge and reviews pass) squash-merge to default branch and delete feature branch.

### README overhaul (mandatory for every product)

Rewrite `README.md` with **two top sections**:

#### Start here (novice)
Plain everyday words, zero jargon:
- What it is
- What problems it solves
- Step-by-step install and first use
- Edge cases and how to still use it when you hit them

#### For technical users
- Mermaid architecture diagram (GitHub-native render)
- How it works under the hood
- Metrics / activation definition
- Dev install, test commands, storage/privacy notes

### Ship checklist per repo

- [ ] All task IDs for this product implemented or honestly deferred with reason in PR
- [ ] `docs/TASKS.md` updated (checkboxes match reality)
- [ ] README novice + technical sections done
- [ ] Build/tests pass (commands in this file)
- [ ] Design pass (hierarchy, motion, empty states, reduced-motion)
- [ ] Code pass (edge cases, no regressions)
- [ ] Security pass (secrets, XSS, storage, permissions, no accidental egress)
- [ ] Branch pushed; PR opened with body mapping commits → task IDs → metrics
- [ ] Merge only if user wants auto-merge **or** explicitly asks

### Related docs (read if needed)

| File | Why |
|------|-----|
| `<local-path>` | Original product task specs + metrics definitions |
| `<local-path>` | Why these metrics matter (senior PM framing) |
| `<local-path>` | Multi-repo orchestration notes |
| `<local-path>` | What Fable completed (mostly plans only) |



## Work already completed

None for flow-metrics.

## Original product task spec

# P2 — Lively

## Product in one line

macOS menu-bar video wallpapers per Space / display, offline.

## Current gap

Activation is “set a wallpaper once.” Retention is “still set weeks later.” Less business narrative — keep metrics light and local.

---

### Task LV-1 — First-run: pick video → apply → confirm Space

| Field | Detail |
|-------|--------|
| **Flow change** | On first launch: pick sample or file → Apply to current Space → toast *“Playing on this Space. Switch Spaces to set another.”* |
| **How it helps** | Activation in one minute. |
| **Metric: Activation** | `activated = wallpaper successfully applied ≥1` |
| **Privacy** | Paths local only; never upload video. |
| **Acceptance** | Sample video works without Finder hunt. |

### Task LV-2 — Menu bar: “Now playing” + days active

| Field | Detail |
|-------|--------|
| **Flow change** | Menu: current display/Space mapping; *“Active X days”* (days app applied a wallpaper for ≥1 hour — local). |
| **How it helps** | Lightweight retention signal for user and portfolio. |
| **Metric** | `days_with_wallpaper_active` |
| **User understanding** | *“Counts days Lively was actively rendering on at least one display.”* |
| **Acceptance** | Zero network dependency. |

### Task LV-3 — Performance honesty

| Field | Detail |
|-------|--------|
| **Flow change** | If thermal/CPU throttle: gentle notice *“Reduced quality to save power”* — builds trust. |
| **How it helps** | Nuance; support burden. |
| **Metric** | Optional local `throttle_events` count for your debugging only (not user-facing required). |

**Lively north star:** still active at day 7 among activated.  
**User-facing:** now playing + days active.

---

## Implementation plan for agent


## Implementation plan (Fable never produced a plan — reconstructed from task list)

### Repo orientation
- Swift Package macOS app: `Package.swift`, `Sources/`, `Tests/`.
- Menu-bar video wallpaper; per Space / display; offline.

### LV-1 — First-run: pick video → apply → confirm Space
- First launch flow with sample video if needed.
- Activation: `ACTIVATION_EVENT = 'wallpaper_applied_once'` when apply succeeds.
- Local flag / date of first apply.

### LV-2 — Menu bar “Now playing” + days active
- Show current Space/display mapping.
- `days_with_wallpaper_active` local counter (days app rendered ≥1 hour optional; if hard, “days app applied wallpaper” is OK with honest copy).
- Privacy: paths local; never upload video.

### LV-3 — Performance honesty
- If thermal/CPU throttle: gentle notice reduced quality.

### Metrics
- Activation: wallpaper applied ≥1
- User-facing: now playing + days active
- Privacy line on stats surfaces

### Verify
```bash
swift build
swift test   # if tests exist
```

### Commit sequence
1. feat: activation + first-run apply flow (LV-1)
2. feat: menu bar now-playing + days active (LV-2)
3. feat: throttle/performance honesty notice (LV-3)
4. docs: README dual sections + docs/TASKS.md


## Agent completion checklist

- [ ] LV-1 … LV-3
- [ ] README dual sections
- [ ] docs/TASKS.md
- [ ] swift build (+ tests if present)
- [ ] Security: no network for wallpapers; local paths only
- [ ] PR against master

# Lively: North Star and the road to 10/10

Written 2026-11-13 from a review of the repository and the October plan. This replaces
`2026-10-19-path-to-10.md` as the thing to work from; that plan's performance findings remain
valid and are referred to below.

The owner has not yet described their own complaint about this project, so the North Star below
is proposed and should be confirmed.

Read "Rules for agents" first, then take the first workstream whose "Done when" is not yet true.

## What it is

A small menu bar app that plays looping video behind the desktop icons. Each display and each
Space can have its own clip. No Dock icon, no account, no cloud. It is public and has releases.

## North Star (proposed)

**People who install it leave it running.** For a wallpaper that means: it is beautiful, and the
Mac's battery and fans never give a reason to quit it.

## What 10/10 looks like: three scenarios

1. **Invisible cost.** With a clip playing on the built-in display, processor use stays within
   the 1.5 % budget set in `PERFORMANCE.md`, and it drops to near zero when the desktop is covered,
   the display sleeps, or the Mac is on low battery.
2. **Thirty seconds to delight.** A new user installs, opens, picks a clip and sees it playing in
   under thirty seconds, with no terminal command to get past the system's security warning.
3. **Set and forget.** Per-display and per-Space choices survive sleep, wake, display changes and
   restarts without a flash, a black frame or a wrong clip.

## Where it is today (purpose score: 7/10)

True today:
- Works, is released, has 100 tests and a performance harness. The binary was cut to 1.5 MB.
- Logs no longer leak file names.

Gaps, from the October plan:
- **Playing costs about 3.4 to 3.6 % of a processor against a 1.5 % budget.** Paused playback
  still holds media resources. Wake-ups and energy impact were never measured.
- **Not notarized**, so new users must run a terminal command to open it.
- Playback and window code has no automated tests; multi-display and sleep/wake were not checked
  on hardware.
- No playlists or schedules. Behaviour under the system's Reduce Motion setting is undecided, as
  is the handling of 4K clips.
- Two pull requests are open (`perf/p0`, `perf/p1`); the Documents checkout sits on the second.

## Workstreams, in order

### 0. One clean base
- Merge or close the two performance pull requests and `harsha/path-to-10-985300`.
- **Done when:** one checkout on `master`, smoke script green, GitHub equals local.

### 1. Meet the performance budget (scenario 1)
- Continue the ranked hypotheses in `perf-findings.md`. Pause fully when the desktop is not
  visible; release media resources when paused; respect low power mode and battery.
- **Done when:** the harness shows playing within budget and covered or asleep near zero, and an
  energy measurement on the owner's Mac confirms it.

### 2. Survive everything (scenario 3)
- A hardware checklist run: two displays, plugging and unplugging, sleep and wake, Space changes,
  restart. Fix every flash, black frame or wrong clip.
- **Done when:** the checklist passes twice in a row.

### 3. No-friction install (scenario 2)
- Signing and notarization; a first-run that ends with a clip playing; a few bundled clips or a
  clear way to get some.
- **Done when:** a fresh Mac user account installs and plays a clip in under thirty seconds.

### 4. Decisions, then features
- Reduce Motion behaviour and the 4K policy first. Then playlists or schedules if the owner wants
  them.
- **Done when:** both decisions are implemented with tests.

### 5. Feel
- The picker and menu: previews, motion, and a clear picture of which display and Space has what.
- **Done when:** the owner accepts a screen recording of first run and of changing a clip.

## Rules for agents

- Fully offline. No network calls except the optional update check.
- Never touch the user's real configuration file in tests; the harness already guards this.
- A performance claim is made only with harness numbers before and after.
- `./scripts/smoke_verify.sh` green before every commit.

## Needs the owner

- Confirming the North Star and what bothers them most about Lively today.
- Apple Developer ID for notarization; running the energy measurement, which needs a password.
- The hardware checklist with a second display.
- The Reduce Motion and 4K decisions.

## Scoring

One point each, ten in all: within budget while playing (2); near zero when covered or asleep
(1); energy measured (1); hardware checklist passes (2); notarized (1); thirty-second first run
(1); both product decisions shipped (1); owner accepts the feel (1).

Today: 7 for a released, working app that costs more power than it should and is awkward to
install.

# Agent log

## 2026-11-23

- Stopped. Branch `agent/north-star` at `0dd626a`. `./scripts/smoke_verify.sh` exit 0: 108 tests passed, release app packaged and signed. `./scripts/check_hygiene.sh` hygiene: OK. Did not launch the app. Did not write `config_v2.json`. Did not view a screen.
- VoiceOver: settings switches and menus stay actions; welcome hides Pause, Quit, and tabs and dismisses with Escape (same as Not now); Dismiss, Reselect, and View are their own controls; focus rings restored where `focusEffectDisabled` had removed them.
- Playback error clears "Playing on this display". Library Remove and All displays confirm before delete or overwrite. Heat pause copy says heat, not battery. Pause banner says Resume, matching the control. Dark primary labels use near-black `onPrimary`, not white on `#55CAD0`. Light `#007078` unchanged. No new on-screen contrast measurement.

## 2026-11-18

- Stopped. Branch `agent/north-star` at `7f79776`. `./scripts/smoke_verify.sh` exit 0: 107 tests passed, release app packaged and signed. Did not launch the app. Did not write `config_v2.json`.
- Workstream 1 is not finished. Playing CPU stays about 3.3-4.6 % against a 1.5 % budget. The measured floor is AVFoundation decode. Hypothesis H (mute audio tracks) and B (cold pause) already landed. The next playing-CPU lever is a smaller stream, which is the owner's 4K decision. Energy and wake-ups need `sudo powermetrics`.
- Left for the owner: confirm the North Star; Apple Developer ID; energy measurement; hardware checklist with a second display; Reduce Motion and 4K decisions; accept a screen recording of first run and of changing a clip. Do not merge this branch to `master`.
- Plan score: 7, unchanged.

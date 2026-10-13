# CPU, GPU and battery budget

Targets (to be measured with Activity Monitor / Instruments on real hardware; they
were not measured in the audit environment):

- Idle with no wallpaper assigned: no decoding, negligible CPU.
- Playing 1080p HEVC on Apple silicon: hardware decode, low single-digit CPU percent per display.
- Nothing visible, nothing decoded: playback stops when displays or the Mac sleep, the
  screen is locked or the screen saver runs, the user session is inactive, or the
  wallpaper window is fully occluded (for example by a full-screen app).
- Battery: playback pauses at or below 25% on battery (forced) and at the user threshold
  (default 35%) when "Pause on Battery" is on; it resumes on AC.
- Thermal: playback is throttled/paused under serious thermal pressure.
- User controls: Playback Quality (peak bit rate cap), Max Resolution, hardware decoding.

Known gap: the wallpaper video itself does not yet react to the system Reduce Motion
setting. Tracked as a follow-up (design decision: pause on first frame vs. keep playing).

# Lively — Implementation Plan (v2)

> macOS live wallpaper app with per-Space video support

---

## 1. Product Overview

**What it does:** Lively renders looping videos as desktop wallpapers on macOS, supporting independent wallpapers per virtual Space (Mission Control desktop).

**Core constraint:** macOS does not expose a stable public Space ID API for third-party apps. Lively works around this by using the static desktop image URL assigned to each Space as a stable proxy identifier.

**Target user:** macOS power users with multiple Spaces who want dynamic, personalized desktops without the resource cost of screensavers.

---

## 2. User Journey

### 2.1 First Launch

1. User downloads and opens Lively.app.
2. A **Welcome sheet** appears explaining the one-time setup requirement: each Space must have a unique static wallpaper assigned via System Settings → Wallpaper.
3. A guided "Space Setup" flow opens System Settings to Wallpaper automatically (`NSWorkspace.open`) with instructions overlaid.
4. User returns to Lively. The app detects all configured Spaces via screen enumeration and shows them in a grid.

### 2.2 Assigning a Video to a Space

1. User sees a grid of Space cards — each card shows a thumbnail of the static wallpaper (the Space's identity).
2. User clicks a Space card or drags a video file onto it.
3. A file picker (`NSOpenPanel`) filters for supported formats: `.mp4`, `.mov`, `.m4v`, `.hevc`.
4. On selection, a **preview loop** plays in the card thumbnail.
5. User clicks "Apply". The video is immediately rendered behind the desktop icons for that Space.
6. A success toast confirms assignment.

### 2.3 Switching Spaces

1. User switches Space (swipe, keyboard shortcut, Mission Control).
2. Lively detects the Space change via `NSWorkspace.activeSpaceDidChangeNotification`.
3. The overlay window cross-fades (configurable duration, default 300ms) to the video assigned to the new Space, or hides if no video is assigned.

### 2.4 Ongoing Use (Menu Bar)

- Lively lives in the **menu bar** (no Dock icon) with a minimal icon.
- Menu bar dropdown gives quick access to: Pause All / Resume, Open Settings, Quit.
- Plays/pauses automatically on battery (opt-in toggle).

---

## 3. Architecture

### 3.1 The Per-Space Problem & Solution

macOS exposes no stable public Space ID. **Solution:** Use the desktop picture URL (`NSWorkspace.shared.desktopImageURL(for: screen)`) as a proxy for Space identity.

**Setup contract:** Each Space the user wants to customize must have a unique static wallpaper image. Lively maps `DesktopImageURL → VideoURL`.

**Edge cases handled:**
- Same static wallpaper on two Spaces → treated as the same context; last-assigned video wins. UI warns on duplicate detection.
- Wallpaper changed mid-session → space config becomes orphaned; surfaced as a warning in Settings.
- No static wallpaper assigned to a Space → Lively shows the default video (if configured) or no video.

### 3.2 Component Map

```
Lively.app
├── AppDelegate              (NSApplicationDelegate, menu bar lifecycle)
├── SpaceMonitor             (detects Space changes, publishes context URL)
├── WallpaperController      (manages WallpaperWindow per NSScreen)
│   └── WallpaperWindow      (NSWindow at desktop level)
│       └── VideoPlayerView  (AVPlayerLayer, looping)
├── ConfigStore              (persists URL→Video mappings)
├── SettingsView             (SwiftUI: Space grid, video assignment, preferences)
└── WelcomeView              (SwiftUI: onboarding flow)
```

---

## 4. Technical Specifications

### 4.1 `WallpaperWindow` (NSWindow)

```swift
// Window level: below desktop icons, above the static wallpaper
window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)

// Behavior
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
window.styleMask = .borderless
window.isOpaque = false
window.backgroundColor = .clear
window.ignoresMouseEvents = true
window.hasShadow = false

// IMPORTANT: Do NOT use .managed collectionBehavior — it breaks Space isolation
```

**Sonoma/Sequoia z-order note:** macOS Sonoma introduced desktop widgets at `kCGDesktopIconWindowLevel`. Target `kCGDesktopWindowLevel` (not `kCGDesktopIconWindowLevel - 1`) to sit behind both widgets and icons. Validate on each major macOS release.

**Multi-monitor:** Create one `WallpaperWindow` per `NSScreen`. Each window independently tracks its screen's current desktop image URL.

### 4.2 `VideoPlayerView` (NSView / CALayer)

```swift
class VideoPlayerView: NSView {
    private var playerLayer: AVPlayerLayer!
    private var playerLooper: AVPlayerLooper!
    private var queuePlayer: AVQueuePlayer!

    func load(url: URL) {
        let item = AVPlayerItem(url: url)
        queuePlayer = AVQueuePlayer()
        playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        playerLayer.player = queuePlayer
        playerLayer.videoGravity = .resizeAspectFill
        queuePlayer.play()
    }

    func crossFade(to newURL: URL, duration: TimeInterval = 0.3) {
        // Fade out current layer, swap video, fade in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            playerLayer.opacity = 0
        } completionHandler: {
            self.load(url: newURL)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = duration
                self.playerLayer.opacity = 1
            }
        }
    }
}
```

**Supported codecs:** H.264, H.265/HEVC, ProRes (via AVFoundation). HEVC hardware decode preferred for efficiency.

**Audio:** Always muted (`player.volume = 0`). No audio controls exposed (wallpapers should be silent by default; future option).

### 4.3 `SpaceMonitor` (ObservableObject)

```swift
@MainActor
class SpaceMonitor: ObservableObject {
    @Published var currentContextURL: URL? = nil

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(spaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )
    }

    @objc private func spaceDidChange() {
        // Small delay to ensure desktopImageURL reflects the new Space
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.currentContextURL = NSWorkspace.shared
                .desktopImageURL(for: NSScreen.main ?? NSScreen.screens[0])
        }
    }
}
```

**Why the 0.05s delay:** `activeSpaceDidChangeNotification` fires slightly before `desktopImageURL` reflects the new Space. Empirically tested; adjust if needed on each macOS version.

### 4.4 `ConfigStore`

```swift
// Stored in: ~/Library/Application Support/Lively/config.json
struct SpaceConfig: Codable {
    let spaceKey: String          // desktopImageURL.absoluteString
    let videoURL: String          // absolute path to video file
    let addedAt: Date
}

class ConfigStore: ObservableObject {
    @Published private(set) var configs: [String: SpaceConfig] = [:]

    func assign(video: URL, toSpaceKey key: String) { ... }
    func videoURL(for spaceKey: String) -> URL? { ... }
    func remove(spaceKey: String) { ... }

    private func persist() {
        // Encode to JSON, write atomically to avoid corruption
    }
}
```

**Security:** Video file access is bookmarked using `URL.bookmarkData(options: .withSecurityScope)` so the app retains access after relaunch without re-prompting.

### 4.5 `WallpaperController`

```swift
class WallpaperController {
    private var windows: [NSScreen: WallpaperWindow] = [:]

    func update(for contextURL: URL?) {
        guard let contextURL else { hideAll(); return }
        let key = contextURL.absoluteString

        if let videoURL = configStore.videoURL(for: key) {
            show(videoAt: videoURL)
        } else if let defaultVideo = configStore.defaultVideoURL {
            show(videoAt: defaultVideo)
        } else {
            hideAll()
        }
    }
}
```

---

## 5. Feature Set

### 5.1 MVP (v1.0)

| Feature | Description |
|---|---|
| Per-Space video assignment | Map unique static wallpaper → looping video |
| Space auto-detection | Detect Space changes, swap video with cross-fade |
| Multi-monitor support | Independent video per screen per Space |
| Menu bar app | No Dock icon; quick pause/resume/quit |
| Battery pause | Automatically pause video when on battery power |
| Supported formats | `.mp4`, `.mov`, `.m4v` (H.264, H.265) |
| Security-scoped bookmarks | Retain file access across relaunches |
| Settings UI | SwiftUI settings panel with Space grid |

### 5.2 v1.1 — Quality of Life

| Feature | Description |
|---|---|
| Default video | Fallback video shown for unmapped Spaces |
| Duplicate Space warning | Alert when two Spaces share the same static wallpaper |
| Orphaned config detection | Warn when a configured wallpaper image no longer exists |
| Video trim/offset | Start video at a specific timestamp |
| Playback speed control | 0.25x – 2x speed multiplier |
| Login item toggle | Auto-start on login (using `SMAppService`) |

### 5.3 v1.2 — Power Features

| Feature | Description |
|---|---|
| Playlist mode | Cycle through multiple videos for a Space on a timer |
| Screensaver link | Use same video as screensaver (via `ScreenSaverView`) |
| Built-in video library | Curated free wallpaper videos (HEVC, royalty-free) |
| iCloud sync | Sync Space configs across Macs |
| CLI / URL scheme | `lively://assign?space=<key>&video=<path>` for automation |

---

## 6. Settings UI (SwiftUI)

```
SettingsView
├── Tab: Wallpapers
│   ├── Space grid (2-col)
│   │   └── SpaceCard: thumbnail, assigned video name, drag-drop target
│   ├── Default video picker
│   └── Add/Remove Space configs
├── Tab: Playback
│   ├── Cross-fade duration (slider: 0–1s)
│   ├── Pause on battery (toggle)
│   ├── Pause when screen locked (toggle)
│   └── Playback speed (slider)
└── Tab: About
    ├── Version, credits
    └── "Check for updates" button
```

**Space detection in Settings:** The currently active Space is highlighted with a blue border on the Space card, updating live as the user switches Spaces while Settings is open.

---

## 7. Performance Targets

| Metric | Target | How |
|---|---|---|
| CPU idle (video playing) | < 5% on Apple Silicon | HEVC via VideoToolbox hardware decode |
| CPU idle (H.264) | < 8% | AVFoundation decode path |
| Memory footprint | < 80 MB | Single AVQueuePlayer per screen; lazy init |
| Launch time | < 1s to menu bar | Async video load; show menu bar first |
| Space switch latency | < 150ms perceptible delay | Pre-cache next video on Space pre-switch signals |

**Frame rate:** Lock playback to display refresh rate (`AVPlayer.rate` + `CADisplayLink`) — no need to render at 60fps for wallpaper content; 24–30fps is sufficient and reduces GPU load.

---

## 8. Permissions & Entitlements

| Permission | Why needed |
|---|---|
| `com.apple.security.files.user-selected.read-only` | Access user-selected video files |
| `com.apple.security.files.bookmarks.app-scope` | Persist file access across relaunches |
| `NSScreenCaptureUsageDescription` | Not needed — AVPlayerLayer renders directly; no screen capture |
| Hardened runtime | Required for notarization |

**Sandboxing note:** Lively can be sandboxed. All file access goes through security-scoped bookmarks. No need for `com.apple.security.temporary-exception.files.absolute-path`.

---

## 9. Verification & Test Plan

### 9.1 Functional Tests

| Test | Steps | Pass Criteria |
|---|---|---|
| Basic playback | Launch app, assign video to current Space | Video renders behind icons |
| Space switching | 2 Spaces, different static wallpapers, different videos assigned | Video changes within 150ms of Space switch |
| Cross-fade | Switch Spaces with fade enabled | Smooth opacity transition, no black flash |
| Multi-monitor | Two displays, assign different videos | Each display shows its own video independently |
| No assignment | Switch to a Space with no video assigned | Desktop shows through cleanly (no black overlay) |
| Relaunch persistence | Assign video, quit, relaunch | Same video plays for configured Space |
| Battery pause | Unplug power with toggle enabled | Playback pauses; resumes on plug-in |

### 9.2 Edge Case Tests

| Scenario | Expected Behavior |
|---|---|
| Video file deleted after assignment | Graceful fallback to default or blank; surface warning in Settings |
| Space removed from Mission Control | Orphaned config remains; no crash |
| External display disconnected | Window for that screen is cleaned up |
| macOS upgrade (major version) | z-order and Space detection re-validated on first launch |
| Ultra-wide / non-standard resolution | `resizeAspectFill` handles; letter-box not visible |

### 9.3 Performance Benchmarks

Run via Instruments (Time Profiler + Metal System Trace):
- Steady-state CPU with 4K HEVC wallpaper on M-series: target < 3%
- Steady-state CPU on Intel Mac (H.264, 1080p): target < 8%
- Memory: `vmmap` snapshot should show no growing regions over 30-min run

---

## 10. Open Questions / Risks

| Item | Risk Level | Notes |
|---|---|---|
| macOS API changes to `desktopImageURL` | Medium | The private Space ID approach could break; monitor release notes |
| Sonoma/Sequoia widget z-order shifts | Medium | Re-test window level on every major release |
| App Store distribution | High | Window level manipulation may trigger App Review rejection; consider direct distribution via Gumroad/website + notarization |
| HEVC licensing on older Macs | Low | VideoToolbox handles this; fallback to H.264 |
| iCloud sync complexity (v1.2) | Medium | Security-scoped bookmarks don't sync well; may require re-linking videos on each machine |

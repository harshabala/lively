# Lively — Rewritten Codebase (macOS Tahoe 26, Multi-Screen)

## Mission
Bring life to every macOS desktop space with seamless per-space video wallpapers.
Multi-screen aware. Non-sandboxed. Liquid Glass UI. Zero resource leaks.

## What Changed vs Original

| Area | Original Bug | Fix Applied |
|---|---|---|
| Window ordering | `makeKeyAndOrderFront` fought Finder, window buried | `orderFront(nil)` + level re-assertion on space change |
| Security scope | `startAccessingSecurityScopedResource` called, never stopped | Removed entirely — non-sandboxed apps don't need it |
| AVPlayer fade | `playerLayer.opacity` animated via NSAnimationContext (no-op on CALayer) | `CABasicAnimation` + KVO `readyToPlay` gate |
| AVPlayerLooper | Looper orphaned on concurrent `crossFade` calls | `isFading` guard + explicit cleanup before reload |
| Space identity | Only `NSScreen.main`, single `WallpaperWindow` | One `WallpaperSession` per `CGDirectDisplayID` |
| Space key | `desktopImageURL` alone (fragile on multi-screen) | `screenID:desktopImageURL` composite key |
| Settings UI | Notion-style static design | macOS 26 Liquid Glass: `GlassEffectContainer`, `.buttonStyle(.glass)`, per-screen sections |

---

## Architecture

```
AppDelegate (main.swift)
├── SpaceMonitor          — publishes [ScreenSpace] for all connected displays
├── ConfigStore           — persists video assignments keyed by screenID:wallpaperURL
└── WallpaperController   — owns one WallpaperSession per screen
    └── WallpaperSession
        ├── WallpaperWindow  — borderless NSWindow at kCGDesktopWindowLevel
        └── VideoPlayerView  — AVQueuePlayer + AVPlayerLooper, fixed crossFade
```

---

## Source Files

### `Sources/LivelyApp/main.swift`

```swift
import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    // Core services
    private let spaceMonitor = SpaceMonitor()
    private let configStore = ConfigStore()
    private lazy var wallpaperController = WallpaperController(
        spaceMonitor: spaceMonitor,
        configStore: configStore
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Warm up the controller (triggers initial wallpaper load)
        _ = wallpaperController

        setupMenuBar()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "play.tv.fill",
                accessibilityDescription: "Lively"
            )
        }

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        menu.addItem(.separator())

        let pauseItem = NSMenuItem(
            title: "Pause Wallpapers",
            action: #selector(togglePause),
            keyEquivalent: "p"
        )
        menu.addItem(pauseItem)
        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Quit Lively",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        statusItem.menu = menu
    }

    @objc private func togglePause() {
        wallpaperController.togglePause()
        if let item = statusItem.menu?.item(withTag: 100) {
            item.title = wallpaperController.isPaused ? "Resume Wallpapers" : "Pause Wallpapers"
        }
    }

    // MARK: - Settings Window

    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(spaceMonitor: spaceMonitor, configStore: configStore)
            let hosting = NSHostingController(rootView: view)

            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.center()
            window.contentViewController = hosting
            window.isReleasedWhenClosed = false
            window.identifier = NSUserInterfaceItemIdentifier("lively.settings")

            self.settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

---

### `Sources/Lively/Logic/SpaceMonitor.swift`

Detects the active wallpaper URL per physical display using `CGDirectDisplayID` as the
stable screen key.

```swift
import AppKit
import Combine

/// A snapshot of one physical screen's current wallpaper/space state.
public struct ScreenSpace: Equatable, Identifiable {
    /// Stable identifier based on CGDirectDisplayID.
    public let id: String
    public let screen: NSScreen
    public let desktopImageURL: URL?
    public let displayName: String

    /// The config-store key: stable even across app restarts.
    public var spaceKey: String {
        guard let url = desktopImageURL else { return id }
        return "\(id):\(url.absoluteString)"
    }

    public static func == (lhs: ScreenSpace, rhs: ScreenSpace) -> Bool {
        lhs.id == rhs.id && lhs.desktopImageURL == rhs.desktopImageURL
    }
}

@MainActor
public class SpaceMonitor: ObservableObject {
    @Published public private(set) var screenSpaces: [ScreenSpace] = []

    private var cancellables = Set<AnyCancellable>()

    public init() {
        refresh()

        // Space changes (swipe between desktops)
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in self?.handleSpaceChange() }
            .store(in: &cancellables)

        // Screen connect / disconnect
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    // MARK: - Private

    private func handleSpaceChange() {
        // macOS needs ~100ms to update desktopImageURL after a space switch
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            refresh()
        }
    }

    public func refresh() {
        screenSpaces = NSScreen.screens.map { screen in
            ScreenSpace(
                id: Self.displayID(for: screen),
                screen: screen,
                desktopImageURL: NSWorkspace.shared.desktopImageURL(for: screen),
                displayName: screen.localizedName
            )
        }
    }

    // MARK: - Helpers

    public static func displayID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let num = screen.deviceDescription[key] as? CGDirectDisplayID {
            return String(num)
        }
        return screen.localizedName
    }
}
```

---

### `Sources/Lively/Logic/ConfigStore.swift`

Non-sandboxed — no security-scoped bookmarks needed. Uses standard bookmarks for
resilience to file moves, but resolved without the `withSecurityScope` flag.

```swift
import Foundation
import AppKit

public struct SpaceConfig: Codable {
    /// Composite key: "displayID:desktopImageURL"
    public let spaceKey: String
    public let videoURL: URL
    /// Bookmark for resilience when files move.
    public let bookmarkData: Data
    public let addedAt: Date
}

@MainActor
public class ConfigStore: ObservableObject {
    @Published public private(set) var configs: [String: SpaceConfig] = [:]

    private let configFileURL: URL

    public init(configFileURL: URL? = nil) {
        let url: URL
        if let provided = configFileURL {
            url = provided
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            let dir = appSupport.appendingPathComponent("Lively")
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
            url = dir.appendingPathComponent("config.json")
        }
        self.configFileURL = url
        load()
    }

    // MARK: - Public API

    public func assign(videoURL: URL, toSpaceKey key: String) {
        do {
            // Non-sandboxed: plain bookmark (no security scope required)
            let bookmark = try videoURL.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let config = SpaceConfig(
                spaceKey: key,
                videoURL: videoURL,
                bookmarkData: bookmark,
                addedAt: Date()
            )
            configs[key] = config
            persist()
            print("ConfigStore: Assigned \(videoURL.lastPathComponent) → \(key)")
        } catch {
            print("ConfigStore: Bookmark creation failed: \(error)")
        }
    }

    /// Resolves the stored URL for a space key.
    /// Returns nil if nothing is assigned or the file no longer exists.
    public func videoURL(for spaceKey: String) -> URL? {
        guard let config = configs[spaceKey] else { return nil }

        // Try bookmark resolution first (survives file moves)
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: config.bookmarkData,
            options: [],               // No security scope — non-sandboxed
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            if isStale {
                // Refresh the bookmark silently
                assign(videoURL: url, toSpaceKey: spaceKey)
            }
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }

        // Fallback: use stored URL directly
        return FileManager.default.fileExists(atPath: config.videoURL.path)
            ? config.videoURL
            : nil
    }

    public func remove(spaceKey: String) {
        configs.removeValue(forKey: spaceKey)
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        do {
            let data = try JSONEncoder().encode(configs)
            try data.write(to: configFileURL, options: .atomic)
        } catch {
            print("ConfigStore: Save failed: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: configFileURL),
              let decoded = try? JSONDecoder().decode([String: SpaceConfig].self, from: data)
        else {
            print("ConfigStore: Starting fresh (no config found)")
            return
        }
        configs = decoded
        print("ConfigStore: Loaded \(configs.count) assignment(s)")
    }
}
```

---

### `Sources/Lively/Core/VideoPlayerView.swift`

Key fixes:
1. `CABasicAnimation` for layer opacity (NSAnimationContext doesn't animate CALayer properties directly).
2. `isFading` guard prevents concurrent crossFades from orphaning `AVPlayerLooper`.
3. KVO on `currentItem.status` delays fade-in until the first frame is decoded.

```swift
import AppKit
import AVFoundation

@MainActor
class VideoPlayerView: NSView {

    private let playerLayer = AVPlayerLayer()
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var readyObservation: NSKeyValueObservation?
    private var isFading = false

    // MARK: - Setup

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        wantsLayer = true
        layer = CALayer()
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(playerLayer)
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    // MARK: - Playback

    func load(url: URL) {
        stopCurrentPlayer()

        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.volume = 0
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false // Don't block display sleep

        playerLooper = AVPlayerLooper(player: player, templateItem: item)
        playerLayer.player = player
        queuePlayer = player
        player.play()
    }

    func stop() {
        stopCurrentPlayer()
    }

    /// Crossfades to a new video. Safe to call repeatedly.
    func crossFade(to url: URL, duration: TimeInterval = 0.4) {
        guard !isFading else {
            // Queue is busy — skip the animation, just swap
            load(url: url)
            setLayerOpacity(1, animated: false)
            return
        }

        isFading = true

        // Fade out current layer
        setLayerOpacity(0, animated: true, duration: duration) { [weak self] in
            guard let self else { return }

            self.load(url: url)

            // Wait for the player to have a decodable frame before fading in
            self.waitForReadyThenFadeIn(duration: duration)
        }
    }

    // MARK: - Private Helpers

    private func stopCurrentPlayer() {
        readyObservation?.invalidate()
        readyObservation = nil
        playerLooper?.disableLooping()
        playerLooper = nil
        queuePlayer?.pause()
        playerLayer.player = nil
        queuePlayer = nil
    }

    private func waitForReadyThenFadeIn(duration: TimeInterval) {
        guard let player = queuePlayer,
              let item = player.currentItem else {
            finishFadeIn(duration: duration)
            return
        }

        if item.status == .readyToPlay {
            finishFadeIn(duration: duration)
            return
        }

        readyObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            if item.status == .readyToPlay {
                Task { @MainActor in
                    self.readyObservation?.invalidate()
                    self.readyObservation = nil
                    self.finishFadeIn(duration: duration)
                }
            }
        }

        // Timeout fallback — fade in after 1s regardless
        Task {
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                guard self.isFading else { return }
                self.readyObservation?.invalidate()
                self.readyObservation = nil
                self.finishFadeIn(duration: duration)
            }
        }
    }

    private func finishFadeIn(duration: TimeInterval) {
        setLayerOpacity(1, animated: true, duration: duration) { [weak self] in
            self?.isFading = false
        }
    }

    /// CABasicAnimation is the correct way to animate CALayer properties —
    /// NSAnimationContext only works with NSView/NSCell animator() proxies.
    private func setLayerOpacity(
        _ opacity: Float,
        animated: Bool,
        duration: TimeInterval = 0.4,
        completion: (() -> Void)? = nil
    ) {
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        if animated {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = playerLayer.presentation()?.opacity ?? playerLayer.opacity
            anim.toValue = opacity
            anim.duration = duration
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            CATransaction.setAnimationDuration(duration)
            playerLayer.add(anim, forKey: "opacityFade")
        } else {
            CATransaction.setDisableActions(true)
        }
        playerLayer.opacity = opacity
        CATransaction.commit()
    }
}
```

---

### `Sources/Lively/Core/WallpaperWindow.swift`

Key fixes:
1. `orderFront(nil)` — never `makeKeyAndOrderFront` on a wallpaper window.
2. `levelReassert()` — called after space change to fight any OS-level reordering.
3. `participatesInCycle: false` prevents Command-Tab from seeing it.

```swift
import AppKit

/// A borderless window sitting at the macOS desktop icon level.
/// One instance is created per physical display.
class WallpaperWindow: NSWindow {

    init(screen: NSScreen) {
        // kCGDesktopWindowLevel sits below the Finder desktop icons layer.
        // Using the raw key constant is more stable than hardcoding the integer.
        let desktopLevel = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.desktopWindow))
        )

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = desktopLevel
        self.collectionBehavior = [
            .canJoinAllSpaces,   // Present on every Space
            .stationary,         // Doesn't move with Exposé/Mission Control
            .ignoresCycle,       // Excluded from Command-Tab
            .fullScreenNone      // Can't accidentally enter full-screen
        ]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = true
        self.hasShadow = false
        self.isReleasedWhenClosed = false
        self.canHide = false

        // Cover the full screen frame (including any notch area)
        setFrame(screen.frame, display: false)
    }

    /// Re-asserts the window level and ordering.
    /// macOS can silently re-order windows after space transitions —
    /// calling this after `activeSpaceDidChangeNotification` keeps the video visible.
    func levelReassert() {
        let desktopLevel = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.desktopWindow))
        )
        self.level = desktopLevel
        orderFront(nil)
    }

    override func orderFront(_ sender: Any?) {
        // Explicitly never steal key-window status
        super.orderFront(sender)
    }
}
```

---

### `Sources/Lively/Core/WallpaperController.swift`

Manages one `WallpaperSession` per physical display.
Responds to space changes, screen connect/disconnect, and config changes.

```swift
import AppKit
import Combine

// MARK: - Session

/// Encapsulates the window + player for a single physical display.
@MainActor
private class WallpaperSession {
    let window: WallpaperWindow
    let playerView: VideoPlayerView
    var currentURL: URL?

    init(screen: NSScreen) {
        window = WallpaperWindow(screen: screen)
        playerView = VideoPlayerView(frame: window.contentView!.bounds)
        window.contentView = playerView
    }

    func play(url: URL) {
        if url == currentURL {
            // Already playing this video — re-assert visibility only
            window.levelReassert()
            return
        }
        currentURL = url
        window.levelReassert()
        playerView.crossFade(to: url)
    }

    func hide() {
        currentURL = nil
        playerView.stop()
        window.orderOut(nil)
    }

    func pause() { playerView.stop() }
    func resume() {
        if let url = currentURL { playerView.crossFade(to: url, duration: 0) }
    }
}

// MARK: - Controller

@MainActor
public class WallpaperController {
    public private(set) var isPaused = false

    private var sessions: [String: WallpaperSession] = [:]   // displayID → session
    private let spaceMonitor: SpaceMonitor
    private let configStore: ConfigStore
    private var cancellables = Set<AnyCancellable>()

    public init(spaceMonitor: SpaceMonitor, configStore: ConfigStore) {
        self.spaceMonitor = spaceMonitor
        self.configStore = configStore
        bind()
    }

    // MARK: - Controls

    public func togglePause() {
        isPaused.toggle()
        sessions.values.forEach { isPaused ? $0.pause() : $0.resume() }
    }

    // MARK: - Private

    private func bind() {
        // React to space changes or new screen connections
        spaceMonitor.$screenSpaces
            .sink { [weak self] spaces in
                self?.synchronize(to: spaces)
            }
            .store(in: &cancellables)

        // React to the user assigning/removing a video in settings
        configStore.$configs
            .sink { [weak self] _ in
                self?.spaceMonitor.refresh()
            }
            .store(in: &cancellables)
    }

    private func synchronize(to spaces: [ScreenSpace]) {
        guard !isPaused else { return }

        let liveIDs = Set(spaces.map(\.id))

        // Remove sessions for disconnected screens
        for id in sessions.keys where !liveIDs.contains(id) {
            sessions[id]?.hide()
            sessions.removeValue(forKey: id)
        }

        // Update / create sessions for each active screen
        for space in spaces {
            let session = sessions[space.id] ?? makeSession(for: space.screen, id: space.id)

            if let url = configStore.videoURL(for: space.spaceKey) {
                session.play(url: url)
            } else {
                session.hide()
            }
        }
    }

    private func makeSession(for screen: NSScreen, id: String) -> WallpaperSession {
        let s = WallpaperSession(screen: screen)
        sessions[id] = s
        return s
    }
}
```

---

### `Sources/Lively/UI/SettingsView.swift`

Full macOS 26 Liquid Glass design.
Per-screen sections with drag-and-drop, browse picker, and live status chips.

```swift
import SwiftUI
import AppKit
import ServiceManagement

public struct SettingsView: View {
    @ObservedObject public var spaceMonitor: SpaceMonitor
    @ObservedObject public var configStore: ConfigStore

    public init(spaceMonitor: SpaceMonitor, configStore: ConfigStore) {
        self.spaceMonitor = spaceMonitor
        self.configStore = configStore
    }

    public var body: some View {
        ZStack {
            // Glass window background — adapts to the video wallpaper behind it
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    screensSection
                    footerSection
                }
                .padding(24)
            }
        }
        .frame(width: 480, height: 560)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.tv.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.tint(.blue), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text("Lively")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Video wallpapers for every Space")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Screens

    private var screensSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("DISPLAYS", systemImage: "display.2")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if spaceMonitor.screenSpaces.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Detecting displays…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 10) {
                    ForEach(spaceMonitor.screenSpaces) { space in
                        ScreenCard(space: space, configStore: configStore)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 12) {
            GlassEffectContainer {
                Toggle(isOn: launchAtLoginBinding) {
                    Label("Launch at Login", systemImage: "power")
                        .font(.system(size: 13))
                }
                .toggleStyle(.switch)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
            }

            Spacer()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.glass)
            .tint(.red)
        }
    }

    // MARK: - Helpers

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enabled in
                try? enabled
                    ? SMAppService.mainApp.register()
                    : SMAppService.mainApp.unregister()
            }
        )
    }
}

// MARK: - Screen Card

private struct ScreenCard: View {
    let space: ScreenSpace
    @ObservedObject var configStore: ConfigStore
    @State private var isDropTargeted = false

    private var assignedVideoURL: URL? {
        configStore.videoURL(for: space.spaceKey)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Display header row
            HStack(spacing: 10) {
                Image(systemName: "display")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(space.displayName)
                        .font(.system(size: 14, weight: .semibold))
                    if let url = space.desktopImageURL {
                        Text(url.lastPathComponent)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                // Status chip
                statusChip
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().opacity(0.3)

            // Drop zone
            dropZone
                .padding(12)
        }
        .glassEffect(
            isDropTargeted ? .regular.tint(.blue) : .regular,
            in: RoundedRectangle(cornerRadius: 14)
        )
        .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: Status Chip

    @ViewBuilder
    private var statusChip: some View {
        if let url = assignedVideoURL {
            HStack(spacing: 5) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text(url.lastPathComponent)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 120)

                Button {
                    configStore.remove(spaceKey: space.spaceKey)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.glass)
                .frame(width: 18, height: 18)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular.tint(.green), in: Capsule())
        } else {
            Text("No Video")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(.clear, in: Capsule())
        }
    }

    // MARK: Drop Zone

    private var dropZone: some View {
        HStack(spacing: 10) {
            GlassEffectContainer {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 12))
                    Text(isDropTargeted ? "Drop to assign" : "Drop video here")
                        .font(.system(size: 12))
                }
                .foregroundStyle(isDropTargeted ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .glassEffect(
                    isDropTargeted ? .regular.tint(.blue) : .clear,
                    in: RoundedRectangle(cornerRadius: 10)
                )
            }

            Button {
                openFilePicker()
            } label: {
                Label("Browse", systemImage: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .frame(height: 38)
                    .padding(.horizontal, 14)
            }
            .buttonStyle(.glass)
        }
    }

    // MARK: Interactions

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            configStore.assign(videoURL: url, toSpaceKey: space.spaceKey)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url") { urlData, _ in
            guard let data = urlData as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil)
            else { return }
            Task { @MainActor in
                configStore.assign(videoURL: url, toSpaceKey: space.spaceKey)
            }
        }
        return true
    }
}
```

---

## Key Gotchas & Notes

### Why video didn't appear before

The original `makeKeyAndOrderFront(nil)` tells the window server to bring the window
to the front of its level AND make it the first responder. For a window at
`kCGDesktopWindowLevel`, macOS interprets this as "something wants focus at desktop level"
and Finder immediately reasserts the actual desktop layer on top. The fix is `orderFront(nil)`
(just z-orders at the current level) combined with `levelReassert()` after space changes.

### Why `.canJoinAllSpaces` + `orderOut` is correct

Setting `.canJoinAllSpaces` makes the window persistent across all Spaces. We control
**visibility** via `orderOut` / `orderFront`. When no video is assigned to the current
Space, `orderOut` hides the window everywhere; when a video is assigned, `orderFront`
brings it back. This is cleaner than creating/destroying windows per Space.

### Space identity limitation

`desktopImageURL` is the only stable, public macOS API for identifying which Space is
active. If two Spaces share the same wallpaper image, Lively can't distinguish them.
The composite key `displayID:desktopImageURL` at least prevents cross-screen confusion.
If you want true Space-UUID tracking, it requires private frameworks (`CGSPrivate`).

### macOS 26 Transparent Menu Bar

Because Tahoe's menu bar is now fully transparent, your video wallpaper bleeds through
the menu bar region. This is a feature, not a bug — it makes the effect dramatically
more immersive on Tahoe vs earlier macOS versions.

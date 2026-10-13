import AppKit
import AVFoundation
import Combine
import IOKit.ps

// MARK: - WallpaperSession

/// Encapsulates the WallpaperWindow + video player for one physical display.
/// Follows LiveDesk's proven pattern: plain NSView + AVPlayerLayer, no subclass.
///
/// Playback runs only while the controller wants it (`wantsPlayback`) *and*
/// the window is actually visible (not fully covered by full-screen or
/// maximised windows), so a hidden wallpaper stops decoding.
@MainActor
private final class WallpaperSession {
    let window: WallpaperWindow
    private let contentView: NSView
    private let playerLayer: AVPlayerLayer
    private var player: AVPlayer?
    private var itemObservers: [NSObjectProtocol] = []
    private var statusObservation: AnyCancellable?
    private var occlusionObservation: AnyCancellable?
    private(set) var currentURL: URL?
    /// URL that last failed to load; not retried until `retryFailedPlayback()`
    /// so a broken or unreachable file doesn't flash a black window on every sync.
    private var failedURL: URL?
    private var isReady = false
    private var wantsPlayback = false
    private var isOccluded = false

    init(screen: NSScreen) {
        window = WallpaperWindow(screen: screen)
        
        // Create a plain NSView as the content view (no subclass)
        let localFrame = NSRect(origin: .zero, size: screen.frame.size)
        contentView = NSView(frame: localFrame)
        contentView.wantsLayer = true
        
        // Create AVPlayerLayer and add directly to the content view's layer
        playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = contentView.bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        contentView.layer!.addSublayer(playerLayer)
        
        window.contentView = contentView

        occlusionObservation = NotificationCenter.default
            .publisher(for: NSWindow.didChangeOcclusionStateNotification, object: window)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.occlusionDidChange() }
    }

    /// Shows the window and plays (or crossfades to) the given video.
    func play(url: URL, wallpaper: DynamicWallpaper, screen: NSScreen, onError: @escaping @Sendable (Error) -> Void) {
        wantsPlayback = true

        // Ensure the window matches the current screen frame (resolution /
        // arrangement changes arrive as a re-sync with the new NSScreen).
        let localFrame = NSRect(origin: .zero, size: screen.frame.size)
        if window.frame != screen.frame {
            window.setFrame(screen.frame, display: true)
        }
        contentView.frame = localFrame
        playerLayer.frame = localFrame
        
        // Apply display settings
        let gravity: AVLayerVideoGravity = wallpaper.videoGravity == .fit ? .resizeAspect : .resizeAspectFill
        playerLayer.videoGravity = gravity
        
        if url == currentURL {
            player?.isMuted = wallpaper.isMuted
            player?.volume = wallpaper.volume
            if isReady { window.show() }
            updatePlaybackRate()
            return
        }

        if url == failedURL {
            // Known-bad file: stay hidden (system wallpaper shows) until retried.
            return
        }

        currentURL = url
        failedURL = nil
        PerfSignposts.interval(PerfSignposts.playerBuild) {
            loadVideo(url: url, muted: wallpaper.isMuted, volume: wallpaper.volume, onError: onError)
        }
    }

    private func loadVideo(url: URL, muted: Bool, volume: Float, onError: @escaping @Sendable (Error) -> Void) {
        tearDownPlayer()

        let prefs = AppPreferences.shared
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = muted
        newPlayer.volume = volume
        newPlayer.preventsDisplaySleepDuringVideoPlayback = false
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        newPlayer.actionAtItemEnd = .pause

        applyPreferences(to: newPlayer, prefs: prefs)

        // Loop or freeze at end based on preference (captured for the observer).
        let loopMode = prefs.loopBehavior
        itemObservers.append(NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak newPlayer] _ in
            MainActor.assumeIsolated {
                switch loopMode {
                case .loop:
                    newPlayer?.seek(to: .zero)
                    self?.updatePlaybackRate()
                case .playOnceFreeze:
                    newPlayer?.pause()
                }
            }
        })

        // Mid-playback I/O failure (e.g. the drive holding the file was ejected).
        itemObservers.append(NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                ?? CocoaError(.fileReadUnknown)
            MainActor.assumeIsolated {
                self?.handleFailure(error, onError: onError)
            }
        })

        // KVO callbacks can fire on arbitrary queues. By using Combine, we ensure
        // the closure executes on the main thread and avoids @MainActor isolation crashes.
        statusObservation = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] status in
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    self.isReady = true
                    // Only reveal the window once there is a frame to show, so a
                    // bad file never covers the desktop with a black window.
                    if self.wantsPlayback { self.window.show() }
                    self.updatePlaybackRate()
                case .failed:
                    self.handleFailure(item?.error ?? CocoaError(.fileReadCorruptFile), onError: onError)
                default:
                    break
                }
            }

        // Connect player to layer; playback starts when the item is ready.
        playerLayer.player = newPlayer
        self.player = newPlayer
        updatePlaybackRate()
    }

    private func handleFailure(_ error: Error, onError: @escaping @Sendable (Error) -> Void) {
        guard let url = currentURL else { return }
        LivelyLogger.wallpaper.error("Playback failed for \(url.lastPathComponent): \(error.localizedDescription)")
        failedURL = url
        currentURL = nil
        tearDownPlayer()
        window.orderOut(nil)
        onError(error)
    }

    private func applyPreferences(to player: AVPlayer, prefs: AppPreferences) {
        player.currentItem?.preferredPeakBitRate = max(0, prefs.playbackQuality.preferredPeakBitRate)

        // When hardware decoding is off, cap resolution as a software-friendly budget.
        if !prefs.hardwareDecoding {
            player.currentItem?.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
        } else {
            let maxH = prefs.maxResolution.preferredMaxHeight
            if maxH > 0 {
                player.currentItem?.preferredMaximumResolution = CGSize(width: maxH * 16 / 9, height: maxH)
            } else {
                player.currentItem?.preferredMaximumResolution = .zero
            }
        }
    }

    func applyPlaybackPreferences(_ prefs: AppPreferences = .shared) {
        guard let player else { return }
        applyPreferences(to: player, prefs: prefs)
    }

    /// Forces the next `play` call to rebuild the player (e.g. loop mode change).
    func invalidatePlayback() {
        currentURL = nil
    }

    /// Allows a previously failed file to be tried again (drive re-mounted, wake).
    func retryFailedPlayback() {
        failedURL = nil
    }

    /// Hides the window and stops playback.
    func hide() {
        wantsPlayback = false
        currentURL = nil
        tearDownPlayer()
        window.orderOut(nil)
    }

    /// Final teardown when the display goes away or the app quits.
    func destroy() {
        hide()
        occlusionObservation?.cancel()
        occlusionObservation = nil
        window.close()
    }

    func pause() {
        PerfSignposts.interval(PerfSignposts.pause) {
            wantsPlayback = false
            updatePlaybackRate()
        }
    }

    func resume() {
        PerfSignposts.interval(PerfSignposts.resume) {
            wantsPlayback = true
            updatePlaybackRate()
        }
    }

    private func occlusionDidChange() {
        // Only trust occlusion while ordered in; orderOut also reports "hidden".
        guard window.isVisible else { return }
        let occluded = !window.occlusionState.contains(.visible)
        guard occluded != isOccluded else { return }
        isOccluded = occluded
        updatePlaybackRate()
    }

    /// Single place that decides whether the decoder runs.
    private func updatePlaybackRate() {
        guard let player else { return }
        if WallpaperPlaybackPolicy.shouldDecode(wantsPlayback: wantsPlayback, isOccluded: isOccluded) {
            player.play()
        } else {
            player.pause()
        }
    }
    
    private func tearDownPlayer() {
        for observer in itemObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        itemObservers.removeAll()
        statusObservation?.cancel()
        statusObservation = nil
        isReady = false
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playerLayer.player = nil
        player = nil
    }
}

// MARK: - BookmarkManager

@MainActor
private final class BookmarkManager {
    private let configStore: ConfigStore
    private var activeScopes: [String: URL] = [:]

    init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    func urlForSpace(_ space: ScreenSpace, appearance: NSAppearance?) -> URL? {
        // Release scopes for other Spaces on the same display before starting a new one.
        let displayPrefix = "\(space.id):"
        for key in Array(activeScopes.keys) where key.hasPrefix(displayPrefix) && key != space.spaceKey {
            stopScope(for: key)
        }

        guard let url = configStore.resolvedURL(for: space.spaceKey, appearance: appearance) else {
            stopScope(for: space.spaceKey)
            return nil
        }
        startScope(for: space.spaceKey, url: url)
        return url
    }

    func stopScope(for spaceKey: String) {
        if let oldURL = activeScopes.removeValue(forKey: spaceKey) {
            oldURL.stopAccessingSecurityScopedResource()
            LivelyLogger.wallpaper.info("Security scope stopped for \(oldURL.lastPathComponent)")
        }
    }

    func stopScopes(withDisplayID displayID: String) {
        let prefix = "\(displayID):"
        for key in Array(activeScopes.keys) where key.hasPrefix(prefix) {
            stopScope(for: key)
        }
    }

    func stopAllScopes() {
        for key in Array(activeScopes.keys) {
            stopScope(for: key)
        }
    }

    private func startScope(for spaceKey: String, url: URL) {
        if let existing = activeScopes[spaceKey], existing == url {
            // Already scoped for this exact URL
            return
        }
        stopScope(for: spaceKey)
        let didStart = url.startAccessingSecurityScopedResource()
        if didStart {
            activeScopes[spaceKey] = url
            LivelyLogger.wallpaper.info("Security scope started for \(url.lastPathComponent)")
        }
    }
}

// MARK: - WallpaperSessionManager

@MainActor
private final class WallpaperSessionManager {
    private var sessions: [String: WallpaperSession] = [:]

    var allSessions: [String: WallpaperSession] {
        sessions
    }

    func tearDownAll(bookmarkManager: BookmarkManager) {
        for (_, session) in sessions {
            session.destroy()
        }
        sessions.removeAll()
        bookmarkManager.stopAllScopes()
    }

    func retryFailedPlayback() {
        sessions.values.forEach { $0.retryFailedPlayback() }
    }

    func synchronize(
        to spaces: [ScreenSpace],
        appearance: NSAppearance,
        configStore: ConfigStore,
        bookmarkManager: BookmarkManager,
        isPaused: Bool,
        onPlaybackError: @escaping @Sendable (String, String) -> Void
    ) {
        let liveDisplayIDs = Set(spaces.map(\.id))

        // Always clean up sessions for displays that are no longer connected,
        // even when paused — a disconnected monitor should never keep a hidden window alive.
        for id in Array(sessions.keys) where !liveDisplayIDs.contains(id) {
            sessions.removeValue(forKey: id)?.destroy()
            bookmarkManager.stopScopes(withDisplayID: id)
            LivelyLogger.wallpaper.info("Display \(id) disconnected; wallpaper window released")
        }

        // While paused, skip playback updates; togglePause() will re-sync on resume.
        guard !isPaused else { return }

        for space in spaces {
            let session: WallpaperSession
            if let existing = sessions[space.id] {
                session = existing
            } else {
                session = WallpaperSession(screen: space.screen)
                sessions[space.id] = session
            }

            let spaceKey = space.spaceKey  // capture before Sendable closure
            let wallpaperConfig = configStore.configs[spaceKey]?.dynamicWallpaper ?? DynamicWallpaper()

            if let videoURL = bookmarkManager.urlForSpace(space, appearance: appearance) {
                session.play(
                    url: videoURL,
                    wallpaper: wallpaperConfig,
                    screen: space.screen,
                    onError: { error in
                        onPlaybackError(spaceKey, error.localizedDescription)
                    }
                )
            } else {
                bookmarkManager.stopScope(for: spaceKey)
                session.hide()
            }
        }
    }
}

// MARK: - WallpaperController

@MainActor
public final class WallpaperController: ObservableObject {

    // MARK: - Public State

    @Published public private(set) var isPaused = false
    @Published public private(set) var isThrottled = false
    /// True when wallpapers are paused due to battery policy (threshold or hard 25% floor).
    @Published public private(set) var isBatteryPaused = false
    /// Current battery charge 0–100 when available; nil on desktops without a battery.
    @Published public private(set) var batteryLevelPercent: Double?
    /// True when the Mac is drawing from battery.
    @Published public private(set) var isOnBattery = false
    /// True when pause was forced by the hard 25% floor (vs user threshold).
    @Published public private(set) var isForcedBatteryPause = false
    /// True while the system makes wallpapers invisible anyway (display or
    /// system sleep, screen lock, screen saver, fast user switch). Playback
    /// stops so the decoder doesn't run for nobody.
    @Published public private(set) var isSystemSuspended = false
    
    /// Bubbles up playback errors (spaceKey, Error message) to the UI
    public let playbackErrors = PassthroughSubject<(String, String), Never>()

    // MARK: - Private

    private let spaceMonitor: SpaceMonitor
    private let configStore: ConfigStore
    private let preferences: AppPreferences
    private let bookmarkManager: BookmarkManager
    private let sessionManager: WallpaperSessionManager
    private var cancellables = Set<AnyCancellable>()
    
    private var appearanceObserver: AnyCancellable?
    private var thermalStateObserver: AnyCancellable?
    private var powerSourceTimer: Timer?
    private var systemSuspension = SystemSuspension()

    // MARK: - Init

    public init(
        spaceMonitor: SpaceMonitor,
        configStore: ConfigStore,
        preferences: AppPreferences = .shared
    ) {
        self.spaceMonitor = spaceMonitor
        self.configStore = configStore
        self.preferences = preferences
        self.bookmarkManager = BookmarkManager(configStore: configStore)
        self.sessionManager = WallpaperSessionManager()
        
        let state = ProcessInfo.processInfo.thermalState
        self.isThrottled = state == .serious || state == .critical
        let snap = PowerSourceMonitor.snapshot()
        self.isOnBattery = snap.isOnBattery
        self.batteryLevelPercent = snap.levelPercent
        let decision = Self.batteryPauseDecision(
            isOnBattery: snap.isOnBattery,
            level: snap.levelPercent,
            pauseEnabled: preferences.pauseOnBattery,
            threshold: preferences.batteryPauseThreshold
        )
        self.isBatteryPaused = decision.shouldPause
        self.isForcedBatteryPause = decision.isForcedFloor
        
        bind()
        setupAppearanceObserver()
        setupThermalStateObserver()
        setupBatteryMonitor()
        setupSystemStateObservers()
        observePreferences()
    }

    // MARK: - Public Controls

    /// Tears down all sessions and releases security-scoped resources.
    /// Call from `applicationWillTerminate` before flushing config.
    public func tearDown() {
        sessionManager.tearDownAll(bookmarkManager: bookmarkManager)
        appearanceObserver?.cancel()
        appearanceObserver = nil
        thermalStateObserver?.cancel()
        thermalStateObserver = nil
        powerSourceTimer?.invalidate()
        powerSourceTimer = nil
        cancellables.removeAll()
    }

    public func togglePause() {
        isPaused.toggle()
        applyPlaybackState()
    }

    private var shouldHaltPlayback: Bool {
        isPaused || isThrottled || isBatteryPaused || isSystemSuspended
    }

    private func applyPlaybackState() {
        if shouldHaltPlayback {
            sessionManager.allSessions.values.forEach { $0.pause() }
        } else {
            // Re-sync rather than just resuming, so any config or space changes
            // that arrived while paused are picked up immediately.
            PerfSignposts.interval(PerfSignposts.resume) {
                synchronize(to: spaceMonitor.screenSpaces)
            }
        }
    }

    private func observePreferences() {
        preferences.$pauseOnBattery
            .combineLatest(preferences.$batteryPauseThreshold)
            .dropFirst()
            .sink { [weak self] _, _ in
                self?.refreshBatteryState()
            }
            .store(in: &cancellables)

        // Loop mode is captured when the player is created — full reload required.
        preferences.$loopBehavior
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.sessionManager.allSessions.values.forEach { $0.invalidatePlayback() }
                if !self.shouldHaltPlayback {
                    self.synchronize(to: self.spaceMonitor.screenSpaces)
                }
            }
            .store(in: &cancellables)

        // Quality / decode budget can soft-apply without tearing down AVPlayers.
        preferences.$playbackQuality
            .combineLatest(preferences.$hardwareDecoding, preferences.$maxResolution)
            .dropFirst()
            .sink { [weak self] _, _, _ in
                guard let self else { return }
                self.sessionManager.allSessions.values.forEach {
                    $0.applyPlaybackPreferences(self.preferences)
                }
            }
            .store(in: &cancellables)
    }

    private func setupBatteryMonitor() {
        // IOKit has no simple Combine publisher; 20s is enough for battery pause.
        powerSourceTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshBatteryState()
            }
        }
        // Let the OS coalesce wake-ups; exact timing doesn't matter here.
        powerSourceTimer?.tolerance = 5
        // Also refresh when Low Power Mode changes (related power policy signal).
        NotificationCenter.default.publisher(for: Notification.Name("NSProcessInfoPowerStateDidChange"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_: Notification) in
                self?.refreshBatteryState()
            }
            .store(in: &cancellables)
    }

    private func refreshBatteryState() {
        let snap = PowerSourceMonitor.snapshot()
        let decision = Self.batteryPauseDecision(
            isOnBattery: snap.isOnBattery,
            level: snap.levelPercent,
            pauseEnabled: preferences.pauseOnBattery,
            threshold: preferences.batteryPauseThreshold
        )

        let levelChanged = batteryLevelPercent != snap.levelPercent
        let onBatteryChanged = isOnBattery != snap.isOnBattery
        let pauseChanged = isBatteryPaused != decision.shouldPause
            || isForcedBatteryPause != decision.isForcedFloor

        isOnBattery = snap.isOnBattery
        batteryLevelPercent = snap.levelPercent
        isForcedBatteryPause = decision.isForcedFloor

        guard pauseChanged || levelChanged || onBatteryChanged else { return }

        if pauseChanged {
            isBatteryPaused = decision.shouldPause
            applyPlaybackState()
            if decision.shouldPause {
                let pct = snap.levelPercent.map { String(format: "%.0f%%" , $0) } ?? "unknown"
                if decision.isForcedFloor {
                    LivelyLogger.wallpaper.info("Paused wallpapers — battery at \(pct) (hard floor 25%)")
                } else {
                    LivelyLogger.wallpaper.info("Paused wallpapers — battery at \(pct) (threshold \(Int(preferences.batteryPauseThreshold))%)")
                }
            } else {
                LivelyLogger.wallpaper.info("Resumed wallpapers — AC power or battery above threshold")
            }
        }
    }

    /// Battery pause policy:
    /// - On AC: never pause for battery.
    /// - On battery at/below 25%: always pause (forced floor).
    /// - On battery with "Pause on Battery" on: pause when level ≤ user threshold.
    nonisolated static func batteryPauseDecision(
        isOnBattery: Bool,
        level: Double?,
        pauseEnabled: Bool,
        threshold: Double
    ) -> (shouldPause: Bool, isForcedFloor: Bool) {
        guard isOnBattery else { return (false, false) }
        let floor = AppPreferences.forcedBatteryPausePercent
        let clampedThreshold = AppPreferences.clampThreshold(threshold)

        if let level {
            if level <= floor {
                return (true, true)
            }
            if pauseEnabled && level <= clampedThreshold {
                return (true, false)
            }
            return (false, false)
        }

        // Unknown level: if user enabled pause-on-battery, treat as pause while on battery.
        if pauseEnabled {
            return (true, false)
        }
        return (false, false)
    }

    // MARK: - System state (sleep, lock, screen saver, user switch)

    private func setupSystemStateObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        let observe: (NotificationCenter, Notification.Name, @escaping @MainActor () -> Void) -> Void = { [weak self] center, name, action in
            guard let self else { return }
            center.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { _ in action() }
                .store(in: &self.cancellables)
        }

        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.setSystemSuspension(.displaysAsleep, active: true)
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.setSystemSuspension(.displaysAsleep, active: false)
            self?.reconcileLockState()
        }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in
            self?.setSystemSuspension(.systemAsleep, active: true)
        }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in
            self?.systemDidWake()
        }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
            self?.setSystemSuspension(.sessionInactive, active: true)
        }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.setSystemSuspension(.sessionInactive, active: false)
            self?.reconcileLockState()
        }
        // A re-inserted drive may bring back a file that failed to load.
        observe(workspace, NSWorkspace.didMountNotification) { [weak self] in
            self?.retryFailedPlayback()
        }

        // Lock / screen saver are only published as distributed notifications.
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            self?.setSystemSuspension(.screenLocked, active: true)
        }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            // A screen saver can't still be running once the user unlocked;
            // clearing it guards against a missed "didstop".
            self?.setSystemSuspension([.screenLocked: false, .screenSaver: false])
        }
        observe(distributed, Notification.Name("com.apple.screensaver.didstart")) { [weak self] in
            self?.setSystemSuspension(.screenSaver, active: true)
        }
        observe(distributed, Notification.Name("com.apple.screensaver.didstop")) { [weak self] in
            self?.setSystemSuspension(.screenSaver, active: false)
        }
    }

    func setSystemSuspension(_ reason: SystemSuspensionReason, active: Bool) {
        setSystemSuspension([reason: active])
    }

    /// Applies several reason changes with a single playback update.
    func setSystemSuspension(_ changes: [SystemSuspensionReason: Bool]) {
        var flipped = false
        for (reason, active) in changes {
            flipped = systemSuspension.set(reason, active: active) || flipped
        }
        guard flipped else { return }
        let trigger = changes.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: ",")
        applySystemSuspension(trigger: trigger)
    }

    /// Distributed lock/unlock notifications can be missed around sleep and
    /// user switching; ask the window server so a lost "unlocked" can't leave
    /// wallpapers paused forever.
    private func reconcileLockState() {
        if Self.isScreenLockedNow() {
            setSystemSuspension(.screenLocked, active: true)
        } else {
            setSystemSuspension([.screenLocked: false, .screenSaver: false])
        }
    }

    nonisolated static func isScreenLockedNow() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (info["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    func systemDidWake() {
        // AVPlayer can come back stalled after sleep; clear failures so files
        // on drives that re-mounted during wake get another try.
        sessionManager.retryFailedPlayback()
        if !Self.isScreenLockedNow() {
            systemSuspension.set(.screenLocked, active: false)
        }
        if systemSuspension.systemDidWake() || isSystemSuspended != systemSuspension.isSuspended {
            applySystemSuspension(trigger: "didWake")
        } else if !shouldHaltPlayback {
            synchronize(to: spaceMonitor.screenSpaces)
        }
    }

    private func applySystemSuspension(trigger: String) {
        isSystemSuspended = systemSuspension.isSuspended
        LivelyLogger.wallpaper.info("System suspension \(self.isSystemSuspended ? "on" : "off") (\(trigger))")
        applyPlaybackState()
    }

    private func retryFailedPlayback() {
        sessionManager.retryFailedPlayback()
        if !shouldHaltPlayback {
            synchronize(to: spaceMonitor.screenSpaces)
        }
    }

    // MARK: - Reactive Bindings

    private func bind() {
        // NOTE: never prune configs here. `screenSpaces` only describes the
        // *currently visible* Space on each *currently connected* display, so
        // assignments for other Spaces and unplugged monitors must survive.
        spaceMonitor.$screenSpaces
            .sink { [weak self] spaces in
                self?.synchronize(to: spaces)
            }
            .store(in: &cancellables)

        configStore.$configs
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    // An edited assignment (e.g. re-choosing the same file
                    // after fixing it) deserves a fresh attempt.
                    self?.sessionManager.retryFailedPlayback()
                    self?.spaceMonitor.refresh()
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupAppearanceObserver() {
        // NSApp is nil in unit test contexts — skip observation
        guard let app = NSApp else { return }
        appearanceObserver = app.publisher(for: \.effectiveAppearance)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.spaceMonitor.refresh()
            }
    }

    private func setupThermalStateObserver() {
        thermalStateObserver = NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                let state = ProcessInfo.processInfo.thermalState
                let shouldThrottle = state == .serious || state == .critical
                if self.isThrottled != shouldThrottle {
                    self.isThrottled = shouldThrottle
                    self.applyPlaybackState()
                }
            }
    }
    
    // MARK: - Security-Scoped Access (Balanced)
    // MARK: - Synchronization

    private func synchronize(to spaces: [ScreenSpace]) {
        // NSApp is nil in unit test contexts — can't create windows without a running application
        guard let app = NSApp else { return }
        PerfSignposts.interval(PerfSignposts.synchronize) {
            let appearance = app.effectiveAppearance
            sessionManager.synchronize(
                to: spaces,
                appearance: appearance,
                configStore: configStore,
                bookmarkManager: bookmarkManager,
                isPaused: shouldHaltPlayback,
                onPlaybackError: { [weak self] spaceKey, message in
                    Task { @MainActor in
                        self?.playbackErrors.send((spaceKey, message))
                    }
                }
            )
        }
    }
}

// MARK: - Power Source

enum PowerSourceMonitor {
    struct Snapshot {
        var isOnBattery: Bool
        /// 0–100 when known.
        var levelPercent: Double?
    }

    static func snapshot() -> Snapshot {
        guard
            let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return Snapshot(
                isOnBattery: ProcessInfo.processInfo.isLowPowerModeEnabled,
                levelPercent: nil
            )
        }

        var onBattery = false
        var level: Double?

        for source in list {
            guard
                let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
            else { continue }

            if let state = desc[kIOPSPowerSourceStateKey] as? String,
               state == kIOPSBatteryPowerValue {
                onBattery = true
            }
            // Current capacity is typically 0–100 for internal batteries.
            if let capacity = desc[kIOPSCurrentCapacityKey] as? Int {
                level = Double(capacity)
            } else if let capacity = desc[kIOPSCurrentCapacityKey] as? Double {
                level = capacity
            }
        }

        if !onBattery && list.isEmpty {
            onBattery = ProcessInfo.processInfo.isLowPowerModeEnabled
        }

        return Snapshot(isOnBattery: onBattery, levelPercent: level)
    }
}

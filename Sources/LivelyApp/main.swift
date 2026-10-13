import AppKit
import SwiftUI
import LivelyCore

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?

    // Core services — lazy so init order is explicit
    private let spaceMonitor = SpaceMonitor()
    private let configStore = ConfigStore()
    private lazy var wallpaperController = WallpaperController(
        spaceMonitor: spaceMonitor,
        configStore: configStore
    )

    private let runMarker = RunMarker.default

    func applicationDidFinishLaunching(_ notification: Notification) {
        if runMarker.begin() {
            LogStore.shared.previousRunEndedUncleanly = true
            LivelyLogger.config.error("Previous run ended unexpectedly (crash, force quit or power loss)")
        }
        // Background-only process — no Dock icon
        NSApp.setActivationPolicy(.accessory)

        // Warm up the controller (triggers initial wallpaper load for all screens)
        _ = wallpaperController

        setupMenuBar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeEventMonitor()
        wallpaperController.tearDown()
        configStore.flushPendingPersist()
        runMarker.end()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            // Template SF Symbol reads clearly in the menu bar (light/dark).
            // Full app icon remains for Finder / About / .app bundle.
            button.image = NSImage(
                systemSymbolName: "play.tv.fill",
                accessibilityDescription: "Lively"
            )
            button.toolTip = "Lively — video wallpapers"
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        let view = SettingsContainerView(spaceMonitor: spaceMonitor, configStore: configStore)
            .environmentObject(wallpaperController)
        let hosting = NSHostingController(rootView: view)

        popover = NSPopover()
        popover.contentSize = SettingsContainerView.windowSize
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = hosting

        // Start Minimized off → open settings once after launch.
        if !AppPreferences.shared.startMinimized {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showPopover(nil)
            }
        }

        // Apply saved appearance (Light / Dark / System) before first paint.
        AppPreferences.applyAppAppearance(AppPreferences.shared.appearance)

        if AppPreferences.shared.checkForUpdates {
            Task { await UpdateChecker.shared.checkIfEnabled() }
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            closePopover(sender)
        } else {
            showPopover(sender)
        }
    }

    private func showPopover(_ sender: AnyObject?) {
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            
            // Close popover when clicking outside. Replace any previous monitor:
            // a transient popover can close itself without going through
            // closePopover, which used to leak one global monitor per open.
            removeEventMonitor()
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                if let self = self, self.popover.isShown {
                    self.closePopover(event)
                }
            }
        }
    }

    private func closePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
        removeEventMonitor()
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    // MARK: - NSPopoverDelegate

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated { removeEventMonitor() }
    }
}

// Entry point
AppDelegate.main()

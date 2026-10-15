import AppKit
import Combine

// MARK: - ScreenSpace

/// A snapshot of one physical display's active Space / wallpaper state.
///
/// This type is `@MainActor`-only — it holds an `NSScreen` reference which is
/// not `Sendable`. Never pass instances across isolation boundaries.
@MainActor
public struct ScreenSpace: Equatable, Identifiable {

    /// Stable display identifier derived from CGDirectDisplayID.
    public let id: String

    public let screen: NSScreen
    public let desktopImageURL: URL?
    public let displayName: String

    /// Composite config-store key: "displayID:desktopImageURL".
    /// Stable across app restarts; encodes both which screen AND which Space.
    public var spaceKey: String {
        guard let url = desktopImageURL else { return id }
        return "\(id):\(url.absoluteString)"
    }

    nonisolated public static func == (lhs: ScreenSpace, rhs: ScreenSpace) -> Bool {
        lhs.id == rhs.id && lhs.desktopImageURL == rhs.desktopImageURL
    }
}

// MARK: - SpaceMonitor

@MainActor
public class SpaceMonitor: ObservableObject {

    @Published public private(set) var screenSpaces: [ScreenSpace] = []
    @Published public private(set) var isRefreshing = false

    /// When false, Space switches skip the 10×50 ms desktop-image poll.
    /// Default `{ true }` keeps the poll unless the controller assigns otherwise.
    public var hasAssignedWallpaper: () -> Bool = { true }

    private var cancellables = Set<AnyCancellable>()
    private var spaceChangeTask: Task<Void, Never>?

    public init() {
        refresh()

        // User switches Spaces (swipe with 4 fingers / Control+Arrow)
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in self?.handleSpaceChange() }
            .store(in: &cancellables)

        // Monitor connected or disconnected
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    // MARK: - Public

    /// Force a refresh — used by WallpaperController when configs change.
    public func refresh() {
        isRefreshing = true
        screenSpaces = NSScreen.screens.map { screen in
            ScreenSpace(
                id: Self.displayID(for: screen),
                screen: screen,
                desktopImageURL: NSWorkspace.shared.desktopImageURL(for: screen),
                displayName: screen.localizedName
            )
        }
        isRefreshing = false
    }

    // MARK: - Private

    private func handleSpaceChange() {
        spaceChangeTask?.cancel()
        guard hasAssignedWallpaper() else {
            refresh()
            return
        }
        let previousURLs = Dictionary(
            uniqueKeysWithValues: screenSpaces.map { ($0.id, $0.desktopImageURL) }
        )
        isRefreshing = true
        spaceChangeTask = Task {
            for _ in 0..<10 {
                if Task.isCancelled {
                    isRefreshing = false
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
                let current = NSScreen.screens.map { screen -> (String, URL?) in
                    (Self.displayID(for: screen), NSWorkspace.shared.desktopImageURL(for: screen))
                }
                let changed = current.contains { id, url in
                    previousURLs[id] != url
                }
                if changed || previousURLs.isEmpty { break }
            }
            guard !Task.isCancelled else {
                isRefreshing = false
                return
            }
            refresh()
        }
    }

    // MARK: - Helpers

    /// Returns the CGDirectDisplayID as a String — stable across reboots for the
    /// same physical display connection.
    public static func displayID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let displayID = screen.deviceDescription[key] as? CGDirectDisplayID {
            return String(displayID)
        }
        // Fallback: localizedName is less stable but better than nothing
        return screen.localizedName
    }
}

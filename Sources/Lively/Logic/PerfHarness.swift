import Foundation

/// Isolated launch path for `scripts/perf/measure.sh`.
///
/// Reads `LIVELY_PERF_MODE` and `LIVELY_PERF_FIXTURE`. Does not change the
/// config schema or spaceKey format. Measure with a throwaway `HOME` so the
/// operator's real Application Support is never touched.
public enum PerfHarness {
    public enum Mode: String, Equatable, Sendable {
        case off
        case idle
        case playing
        case paused
    }

    public struct Request: Equatable, Sendable {
        public var mode: Mode
        public var fixtureURL: URL?

        public static func parse(
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> Request {
            let raw = environment["LIVELY_PERF_MODE"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let raw, let mode = Mode(rawValue: raw), mode != .off else {
                return Request(mode: .off, fixtureURL: nil)
            }
            let fixture = environment["LIVELY_PERF_FIXTURE"]
                .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            return Request(mode: mode, fixtureURL: fixture)
        }
    }

    public static func isValidRequest(_ request: Request) -> Bool {
        switch request.mode {
        case .off, .idle:
            return true
        case .playing, .paused:
            guard let url = request.fixtureURL else { return false }
            return isValidLivelyVideoFile(url)
        }
    }

    /// Assigns the fixture to every currently visible Space via the existing
    /// `ConfigStore.assign` API. Paused mode waits one run-loop turn plus a
    /// short grace so the player is built before `togglePause`.
    @MainActor
    public static func apply(
        _ request: Request,
        spaceMonitor: SpaceMonitor,
        configStore: ConfigStore,
        wallpaperController: WallpaperController
    ) {
        guard request.mode != .off else { return }
        guard isValidRequest(request) else {
            LivelyLogger.perf.error("Perf harness: playing/paused requires a supported LIVELY_PERF_FIXTURE")
            return
        }

        spaceMonitor.refresh()

        if request.mode == .idle {
            LivelyLogger.perf.info("Perf harness: idle (no wallpaper assigned)")
            return
        }

        guard let url = request.fixtureURL else { return }

        var wallpaper = DynamicWallpaper()
        wallpaper.mode = .staticVideo
        wallpaper.staticURL = url
        wallpaper.isMuted = true
        wallpaper.volume = 0

        let spaces = spaceMonitor.screenSpaces
        for space in spaces {
            configStore.assign(dynamicWallpaper: wallpaper, toSpaceKey: space.spaceKey)
        }
        LivelyLogger.perf.info("Perf harness: assigned fixture to \(spaces.count) space(s)")

        if request.mode == .paused {
            // Config sink refreshes asynchronously; pause after the player is up
            // so the paused footprint includes a resident AVPlayer (hypothesis B).
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if !wallpaperController.isPaused {
                    wallpaperController.togglePause()
                }
            }
        }
    }
}

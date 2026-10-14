import Foundation
import Testing
@testable import LivelyCore

@MainActor
struct PowerSourceMonitorTests {

    @Test func snapshotReturnsWithoutCrashing() {
        let snap = PowerSourceMonitor.snapshot()
        if let level = snap.levelPercent {
            #expect(level >= 0)
            #expect(level <= 100)
        }
    }

    @Test func startStopIsIdempotent() {
        let stop = PowerSourceMonitor.start {}
        stop()
        stop()
    }
}

@MainActor
struct WallpaperControllerPowerSourceTests {

    @Test func repeatingPowerSourceTimerStaysNilAfterInit() {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let controller = WallpaperController(
            spaceMonitor: SpaceMonitor(),
            configStore: ConfigStore(configFileURL: tempFile)
        )
        defer {
            controller.tearDown()
            try? FileManager.default.removeItem(at: tempFile)
        }
        #expect(controller.repeatingPowerSourceTimer == nil)
    }
}

import Testing
@testable import LivelyCore
import AppKit

struct SystemSuspensionTests {

    @Test func overlappingReasonsLiftIndependently() {
        var s = SystemSuspension()
        #expect(!s.isSuspended)

        let r1 = s.set(.screenLocked, active: true)
        #expect(r1)       // flipped on
        let r2 = s.set(.displaysAsleep, active: true)
        #expect(!r2)    // already suspended
        let r3 = s.set(.displaysAsleep, active: false)
        #expect(!r3)   // still locked
        #expect(s.isSuspended)
        let r4 = s.set(.screenLocked, active: false)
        #expect(r4)      // flipped off
        #expect(!s.isSuspended)
    }

    @Test func repeatedEventsAreIdempotent() {
        var s = SystemSuspension()
        s.set(.screenSaver, active: true)
        let r5 = s.set(.screenSaver, active: true)
        #expect(!r5)
        s.set(.screenSaver, active: false)
        let r6 = s.set(.screenSaver, active: false)
        #expect(!r6)
        #expect(!s.isSuspended)
    }

    @Test func wakeClearsSleepButNotLock() {
        var s = SystemSuspension()
        s.set(.systemAsleep, active: true)
        s.set(.displaysAsleep, active: true)
        s.set(.screenLocked, active: true)
        let r7 = s.systemDidWake()
        #expect(!r7)
        #expect(s.reasons == [.screenLocked])

        var t = SystemSuspension()
        t.set(.systemAsleep, active: true)
        let r8 = t.systemDidWake()
        #expect(r8)
        #expect(!t.isSuspended)
    }

    @Test func decodePolicy() {
        #expect(WallpaperPlaybackPolicy.shouldDecode(wantsPlayback: true, isOccluded: false))
        #expect(!WallpaperPlaybackPolicy.shouldDecode(wantsPlayback: true, isOccluded: true))
        #expect(!WallpaperPlaybackPolicy.shouldDecode(wantsPlayback: false, isOccluded: false))
        #expect(!WallpaperPlaybackPolicy.shouldDecode(wantsPlayback: false, isOccluded: true))
    }

    /// A muted AVPlayer still decodes and mixes audio; silent wallpapers must
    /// disable their audio tracks instead.
    @Test func audioTracksDecodeOnlyWhenAudible() {
        #expect(WallpaperPlaybackPolicy.shouldDecodeAudio(isMuted: false, volume: 0.5))
        #expect(!WallpaperPlaybackPolicy.shouldDecodeAudio(isMuted: true, volume: 0.5))
        #expect(!WallpaperPlaybackPolicy.shouldDecodeAudio(isMuted: false, volume: 0))
        #expect(!WallpaperPlaybackPolicy.shouldDecodeAudio(isMuted: true, volume: 0))
        // Shipped default (`DynamicWallpaper()`) is silent.
        let fresh = DynamicWallpaper()
        #expect(!WallpaperPlaybackPolicy.shouldDecodeAudio(isMuted: fresh.isMuted, volume: fresh.volume))
    }
}

@MainActor
struct WallpaperControllerSystemStateTests {

    private func makeController() -> (WallpaperController, URL) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let controller = WallpaperController(spaceMonitor: SpaceMonitor(), configStore: ConfigStore(configFileURL: file))
        return (controller, file)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func displaySleepNotificationSuspendsAndWakeResumes() async throws {
        let (controller, file) = makeController()
        defer { try? FileManager.default.removeItem(at: file); controller.tearDown() }

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: NSWorkspace.shared)
        try await waitUntil { controller.isSystemSuspended }
        #expect(controller.isSystemSuspended)

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: NSWorkspace.shared)
        try await waitUntil { !controller.isSystemSuspended }
        #expect(!controller.isSystemSuspended)
    }

    @Test func screenSaverSurvivesSystemWake() {
        let (controller, file) = makeController()
        defer { try? FileManager.default.removeItem(at: file); controller.tearDown() }

        controller.setSystemSuspension(.screenSaver, active: true)
        controller.setSystemSuspension(.systemAsleep, active: true)
        controller.systemDidWake()
        #expect(controller.isSystemSuspended)
        controller.setSystemSuspension(.screenSaver, active: false)
        #expect(!controller.isSystemSuspended)
        // User pause is independent of system suspension.
        #expect(!controller.isPaused)
    }

    @Test func tearDownStopsObservingSystemEvents() async throws {
        let (controller, file) = makeController()
        defer { try? FileManager.default.removeItem(at: file) }
        controller.tearDown()

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: NSWorkspace.shared)
        try await Task.sleep(for: .milliseconds(50))
        #expect(!controller.isSystemSuspended)
    }
}

@MainActor
struct LockReconciliationTests {
    @Test func unlockAlsoClearsScreenSaver() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let controller = WallpaperController(spaceMonitor: SpaceMonitor(), configStore: ConfigStore(configFileURL: file))
        defer { try? FileManager.default.removeItem(at: file); controller.tearDown() }

        controller.setSystemSuspension(.screenSaver, active: true)
        controller.setSystemSuspension(.screenLocked, active: true)
        // Missed "didstop": the unlock alone must resume playback.
        controller.setSystemSuspension([.screenLocked: false, .screenSaver: false])
        #expect(!controller.isSystemSuspended)
    }

    @Test func wakeClearsStaleLockWhenSessionIsUnlocked() {
        // Test runs in an unlocked GUI session.
        guard !WallpaperController.isScreenLockedNow() else { return }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let controller = WallpaperController(spaceMonitor: SpaceMonitor(), configStore: ConfigStore(configFileURL: file))
        defer { try? FileManager.default.removeItem(at: file); controller.tearDown() }

        controller.setSystemSuspension(.screenLocked, active: true)   // "unlocked" never arrives
        controller.systemDidWake()
        #expect(!controller.isSystemSuspended)
    }
}

import Testing
import Combine
@testable import LivelyCore
import Foundation

@MainActor
struct WallpaperControllerTests {

    @Test func playbackErrorBubblesToSubject() {
        let monitor = SpaceMonitor()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let store = ConfigStore(configFileURL: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let controller = WallpaperController(spaceMonitor: monitor, configStore: store)

        var receivedSpaceKey: String?
        var receivedMessage: String?

        let cancellable = controller.playbackErrors.sink { (spaceKey, message) in
            receivedSpaceKey = spaceKey
            receivedMessage = message
        }

        // PassthroughSubject.send is synchronous — sink fires immediately
        controller.playbackErrors.send(("test-space", "Simulated error"))

        #expect(receivedSpaceKey == "test-space")
        #expect(receivedMessage == "Simulated error")
        cancellable.cancel()
    }

    @Test func togglePause() {
        let monitor = SpaceMonitor()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let store = ConfigStore(configFileURL: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let controller = WallpaperController(spaceMonitor: monitor, configStore: store)

        #expect(!controller.isPaused)
        controller.togglePause()
        #expect(controller.isPaused)
        controller.togglePause()
        #expect(!controller.isPaused)
    }

    @Test func resumeAfterPauseDoesNotCrash() {
        let monitor = SpaceMonitor()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let store = ConfigStore(configFileURL: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let controller = WallpaperController(spaceMonitor: monitor, configStore: store)

        controller.togglePause()
        #expect(controller.isPaused)
        controller.togglePause()
        #expect(!controller.isPaused, "Controller should be playing after second toggle")
    }
}

@MainActor
struct PowerSourceObserverTests {

    /// Battery pause is driven by IOKit notifications, not a polling timer.
    @Test func registersWithIOKitAndInvalidatesIdempotently() {
        let observer = PowerSourceObserver { }
        #expect(observer.isActive)
        observer.invalidate()
        #expect(!observer.isActive)
        observer.invalidate()
        #expect(!observer.isActive)
    }
}

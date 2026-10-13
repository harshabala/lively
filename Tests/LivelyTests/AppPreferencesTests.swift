import Testing
@testable import LivelyCore
import Foundation

@MainActor
struct AppPreferencesTests {

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "lively.tests.prefs.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func updateCheckIsOffOnFreshInstall() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let prefs = AppPreferences(defaults: defaults)
        #expect(prefs.checkForUpdates == false)
    }

    @Test func legacyDefaultOnIsResetOnceThenRespected() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Builds ≤ 1.2.0 wrote `true` as the first-launch default.
        defaults.set(true, forKey: "prefs.checkForUpdates")
        let migrated = AppPreferences(defaults: defaults)
        #expect(migrated.checkForUpdates == false)

        // After migration an explicit opt-in sticks across launches.
        migrated.checkForUpdates = true
        let relaunched = AppPreferences(defaults: defaults)
        #expect(relaunched.checkForUpdates == true)
    }

    @Test func unknownEnumValuesFallBackToDefaults() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("ultra", forKey: "prefs.playbackQuality")
        defaults.set("bounce", forKey: "prefs.loopBehavior")
        defaults.set("8k", forKey: "prefs.maxResolution")
        defaults.set("neon", forKey: "prefs.appearance")
        defaults.set(3.0, forKey: "prefs.batteryPauseThreshold")

        let prefs = AppPreferences(defaults: defaults)
        #expect(prefs.playbackQuality == .high)
        #expect(prefs.loopBehavior == .loop)
        #expect(prefs.maxResolution == .matchSource)
        #expect(prefs.appearance == .system)
        #expect(prefs.batteryPauseThreshold == AppPreferences.batteryThresholdRange.lowerBound)
    }

    @Test func legacyFrameRateCapMigratesToMaxResolution() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("fps30", forKey: "prefs.frameRateCap")
        #expect(AppPreferences(defaults: defaults).maxResolution == .p1080)
    }
}

@MainActor
struct ResetDataTests {

    @Test func resetRestoresShippedDefaultsButKeepsOnboarding() {
        let suite = "lively.tests.reset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let prefs = AppPreferences(defaults: defaults)
        prefs.pauseOnBattery = false
        prefs.batteryPauseThreshold = 80
        prefs.checkForUpdates = true
        prefs.playbackQuality = .powerSaver
        prefs.loopBehavior = .playOnceFreeze
        prefs.hardwareDecoding = false
        prefs.maxResolution = .p1080
        prefs.startMinimized = false
        prefs.hasCompletedWelcome = true

        prefs.resetToDefaults()

        let freshSuite = "lively.tests.reset.fresh.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: freshSuite)?.removePersistentDomain(forName: freshSuite) }
        let fresh = AppPreferences(defaults: UserDefaults(suiteName: freshSuite)!)
        #expect(prefs.pauseOnBattery == fresh.pauseOnBattery)
        #expect(prefs.batteryPauseThreshold == fresh.batteryPauseThreshold)
        #expect(prefs.checkForUpdates == false)
        #expect(prefs.playbackQuality == fresh.playbackQuality)
        #expect(prefs.loopBehavior == fresh.loopBehavior)
        #expect(prefs.hardwareDecoding == fresh.hardwareDecoding)
        #expect(prefs.maxResolution == fresh.maxResolution)
        #expect(prefs.startMinimized == fresh.startMinimized)
        #expect(prefs.hasCompletedWelcome)

        // Persisted, not just in memory.
        let relaunched = AppPreferences(defaults: defaults)
        #expect(relaunched.playbackQuality == .high)
        #expect(relaunched.pauseOnBattery)
    }

    @Test func libraryRecoversAfterItsFolderIsDeleted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lively-lib-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let libraryDir = root.appendingPathComponent("Library")
        let manager = WallpaperLibraryManager(libraryDir: libraryDir)

        let source = root.appendingPathComponent("clip.mp4")
        FileManager.default.createFile(atPath: source.path, contents: Data("x".utf8))
        try manager.add(from: source)
        #expect(manager.items.count == 1)

        // Reset Data removes the whole Application Support folder.
        try FileManager.default.removeItem(at: libraryDir)
        manager.reload()
        #expect(manager.items.isEmpty)

        // Adding again must recreate the folder instead of failing.
        try manager.add(from: source)
        #expect(manager.items.count == 1)
        #expect(manager.resolvedURL(for: manager.items[0]) != nil)
    }
}

@MainActor
struct PreferencesSchemaTests {
    @Test func freshAndLegacyStoresAreStampedWithCurrentVersion() {
        let suite = "lively.tests.schema.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("fps60", forKey: "prefs.frameRateCap")   // pre-versioning store
        let prefs = AppPreferences(defaults: defaults)
        #expect(prefs.maxResolution == .p4k)
        #expect(defaults.integer(forKey: "prefs.schemaVersion") == AppPreferences.currentSchemaVersion)
    }

    @Test func newerSchemaVersionIsNotDowngraded() {
        let suite = "lively.tests.schema2.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(99, forKey: "prefs.schemaVersion")
        _ = AppPreferences(defaults: defaults)
        #expect(defaults.integer(forKey: "prefs.schemaVersion") == 99)
    }
}

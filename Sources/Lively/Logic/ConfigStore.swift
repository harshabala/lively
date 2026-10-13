import Foundation
import AppKit
import Combine

// MARK: - SpaceConfig

public struct SpaceConfig: Codable, Sendable {
    /// Composite key: "displayID:desktopImageURL.absoluteString"
    public let spaceKey: String

    /// The dynamic wallpaper configuration.
    public let dynamicWallpaper: DynamicWallpaper

    /// Bookmarks for all relevant URLs.
    /// Key: "static", "light", "dark".
    public let bookmarks: [String: Data]

    public let addedAt: Date

    func replacing(dynamicWallpaper: DynamicWallpaper? = nil, bookmarks: [String: Data]? = nil) -> SpaceConfig {
        SpaceConfig(
            spaceKey: spaceKey,
            dynamicWallpaper: dynamicWallpaper ?? self.dynamicWallpaper,
            bookmarks: bookmarks ?? self.bookmarks,
            addedAt: addedAt
        )
    }
}

// MARK: - ConfigStore

@MainActor
public class ConfigStore: ObservableObject {

    @Published public private(set) var configs: [String: SpaceConfig] = [:]

    public enum Error: Swift.Error {
        case directoryCreationFailed(Swift.Error)
        case persistFailed(Swift.Error)
        case loadFailed(Swift.Error)
        case bookmarkRefreshFailed(String)
        case bookmarkCreationFailed(String)
    }

    public let errors = PassthroughSubject<Error, Never>()

    private let configFileURL: URL
    private let persistQueue = DispatchQueue(label: "Lively.ConfigStore.persist")
    private var pendingPersistWorkItem: DispatchWorkItem?

    public init(configFileURL: URL? = nil) {
        if let provided = configFileURL {
            self.configFileURL = provided
        } else if let envPath = ProcessInfo.processInfo.environment["LIVELY_CONFIG_FILE"],
                  !envPath.isEmpty {
            self.configFileURL = URL(fileURLWithPath: envPath)
        } else {
            let dir = AppSupportPaths.livelyDirectory()
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                LivelyLogger.config.error("Failed to create config directory: \(error.localizedDescription)")
                errors.send(.directoryCreationFailed(error))
            }
            self.configFileURL = dir.appendingPathComponent("config_v2.json")
        }
        load()
    }

    // MARK: - Public API

    /// Assigns a dynamic wallpaper configuration to a space.
    public func assign(dynamicWallpaper: DynamicWallpaper, toSpaceKey key: String) {
        AppMetrics.shared.recordWallpaperApplied()
        
        var bookmarks: [String: Data] = [:]
        let sources: [(String, URL?)] = [
            ("static", dynamicWallpaper.staticURL),
            ("light", dynamicWallpaper.lightURL),
            ("dark", dynamicWallpaper.darkURL),
        ]
        for (bookmarkKey, url) in sources {
            guard let url else { continue }
            guard let data = makeBookmarkData(for: url, key: bookmarkKey) else { return }
            bookmarks[bookmarkKey] = data
        }

        let config = SpaceConfig(
            spaceKey: key,
            dynamicWallpaper: dynamicWallpaper,
            bookmarks: bookmarks,
            addedAt: Date()
        )
        configs[key] = config
        persist()
        LivelyLogger.config.info("Assigned dynamic wallpaper to display \(Self.redactedSpaceKey(key))")
    }

    /// Resolves the URL for the current mode/appearance.
    ///
    /// This method only decodes the bookmark — it does NOT call
    /// `startAccessingSecurityScopedResource`. The caller (WallpaperController)
    /// is responsible for calling start/stop to balance the access handles.
    public func resolvedURL(for spaceKey: String, appearance: NSAppearance?) -> URL? {
        guard let config = configs[spaceKey] else { return nil }

        let targetURL = config.dynamicWallpaper.url(for: appearance)
        guard let url = targetURL else { return nil }

        let bookmarkKey: String
        switch config.dynamicWallpaper.mode {
        case .staticVideo: bookmarkKey = "static"
        case .appearance:
            if url == config.dynamicWallpaper.darkURL { bookmarkKey = "dark" }
            else { bookmarkKey = "light" }
        }

        guard let data = config.bookmarks[bookmarkKey] else {
            LivelyLogger.config.debug("No bookmark for \(bookmarkKey); rejecting raw path")
            return nil
        }

        return resolveURL(fromBookmark: data, spaceKey: spaceKey, bookmarkKey: bookmarkKey, verbose: true)
    }

    /// Resolves a specific bookmark key directly.
    /// Used by secondary components like VideoThumbnailView to gain access.
    public func resolveBookmark(for spaceKey: String, bookmarkKey: String) -> URL? {
        guard let data = configs[spaceKey]?.bookmarks[bookmarkKey] else { return nil }
        return resolveURL(fromBookmark: data, spaceKey: spaceKey, bookmarkKey: bookmarkKey, verbose: false)
    }

    private func resolveURL(fromBookmark data: Data, spaceKey: String, bookmarkKey: String, verbose: Bool) -> URL? {
        var isStale = false
        do {
            let resolved = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                if verbose { LivelyLogger.config.info("Refreshing stale bookmark for \(bookmarkKey)") }
                refreshBookmark(spaceKey: spaceKey, bookmarkKey: bookmarkKey, url: resolved)
            }
            if verbose {
                LivelyLogger.config.info("Resolved \(bookmarkKey) via security-scoped bookmark → \(resolved.lastPathComponent)")
            }
            return resolved
        } catch {
            do {
                var legacyStale = false
                let legacyResolved = try URL(
                    resolvingBookmarkData: data,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &legacyStale
                )
                if verbose {
                    LivelyLogger.config.info("Legacy bookmark resolved for \(bookmarkKey), upgrading to security-scoped")
                }
                refreshBookmark(spaceKey: spaceKey, bookmarkKey: bookmarkKey, url: legacyResolved)
                return legacyResolved
            } catch let legacyError {
                if verbose {
                    LivelyLogger.config.error("Bookmark resolution failed for \(bookmarkKey). Primary error: \(error.localizedDescription). Legacy fallback error: \(legacyError.localizedDescription)")
                }
                return nil
            }
        }
    }

    private func makeBookmarkData(for url: URL, key: String) -> Data? {
        do {
            return try Self.securityScopedBookmarkData(for: url)
        } catch {
            errors.send(.bookmarkCreationFailed(key))
            LivelyLogger.config.error("Failed to create bookmark for \(key): \(error.localizedDescription)")
            return nil
        }
    }

    nonisolated private static func securityScopedBookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Re-creates a bookmark for a URL with security scope.
    private func refreshBookmark(spaceKey: String, bookmarkKey: String, url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        guard let config = configs[spaceKey] else {
            errors.send(.bookmarkRefreshFailed(bookmarkKey))
            LivelyLogger.config.error("No config found while refreshing bookmark for \(bookmarkKey)")
            return
        }

        let newData: Data
        do {
            newData = try Self.securityScopedBookmarkData(for: url)
        } catch {
            errors.send(.bookmarkRefreshFailed(bookmarkKey))
            LivelyLogger.config.error("Failed to refresh bookmark for \(bookmarkKey): \(error.localizedDescription)")
            return
        }

        var updatedBookmarks = config.bookmarks
        updatedBookmarks[bookmarkKey] = newData

        // A stale bookmark usually means the file was moved or renamed; keep the
        // stored path in step so the UI shows the real name.
        configs[spaceKey] = config.replacing(
            dynamicWallpaper: Self.wallpaper(config.dynamicWallpaper, replacing: bookmarkKey, with: url),
            bookmarks: updatedBookmarks
        )
        persist()
        LivelyLogger.config.info("Bookmark upgraded to security-scoped for \(bookmarkKey)")
    }

    static func wallpaper(_ wallpaper: DynamicWallpaper, replacing bookmarkKey: String, with url: URL) -> DynamicWallpaper {
        var updated = wallpaper
        let fileURL = URL(fileURLWithPath: url.path)
        switch bookmarkKey {
        case "static": updated.staticURL = fileURL
        case "light": updated.lightURL = fileURL
        case "dark": updated.darkURL = fileURL
        default: break
        }
        return updated
    }

    /// Updates only the display settings (gravity, mute, volume) for an existing config.
    public func updateDisplaySettings(for key: String, gravity: VideoGravity, isMuted: Bool, volume: Float) {
        guard let existing = configs[key] else { return }

        var updated = existing.dynamicWallpaper
        updated.videoGravity = gravity
        updated.isMuted = isMuted
        updated.volume = volume

        guard updated != existing.dynamicWallpaper else { return }

        configs[key] = existing.replacing(dynamicWallpaper: updated)
        persist()
    }

    public func remove(spaceKey: String) {
        configs.removeValue(forKey: spaceKey)
        persist()
        LivelyLogger.config.info("Removed assignment for \(Self.redactedSpaceKey(spaceKey))")
    }

    /// Assigns the same static video wallpaper to every provided space key.
    public func applyStaticWallpaper(_ url: URL, toAllSpaceKeys keys: [String]) {
        for key in keys {
            var wallpaper = configs[key]?.dynamicWallpaper ?? DynamicWallpaper()
            wallpaper.mode = .staticVideo
            wallpaper.staticURL = url
            assign(dynamicWallpaper: wallpaper, toSpaceKey: key)
        }
    }

    /// Logs display ID only — never full file paths (spaceKey embeds desktop URLs).
    static func redactedSpaceKey(_ key: String) -> String {
        if let colon = key.firstIndex(of: ":") {
            return String(key[..<colon])
        }
        return key
    }

    /// Deletes all saved configuration data from disk and memory.
    public func clearAllData() {
        pendingPersistWorkItem?.cancel()
        pendingPersistWorkItem = nil
        configs.removeAll()

        let fm = FileManager.default
        let dir = configFileURL.deletingLastPathComponent()
        if fm.fileExists(atPath: dir.path) {
            do {
                try fm.removeItem(at: dir)
                LivelyLogger.config.info("Successfully deleted all application data")
            } catch {
                LivelyLogger.config.error("Failed to delete application data: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Persistence

    private func persist() {
        let snapshot = configs

        let workItem = DispatchWorkItem { @Sendable [configFileURL, weak self] in
            do {
                try Self.write(snapshot, to: configFileURL)
            } catch {
                DispatchQueue.main.async {
                    self?.errors.send(.persistFailed(error))
                    LivelyLogger.config.error("Failed to save config: \(error.localizedDescription)")
                }
            }
        }

        pendingPersistWorkItem?.cancel()
        pendingPersistWorkItem = workItem

        persistQueue.asyncAfter(deadline: .now() + .milliseconds(300), execute: workItem)
    }

    /// Atomic write that recreates the directory (it is removed by Reset Data).
    nonisolated private static func write(_ snapshot: [String: SpaceConfig], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    public func flushPendingPersist() {
        guard let pending = pendingPersistWorkItem else { return }
        pending.cancel()
        pendingPersistWorkItem = nil

        let snapshot = configs
        let fileURL = self.configFileURL
        persistQueue.sync {
            do {
                try Self.write(snapshot, to: fileURL)
                LivelyLogger.config.info("Config flushed synchronously on exit")
            } catch {
                LivelyLogger.config.error("Failed to flush config on exit: \(error.localizedDescription)")
            }
        }
    }

    private func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: configFileURL.path) else {
            LivelyLogger.config.info("Starting fresh (no existing config)")
            return
        }

        let data: Data
        do {
            data = try Data(contentsOf: configFileURL)
        } catch {
            errors.send(.loadFailed(error))
            LivelyLogger.config.error("Failed to read config, starting fresh: \(error.localizedDescription)")
            return
        }

        do {
            // Decode entry-by-entry so one bad or future-schema assignment
            // doesn't throw away every other display's wallpaper.
            let decoded = try JSONDecoder().decode([String: LossyDecodable<SpaceConfig>].self, from: data)
            configs = decoded.compactMapValues(\.value)
            let dropped = decoded.count - configs.count
            if dropped > 0 {
                LivelyLogger.config.error("Dropped \(dropped) unreadable assignment(s) from config")
            }
            sanitizeLoadedConfigs(forcePersist: dropped > 0)
            LivelyLogger.config.info("Loaded \(self.configs.count) assignment(s)")
        } catch {
            // Not even a JSON object: keep a copy for diagnosis instead of
            // silently overwriting it on the next save.
            errors.send(.loadFailed(error))
            let backup = Self.corruptBackupURL(for: configFileURL)
            try? fm.removeItem(at: backup)
            try? fm.moveItem(at: configFileURL, to: backup)
            LivelyLogger.config.error("Config was unreadable; moved aside to \(backup.lastPathComponent) and starting fresh: \(error.localizedDescription)")
            configs = [:]
        }
    }

    static func corruptBackupURL(for url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("corrupt.json")
    }

    /// Drops configs with invalid extensions or missing required bookmarks.
    private func sanitizeLoadedConfigs(forcePersist: Bool) {
        let before = configs.count
        configs = configs.filter { _, config in
            isConfigPlayable(config)
        }
        if configs.count != before {
            LivelyLogger.config.info("Sanitized config: dropped \(before - self.configs.count) invalid assignment(s)")
        }
        if forcePersist || configs.count != before {
            persist()
        }
    }

    private func isConfigPlayable(_ config: SpaceConfig) -> Bool {
        let wallpaper = config.dynamicWallpaper
        func playable(_ url: URL?, key: String) -> Bool {
            guard let url, isValidLivelyVideoFile(url), config.bookmarks[key] != nil else { return false }
            return true
        }
        switch wallpaper.mode {
        case .staticVideo:
            return playable(wallpaper.staticURL, key: "static")
        case .appearance:
            return playable(wallpaper.lightURL, key: "light") || playable(wallpaper.darkURL, key: "dark")
        }
    }
}

// MARK: - Lossy decoding

/// Decodes a value if possible and swallows the error otherwise, so a single
/// malformed entry in a keyed collection doesn't fail the whole document.
struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

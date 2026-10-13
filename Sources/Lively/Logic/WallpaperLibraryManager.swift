import Foundation
import AppKit
import Combine

/// Manages the user's reusable wallpaper library (local files only).
///
/// Videos are copied into Application Support so assignments stay reliable
/// even if the original file is moved. No remote catalog or downloads.
@MainActor
public final class WallpaperLibraryManager: ObservableObject {
    public static let shared = WallpaperLibraryManager()

    @Published public private(set) var items: [LibraryWallpaper] = []
    @Published public var spaceKeyTarget: String?

    public let libraryDir: URL
    private let indexURL: URL
    private let fileManager: FileManager

    public init(libraryDir: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager

        if let libraryDir {
            self.libraryDir = libraryDir
        } else if ProcessInfo.processInfo.environment["LIVELY_APPLICATION_SUPPORT"] != nil {
            self.libraryDir = AppSupportPaths.livelyDirectory()
                .appendingPathComponent("Library", isDirectory: true)
        } else if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            self.libraryDir = support.appendingPathComponent("Lively/Library", isDirectory: true)
        } else {
            self.libraryDir = fileManager.temporaryDirectory.appendingPathComponent("Lively/Library", isDirectory: true)
        }
        self.indexURL = self.libraryDir.appendingPathComponent("library_index.json")

        do {
            try fileManager.createDirectory(at: self.libraryDir, withIntermediateDirectories: true)
        } catch {
            LivelyLogger.wallpaper.error("Failed to create library directory: \(error.localizedDescription)")
        }

        loadIndex()
        reconcileMissingFiles()
    }

    // MARK: - Paths

    public func fileURL(for item: LibraryWallpaper) -> URL {
        libraryDir.appendingPathComponent(item.fileName)
    }

    public func resolvedURL(for item: LibraryWallpaper) -> URL? {
        let url = fileURL(for: item)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return url
    }

    // MARK: - Add / Remove

    /// Copies a user-selected video into the library as a reusable wallpaper.
    @discardableResult
    public func add(from sourceURL: URL) throws -> LibraryWallpaper {
        guard isValidLivelyVideoFile(sourceURL) else {
            throw LibraryError.unsupportedFormat
        }

        let access = sourceURL.startAccessingSecurityScopedResource()
        defer { if access { sourceURL.stopAccessingSecurityScopedResource() } }

        let id = UUID().uuidString
        let ext = sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension.lowercased()
        let fileName = "\(id).\(ext)"
        let destination = libraryDir.appendingPathComponent(fileName)

        // The directory may have been removed by Reset Data.
        try fileManager.createDirectory(at: libraryDir, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)

        let displayName = sourceURL.deletingPathExtension().lastPathComponent
        let item = LibraryWallpaper(
            id: id,
            name: displayName.isEmpty ? "Wallpaper" : displayName,
            fileName: fileName
        )
        items.insert(item, at: 0)
        saveIndex()
        LivelyLogger.wallpaper.info("Added library wallpaper: \(item.name)")
        return item
    }

    public func remove(_ item: LibraryWallpaper) {
        items.removeAll { $0.id == item.id }
        let url = fileURL(for: item)
        try? fileManager.removeItem(at: url)
        saveIndex()
        LivelyLogger.wallpaper.info("Removed library wallpaper: \(item.name)")
    }

    public func rename(_ item: LibraryWallpaper, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].name = trimmed
        saveIndex()
    }

    /// Re-reads the index from disk and drops entries whose files are gone
    /// (e.g. after Reset Data removed the Application Support folder).
    public func reload() {
        loadIndex()
        reconcileMissingFiles()
    }

    // MARK: - Persistence

    private func loadIndex() {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            items = []
            return
        }
        do {
            let data = try Data(contentsOf: indexURL)
            items = try JSONDecoder().decode([LibraryWallpaper].self, from: data)
        } catch {
            LivelyLogger.wallpaper.error("Failed to load library index: \(error.localizedDescription)")
            items = []
        }
    }

    private func saveIndex() {
        do {
            try fileManager.createDirectory(at: libraryDir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(items)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            LivelyLogger.wallpaper.error("Failed to save library index: \(error.localizedDescription)")
        }
    }

    /// Drop index entries whose files disappeared.
    private func reconcileMissingFiles() {
        let before = items.count
        items.removeAll { !fileManager.fileExists(atPath: fileURL(for: $0).path) }
        if items.count != before {
            saveIndex()
        }
    }

    public enum LibraryError: LocalizedError {
        case unsupportedFormat

        public var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return "Only MP4, MOV, and M4V video files can be added to the library."
            }
        }
    }
}

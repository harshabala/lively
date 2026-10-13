import Foundation

/// Removes personal data from text before it is shown in an exported report.
public enum DiagnosticsRedactor {
    /// Replaces the user's home directory and any `/Users/<name>/` path with `~`.
    public static func redact(_ text: String, homeDirectory: String = NSHomeDirectory()) -> String {
        var result = text
        if homeDirectory.count > 1 {
            result = result.replacingOccurrences(of: homeDirectory, with: "~")
        }
        // Other accounts and paths copied from elsewhere (e.g. external volumes).
        let pattern = #"/Users/[^/\s]+"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "~")
        }
        return result
    }
}

/// A plain-text support report the user can save and attach to an issue.
/// Contains no video paths, file names or personal data: only versions, counts
/// and redacted log lines. Nothing is sent anywhere; the user decides.
public struct DiagnosticsReport: Sendable {
    public struct Snapshot: Sendable {
        public var appVersion: String
        public var build: String
        public var osVersion: String
        public var displayCount: Int
        public var assignmentCount: Int?
        public var isPaused: Bool?
        public var preferences: [String: String]
        public var previousRunEndedUncleanly: Bool
        public var logLines: [String]

        public init(
            appVersion: String,
            build: String,
            osVersion: String,
            displayCount: Int,
            assignmentCount: Int?,
            isPaused: Bool?,
            preferences: [String: String],
            previousRunEndedUncleanly: Bool,
            logLines: [String]
        ) {
            self.appVersion = appVersion
            self.build = build
            self.osVersion = osVersion
            self.displayCount = displayCount
            self.assignmentCount = assignmentCount
            self.isPaused = isPaused
            self.preferences = preferences
            self.previousRunEndedUncleanly = previousRunEndedUncleanly
            self.logLines = logLines
        }
    }

    /// Only the most recent lines are exported, to keep reports small.
    public static let maxLogLines = 200

    public static func render(_ snapshot: Snapshot, homeDirectory: String = NSHomeDirectory()) -> String {
        var lines: [String] = []
        lines.append("Lively diagnostics")
        lines.append("App version: \(snapshot.appVersion) (\(snapshot.build))")
        lines.append("macOS: \(snapshot.osVersion)")
        lines.append("Displays: \(snapshot.displayCount)")
        if let count = snapshot.assignmentCount {
            lines.append("Wallpaper assignments: \(count)")
        }
        if let paused = snapshot.isPaused {
            lines.append("Playback paused: \(paused ? "yes" : "no")")
        }
        lines.append("Previous run ended unexpectedly: \(snapshot.previousRunEndedUncleanly ? "yes" : "no")")
        lines.append("")
        lines.append("Preferences")
        for key in snapshot.preferences.keys.sorted() {
            lines.append("  \(key) = \(snapshot.preferences[key] ?? "")")
        }
        lines.append("")
        lines.append("Recent log (last \(maxLogLines) lines, paths redacted)")
        let tail = snapshot.logLines.suffix(maxLogLines)
        for line in tail {
            lines.append(DiagnosticsRedactor.redact(line, homeDirectory: homeDirectory))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Detects that the previous run did not shut down cleanly (crash, force quit,
/// power loss) using a marker file that exists only while the app is running.
public struct RunMarker: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static var `default`: RunMarker {
        let dir = AppSupportPaths.livelyDirectory()
        return RunMarker(url: dir.appendingPathComponent("running.marker"))
    }

    /// Call once at launch. Returns true when the previous run left its marker behind.
    @discardableResult
    public func begin() -> Bool {
        let fm = FileManager.default
        let wasUnclean = fm.fileExists(atPath: url.path)
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data().write(to: url, options: .atomic)
        return wasUnclean
    }

    /// Call on normal termination.
    public func end() {
        try? FileManager.default.removeItem(at: url)
    }
}

import Foundation

/// Resolves Application Support. `LIVELY_APPLICATION_SUPPORT` wins so
/// `scripts/perf/measure.sh` can isolate I/O. Setting `HOME` is not enough:
/// `FileManager.SearchPathDomainMask.userDomainMask` still points at the
/// real user Library on current macOS.
public enum AppSupportPaths {
    public static func applicationSupportDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let override = environment["LIVELY_APPLICATION_SUPPORT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory.appendingPathComponent("Application Support", isDirectory: true)
    }

    public static func livelyDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        applicationSupportDirectory(environment: environment, fileManager: fileManager)
            .appendingPathComponent("Lively", isDirectory: true)
    }

    public static func perfUserDefaults(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> UserDefaults {
        let mode = environment["LIVELY_PERF_MODE"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !mode.isEmpty, mode != "off" else { return .standard }
        let suite = "com.lively.app.perf"
        if let defaults = UserDefaults(suiteName: suite) {
            defaults.removePersistentDomain(forName: suite)
            return defaults
        }
        return .standard
    }
}

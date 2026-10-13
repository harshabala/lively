import os

/// `os_signpost` intervals for Instruments. Cheap when a recording is not
/// attached: begin/end become no-ops at the tracing layer.
///
/// Names match `docs/PERFORMANCE_MASTER_PLAN.md` P0: launch, synchronize,
/// playerBuild, pause, resume.
public enum PerfSignposts {
    public static let subsystem = "com.lively.app"
    public static let category = "Performance"

    public static let launch: StaticString = "launch"
    public static let synchronize: StaticString = "synchronize"
    public static let playerBuild: StaticString = "playerBuild"
    public static let pause: StaticString = "pause"
    public static let resume: StaticString = "resume"

    public static let signposter = OSSignposter(subsystem: subsystem, category: category)

    /// Runs `body` inside a matching begin/end interval.
    @discardableResult
    public static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try body()
    }
}

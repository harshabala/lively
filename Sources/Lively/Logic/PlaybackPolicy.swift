import Foundation

/// Why wallpapers are suspended by the system (as opposed to the user's
/// Pause button, battery policy, or thermal throttling). While any reason is
/// active nothing is visible, so decoding would only burn CPU/GPU and battery.
public enum SystemSuspensionReason: String, CaseIterable, Sendable {
    /// Displays went to sleep (idle timer, lid closed on a single display).
    case displaysAsleep
    /// The Mac is going to sleep.
    case systemAsleep
    /// Fast User Switching moved this login session to the background.
    case sessionInactive
    /// The screen is locked.
    case screenLocked
    /// The screen saver is running over the desktop.
    case screenSaver
}

/// Tracks overlapping system suspension reasons. Wake/unlock events only lift
/// their own reason, so e.g. waking the displays while still locked keeps
/// wallpapers paused until unlock.
public struct SystemSuspension: Equatable, Sendable {
    public private(set) var reasons: Set<SystemSuspensionReason> = []

    public init() {}

    public var isSuspended: Bool { !reasons.isEmpty }

    /// Returns true when the overall suspended state flipped.
    @discardableResult
    public mutating func set(_ reason: SystemSuspensionReason, active: Bool) -> Bool {
        let before = isSuspended
        if active {
            reasons.insert(reason)
        } else {
            reasons.remove(reason)
        }
        return before != isSuspended
    }

    /// A full system wake clears everything that implies "asleep"; lock and
    /// session state are reported separately and keep their own reasons.
    @discardableResult
    public mutating func systemDidWake() -> Bool {
        let before = isSuspended
        reasons.remove(.systemAsleep)
        reasons.remove(.displaysAsleep)
        return before != isSuspended
    }
}

/// Per-display decode decision.
enum WallpaperPlaybackPolicy {
    /// Decode only when the controller wants playback and the wallpaper window
    /// is at least partly visible.
    static func shouldDecode(wantsPlayback: Bool, isOccluded: Bool) -> Bool {
        wantsPlayback && !isOccluded
    }

    /// `AVPlayer.isMuted` still decodes and mixes the soundtrack (P1 profile:
    /// 13.7% vs 4.4% CPU), so audio tracks stay enabled only when audible.
    static func shouldDecodeAudio(isMuted: Bool, volume: Float) -> Bool {
        !isMuted && volume > 0
    }
}

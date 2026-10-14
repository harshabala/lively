import Foundation

public enum ColdPauseTrigger: Equatable {
    case userPause
    case batteryOrThermal
    case lockSleepOrSaver
}

public enum ColdPausePolicy {
    public static func grace(for trigger: ColdPauseTrigger) -> Duration {
        switch trigger {
        case .userPause, .lockSleepOrSaver:
            return .seconds(10)
        case .batteryOrThermal:
            return .seconds(0)
        }
    }

    public static func shouldTearDown(elapsed: Duration, grace: Duration) -> Bool {
        elapsed >= grace
    }

    /// One-shot per halt: do not restart grace if a task is already scheduled
    /// or the player is already gone (poster on screen).
    public static func shouldScheduleTearDown(alreadyScheduled: Bool, playerExists: Bool) -> Bool {
        playerExists && !alreadyScheduled
    }

    /// After an async poster capture, never tear down a resumed or replaced player.
    public static func shouldCommitTearDown(
        isCancelled: Bool,
        wantsPlayback: Bool,
        isSamePlayer: Bool
    ) -> Bool {
        !isCancelled && !wantsPlayback && isSamePlayer
    }
}

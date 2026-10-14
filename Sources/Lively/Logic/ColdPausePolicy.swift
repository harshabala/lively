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
}

import Foundation
import IOKit.ps

/// Reads IOKit power-source state and observes AC/battery and Low Power Mode changes.
public enum PowerSourceMonitor {
    public typealias Stop = () -> Void

    public struct Snapshot: Equatable, Sendable {
        public var isOnBattery: Bool
        /// 0–100 when known.
        public var levelPercent: Double?
    }

    public static func snapshot() -> Snapshot {
        guard
            let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return Snapshot(
                isOnBattery: ProcessInfo.processInfo.isLowPowerModeEnabled,
                levelPercent: nil
            )
        }

        var onBattery = false
        var level: Double?

        for source in list {
            guard
                let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
            else { continue }

            if let state = desc[kIOPSPowerSourceStateKey] as? String,
               state == kIOPSBatteryPowerValue {
                onBattery = true
            }
            // Current capacity is typically 0–100 for internal batteries.
            if let capacity = desc[kIOPSCurrentCapacityKey] as? Int {
                level = Double(capacity)
            } else if let capacity = desc[kIOPSCurrentCapacityKey] as? Double {
                level = capacity
            }
        }

        if !onBattery && list.isEmpty {
            onBattery = ProcessInfo.processInfo.isLowPowerModeEnabled
        }

        return Snapshot(isOnBattery: onBattery, levelPercent: level)
    }

    /// Adds an IOPS run-loop source and observes `NSProcessInfoPowerStateDidChange`.
    /// The returned stop token is idempotent.
    public static func start(_ onChange: @escaping @Sendable () -> Void) -> Stop {
        let observation = PowerSourceObservation(onChange: onChange)
        let context = Unmanaged.passUnretained(observation).toOpaque()

        if let created = IOPSNotificationCreateRunLoopSource(powerSourceCallback, context) {
            let source = created.takeRetainedValue()
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, source, .defaultMode)
            observation.source = source
            observation.runLoop = loop
        }

        observation.powerStateObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("NSProcessInfoPowerStateDidChange"),
            object: nil,
            queue: .main
        ) { [weak observation] _ in
            observation?.fire()
        }

        return { observation.stop() }
    }
}

private final class PowerSourceObservation: @unchecked Sendable {
    let onChange: @Sendable () -> Void
    var source: CFRunLoopSource?
    var runLoop: CFRunLoop?
    var powerStateObserver: NSObjectProtocol?
    private var stopped = false

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func fire() {
        onChange()
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        if let source {
            CFRunLoopRemoveSource(runLoop ?? CFRunLoopGetCurrent(), source, .defaultMode)
            self.source = nil
            self.runLoop = nil
        }
        if let observer = powerStateObserver {
            NotificationCenter.default.removeObserver(observer)
            powerStateObserver = nil
        }
    }
}

private let powerSourceCallback: IOPowerSourceCallbackType = { context in
    guard let context else { return }
    Unmanaged<PowerSourceObservation>.fromOpaque(context).takeUnretainedValue().fire()
}

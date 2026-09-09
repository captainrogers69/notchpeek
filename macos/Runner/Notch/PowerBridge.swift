import Foundation
import IOKit.ps

/// Battery percentage and the charging edge. Cheap: IOKit posts a run-loop
/// source when anything changes, so there is no polling here at all.
final class PowerBridge {

    private let onChange: ([String: Any]) -> Void
    private var runLoopSource: CFRunLoopSource?
    private var last: [String: Any]?

    init(onChange: @escaping ([String: Any]) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard runLoopSource == nil else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard
            let source = IOPSNotificationCreateRunLoopSource(
                { context in
                    guard let context else { return }
                    Unmanaged<PowerBridge>.fromOpaque(context)
                        .takeUnretainedValue()
                        .emit()
                }, context)?.takeRetainedValue()
        else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
        emit()
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
    }

    private func emit() {
        let snapshot = PowerBridge.snapshot()
        // IOKit fires for things we do not care about. Only report changes.
        guard !NSDictionary(dictionary: snapshot).isEqual(to: last ?? [:]) else {
            return
        }
        last = snapshot
        onChange(snapshot)
    }

    /// A Mac with no battery reports `isPresent: false` rather than 0% — a
    /// desktop is not a laptop that is flat.
    static func snapshot() -> [String: Any] {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue()
                as? [CFTypeRef],
            let first = sources.first,
            let description = IOPSGetPowerSourceDescription(blob, first)?
                .takeUnretainedValue() as? [String: Any]
        else {
            return ["isPresent": false, "percent": 0, "isCharging": false]
        }

        let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
        let percent = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : 0

        return [
            "isPresent": true,
            "percent": percent,
            "isCharging": (description[kIOPSIsChargingKey] as? Bool) ?? false,
        ]
    }

    deinit { stop() }
}

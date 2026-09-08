import Foundation

/// Channel names live in exactly one Swift file and one Dart file
/// (`lib/core/platform/channels.dart`). Never a string literal at a call site.
///
/// Later milestones **extend** this set. They do not redesign it: one method
/// channel for all commands, one event channel per data domain.
enum NotchChannel {
    static let control = "notchpeek/control"
    static let media = "notchpeek/media"
    static let system = "notchpeek/system"
    /// Reserved for M2. Declared now so the set is fixed in M1.
    static let calendar = "notchpeek/calendar"
}

/// Every method Dart may invoke on `NotchChannel.control`.
enum ControlMethod {
    static let setInteractiveRect = "setInteractiveRect"
    static let mediaCommand = "mediaCommand"
    static let openSettings = "openSettings"
    static let requestPermission = "requestPermission"
    static let getCapabilities = "getCapabilities"
    static let haptic = "haptic"
}

/// Every event kind that crosses `NotchChannel.system`.
enum SystemEvent {
    static let geometry = "geometry"
    static let power = "power"
    static let capabilities = "capabilities"
    /// Whether the cursor is inside the rect Dart last reported. `MouseGate`
    /// is the only thing that can answer this correctly, so it answers it.
    static let hover = "hover"
}

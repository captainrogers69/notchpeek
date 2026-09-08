import AVFoundation
import AppKit
import EventKit

/// Answers what this build, this OS version and these permissions can do.
/// Nothing here decides what to *show* — that is a Dart decision.
enum CapabilityProbe {

    static func snapshot() -> [String: Any] {
        [
            "buildFlavor": buildFlavor,
            // The OS floor is macOS 26, so this is unconditionally true. The
            // field stays because M4 reads it and because a lowered floor
            // later must not change the payload's shape (R1).
            "osSupportsOnDeviceAI": true,
            "scriptingMedia": [
                "appleMusic": appleEventsState(for: BundleId.appleMusic),
                "spotify": appleEventsState(for: BundleId.spotify),
            ],
            // Gated on macOS 26: the info dictionary comes back empty, the
            // client is nil, no notifications fire — and it fails *silently*
            // (spike §1). Kept so it flips if Apple reopens the read path.
            "systemWideMediaRead": false,
            // Writes do land, but M1 commands through scripting (spec §2, §9).
            "systemWideMediaCommand": buildFlavor == "direct",
            // Permission state alone cannot drive the panel: macOS raises no
            // prompt for a player that is not running
            // (`AEDeterminePermissionToAutomateTarget` answers `procNotFound`),
            // so the panel has to be able to say "start a player first".
            "playersRunning": installedPlayers.contains(where: isRunning),
            "calendar": calendarState,
            "camera": cameraState,
        ]
    }

    /// Only the players this Mac actually has. Never launches anything.
    static var installedPlayers: [String] {
        [BundleId.appleMusic, BundleId.spotify].filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }
    }

    static func isRunning(_ bundleId: String) -> Bool {
        !NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleId)
            .isEmpty
    }

    /// The two players M1 knows about. String literals for these belong here
    /// and nowhere else.
    enum BundleId {
        static let appleMusic = "com.apple.Music"
        static let spotify = "com.spotify.client"
    }

    /// M1 only ever builds `direct`. The MAS build differs in what it may call
    /// (spike §4.3), so the field exists from the start.
    static var buildFlavor: String { "direct" }

    /// `notDetermined` until the user has been asked, then `granted`/`denied`.
    /// An app that is not installed reports `absent` — a panel hides for that,
    /// rather than teasing a player the user does not have.
    static func appleEventsState(for bundleId: String) -> String {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
        else {
            return "absent"
        }

        var target = AEAddressDesc()
        let bytes = Array(bundleId.utf8)
        let created = AECreateDesc(
            typeApplicationBundleID, bytes, bytes.count, &target
        )
        guard created == OSErr(noErr) else { return "notDetermined" }
        defer { AEDisposeDesc(&target) }

        // askUserIfNeeded: false — the probe must never prompt. Prompting is
        // `requestAppleEvents`'s job, and only on the user's action.
        switch AEDeterminePermissionToAutomateTarget(
            &target, typeWildCard, typeWildCard, false
        ) {
        case noErr: return "granted"
        case OSStatus(errAEEventNotPermitted): return "denied"
        case OSStatus(procNotFound): return "notDetermined"
        default: return "notDetermined"
        }
    }

    /// Prompts, and **blocks until the user answers** — never call it on the
    /// main thread or the panel freezes behind the sheet. macOS raises nothing
    /// for a player that is not running.
    static func requestAppleEvents(for bundleId: String) {
        var target = AEAddressDesc()
        let bytes = Array(bundleId.utf8)
        guard AECreateDesc(typeApplicationBundleID, bytes, bytes.count, &target)
            == OSErr(noErr)
        else { return }
        defer { AEDisposeDesc(&target) }
        _ = AEDeterminePermissionToAutomateTarget(
            &target, typeWildCard, typeWildCard, true)
    }

    /// Opens the pane the user needs. macOS gives no API to un-deny.
    static func openAutomationSettings() {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
            )
        else { return }
        NSWorkspace.shared.open(url)
    }

    // M2 and M3 read these; they are reported from M1 so the shape never churns.

    private static var calendarState: String {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return "granted"
        case .denied, .restricted, .writeOnly: return "denied"
        default: return "notDetermined"
        }
    }

    private static var cameraState: String {
        guard AVCaptureDevice.default(for: .video) != nil else { return "absent" }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return "granted"
        case .denied, .restricted: return "denied"
        default: return "notDetermined"
        }
    }
}

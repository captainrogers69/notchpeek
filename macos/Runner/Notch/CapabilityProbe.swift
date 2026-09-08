import AVFoundation
import AppKit
import EventKit

/// Answers what this build, this OS version and these permissions can do.
/// Nothing here decides what to *show* — that is a Dart decision.
enum CapabilityProbe {

    /// The two players M1 knows about, and the payload key each answers under.
    private static let players: [(key: String, bundleId: String)] = [
        ("appleMusic", BundleId.appleMusic),
        ("spotify", BundleId.spotify),
    ]

    /// **Never blocks.** Nothing here sends an Apple Event: the permission
    /// answer comes from what the last real read discovered, and everything
    /// else is a cheap Launch Services or process lookup.
    ///
    /// It used to ask `AEDeterminePermissionToAutomateTarget` directly, which
    /// parks on a semaphore indefinitely once the target app is running. A
    /// thread sample caught it there with Spotify open, and moving it to a
    /// background queue only relocated the problem — the queue then wedged and
    /// no capability snapshot was ever pushed again, so the panel sat on its
    /// launch-time answer while Apple Music was plainly open.
    static func snapshot() -> [String: Any] {
        var scripting: [String: String] = [:]
        for player in players {
            scripting[player.key] = appleEventsState(for: player.bundleId)
        }
        return payload(scripting: scripting)
    }

    private static func payload(scripting: [String: String]) -> [String: Any] {
        [
            "buildFlavor": buildFlavor,
            // The OS floor is macOS 26, so this is unconditionally true. The
            // field stays because M4 reads it and because a lowered floor
            // later must not change the payload's shape (R1).
            "osSupportsOnDeviceAI": true,
            "scriptingMedia": scripting,
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
            // *Which* players are running, not just whether any is. The panel
            // needs a target to send a command to, or to bring forward, and a
            // bare bool cannot name one.
            "runningPlayers": players
                .filter { isInstalled($0.bundleId) && isRunning($0.bundleId) }
                .map(\.key),
            "calendar": calendarState,
            "camera": cameraState,
        ]
    }

    /// Only the players this Mac actually has. Never launches anything.
    static var installedPlayers: [String] {
        players.map(\.bundleId).filter(isInstalled)
    }

    static func isInstalled(_ bundleId: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
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

    /// `notDetermined` until a read has actually been attempted, then
    /// `granted`/`denied` as that read discovered. An app that is not
    /// installed reports `absent` — a panel hides for that, rather than
    /// teasing a player the user does not have.
    static func appleEventsState(for bundleId: String) -> String {
        guard isInstalled(bundleId) else { return "absent" }
        return remembered(for: bundleId) ?? "notDetermined"
    }

    /// TCC state cannot be read for an app that is not running:
    /// `AEDeterminePermissionToAutomateTarget` answers `procNotFound` whether
    /// the user granted access months ago or has never been asked. Recording
    /// the last definitive answer is the only way to tell a granted-but-quit
    /// player from an unasked one — otherwise quitting Spotify puts the panel
    /// back to asking for permission it already has.
    ///
    /// A stale entry — access revoked in System Settings while the player was
    /// closed — corrects itself the moment the player runs again.
    static func remembered(for bundleId: String) -> String? {
        UserDefaults.standard.string(forKey: "automation.\(bundleId)")
    }

    /// Recorded by whoever actually talked to the player. Fires
    /// [onPermissionChanged] only on a change, so a 1 Hz poll that keeps
    /// succeeding does not push a snapshot every second.
    static func remember(_ state: String, for bundleId: String) {
        guard remembered(for: bundleId) != state else { return }
        UserDefaults.standard.set(state, forKey: "automation.\(bundleId)")
        DispatchQueue.main.async { onPermissionChanged?() }
    }

    /// Set by `AppDelegate`: a permission answer that arrives from a read has
    /// to reach the panel, or it waits for the next app switch to find out.
    static var onPermissionChanged: (() -> Void)?

    /// Brings a player to the front, launching it if it is not running. Only
    /// ever called from the panel's own button — nothing here launches a
    /// player to answer a question about it.
    static func openPlayer(_ bundleId: String) {
        guard
            let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleId)
        else { return }
        NSWorkspace.shared.openApplication(
            at: url, configuration: NSWorkspace.OpenConfiguration())
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

        // The one place a blocking Apple Event call is right: the user asked
        // for it, it is on a background queue, and a prompt is the point.
        switch AEDeterminePermissionToAutomateTarget(
            &target, typeWildCard, typeWildCard, true)
        {
        case noErr: remember("granted", for: bundleId)
        case OSStatus(errAEEventNotPermitted): remember("denied", for: bundleId)
        default: break
        }
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

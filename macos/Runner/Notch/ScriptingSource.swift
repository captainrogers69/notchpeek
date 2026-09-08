import AppKit
import ScriptingBridge

/// Shared machinery for the two scripted players. Holds the `SBApplication`
/// and reads properties by key, so no generated `sdef` headers are needed and
/// nothing of the players' own interfaces is transcribed into this repo (R9).
///
/// **Every call here must run off the main thread.** `MediaBridge` owns that
/// queue; this class does not hop for you.
class ScriptingSource: MusicSource {

    let sourceId: String
    let bundleIdentifier: String

    init(sourceId: String, bundleIdentifier: String) {
        self.sourceId = sourceId
        self.bundleIdentifier = bundleIdentifier
    }

    /// Never launches the player: `SBApplication` would happily start it, and
    /// an app that opens Spotify because you looked at the notch is a bug.
    var isRunning: Bool {
        !NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .isEmpty
    }

    private var app: SBApplication? {
        guard isRunning else { return nil }
        let app = SBApplication(bundleIdentifier: bundleIdentifier)
        // A hung player must not hang the poll.
        app?.timeout = 2 * 60  // ticks; 2 seconds
        // `AESendMode` is a bare Int32, so the constant is the only spelling.
        app?.sendMode = AESendMode(kAEWaitReply)
        return app
    }

    func read() -> NowPlayingPayload? {
        guard let app else { return nil }

        // The read is also how permission is discovered. Asking
        // `AEDeterminePermissionToAutomateTarget` instead parks forever once
        // the player is running; this call has a 2 second timeout and has to
        // happen anyway.
        let trap = ScriptingErrorTrap()
        app.delegate = trap
        let payload = read(from: app)

        if trap.wasRefused {
            CapabilityProbe.remember("denied", for: bundleIdentifier)
            return nil
        }
        if payload != nil {
            CapabilityProbe.remember("granted", for: bundleIdentifier)
        }
        return payload
    }

    /// Overridden per player.
    func read(from app: SBApplication) -> NowPlayingPayload? { nil }

    /// A player that is running and answering, with nothing loaded. Distinct
    /// from `nil`, which means we could not read it at all — reporting idle as
    /// unavailable is the misdiagnosis spec §7 exists to prevent.
    func idle(state: String) -> NowPlayingPayload {
        NowPlayingPayload(
            sourceId: sourceId,
            trackId: "",
            title: "",
            artist: "",
            album: "",
            duration: 0,
            position: 0,
            state: state,
            artworkPath: nil
        )
    }

    /// `playerState` doubles as the access probe: a player we are not allowed
    /// to automate answers nothing at all, so an unreadable state means
    /// unavailable rather than idle.
    func playerState(of app: SBApplication) -> String? {
        let state = MediaUnits.playbackState(
            fromFourCharCode: fourCharCode(app, "playerState"))
        return state == "unknown" ? nil : state
    }

    func send(command: String, seekTo: TimeInterval?) {
        guard let app else { return }
        switch command {
        case "playPause": _ = app.perform(Selector(("playpause")))
        case "next": _ = app.perform(Selector(("nextTrack")))
        case "previous": _ = app.perform(Selector(("previousTrack")))
        case "seek":
            guard let seekTo else { return }
            app.setValue(seekTo, forKey: positionKey)
        default: break
        }
    }

    /// Spotify calls it `playerPosition`; Music calls it `playerPosition` too,
    /// but the override point stays for the next source that does not.
    var positionKey: String { "playerPosition" }

    // MARK: - KVC helpers

    func string(_ object: NSObject?, _ key: String) -> String {
        (object?.value(forKey: key) as? String) ?? ""
    }

    func double(_ object: NSObject?, _ key: String) -> Double {
        (object?.value(forKey: key) as? NSNumber)?.doubleValue ?? 0
    }

    /// ScriptingBridge hands an sdef `enumerated` property back as an
    /// `NSNumber` when it can map the type and as an `NSAppleEventDescriptor`
    /// when it cannot. Reading only the first would report every player as
    /// `unknown`, which silently disables the whole transport row — so both
    /// are handled.
    func fourCharCode(_ object: NSObject?, _ key: String) -> UInt32 {
        let value = object?.value(forKey: key)
        if let number = value as? NSNumber { return number.uint32Value }
        if let descriptor = value as? NSAppleEventDescriptor {
            return descriptor.typeCodeValue != 0
                ? descriptor.typeCodeValue
                : descriptor.enumCodeValue
        }
        return 0
    }

    func object(_ object: NSObject?, _ key: String) -> NSObject? {
        object?.value(forKey: key) as? NSObject
    }
}

/// Catches the one Apple Event error that matters: `errAEEventNotPermitted`,
/// which is how a refused automation request comes back. ScriptingBridge
/// otherwise swallows failures and hands back nil, which is indistinguishable
/// from "nothing playing".
private final class ScriptingErrorTrap: NSObject, SBApplicationDelegate {
    private(set) var wasRefused = false

    func eventDidFail(
        _ event: UnsafePointer<AppleEvent>, withError error: any Error
    ) -> Any? {
        if (error as NSError).code == Int(errAEEventNotPermitted) {
            wasRefused = true
        }
        return nil
    }
}

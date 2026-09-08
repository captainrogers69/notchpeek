import Foundation

/// One shape for Dart, whatever the source did. Times are **always seconds**;
/// artwork is **always a local file path**, never bytes and never a remote URL
/// (architecture-playbook §4.2).
struct NowPlayingPayload: Equatable {
    let sourceId: String
    /// Stable per track. The key for the artwork cache, and the thing that
    /// decides whether a peek fires.
    let trackId: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let position: TimeInterval
    let state: String
    let artworkPath: String?

    var channelMap: [String: Any] {
        var map: [String: Any] = [
            "sourceId": sourceId,
            "trackId": trackId,
            "title": title,
            "artist": artist,
            "album": album,
            "durationSeconds": duration,
            "positionSeconds": position,
            "state": state,
        ]
        if let artworkPath { map["artworkPath"] = artworkPath }
        return map
    }

    /// A tick carries no artwork. Artwork crosses once per track change; the
    /// tick fires about twice a second, and shipping an image through it would
    /// eat the app's whole CPU budget (spec §3.5).
    var tickMap: [String: Any] {
        [
            "sourceId": sourceId,
            "trackId": trackId,
            "positionSeconds": position,
            "state": state,
            "isTick": true,
        ]
    }
}

/// `MediaBridge` is the only thing that talks to these. The strategy choice —
/// which player, how it is read — hides behind this protocol.
protocol MusicSource: AnyObject {
    var sourceId: String { get }
    var bundleIdentifier: String { get }
    /// True only if the app is already running. **Never launch a player** to
    /// answer a question about it.
    var isRunning: Bool { get }
    /// Nil means *unavailable*, never *nothing playing* (spec §7).
    func read() -> NowPlayingPayload?
    func send(command: String, seekTo: TimeInterval?)
}

/// The normalizations that belong in Swift so Dart sees one shape. Every one
/// of these is a bug that has already been written somewhere.
enum MediaUnits {

    /// Spotify's `duration of current track` is milliseconds while its
    /// `player position` is fractional seconds. Same object, different units.
    static func seconds(fromMilliseconds ms: Double) -> TimeInterval {
        ms / 1000
    }

    /// A zero duration means "we could not read it" — clamping to it would
    /// report every track as finished.
    static func clamp(position: TimeInterval, duration: TimeInterval) -> TimeInterval {
        if position < 0 { return 0 }
        if duration > 0, position > duration { return duration }
        return position
    }

    /// Both players use the same `EPlS` four-char codes.
    static func playbackState(fromFourCharCode code: UInt32) -> String {
        switch code {
        case 0x6B50_5350: return "playing"  // 'kPSP'
        case 0x6B50_5370: return "paused"  // 'kPSp'
        case 0x6B50_5353: return "stopped"  // 'kPSS'
        default: return "unknown"
        }
    }
}

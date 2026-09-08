import Foundation
import ScriptingBridge

/// Reads Apple Music. Times are already seconds here; artwork arrives as
/// **bytes**, so the cache writes it out and hands Dart the same file-path
/// shape Spotify's URL ends up as.
///
/// **Not covered by spike 0** — the spike machine's library was empty, so
/// `current track` errored with -1700. This path needs a manual check on a
/// machine with a library or an active subscription (spike §3).
final class AppleMusicSource: ScriptingSource {

    init() {
        super.init(sourceId: "appleMusic", bundleIdentifier: "com.apple.Music")
    }

    override func read(from app: SBApplication) -> NowPlayingPayload? {
        guard let state = playerState(of: app) else { return nil }

        guard let track = object(app, "currentTrack") else {
            return idle(state: state)
        }

        // Music's persistent id is stable across launches; `databaseID` is not
        // unique for streamed tracks, so fall back to a composed key.
        var trackId = string(track, "persistentID")
        if trackId.isEmpty {
            trackId =
                "\(string(track, "name"))|\(string(track, "artist"))|\(string(track, "album"))"
        }
        guard trackId != "||" else { return idle(state: state) }

        let duration = double(track, "duration")  // already seconds
        let position = MediaUnits.clamp(
            position: double(app, "playerPosition"),
            duration: duration
        )

        let artwork = ArtworkCache.resolve(
            trackId: trackId,
            data: firstArtworkData(of: track)
        )

        return NowPlayingPayload(
            sourceId: sourceId,
            trackId: trackId,
            title: string(track, "name"),
            artist: string(track, "artist"),
            album: string(track, "album"),
            duration: duration,
            position: position,
            state: state,
            artworkPath: artwork
        )
    }

    /// Only called when the cache misses — pulling image bytes across Apple
    /// Events is the most expensive read in the app.
    private func firstArtworkData(of track: NSObject) -> Data? {
        guard let artworks = track.value(forKey: "artworks") as? SBElementArray,
            let first = artworks.firstObject as? NSObject,
            let data = first.value(forKey: "rawData") as? Data,
            !data.isEmpty
        else { return nil }
        return data
    }
}

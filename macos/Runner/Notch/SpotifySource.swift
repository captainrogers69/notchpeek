import ScriptingBridge

/// Reads Spotify. Every field the music panel needs is in its scripting
/// dictionary, including artwork — as a URL, not bytes (spike §3).
final class SpotifySource: ScriptingSource {

    init() {
        super.init(sourceId: "spotify", bundleIdentifier: "com.spotify.client")
    }

    override func read(from app: SBApplication) -> NowPlayingPayload? {
        guard let track = object(app, "currentTrack") else { return nil }

        let trackId = string(track, "id")
        guard !trackId.isEmpty else { return nil }

        // The unit trap, in one place: duration is milliseconds, position is
        // fractional seconds, on the same object.
        let duration = MediaUnits.seconds(fromMilliseconds: double(track, "duration"))
        let position = MediaUnits.clamp(
            position: double(app, "playerPosition"),
            duration: duration
        )

        // Artwork is a URL here. Resolving it to a file is the cache's job, and
        // it happens once per track id — never on a tick.
        let artwork = ArtworkCache.resolve(
            trackId: trackId,
            remoteURL: string(track, "artworkUrl")
        )

        return NowPlayingPayload(
            sourceId: sourceId,
            trackId: trackId,
            title: string(track, "name"),
            artist: string(track, "artist"),
            album: string(track, "album"),
            duration: duration,
            position: position,
            state: MediaUnits.playbackState(
                fromFourCharCode: fourCharCode(app, "playerState")),
            artworkPath: artwork
        )
    }
}

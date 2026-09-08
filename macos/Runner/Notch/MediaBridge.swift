import AppKit

/// Selects the active player, emits now-playing updates, and routes transport
/// commands. Holds no product logic: it does not decide what the panel shows.
final class MediaBridge {

    private let sources: [MusicSource]
    /// Every scripting call runs here. **Never on the main thread**
    /// (architecture-playbook §4.3).
    private let queue = DispatchQueue(label: "com.capcraft.notchpeek.media")
    private var ticker: DispatchSourceTimer?
    private var lastTrackId: String?
    private var observers: [NSObjectProtocol] = []

    var onUpdate: (([String: Any]) -> Void)?

    init(sources: [MusicSource]) {
        self.sources = sources
    }

    convenience init() {
        self.init(sources: [AppleMusicSource(), SpotifySource()])
    }

    /// A source that is *playing* wins. Otherwise any running source that can
    /// actually be read. A running source whose read comes back empty is
    /// **unavailable**, not idle (spec §7).
    static func select(from sources: [MusicSource]) -> MusicSource? {
        readable(from: sources)?.0
    }

    /// Reads each running source **once** and keeps the payload. Every read is
    /// an Apple Event round trip and this runs at 1 Hz, so re-reading to ask a
    /// second question about the same source is not free (spike §3).
    private static func readable(from sources: [MusicSource])
        -> (MusicSource, NowPlayingPayload)?
    {
        let readable = sources.compactMap {
            source -> (MusicSource, NowPlayingPayload)? in
            guard source.isRunning, let payload = source.read() else { return nil }
            return (source, payload)
        }
        return readable.first { $0.1.state == "playing" } ?? readable.first
    }

    func start() {
        // Track changes arrive as distributed notifications, so a collapsed
        // notch costs nothing and still peeks (spec §9, playbook §4.3).
        for name in [
            "com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged",
        ] {
            observers.append(
                DistributedNotificationCenter.default().addObserver(
                    forName: Notification.Name(name), object: nil, queue: nil
                ) { [weak self] _ in
                    self?.queue.async { self?.refresh() }
                }
            )
        }

        // The whole body runs on `queue`: `lastTrackId` belongs to that queue,
        // and this callback arrives on the artwork queue.
        ArtworkCache.onArtworkReady = { [weak self] trackId in
            guard let self else { return }
            self.queue.async {
                guard self.lastTrackId == trackId else { return }
                // Force the next emit to be a full payload so the panel picks
                // up the image that just landed.
                self.lastTrackId = nil
                self.refresh()
            }
        }

        queue.async { [weak self] in self?.refresh() }
    }

    func stop() {
        setPolling(false)
        observers.forEach(DistributedNotificationCenter.default().removeObserver)
        observers.removeAll()
    }

    /// Poll at 1 Hz while the panel is showing, and not at all while it is
    /// collapsed. Position polling is the single most expensive thing the app
    /// does (spike §3).
    func setPolling(_ enabled: Bool) {
        ticker?.cancel()
        ticker = nil
        guard enabled else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.refresh() }
        timer.resume()
        ticker = timer
    }

    func command(_ payload: [String: Any]) {
        guard let command = payload["command"] as? String else { return }
        let seconds = payload["seconds"] as? Double

        queue.async { [weak self] in
            guard let self, let source = MediaBridge.select(from: self.sources)
            else { return }
            source.send(command: command, seekTo: seconds)
            // Read straight back so the UI does not wait a tick to catch up.
            self.refresh()
        }
    }

    /// Reads the active source once and emits. Full payload on a track change,
    /// a tick otherwise — **artwork never crosses on a tick** (spec §3.5).
    func refresh() {
        guard let (_, payload) = MediaBridge.readable(from: sources) else {
            lastTrackId = nil
            onUpdate?(["available": false])
            return
        }

        if payload.trackId != lastTrackId {
            lastTrackId = payload.trackId
            var map = payload.channelMap
            map["available"] = true
            map["trackChanged"] = true
            onUpdate?(map)
            ArtworkCache.prune()
        } else {
            var map = payload.tickMap
            map["available"] = true
            onUpdate?(map)
        }
    }

    deinit { stop() }
}

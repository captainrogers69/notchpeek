import CryptoKit
import Foundation

/// One artwork shape for Dart: a local file path, keyed by track id. Spotify
/// gives a URL and Apple Music gives bytes; both end up here (spec §4).
///
/// Swift owns storage. Dart never touches persistence
/// (architecture-playbook §4.2).
enum ArtworkCache {

    private static let queue = DispatchQueue(label: "com.capcraft.notchpeek.artwork")

    private static var directory: URL? {
        guard
            let base = FileManager.default.urls(
                for: .cachesDirectory, in: .userDomainMask
            ).first
        else { return nil }
        let dir = base.appendingPathComponent(
            "com.capcraft.notchpeek/artwork", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(for trackId: String) -> URL? {
        // Track ids contain colons and slashes. Hash rather than sanitize.
        let digest = SHA256.hash(data: Data(trackId.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory?.appendingPathComponent("\(name).img")
    }

    static func cachedPath(forTrackId trackId: String) -> String? {
        guard let url = fileURL(for: trackId),
            FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url.path
    }

    /// Spotify's path: a remote URL. Returns the cached path immediately if we
    /// have it, and otherwise nil while the download runs — **never block the
    /// track update on the image** (spec §7).
    @discardableResult
    static func resolve(trackId: String, remoteURL: String) -> String? {
        if let hit = cachedPath(forTrackId: trackId) { return hit }
        guard !remoteURL.isEmpty, let url = URL(string: remoteURL) else { return nil }

        queue.async {
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { return }
            store(data: data, forTrackId: trackId)
            onArtworkReady?(trackId)
        }
        return nil
    }

    /// Apple Music's path: raw bytes, already in hand.
    @discardableResult
    static func resolve(trackId: String, data: Data?) -> String? {
        if let hit = cachedPath(forTrackId: trackId) { return hit }
        guard let data, !data.isEmpty else { return nil }
        return store(data: data, forTrackId: trackId)
    }

    /// Set by `MediaBridge`: a late-arriving download re-emits the track so the
    /// panel swaps its placeholder for the real image.
    static var onArtworkReady: ((String) -> Void)?

    @discardableResult
    static func store(data: Data, forTrackId trackId: String) -> String? {
        guard let url = fileURL(for: trackId) else { return nil }
        try? data.write(to: url, options: .atomic)
        return url.path
    }

    /// Keeps the cache from growing without bound over a long session.
    static func prune(keeping limit: Int = 200) {
        queue.async {
            guard let directory,
                let files = try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.contentAccessDateKey]
                ), files.count > limit
            else { return }

            let sorted = files.sorted {
                let a =
                    (try? $0.resourceValues(forKeys: [.contentAccessDateKey])
                        .contentAccessDate) ?? .distantPast
                let b =
                    (try? $1.resourceValues(forKeys: [.contentAccessDateKey])
                        .contentAccessDate) ?? .distantPast
                return a < b
            }
            for url in sorted.prefix(files.count - limit) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

import XCTest

@testable import NotchPeek

private final class StubSource: MusicSource {
    let sourceId: String
    let bundleIdentifier = "stub"
    var isRunning: Bool
    var payload: NowPlayingPayload?
    var sent: [(String, TimeInterval?)] = []
    var reads = 0

    /// `MediaBridge.command` dispatches onto its own queue, so a test that
    /// asserts straight after the call is racing it.
    var onSend: (() -> Void)?

    init(sourceId: String, isRunning: Bool, state: String?) {
        self.sourceId = sourceId
        self.isRunning = isRunning
        if let state {
            payload = NowPlayingPayload(
                sourceId: sourceId, trackId: "\(sourceId)-1", title: "t",
                artist: "a", album: "b", duration: 100, position: 10,
                state: state, artworkPath: nil
            )
        }
    }

    func read() -> NowPlayingPayload? {
        reads += 1
        return payload
    }

    func send(command: String, seekTo: TimeInterval?) {
        sent.append((command, seekTo))
        onSend?()
    }
}

final class MediaBridgeTests: XCTestCase {

    func testPrefersASourceThatIsActuallyPlaying() {
        let music = StubSource(sourceId: "appleMusic", isRunning: true, state: "paused")
        let spotify = StubSource(sourceId: "spotify", isRunning: true, state: "playing")

        XCTAssertEqual(MediaBridge.select(from: [music, spotify])?.sourceId, "spotify")
    }

    func testFallsBackToARunningButPausedSource() {
        let music = StubSource(sourceId: "appleMusic", isRunning: true, state: "paused")
        let spotify = StubSource(sourceId: "spotify", isRunning: false, state: nil)

        XCTAssertEqual(
            MediaBridge.select(from: [music, spotify])?.sourceId, "appleMusic")
    }

    func testIgnoresSourcesThatAreNotRunning() {
        let music = StubSource(sourceId: "appleMusic", isRunning: false, state: "playing")

        XCTAssertNil(MediaBridge.select(from: [music]))
    }

    /// An empty read means *unavailable*, never *nothing playing* — the
    /// macOS 26 wall fails silently, and this is exactly where it would be
    /// misdiagnosed (spike §2, spec §7).
    func testARunningSourceThatReadsNothingIsNotSelected() {
        let music = StubSource(sourceId: "appleMusic", isRunning: true, state: nil)

        XCTAssertNil(MediaBridge.select(from: [music]))
    }

    /// Every read is an Apple Event round trip, and position polling is the
    /// most expensive thing this app does (spike §3). Selecting must not read
    /// a source more than once.
    func testSelectionReadsEachSourceAtMostOnce() {
        let music = StubSource(sourceId: "appleMusic", isRunning: true, state: "paused")
        let spotify = StubSource(sourceId: "spotify", isRunning: true, state: "playing")

        _ = MediaBridge.select(from: [music, spotify])

        XCTAssertEqual(music.reads, 1)
        XCTAssertEqual(spotify.reads, 1)
    }

    func testRoutesACommandToTheActiveSource() {
        let spotify = StubSource(sourceId: "spotify", isRunning: true, state: "playing")
        let bridge = MediaBridge(sources: [spotify])

        let sent = expectation(description: "command reached the source")
        spotify.onSend = { sent.fulfill() }

        bridge.command(["command": "seek", "seconds": 42.0])
        wait(for: [sent], timeout: 2)

        XCTAssertEqual(spotify.sent.count, 1)
        XCTAssertEqual(spotify.sent.first?.0, "seek")
        XCTAssertEqual(spotify.sent.first?.1, 42)
    }

    /// A running player that cannot be read still takes commands. Requiring a
    /// readable source is why play did nothing in the "Not Playing" state.
    func testRoutesACommandToARunningSourceThatCannotBeRead() {
        let spotify = StubSource(sourceId: "spotify", isRunning: true, state: nil)
        let bridge = MediaBridge(sources: [spotify])

        let sent = expectation(description: "command reached the source")
        spotify.onSend = { sent.fulfill() }

        bridge.command(["command": "playPause"])
        wait(for: [sent], timeout: 2)

        XCTAssertEqual(spotify.sent.first?.0, "playPause")
    }

    func testDropsACommandWhenNoPlayerIsRunningAtAll() {
        let spotify = StubSource(sourceId: "spotify", isRunning: false, state: nil)
        let bridge = MediaBridge(sources: [spotify])

        bridge.command(["command": "playPause"])
        // Nothing to wait for; give the queue a moment to be sure.
        let idle = expectation(description: "queue drained")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { idle.fulfill() }
        wait(for: [idle], timeout: 2)

        XCTAssertTrue(spotify.sent.isEmpty)
    }

    func testAnUnknownCommandIsIgnoredRatherThanCrashing() {
        let spotify = StubSource(sourceId: "spotify", isRunning: true, state: "playing")
        let bridge = MediaBridge(sources: [spotify])

        let sent = expectation(description: "command reached the source")
        spotify.onSend = { sent.fulfill() }

        bridge.command(["command": "selfDestruct"])
        wait(for: [sent], timeout: 2)

        XCTAssertEqual(spotify.sent.count, 1)
        XCTAssertEqual(
            spotify.sent.first?.0, "selfDestruct",
            "routing is the bridge's job; validation is the source's")
    }

    func testEmitsAFullPayloadOnTrackChangeAndATickOtherwise() {
        let spotify = StubSource(sourceId: "spotify", isRunning: true, state: "playing")
        let bridge = MediaBridge(sources: [spotify])

        var emitted: [[String: Any]] = []
        bridge.onUpdate = { emitted.append($0) }

        bridge.refresh()
        bridge.refresh()

        XCTAssertEqual(emitted.count, 2)
        XCTAssertNil(emitted[0]["isTick"], "the first read of a track is a full payload")
        XCTAssertEqual(
            emitted[1]["isTick"] as? Bool, true, "the same track again is a tick")
    }

    /// A running player with nothing loaded is **idle**, and the panel should
    /// say "Nothing playing". Reporting it as unavailable is the exact
    /// misdiagnosis spec §7 exists to prevent — and it is what `SpotifySource`
    /// did by returning nil for an empty track id.
    func testAnIdleSourceIsAvailableRatherThanUnavailable() {
        let spotify = StubSource(sourceId: "spotify", isRunning: true, state: "stopped")
        spotify.payload = NowPlayingPayload(
            sourceId: "spotify", trackId: "", title: "", artist: "", album: "",
            duration: 0, position: 0, state: "stopped", artworkPath: nil
        )
        let bridge = MediaBridge(sources: [spotify])

        var emitted: [[String: Any]] = []
        bridge.onUpdate = { emitted.append($0) }

        bridge.refresh()

        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(emitted[0]["available"] as? Bool, true)
        XCTAssertEqual(emitted[0]["trackId"] as? String, "")
    }

    /// A player that is running and cannot be read is the silent macOS 26
    /// wall, and the panel must say so rather than pretending all is well.
    func testARunningSourceThatCannotBeReadIsUnavailable() {
        let bridge = MediaBridge(sources: [
            StubSource(sourceId: "spotify", isRunning: true, state: nil)
        ])

        var emitted: [[String: Any]] = []
        bridge.onUpdate = { emitted.append($0) }

        bridge.refresh()

        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(emitted[0]["available"] as? Bool, false)
    }

    /// Nothing running is **not** a failed read: there is nothing to read.
    /// Reporting it as unavailable put "Player unavailable" on screen the
    /// moment the user quit Spotify.
    func testNoPlayerRunningIsIdleRatherThanUnavailable() {
        let bridge = MediaBridge(sources: [
            StubSource(sourceId: "spotify", isRunning: false, state: nil)
        ])

        var emitted: [[String: Any]] = []
        bridge.onUpdate = { emitted.append($0) }

        bridge.refresh()

        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(emitted[0]["available"] as? Bool, true)
        XCTAssertEqual(emitted[0]["trackId"] as? String, "")
    }
}

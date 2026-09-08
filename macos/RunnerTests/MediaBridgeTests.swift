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

    func testEmitsAnUnavailablePayloadWhenNoSourceCanBeRead() {
        let bridge = MediaBridge(sources: [
            StubSource(sourceId: "spotify", isRunning: false, state: nil)
        ])

        var emitted: [[String: Any]] = []
        bridge.onUpdate = { emitted.append($0) }

        bridge.refresh()

        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(emitted[0]["available"] as? Bool, false)
    }
}

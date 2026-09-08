import XCTest

@testable import NotchPeek

final class MusicSourceTests: XCTestCase {

    func testConvertsSpotifysMillisecondDurationToSeconds() {
        XCTAssertEqual(
            MediaUnits.seconds(fromMilliseconds: 240_000), 240, accuracy: 0.001)
        XCTAssertEqual(
            MediaUnits.seconds(fromMilliseconds: 1), 0.001, accuracy: 0.0001)
        XCTAssertEqual(MediaUnits.seconds(fromMilliseconds: 0), 0)
    }

    func testClampsPositionIntoTheTrack() {
        XCTAssertEqual(MediaUnits.clamp(position: -3, duration: 200), 0)
        XCTAssertEqual(MediaUnits.clamp(position: 240, duration: 200), 200)
        XCTAssertEqual(
            MediaUnits.clamp(position: 61.5, duration: 200), 61.5, accuracy: 0.001)
    }

    /// A zero duration means "we could not read it". Clamping to it would
    /// report every track as finished.
    func testAZeroDurationDoesNotSwallowThePosition() {
        XCTAssertEqual(
            MediaUnits.clamp(position: 61.5, duration: 0), 61.5, accuracy: 0.001)
    }

    func testMapsThePlayerStateFourCharCodes() {
        XCTAssertEqual(MediaUnits.playbackState(fromFourCharCode: 0x6B50_5350), "playing")  // kPSP
        XCTAssertEqual(MediaUnits.playbackState(fromFourCharCode: 0x6B50_5370), "paused")  // kPSp
        XCTAssertEqual(MediaUnits.playbackState(fromFourCharCode: 0x6B50_5353), "stopped")  // kPSS
        XCTAssertEqual(MediaUnits.playbackState(fromFourCharCode: 0), "unknown")
    }

    func testChannelMapCarriesSecondsAsDoubles() {
        let payload = NowPlayingPayload(
            sourceId: "spotify",
            trackId: "spotify:track:abc",
            title: "Ada", artist: "Sonu Nigam", album: "Ada",
            duration: MediaUnits.seconds(fromMilliseconds: 240_000),
            position: 61.5,
            state: "playing",
            artworkPath: "/tmp/a.jpg"
        )

        let map = payload.channelMap
        XCTAssertEqual(map["durationSeconds"] as? Double, 240)
        XCTAssertEqual(map["positionSeconds"] as? Double, 61.5)
        XCTAssertEqual(map["trackId"] as? String, "spotify:track:abc")
        XCTAssertEqual(map["state"] as? String, "playing")
        XCTAssertEqual(map["sourceId"] as? String, "spotify")
    }

    /// A tick fires about twice a second. Artwork crossing on one would eat
    /// the app's whole CPU budget, so the tick must not carry it — nor the
    /// track metadata that only changes with the track.
    func testATickCarriesNoArtworkAndNoMetadata() {
        let payload = NowPlayingPayload(
            sourceId: "spotify",
            trackId: "spotify:track:abc",
            title: "Ada", artist: "Sonu Nigam", album: "Ada",
            duration: 240,
            position: 61.5,
            state: "playing",
            artworkPath: "/tmp/a.jpg"
        )

        let tick = payload.tickMap
        XCTAssertNil(tick["artworkPath"])
        XCTAssertNil(tick["title"])
        XCTAssertNil(tick["durationSeconds"])
        XCTAssertEqual(tick["positionSeconds"] as? Double, 61.5)
        XCTAssertEqual(tick["isTick"] as? Bool, true)
    }
}

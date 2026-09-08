import XCTest

@testable import NotchPeek

final class ReplayBufferTests: XCTestCase {

    /// The reason this class exists: Swift resolves geometry during launch,
    /// roughly 200 ms before the Dart isolate subscribes to the event channel.
    /// Without a replay the first — and for a stationary machine, only —
    /// geometry event is dropped and the panel never draws.
    func testReplaysAPayloadRecordedBeforeAnyoneWasListening() {
        let buffer = ReplayBuffer()
        buffer.record(["notchWidth": 179.0], key: "geometry")

        let replayed = buffer.replay

        XCTAssertEqual(replayed.count, 1)
        XCTAssertEqual(replayed.first?["notchWidth"] as? Double, 179.0)
    }

    func testKeepsOnlyTheLatestPayloadPerKind() {
        let buffer = ReplayBuffer()
        buffer.record(["percent": 80], key: "power")
        buffer.record(["percent": 79], key: "power")

        XCTAssertEqual(buffer.replay.count, 1)
        XCTAssertEqual(buffer.replay.first?["percent"] as? Int, 79)
    }

    /// The system channel carries three kinds. A single slot would let power
    /// overwrite geometry, which is the same bug in a different costume.
    func testKeepsOneSlotPerKindAndReplaysInFirstSeenOrder() {
        let buffer = ReplayBuffer()
        buffer.record(["notchWidth": 179.0], key: "geometry")
        buffer.record(["percent": 80], key: "power")
        buffer.record(["notchWidth": 200.0], key: "geometry")

        let replayed = buffer.replay

        XCTAssertEqual(replayed.count, 2)
        XCTAssertEqual(replayed[0]["notchWidth"] as? Double, 200.0)
        XCTAssertEqual(replayed[1]["percent"] as? Int, 80)
    }

    /// Dart re-subscribes after a hot restart and after the reconnect backoff.
    func testReplaysAgainForASecondSubscriber() {
        let buffer = ReplayBuffer()
        buffer.record(["notchWidth": 179.0], key: "geometry")

        XCTAssertEqual(buffer.replay.count, 1)
        XCTAssertEqual(buffer.replay.count, 1, "replay does not consume")
    }

    func testAnEmptyBufferReplaysNothing() {
        XCTAssertTrue(ReplayBuffer().replay.isEmpty)
    }
}

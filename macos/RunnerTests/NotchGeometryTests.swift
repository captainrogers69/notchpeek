import XCTest

@testable import NotchPeek

final class NotchGeometryTests: XCTestCase {

    /// MacBook Air M2 at its default scaled resolution, the dev machine.
    func testDerivesTheNotchFromTheGapBetweenTheAuxiliaryAreas() {
        let metrics = NotchGeometry.derive(
            screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            auxLeft: CGRect(x: 0, y: 924, width: 585, height: 32),
            auxRight: CGRect(x: 885, y: 924, width: 585, height: 32),
            safeAreaTop: 32,
            scale: 2,
            displayId: 7
        )

        XCTAssertFalse(metrics.isVirtual)
        XCTAssertEqual(metrics.notchLeft, 585)
        XCTAssertEqual(metrics.notchWidth, 300)
        XCTAssertEqual(metrics.notchHeight, 32)
        XCTAssertEqual(metrics.screenWidth, 1470)
    }

    func testOffsetsTheNotchByTheScreenOriginOnASecondDisplay() {
        let metrics = NotchGeometry.derive(
            screenFrame: CGRect(x: 1470, y: 0, width: 1000, height: 800),
            auxLeft: CGRect(x: 1470, y: 768, width: 400, height: 32),
            auxRight: CGRect(x: 2070, y: 768, width: 400, height: 32),
            safeAreaTop: 32,
            scale: 2,
            displayId: 7
        )

        // notchLeft is relative to the screen, not to the global origin.
        XCTAssertEqual(metrics.notchLeft, 400)
        XCTAssertEqual(metrics.notchWidth, 200)
    }

    func testSynthesizesACentredVirtualNotchWhenThereIsNoSafeArea() {
        let metrics = NotchGeometry.derive(
            screenFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            auxLeft: nil,
            auxRight: nil,
            safeAreaTop: 0,
            scale: 2,
            displayId: 7
        )

        XCTAssertTrue(metrics.isVirtual)
        XCTAssertEqual(metrics.notchWidth, 200)
        XCTAssertEqual(metrics.notchHeight, 32)
        XCTAssertEqual(metrics.notchLeft, 1180)  // (2560 - 200) / 2
    }

    func testFallsBackToTheVirtualNotchWhenTheAuxiliaryAreasDoNotLeaveAGap() {
        // Seen when a display reports a safe area but no auxiliary split.
        let metrics = NotchGeometry.derive(
            screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            auxLeft: CGRect(x: 0, y: 924, width: 800, height: 32),
            auxRight: CGRect(x: 700, y: 924, width: 770, height: 32),
            safeAreaTop: 32,
            scale: 2,
            displayId: 7
        )

        XCTAssertTrue(metrics.isVirtual)
        XCTAssertEqual(metrics.notchWidth, 200)
    }

    func testChannelMapCarriesEveryFieldDartReads() {
        let metrics = NotchGeometry.derive(
            screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            auxLeft: CGRect(x: 0, y: 924, width: 585, height: 32),
            auxRight: CGRect(x: 885, y: 924, width: 585, height: 32),
            safeAreaTop: 32,
            scale: 2,
            displayId: 7
        )

        let map = metrics.channelMap
        XCTAssertEqual(map["screenWidth"] as? CGFloat, 1470)
        XCTAssertEqual(map["screenHeight"] as? CGFloat, 956)
        XCTAssertEqual(map["notchWidth"] as? CGFloat, 300)
        XCTAssertEqual(map["notchHeight"] as? CGFloat, 32)
        XCTAssertEqual(map["notchLeft"] as? CGFloat, 585)
        XCTAssertEqual(map["scale"] as? CGFloat, 2)
        XCTAssertEqual(map["isVirtual"] as? Bool, false)
    }
}

/// Follow-the-active-screen: the panel lives on whichever screen the cursor is
/// on, so it is always where the user is looking (spec §3.3). On a notched
/// laptop plus an external main display, "the screen with a notch" would park
/// the panel on the laptop while the user works on the external.
final class ActiveScreenTests: XCTestCase {

    private let laptop = CGRect(x: 476, y: -956, width: 1470, height: 956)
    private let external = CGRect(x: 0, y: 0, width: 2560, height: 1440)

    func testPicksTheScreenTheCursorIsOn() {
        let frames = [external, laptop]

        XCTAssertEqual(
            NotchGeometry.indexOfScreen(containing: CGPoint(x: 1000, y: 700), frames: frames), 0)
        XCTAssertEqual(
            NotchGeometry.indexOfScreen(containing: CGPoint(x: 1000, y: -400), frames: frames), 1)
    }

    /// Screens abut exactly; a point on the shared edge must resolve to one of
    /// them and always the same one, never nil.
    func testAPointOnASharedEdgeResolvesDeterministically() {
        let frames = [external, laptop]

        let first = NotchGeometry.indexOfScreen(containing: CGPoint(x: 1000, y: 0), frames: frames)
        let second = NotchGeometry.indexOfScreen(containing: CGPoint(x: 1000, y: 0), frames: frames)

        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
    }

    func testAPointOnNoScreenIsNil() {
        XCTAssertNil(
            NotchGeometry.indexOfScreen(
                containing: CGPoint(x: -5000, y: -5000), frames: [external, laptop]))
        XCTAssertNil(
            NotchGeometry.indexOfScreen(containing: .zero, frames: []))
    }

    /// Two identically sized screens produce identical metrics apart from the
    /// display id. Without it the observer would not notice the panel had to
    /// move.
    func testMetricsDifferByDisplayIdAlone() {
        let a = NotchGeometry.derive(
            screenFrame: external, auxLeft: nil, auxRight: nil, safeAreaTop: 0, scale: 2,
            displayId: 1)
        let b = NotchGeometry.derive(
            screenFrame: external, auxLeft: nil, auxRight: nil, safeAreaTop: 0, scale: 2,
            displayId: 2)

        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.channelMap["displayId"] as? UInt32, 1)
    }
}

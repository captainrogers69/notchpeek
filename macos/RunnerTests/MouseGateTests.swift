import XCTest

@testable import NotchPeek

final class MouseGateTests: XCTestCase {

    /// Dart measures from the top-left of the canvas; AppKit from the
    /// bottom-left of the window. Getting this backwards puts the hole at the
    /// bottom of the screen, where nothing is.
    func testFlipsDartsTopLeftRectIntoWindowCoordinates() {
        let flipped = MouseGate.windowRect(
            fromDartRect: CGRect(x: 585, y: 0, width: 300, height: 32),
            canvasHeight: 420
        )

        XCTAssertEqual(flipped, CGRect(x: 585, y: 388, width: 300, height: 32))
    }

    func testCapturesOnlyInsideTheInteractiveRect() {
        let rect = CGRect(x: 100, y: 300, width: 200, height: 40)

        XCTAssertTrue(
            MouseGate.shouldCapture(
                mouseInWindow: CGPoint(x: 150, y: 320), interactiveRect: rect))
        XCTAssertFalse(
            MouseGate.shouldCapture(
                mouseInWindow: CGPoint(x: 50, y: 320), interactiveRect: rect))
        XCTAssertFalse(
            MouseGate.shouldCapture(
                mouseInWindow: CGPoint(x: 150, y: 200), interactiveRect: rect))
    }

    func testTheEdgeOfTheRectCounts() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)

        XCTAssertTrue(
            MouseGate.shouldCapture(
                mouseInWindow: CGPoint(x: 0, y: 0), interactiveRect: rect))
        XCTAssertTrue(
            MouseGate.shouldCapture(
                mouseInWindow: CGPoint(x: 10, y: 10), interactiveRect: rect))
        XCTAssertFalse(
            MouseGate.shouldCapture(
                mouseInWindow: CGPoint(x: 10.1, y: 5), interactiveRect: rect))
    }

    func testNeverCapturesWhenDartHasNotReportedARect() {
        XCTAssertFalse(
            MouseGate.shouldCapture(
                mouseInWindow: CGPoint(x: 5, y: 5), interactiveRect: nil))
    }
}

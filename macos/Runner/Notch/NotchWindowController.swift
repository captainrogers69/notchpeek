import AppKit

/// Owns the one window this app has: a borderless, non-activating `NSPanel`
/// pinned to the top of the notched screen, sized once to
/// `screenWidth x canvasHeight` and **never resized**. Every expand, collapse
/// and peek is a Flutter animation painted inside it (spec §3.1).
final class NotchWindowController {

    /// **Must match `NotchSizes.canvasHeight` in `lib/app/theme.dart`.**
    static let canvasHeight: CGFloat = 420

    let panel: NSPanel

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above the menu bar. The panel must draw over it, not under it.
        panel.level = NotchWindowController.aboveMenuBar
        panel.collectionBehavior = NotchWindowController.behavior
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        // Swallowing every click across the menu bar is the failure mode this
        // app must never have. Default to transparent to the mouse; `MouseGate`
        // opens a hole only where Dart says it is interactive (spec §3.2).
        panel.ignoresMouseEvents = true
        // Off by default on every NSWindow. Without it the panel never sees a
        // `mouseMoved`, so Flutter's hover state only ever changes on a click.
        panel.acceptsMouseMovedEvents = true
    }

    /// Install the Flutter view **after** `reposition`, never before: a view
    /// reads its backing scale factor from the window it loads into, and a
    /// panel still sitting at `.zero` has no screen to read it from.
    func install(_ contentViewController: NSViewController) {
        panel.contentViewController = contentViewController

        // Dart paints the only visible pixels.
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private static var aboveMenuBar: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
    }

    private static let behavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]

    func show() {
        panel.orderFrontRegardless()
    }

    /// Called on every geometry change: display added or removed, resolution
    /// changed, Space switched to one on another screen.
    func reposition(for metrics: NotchMetrics) {
        guard let screen = NotchGeometry.preferredScreen() else { return }

        let frame = CGRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - Self.canvasHeight,
            width: metrics.screenWidth,
            height: Self.canvasHeight
        )

        // setFrame, not setFrameSize: the size only ever changes because the
        // *display* changed, never because the panel animated.
        panel.setFrame(frame, display: true)
    }

    /// Re-assert the window level and collection behavior after a Space or
    /// fullscreen transition. macOS occasionally drops a borderless panel
    /// behind a fullscreen window otherwise.
    func reassert() {
        panel.level = NotchWindowController.aboveMenuBar
        panel.collectionBehavior = NotchWindowController.behavior
        panel.orderFrontRegardless()
    }
}

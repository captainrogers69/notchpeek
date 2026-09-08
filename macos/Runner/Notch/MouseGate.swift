import AppKit

/// Decides, on every mouse move, whether the panel should accept the mouse or
/// let it fall through to whatever is underneath.
///
/// Uses event monitors for `.mouseMoved` only, which need no Accessibility
/// permission — only keyboard monitoring does. Nothing in this app should ever
/// prompt at launch.
final class MouseGate {

    private weak var panel: NSPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var interactiveRect: CGRect?

    private(set) var isCapturing = false

    /// Fired on every in/out transition. This is the shell's hover signal:
    /// AppKit sends no `mouseExited` when the panel goes mouse-transparent, so
    /// Flutter's own `MouseRegion` can never see the cursor leave.
    var onHoverChanged: ((Bool) -> Void)?

    init(panel: NSPanel) {
        self.panel = panel
    }

    // MARK: - Pure, and therefore tested

    /// Dart measures from the top-left of the canvas; AppKit from the
    /// bottom-left of the window.
    static func windowRect(fromDartRect rect: CGRect, canvasHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: canvasHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Inclusive of the edges: a cursor resting exactly on the boundary of the
    /// hot zone must still open the panel. `CGRect.contains` excludes the max
    /// edge, which is why this is hand-rolled.
    static func shouldCapture(mouseInWindow point: CGPoint, interactiveRect rect: CGRect?)
        -> Bool
    {
        guard let rect else { return false }
        return point.x >= rect.minX && point.x <= rect.maxX
            && point.y >= rect.minY && point.y <= rect.maxY
    }

    // MARK: - Wiring

    func start() {
        guard localMonitor == nil else { return }

        // The local monitor fires while this app is active; the global one
        // while it is not. An agent app is usually not active, so both are
        // needed.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) {
            [weak self] event in
            self?.evaluate()
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) {
            [weak self] _ in
            self?.evaluate()
        }

        evaluate()
    }

    func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    /// Dart's rect, in Dart's coordinate space. `nil` means "capture nothing".
    func update(interactiveRect rect: CGRect?) {
        guard let rect else {
            interactiveRect = nil
            apply(capturing: false)
            return
        }
        interactiveRect = MouseGate.windowRect(
            fromDartRect: rect,
            canvasHeight: NotchWindowController.canvasHeight
        )
        evaluate()
    }

    private func evaluate() {
        guard let panel else { return }
        let mouseInWindow = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        apply(
            capturing: MouseGate.shouldCapture(
                mouseInWindow: mouseInWindow,
                interactiveRect: interactiveRect
            ))
    }

    private func apply(capturing: Bool) {
        guard capturing != isCapturing else { return }
        isCapturing = capturing
        panel?.ignoresMouseEvents = !capturing
        onHoverChanged?(capturing)
    }

    deinit { stop() }
}

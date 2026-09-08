import AppKit

/// Everything Dart needs to lay out the panel, in points, in the screen's own
/// coordinate space. Normalized here so Dart sees exactly one shape
/// (architecture-playbook §4.2).
struct NotchMetrics: Equatable {
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    /// Distance from the screen's left edge to the notch's left edge.
    let notchLeft: CGFloat
    let scale: CGFloat
    /// True when this machine has no hardware notch and we synthesized one.
    let isVirtual: Bool
    /// `CGDirectDisplayID`. Two identically sized screens produce identical
    /// metrics without it, and the observer would not notice the panel had to
    /// move between them.
    let displayId: UInt32

    var channelMap: [String: Any] {
        [
            "screenWidth": screenWidth,
            "screenHeight": screenHeight,
            "notchWidth": notchWidth,
            "notchHeight": notchHeight,
            "notchLeft": notchLeft,
            "scale": scale,
            "isVirtual": isVirtual,
            "displayId": displayId,
        ]
    }
}

/// Resolves the notch rect, synthesizes one on machines without hardware, and
/// watches for the two events that invalidate it.
enum NotchGeometry {

    /// The synthetic notch used on every Mac without one. Chosen to match the
    /// proportions of the real thing so the shell behaves identically (spec §2).
    /// **Must match `NotchSizes.virtualNotchWidth` / `Height` in Dart.**
    static let virtualNotchWidth: CGFloat = 200
    static let virtualNotchHeight: CGFloat = 32

    /// Pure, and therefore the part that is unit-tested. `auxLeft` and
    /// `auxRight` are `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`,
    /// which are nil on hardware without a notch.
    static func derive(
        screenFrame: CGRect,
        auxLeft: CGRect?,
        auxRight: CGRect?,
        safeAreaTop: CGFloat,
        scale: CGFloat,
        displayId: UInt32
    ) -> NotchMetrics {
        let width = screenFrame.width
        let height = screenFrame.height

        if safeAreaTop > 0, let left = auxLeft, let right = auxRight {
            let gap = right.minX - left.maxX
            if gap > 0 {
                return NotchMetrics(
                    screenWidth: width,
                    screenHeight: height,
                    notchWidth: gap,
                    notchHeight: safeAreaTop,
                    notchLeft: left.maxX - screenFrame.minX,
                    scale: scale,
                    isVirtual: false,
                    displayId: displayId
                )
            }
        }

        return NotchMetrics(
            screenWidth: width,
            screenHeight: height,
            notchWidth: virtualNotchWidth,
            notchHeight: virtualNotchHeight,
            notchLeft: (width - virtualNotchWidth) / 2,
            scale: scale,
            isVirtual: true,
            displayId: displayId
        )
    }

    static func metrics(for screen: NSScreen) -> NotchMetrics {
        derive(
            screenFrame: screen.frame,
            auxLeft: screen.auxiliaryTopLeftArea,
            auxRight: screen.auxiliaryTopRightArea,
            safeAreaTop: screen.safeAreaInsets.top,
            scale: screen.backingScaleFactor,
            displayId: NotchGeometry.displayId(of: screen)
        )
    }

    static func displayId(of screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Pure, and therefore tested. First match wins, so a cursor resting on the
    /// shared edge of two abutting screens always resolves to the same one.
    static func indexOfScreen(containing point: CGPoint, frames: [CGRect]) -> Int? {
        frames.firstIndex { frame in
            point.x >= frame.minX && point.x <= frame.maxX
                && point.y >= frame.minY && point.y <= frame.maxY
        }
    }

    /// The screen the panel lives on: **the one the cursor is on**, so the
    /// panel is always where the user is looking (spec §3.3).
    ///
    /// Picking "the screen with a notch" instead would park the panel on a
    /// notched laptop while the user works on an external display. On screens
    /// without hardware, `derive` synthesizes a virtual notch and the shell
    /// behaves identically.
    static func preferredScreen() -> NSScreen? {
        let screens = NSScreen.screens
        if let index = indexOfScreen(
            containing: NSEvent.mouseLocation, frames: screens.map(\.frame))
        {
            return screens[index]
        }
        return NSScreen.main
    }
}

/// Recomputes geometry when the display arrangement changes or the user
/// switches Space, and reports only actual changes.
final class NotchGeometryObserver {
    private let onChange: (NotchMetrics) -> Void
    private var tokens: [NSObjectProtocol] = []
    private var mouseMonitors: [Any] = []
    private(set) var current: NotchMetrics?

    init(onChange: @escaping (NotchMetrics) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard tokens.isEmpty else { return }

        tokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.recompute() }
        )

        tokens.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.recompute() }
        )

        // Follow the cursor across displays. `recompute` de-duplicates, so the
        // per-event cost is one point-in-rect scan and a struct compare.
        mouseMonitors.append(
            NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
                self?.recompute()
            }
        )
        mouseMonitors.append(
            NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
                self?.recompute()
                return event
            }
        )

        recompute()
    }

    func stop() {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        tokens.removeAll()

        for monitor in mouseMonitors { NSEvent.removeMonitor(monitor) }
        mouseMonitors.removeAll()
    }

    func recompute() {
        guard let screen = NotchGeometry.preferredScreen() else { return }
        let metrics = NotchGeometry.metrics(for: screen)
        guard metrics != current else { return }
        current = metrics
        onChange(metrics)
    }

    deinit { stop() }
}

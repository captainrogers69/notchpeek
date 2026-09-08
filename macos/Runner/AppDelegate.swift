import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {

    /// Strong references: nothing else owns these.
    var engine: FlutterEngine?
    var viewController: FlutterViewController?
    var windowController: NotchWindowController?
    var bridge: ChannelBridge?
    var geometryObserver: NotchGeometryObserver?
    var mouseGate: MouseGate?

    private var started = false

    /// An agent app has no windows to close. Quitting is the settings window's
    /// job, not the last window's.
    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication)
        -> Bool
    {
        return false
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    override func applicationDidFinishLaunching(_ notification: Notification) {
        // `start()` runs **before** `super`: `FlutterAppDelegate`'s own
        // implementation raises an ObjC exception on this app's nib, which
        // AppKit swallows and which unwinds out of this method — anything
        // after the super call is never reached.
        start()
        super.applicationDidFinishLaunching(notification)
    }

    /// Everything is built here, in this order, and nothing is built anywhere
    /// else. `MainFlutterWindow` exists only because the nib instantiates it.
    private func start() {
        guard !started else { return }
        started = true

        // The engine is owned by the delegate and headless, and its view
        // controller is created **once, for the panel**. Building the view
        // controller inside another window and re-parenting it leaves its
        // `devicePixelRatio` at the scale factor of the window it was born in:
        // AppKit sends no backing-properties change when a view moves between
        // windows. On a 1x display fed a stale ratio of 2 that halves Dart's
        // whole coordinate space, and the shell paints off the canvas.
        let engine = FlutterEngine(
            name: "notchpeek", project: nil, allowHeadlessExecution: true)
        guard engine.run(withEntrypoint: nil) else {
            NSLog("NotchPeek: the Flutter engine refused to start")
            return
        }
        RegisterGeneratedPlugins(registry: engine)
        self.engine = engine

        let bridge = ChannelBridge(messenger: engine.binaryMessenger)
        bridge.start()
        self.bridge = bridge

        let controller = NotchWindowController()
        windowController = controller

        // Frame before content, always: the view reads its backing scale from
        // the window it loads into, and a panel at `.zero` has no screen.
        if let screen = NotchGeometry.preferredScreen() {
            controller.reposition(for: NotchGeometry.metrics(for: screen))
        }

        let viewController = FlutterViewController(
            engine: engine, nibName: nil, bundle: nil)
        // Dart paints the only visible pixels: the view must not draw a ground.
        viewController.backgroundColor = .clear
        // Flutter tracks the mouse only inside the key window by default. This
        // panel is deliberately never key — a `.nonactivatingPanel` that took
        // focus would steal it from whatever the user is working in — so the
        // default mode means hover never fires and the shell only ever reacts
        // to clicks.
        viewController.mouseTrackingMode = .always
        self.viewController = viewController
        controller.install(viewController)

        let gate = MouseGate(panel: controller.panel)
        gate.onHoverChanged = { [weak bridge] inside in
            bridge?.sendSystem(SystemEvent.hover, ["inside": inside])
        }
        gate.start()
        mouseGate = gate

        bridge.onSetInteractiveRect = { [weak gate] rect in
            gate?.update(interactiveRect: rect)
        }

        // `.alignment` is the only pattern that reads as a single tick rather
        // than a thud, and it is silent on hardware without a Force Touch
        // trackpad, which is the correct behaviour there.
        bridge.onHaptic = {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .alignment, performanceTime: .now)
        }

        let observer = NotchGeometryObserver { [weak self, weak bridge] metrics in
            // Reposition before telling Dart: the window must already be in the
            // right place by the time Dart draws for that geometry.
            self?.windowController?.reposition(for: metrics)
            self?.windowController?.reassert()
            bridge?.sendSystem(SystemEvent.geometry, metrics.channelMap)
        }
        observer.start()
        geometryObserver = observer

        controller.show()
    }
}

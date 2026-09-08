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
    var mediaBridge: MediaBridge?

    private var started = false

    /// The last snapshot pushed to Dart, so an unchanged one is not pushed
    /// again.
    private var lastCapabilities: [String: Any]?
    private var capabilityToken: NSObjectProtocol?

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

        bridge.onGetCapabilities = { CapabilityProbe.snapshot() }

        bridge.onRequestPermission = { [weak self, weak bridge] what in
            switch what {
            case PermissionTarget.settings:
                CapabilityProbe.openAutomationSettings()

            case PermissionTarget.players:
                // Off the main thread: the request blocks until the user
                // answers the prompt. Asking for every installed player is
                // deliberate — the panel is ready if *either* is.
                DispatchQueue.global(qos: .userInitiated).async {
                    for bundleId in CapabilityProbe.installedPlayers {
                        CapabilityProbe.requestAppleEvents(for: bundleId)
                    }
                    // Report the answer straight away rather than waiting for
                    // the next app switch to re-probe.
                    DispatchQueue.main.async {
                        self?.pushCapabilities(via: bridge)
                    }
                }

            default:
                CapabilityProbe.openAutomationSettings()
            }
        }

        bridge.onOpenSettings = { CapabilityProbe.openAutomationSettings() }

        // Replied to before terminating, so Dart is not left awaiting a reply
        // from a process that is going away.
        bridge.onQuit = { NSApp.terminate(nil) }

        // Permissions change while the user is in System Settings, and this
        // app is never the one they come back *to*: an agent app whose only
        // window is a non-activating panel does not become active, so
        // `didBecomeActiveNotification` would never fire. Watch for any app
        // activating instead.
        capabilityToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak bridge] _ in
            self?.pushCapabilities(via: bridge)
        }

        // Seeds `lastCapabilities` as well as the replay buffer, so Dart has
        // an answer even if its own `getCapabilities` call fails.
        pushCapabilities(via: bridge)

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

        let media = MediaBridge()
        media.onUpdate = { [weak bridge] payload in bridge?.sendMedia(payload) }
        media.start()
        mediaBridge = media

        bridge.onMediaCommand = { [weak media] payload in media?.command(payload) }
        bridge.onSetMediaPolling = { [weak media] enabled in
            media?.setPolling(enabled)
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

    /// `didActivateApplicationNotification` fires on every app switch, and
    /// re-sending an identical snapshot would wake the shell for nothing.
    private func pushCapabilities(via bridge: ChannelBridge?) {
        let snapshot = CapabilityProbe.snapshot()
        if let last = lastCapabilities,
            NSDictionary(dictionary: last).isEqual(to: snapshot)
        {
            return
        }
        lastCapabilities = snapshot
        bridge?.sendSystem(SystemEvent.capabilities, snapshot)
    }
}

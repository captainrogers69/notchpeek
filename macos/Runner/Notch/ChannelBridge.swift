import FlutterMacOS
import Foundation

/// Holds the most recent payload per kind so a subscriber that arrives late
/// still learns the current state.
///
/// This is load-bearing, not a nicety. Swift resolves geometry during launch,
/// roughly 200 ms before the Dart isolate subscribes to the event channel. On
/// a machine whose displays never change, that first geometry event is also
/// the only one — without a replay it is dropped and the panel never draws.
final class ReplayBuffer {
    private var latest: [String: [String: Any]] = [:]
    private var order: [String] = []

    func record(_ payload: [String: Any], key: String) {
        if latest[key] == nil { order.append(key) }
        latest[key] = payload
    }

    /// Every retained payload, in the order its kind was first seen, so
    /// geometry reaches Dart before the events that depend on it. Replaying
    /// does not consume: Dart re-subscribes after a hot restart and after the
    /// reconnect backoff.
    var replay: [[String: Any]] {
        order.compactMap { latest[$0] }
    }
}

/// Wires one method channel and three event channels to the modules that own
/// the OS. It holds no state and makes no decisions — it is a switchboard.
final class ChannelBridge: NSObject {

    private let control: FlutterMethodChannel
    private let media: FlutterEventChannel
    private let system: FlutterEventChannel

    private let mediaSink = EventSinkBox()
    private let systemSink = EventSinkBox()

    // Set by AppDelegate once the modules exist.
    var onSetInteractiveRect: ((CGRect) -> Void)?
    var onMediaCommand: (([String: Any]) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onRequestPermission: ((String) -> Void)?
    var onGetCapabilities: (() -> [String: Any])?
    var onHaptic: (() -> Void)?
    var onSetMediaPolling: ((Bool) -> Void)?
    /// Called when Dart attaches to or detaches from the media stream, so
    /// polling can stop the moment nobody is listening.
    var onMediaListenChanged: ((Bool) -> Void)?

    init(messenger: FlutterBinaryMessenger) {
        control = FlutterMethodChannel(
            name: NotchChannel.control, binaryMessenger: messenger)
        media = FlutterEventChannel(
            name: NotchChannel.media, binaryMessenger: messenger)
        system = FlutterEventChannel(
            name: NotchChannel.system, binaryMessenger: messenger)
        super.init()
    }

    func start() {
        control.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result)
        }
        mediaSink.onListenChanged = { [weak self] active in
            self?.onMediaListenChanged?(active)
        }
        media.setStreamHandler(mediaSink)
        system.setStreamHandler(systemSink)
    }

    /// Every send hops to the main thread: `FlutterEventSink` is not thread-safe.
    func sendSystem(_ kind: String, _ payload: [String: Any]) {
        var message = payload
        message["kind"] = kind
        systemSink.send(message, replayKey: kind)
    }

    func sendMedia(_ payload: [String: Any]) {
        mediaSink.send(payload, replayKey: "media")
    }

    private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        switch call.method {
        case ControlMethod.setInteractiveRect:
            guard let a = call.arguments as? [String: Any],
                let x = a["x"] as? Double, let y = a["y"] as? Double,
                let w = a["width"] as? Double, let h = a["height"] as? Double
            else {
                result(
                    FlutterError(
                        code: "badArgs", message: "expected x, y, width, height",
                        details: nil))
                return
            }
            onSetInteractiveRect?(CGRect(x: x, y: y, width: w, height: h))
            result(true)

        case ControlMethod.mediaCommand:
            guard let a = call.arguments as? [String: Any] else {
                result(
                    FlutterError(
                        code: "badArgs", message: "expected a command map", details: nil))
                return
            }
            onMediaCommand?(a)
            result(true)

        case ControlMethod.openSettings:
            onOpenSettings?()
            result(true)

        case ControlMethod.requestPermission:
            let what = (call.arguments as? [String: Any])?["what"] as? String ?? ""
            onRequestPermission?(what)
            result(true)

        case ControlMethod.setMediaPolling:
            let enabled =
                (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
            onSetMediaPolling?(enabled)
            result(true)

        case ControlMethod.haptic:
            onHaptic?()
            result(true)

        case ControlMethod.getCapabilities:
            result(onGetCapabilities?() ?? [:])

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

/// Holds a `FlutterEventSink` across listen/cancel, marshals every send to the
/// main thread, and replays retained state to a late subscriber.
final class EventSinkBox: NSObject, FlutterStreamHandler {
    private var sink: FlutterEventSink?
    private let buffer = ReplayBuffer()

    var onListenChanged: ((Bool) -> Void)?

    var isListening: Bool { sink != nil }

    /// A `replayKey` marks the payload as *state* rather than a one-off event:
    /// it is retained and handed to whoever subscribes next.
    func send(_ payload: [String: Any], replayKey: String? = nil) {
        if let replayKey { buffer.record(payload, key: replayKey) }
        DispatchQueue.main.async { [weak self] in
            self?.sink?(payload)
        }
    }

    func onListen(
        withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        sink = events
        for payload in buffer.replay {
            events(payload)
        }
        onListenChanged?(true)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        onListenChanged?(false)
        return nil
    }
}

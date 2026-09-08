/// Channel names live in exactly one Dart file and one Swift file
/// (`macos/Runner/Notch/Channels.swift`). Never a string literal at a call
/// site (architecture-playbook §4.1).
abstract final class Channels {
  static const String control = 'notchpeek/control';
  static const String media = 'notchpeek/media';
  static const String system = 'notchpeek/system';

  /// Reserved for M2. Declared now so the set is fixed in M1.
  static const String calendar = 'notchpeek/calendar';
}

abstract final class ControlMethod {
  static const String setInteractiveRect = 'setInteractiveRect';
  static const String mediaCommand = 'mediaCommand';
  static const String openSettings = 'openSettings';
  static const String requestPermission = 'requestPermission';
  static const String getCapabilities = 'getCapabilities';
  static const String haptic = 'haptic';
}

/// Discriminator on every payload that crosses [Channels.system].
abstract final class SystemEventKind {
  static const String key = 'kind';
  static const String geometry = 'geometry';
  static const String power = 'power';
  static const String capabilities = 'capabilities';

  /// Whether the cursor is inside the rect last reported to `MouseGate`.
  /// Native-side because nothing in Flutter can see the cursor leave a panel
  /// that has just been made mouse-transparent.
  static const String hover = 'hover';

  /// Payload key on a [hover] event.
  static const String inside = 'inside';
}

import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';

/// The only three levels the playbook allows (§6). `info` and `warning` were
/// dropped deliberately: in practice everything was one of these three.
enum NotchLogLevel { debug, success, error }

/// Where a formatted line ends up. Swapped in tests; `dart:developer` in the
/// app. This seam is why the logger is testable at all.
typedef NotchLogWriter = void Function(String line);

/// The only logging path in NotchPeek. No `print`, no `debugPrint`.
///
/// **Never log user content** — clipboard text, note bodies, calendar titles
/// and file paths are off limits. Log ids, counts and states. That rule is not
/// style: a clipboard-history app that writes clipboard contents to a log has
/// created a security problem.
class NotchLogger {
  /// One tag per class, created once as a field.
  final String tag;

  /// Per-instance mute, for subsystems that would otherwise be chatty.
  final bool enabled;

  /// Debug-only by default. Release builds stay quiet.
  static bool globalEnabled = kDebugMode;
  static bool useColors = true;
  static NotchLogWriter writer = _developerWriter;

  static const String _reset = '\x1B[0m';
  static const String _gray = '\x1B[90m';
  static const String _cyan = '\x1B[36m';
  static const String _red = '\x1B[31m';
  static const String _green = '\x1B[32m';
  static const String _beige = '\x1B[38;5;230m';

  NotchLogger({required this.tag, bool? enabled})
    : enabled = enabled ?? globalEnabled;

  factory NotchLogger.forTag(String tag) => NotchLogger(tag: tag);

  void debug(String message) => _log(NotchLogLevel.debug, message);

  void success(String message) => _log(NotchLogLevel.success, message);

  void error(String message, {Object? error, StackTrace? stackTrace}) {
    _log(NotchLogLevel.error, message);
    if (error != null) _log(NotchLogLevel.error, 'cause: $error');
    if (stackTrace != null) _log(NotchLogLevel.error, '$stackTrace');
  }

  void _log(NotchLogLevel level, String message) {
    if (!enabled || !globalEnabled) return;

    final time = _timestamp(DateTime.now());
    final name = '[${level.name.toUpperCase()}]';

    if (useColors) {
      writer(
        '$_gray$time$_reset ${_colorFor(level)}$name$_reset '
        '$_cyan[$tag]$_reset $message',
      );
    } else {
      writer('[$time] $name [$tag] $message');
    }
  }

  /// `dart:developer`'s `log` only reaches the VM service, which DevTools
  /// reads and the `flutter run` console does not — every line in this app was
  /// invisible in a terminal. `debugPrint` reaches both, and this is the one
  /// place in NotchPeek allowed to call it.
  static void _developerWriter(String line) {
    debugPrint(line);
    dev.log(line);
  }

  static String _timestamp(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  static String _colorFor(NotchLogLevel level) => switch (level) {
    NotchLogLevel.debug => _beige,
    NotchLogLevel.success => _green,
    NotchLogLevel.error => _red,
  };
}

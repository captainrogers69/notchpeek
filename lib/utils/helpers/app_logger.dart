import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';

enum AppLogLevel { debug, info, warning, error, success }

/// Receives every [NotchLogger.error] call. Assigned once by
/// `CrashReporter.bootstrap()`.
///
/// This indirection exists so `shared/utils/helpers` never imports
/// `core/services` — the logger stays dependency-free and unit-testable.
typedef NotchLogSink =
    void Function(
      String tag,
      String message,
      Object? error,
      StackTrace? stackTrace,
    );

class NotchLogger {
  final String tag;
  final bool enabled;
  final bool useColors;

  /// When false, `error()` logs but does not forward to [errorSink]. Use for
  /// chatty subsystems (socket reconnects) and for CrashReporter's own logger,
  /// where forwarding would recurse.
  final bool reportErrors;

  // ANSI color codes
  static const String _reset = '\x1B[0m';
  static const String _gray = '\x1B[90m';
  static const String _blue = '\x1B[34m';
  static const String _yellow = '\x1B[33m';
  static const String _red = '\x1B[31m';
  static const String _cyan = '\x1B[36m';
  static const String _green = '\x1B[32m';
  static const String _beige = '\x1B[38;5;230m';

  // Global configuration
  static bool globalEnabled = kDebugMode;
  static bool globalUseColors = true;

  /// Set by `CrashReporter.bootstrap()`. Null in tests and before bootstrap.
  static NotchLogSink? errorSink;

  NotchLogger({
    required this.tag,
    bool? enabled,
    bool? useColors,
    this.reportErrors = true,
  }) : enabled = enabled ?? globalEnabled,
       useColors = useColors ?? globalUseColors;

  // Factory constructors for common logger instances
  factory NotchLogger.forClass(Type type, {bool reportErrors = true}) {
    return NotchLogger(tag: type.toString(), reportErrors: reportErrors);
  }

  factory NotchLogger.forTag(String tag, {bool reportErrors = true}) {
    return NotchLogger(tag: tag, reportErrors: reportErrors);
  }

  void debug(String message) => _log(AppLogLevel.debug, message);
  void info(String message) => _log(AppLogLevel.info, message);
  void warning(String message) => _log(AppLogLevel.warning, message);
  void success(String message) => _log(AppLogLevel.success, message);

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    _log(AppLogLevel.error, message);
    // These two were previously ungated and ran in release builds.
    if (enabled && globalEnabled && error != null) {
      dev.log('Error details: $error', name: tag);
    }
    if (enabled && globalEnabled && stackTrace != null) {
      dev.log('StackTrace: $stackTrace', name: tag);
    }
    // Deliberately NOT gated on `enabled` — console logging is debug-only,
    // crash reporting is release-only. They are opposites.
    if (reportErrors) {
      errorSink?.call(tag, message, error, stackTrace);
    }
  }

  void _log(AppLogLevel level, String message) {
    if (!enabled || !globalEnabled) return;

    final timestamp = _formatTimestamp(DateTime.now());

    if (useColors && globalUseColors) {
      final levelColor = _getColorForLevel(level);
      final levelName = _formatLevelName(level);
      dev.log(
        '$_gray$timestamp$_reset $levelColor$levelName$_reset $_cyan[$tag]$_reset $message',
        // name: tag,
      );
    } else {
      dev.log(
        '[$timestamp] [${level.name.toUpperCase()}] [$tag] $message',
        // name: tag,
      );
    }
  }

  String _formatTimestamp(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  String _formatLevelName(AppLogLevel level) {
    return '[${level.name.toUpperCase()}]';
  }

  String _getColorForLevel(AppLogLevel level) {
    switch (level) {
      case AppLogLevel.debug:
        return _beige;
      case AppLogLevel.info:
        return _blue;
      case AppLogLevel.warning:
        return _yellow;
      case AppLogLevel.error:
        return _red;
      case AppLogLevel.success:
        return _green;
    }
  }
}

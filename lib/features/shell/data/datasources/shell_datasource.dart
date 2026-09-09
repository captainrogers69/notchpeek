import 'dart:ui';

import 'package:notchpeek/core/logging/notch_logger.dart';
import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/core/platform/channel_service.dart';
import 'package:notchpeek/core/platform/channels.dart';

abstract class ShellDataSource {
  Stream<Map<String, Object?>> watchGeometryEvents();
  Stream<Map<String, Object?>> watchHoverEvents();
  Stream<Map<String, Object?>> watchPowerEvents();
  Future<ApiResponse<bool>> setInteractiveRect(Rect rect);
  Future<ApiResponse<bool>> performHaptic();
  Future<ApiResponse<bool>> quit();
}

/// The only place the shell feature touches a channel
/// (architecture-playbook §3).
class ShellDataSourceImpl implements ShellDataSource {
  ShellDataSourceImpl(this._channels);

  final ChannelService _channels;
  final NotchLogger _log = NotchLogger.forTag('ShellDataSourceImpl');

  /// Extracted so the filter is testable without a channel.
  static Stream<Map<String, Object?>> filterGeometry(
    Stream<Map<String, Object?>> events,
  ) => events.where((e) => e[SystemEventKind.key] == SystemEventKind.geometry);

  static Stream<Map<String, Object?>> filterHover(
    Stream<Map<String, Object?>> events,
  ) => events.where((e) => e[SystemEventKind.key] == SystemEventKind.hover);

  static Stream<Map<String, Object?>> filterPower(
    Stream<Map<String, Object?>> events,
  ) => events.where((e) => e[SystemEventKind.key] == SystemEventKind.power);

  @override
  Stream<Map<String, Object?>> watchGeometryEvents() {
    _log.debug('subscribing to geometry events');
    return filterGeometry(_channels.systemEvents);
  }

  @override
  Stream<Map<String, Object?>> watchHoverEvents() {
    _log.debug('subscribing to hover events');
    return filterHover(_channels.systemEvents);
  }

  @override
  Stream<Map<String, Object?>> watchPowerEvents() {
    _log.debug('subscribing to power events');
    return filterPower(_channels.systemEvents);
  }

  @override
  Future<ApiResponse<bool>> performHaptic() =>
      _channels.invoke<bool>(ControlMethod.haptic);

  @override
  Future<ApiResponse<bool>> quit() {
    _log.debug('quit requested');
    return _channels.invoke<bool>(ControlMethod.quit);
  }

  @override
  Future<ApiResponse<bool>> setInteractiveRect(Rect rect) async {
    final result = await _channels.invoke<bool>(
      ControlMethod.setInteractiveRect,
      {
        'x': rect.left,
        'y': rect.top,
        'width': rect.width,
        'height': rect.height,
      },
    );
    if (result.status) {
      _log.success(
        'interactive rect ${rect.width.toStringAsFixed(0)}'
        'x${rect.height.toStringAsFixed(0)}',
      );
    } else {
      _log.error('interactive rect rejected: ${result.message}');
    }
    return result;
  }
}

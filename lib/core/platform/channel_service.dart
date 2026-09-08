import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/core/logging/notch_logger.dart';
import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/core/platform/channels.dart';
import 'package:notchpeek/core/platform/resilient_stream.dart';

final channelServiceProvider = Provider<ChannelService>(
  (ref) => ChannelService(),
);

/// The only place in Dart that touches a platform channel
/// (architecture-playbook §3). Datasources call this; nothing above them does.
///
/// The naming wart is accepted: channel results come back in `ApiResponse<T>`,
/// where "Api" reads oddly. One wrapper at every boundary is worth more than
/// the rename (architecture-playbook §5).
class ChannelService {
  ChannelService({
    MethodChannel? control,
    EventChannel? media,
    EventChannel? system,
  }) : _control = control ?? const MethodChannel(Channels.control),
       _media = media ?? const EventChannel(Channels.media),
       _system = system ?? const EventChannel(Channels.system);

  final MethodChannel _control;
  final EventChannel _media;
  final EventChannel _system;

  final NotchLogger _log = NotchLogger.forTag('ChannelService');

  Future<ApiResponse<T>> invoke<T>(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    try {
      final value = await _control.invokeMethod<T>(method, args);
      if (value == null) {
        _log.error('$method returned null');
        return ApiResponse.error(message: '$method is not available.');
      }
      _log.success(method);
      return ApiResponse.success(message: 'OK', data: value);
    } on PlatformException catch (e, s) {
      _log.error('$method failed', error: e, stackTrace: s);
      return ApiResponse.error(message: e.message ?? 'Platform call failed.');
    } on MissingPluginException catch (e, s) {
      _log.error('$method has no handler', error: e, stackTrace: s);
      return ApiResponse.error(message: '$method is not implemented.');
    }
  }

  Stream<Map<String, Object?>> get systemEvents => _events(_system, 'system');

  Stream<Map<String, Object?>> get mediaEvents => _events(_media, 'media');

  Stream<Map<String, Object?>> _events(EventChannel channel, String tag) {
    return resilientStream<Map<String, Object?>>(
      open: () => channel.receiveBroadcastStream().map(
        (event) => Map<String, Object?>.from(event as Map),
      ),
      logger: NotchLogger.forTag('ChannelService.$tag'),
    );
  }
}

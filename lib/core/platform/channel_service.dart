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

  /// **One subscription per channel, shared by every consumer.**
  ///
  /// `EventChannel.receiveBroadcastStream` registers its handler with
  /// `binaryMessenger.setMessageHandler(name, ...)`, and there is exactly one
  /// handler slot per channel name. A second call for the same channel
  /// silently unregisters the first, and a cancel nulls it for everyone. These
  /// were getters that opened a fresh channel per access, so the third
  /// consumer of `notchpeek/system` — capabilities, arriving on the first
  /// expand — made hover go deaf and the notch could never collapse again.
  late final Stream<Map<String, Object?>> systemEvents = _shared(
    _system,
    'system',
    (event) => event[SystemEventKind.key] as String?,
  );

  late final Stream<Map<String, Object?>> mediaEvents = _shared(
    _media,
    'media',
    (_) => 'media',
  );

  /// Retains the last payload per key and hands it to whoever subscribes next,
  /// which is the Dart-side twin of Swift's `ReplayBuffer`. Without it a late
  /// consumer would wait for the *next* event: capabilities subscribes on the
  /// first expand, long after the launch snapshot has been and gone.
  Stream<Map<String, Object?>> _shared(
    EventChannel channel,
    String tag,
    String? Function(Map<String, Object?> event) keyOf,
  ) {
    final latest = <String, Map<String, Object?>>{};

    final source = _events(channel, tag)
        .map((event) {
          final key = keyOf(event);
          if (key != null) latest[key] = event;
          return event;
        })
        .asBroadcastStream(
          // Deliberately does not cancel: the native sink must outlive any
          // one consumer, or the next cancel takes the channel down with it.
          onCancel: (_) {},
        );

    return Stream.multi((controller) {
      for (final retained in latest.values) {
        controller.add(retained);
      }
      final subscription = source.listen(
        controller.add,
        onError: controller.addError,
      );
      controller.onCancel = subscription.cancel;
    });
  }

  Stream<Map<String, Object?>> _events(EventChannel channel, String tag) {
    return resilientStream<Map<String, Object?>>(
      open: () => channel.receiveBroadcastStream().map(
        (event) => Map<String, Object?>.from(event as Map),
      ),
      logger: NotchLogger.forTag('ChannelService.$tag'),
    );
  }
}

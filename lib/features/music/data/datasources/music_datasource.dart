import 'package:notchpeek/core/logging/notch_logger.dart';
import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/core/platform/channel_service.dart';
import 'package:notchpeek/core/platform/channels.dart';
import 'package:notchpeek/shared/utils/enums/media_command.dart';

abstract class MusicDataSource {
  Stream<Map<String, Object?>> watchMediaEvents();
  Future<ApiResponse<bool>> command(MediaCommand command, {Duration? seekTo});
  Future<ApiResponse<bool>> setPolling(bool enabled);
}

class MusicDataSourceImpl implements MusicDataSource {
  MusicDataSourceImpl(this._channels);

  final ChannelService _channels;
  final NotchLogger _log = NotchLogger.forTag('MusicDataSourceImpl');

  @override
  Stream<Map<String, Object?>> watchMediaEvents() => _channels.mediaEvents;

  /// Logs ids and states, never titles — a track name is user content
  /// (architecture-playbook §6).
  @override
  Future<ApiResponse<bool>> command(
    MediaCommand command, {
    Duration? seekTo,
  }) async {
    final result = await _channels.invoke<bool>(ControlMethod.mediaCommand, {
      'command': command.apiValue,
      if (seekTo != null) 'seconds': seekTo.inMilliseconds / 1000,
    });
    if (result.status) {
      _log.success(command.apiValue);
    } else {
      _log.error('${command.apiValue} failed: ${result.message}');
    }
    return result;
  }

  @override
  Future<ApiResponse<bool>> setPolling(bool enabled) => _channels.invoke<bool>(
    ControlMethod.setMediaPolling,
    {'enabled': enabled},
  );
}

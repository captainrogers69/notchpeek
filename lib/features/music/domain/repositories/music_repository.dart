import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/shared/utils/enums/media_command.dart';
import 'package:notchpeek/shared/utils/enums/music_source_id.dart';

abstract class MusicRepository {
  Stream<NowPlaying> watch();
  Future<ApiResponse<bool>> command(MediaCommand command, {Duration? seekTo});
  Future<ApiResponse<bool>> setPolling(bool enabled);

  /// Launches or fronts a player. Only ever from the panel's own button:
  /// nothing in this app launches a player to answer a question about it.
  Future<ApiResponse<bool>> openPlayer(MusicSourceId source);
}

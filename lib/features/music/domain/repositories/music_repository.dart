import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/shared/utils/enums/media_command.dart';

abstract class MusicRepository {
  Stream<NowPlaying> watch();
  Future<ApiResponse<bool>> command(MediaCommand command, {Duration? seekTo});
  Future<ApiResponse<bool>> setPolling(bool enabled);
}

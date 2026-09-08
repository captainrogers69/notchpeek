import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/music/data/datasources/music_datasource.dart';
import 'package:notchpeek/features/music/data/models/now_playing_model.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/features/music/domain/repositories/music_repository.dart';
import 'package:notchpeek/shared/utils/enums/media_command.dart';

class MusicRepositoryImpl implements MusicRepository {
  MusicRepositoryImpl(this._source);

  final MusicDataSource _source;

  /// Folds ticks into the last full payload here, so nothing above this layer
  /// has to know that two payload shapes exist.
  @override
  Stream<NowPlaying> watch() async* {
    var current = const NowPlaying.unavailable();

    await for (final event in _source.watchMediaEvents()) {
      final parsed = NowPlayingModel.toEntity(event);
      current = NowPlayingModel.isTick(event)
          ? current.mergeTick(parsed)
          : parsed;
      yield current;
    }
  }

  @override
  Future<ApiResponse<bool>> command(MediaCommand command, {Duration? seekTo}) =>
      _source.command(command, seekTo: seekTo);

  @override
  Future<ApiResponse<bool>> setPolling(bool enabled) =>
      _source.setPolling(enabled);
}

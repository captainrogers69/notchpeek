import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/features/music/domain/repositories/music_repository.dart';

class WatchNowPlaying {
  const WatchNowPlaying(this._repository);

  final MusicRepository _repository;

  Stream<NowPlaying> call() => _repository.watch();
}

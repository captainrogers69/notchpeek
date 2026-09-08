import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/shared/utils/enums/music_source_id.dart';
import 'package:notchpeek/shared/utils/enums/playback_state.dart';

abstract final class NowPlayingModel {
  static bool isTick(Map<String, Object?> json) => json['isTick'] == true;

  static NowPlaying toEntity(Map<String, Object?> json) {
    if (json['available'] != true) return const NowPlaying.unavailable();

    return NowPlaying(
      available: true,
      source: MusicSourceId.fromApi(_string(json['sourceId'])),
      trackId: _string(json['trackId']) ?? '',
      title: _string(json['title']) ?? '',
      artist: _string(json['artist']) ?? '',
      album: _string(json['album']) ?? '',
      duration: _duration(json['durationSeconds']),
      position: _duration(json['positionSeconds']),
      state: PlaybackState.fromApi(_string(json['state'])),
      artworkPath: _string(json['artworkPath']),
    );
  }

  /// `as String?` **throws** on a value of the wrong type, which is the
  /// opposite of degrading (architecture-playbook §5). A field that is not a
  /// string reads as absent.
  static String? _string(Object? value) => value is String ? value : null;

  static Duration _duration(Object? seconds) => Duration(
    milliseconds: (((seconds is num ? seconds : 0).toDouble()) * 1000).round(),
  );
}

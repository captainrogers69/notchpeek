import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/features/music/data/models/now_playing_model.dart';
import 'package:notchpeek/shared/utils/enums/music_source_id.dart';
import 'package:notchpeek/shared/utils/enums/playback_state.dart';

const _full = <String, Object?>{
  'available': true,
  'trackChanged': true,
  'sourceId': 'spotify',
  'trackId': 'spotify:track:abc',
  'title': 'Ada',
  'artist': 'Sonu Nigam',
  'album': 'Ada',
  'durationSeconds': 240.0,
  'positionSeconds': 61.5,
  'state': 'playing',
  'artworkPath': '/tmp/a.jpg',
};

void main() {
  test('parses a full payload', () {
    final track = NowPlayingModel.toEntity(_full);

    expect(track.available, isTrue);
    expect(track.source, MusicSourceId.spotify);
    expect(track.title, 'Ada');
    expect(track.duration, const Duration(seconds: 240));
    expect(track.position, const Duration(milliseconds: 61500));
    expect(track.state, PlaybackState.playing);
    expect(track.artworkPath, '/tmp/a.jpg');
    expect(track.hasTrack, isTrue);
  });

  test('an unavailable payload is not the same as nothing playing', () {
    final track = NowPlayingModel.toEntity(const {'available': false});

    expect(track.available, isFalse);
    expect(track.hasTrack, isFalse);
    expect(track.state, PlaybackState.unknown);
  });

  test('recognises a tick and keeps everything the tick does not carry', () {
    expect(NowPlayingModel.isTick(const {'isTick': true}), isTrue);
    expect(NowPlayingModel.isTick(_full), isFalse);

    final full = NowPlayingModel.toEntity(_full);
    final tick = NowPlayingModel.toEntity(const {
      'available': true,
      'isTick': true,
      'sourceId': 'spotify',
      'trackId': 'spotify:track:abc',
      'positionSeconds': 90.0,
      'state': 'paused',
    });

    final merged = full.mergeTick(tick);

    expect(merged.title, 'Ada', reason: 'the tick carries no title');
    expect(
      merged.artworkPath,
      '/tmp/a.jpg',
      reason: 'artwork never crosses on a tick',
    );
    expect(merged.position, const Duration(seconds: 90));
    expect(merged.state, PlaybackState.paused);
  });

  test('a tick for a different track is not merged in', () {
    final full = NowPlayingModel.toEntity(_full);
    final other = NowPlayingModel.toEntity(const {
      'available': true,
      'isTick': true,
      'trackId': 'other',
      'positionSeconds': 5.0,
    });

    expect(full.mergeTick(other), full);
  });

  test(
    'progress is a fraction, and a zero duration does not divide by zero',
    () {
      expect(NowPlayingModel.toEntity(_full).progress, closeTo(0.256, 0.001));

      final noDuration = NowPlayingModel.toEntity(const {
        'available': true,
        'trackId': 'x',
        'positionSeconds': 10.0,
        'durationSeconds': 0.0,
      });
      expect(noDuration.progress, 0);
      expect(noDuration.canSeek, isFalse);
    },
  );

  test('a malformed payload degrades rather than throwing', () {
    final track = NowPlayingModel.toEntity(const {
      'available': true,
      'title': 42,
    });

    expect(track.title, isEmpty);
    expect(track.hasTrack, isFalse);
  });
}

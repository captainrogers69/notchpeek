import 'package:equatable/equatable.dart';
import 'package:notchpeek/shared/utils/enums/music_source_id.dart';
import 'package:notchpeek/shared/utils/enums/playback_state.dart';

class NowPlaying extends Equatable {
  const NowPlaying({
    required this.available,
    this.source = MusicSourceId.none,
    this.trackId = '',
    this.title = '',
    this.artist = '',
    this.album = '',
    this.duration = Duration.zero,
    this.position = Duration.zero,
    this.state = PlaybackState.unknown,
    this.artworkPath,
  });

  const NowPlaying.unavailable() : this(available: false);

  /// **False means the read failed, not that nothing is playing.** The
  /// macOS 26 wall fails silently, so this distinction is the difference
  /// between a needs-permission panel and a lying empty one (spec §7).
  final bool available;

  final MusicSourceId source;
  final String trackId;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final Duration position;
  final PlaybackState state;

  /// Always a local file path. Swift resolved Spotify's URL and Apple Music's
  /// bytes to the same shape before it crossed.
  final String? artworkPath;

  bool get hasTrack => available && trackId.isNotEmpty && title.isNotEmpty;
  bool get canSeek => duration > Duration.zero;
  double get progress => canSeek
      ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
      : 0;

  /// A tick carries position and state only. Everything else is kept.
  NowPlaying mergeTick(NowPlaying tick) {
    if (tick.trackId != trackId) return this;
    return copyWith(
      position: tick.position,
      state: tick.state,
      available: tick.available,
    );
  }

  NowPlaying copyWith({
    bool? available,
    MusicSourceId? source,
    String? trackId,
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    Duration? position,
    PlaybackState? state,
    String? artworkPath,
  }) => NowPlaying(
    available: available ?? this.available,
    source: source ?? this.source,
    trackId: trackId ?? this.trackId,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    album: album ?? this.album,
    duration: duration ?? this.duration,
    position: position ?? this.position,
    state: state ?? this.state,
    artworkPath: artworkPath ?? this.artworkPath,
  );

  @override
  List<Object?> get props => [
    available,
    source,
    trackId,
    title,
    artist,
    album,
    duration,
    position,
    state,
    artworkPath,
  ];
}

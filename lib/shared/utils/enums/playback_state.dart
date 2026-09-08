/// A raw string from a channel is never passed around unwrapped
/// (architecture-playbook §8).
enum PlaybackState {
  playing('playing', 'Playing'),
  paused('paused', 'Paused'),
  stopped('stopped', 'Stopped'),

  /// Also what a source that could not be read reports. The caller decides
  /// whether that means "nothing playing" or "unavailable" — see spec §7.
  unknown('unknown', 'Unknown');

  const PlaybackState(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static PlaybackState fromApi(String? value) {
    for (final s in PlaybackState.values) {
      if (s.apiValue == value) return s;
    }
    return PlaybackState.unknown;
  }

  bool get isPlaying => this == PlaybackState.playing;
}

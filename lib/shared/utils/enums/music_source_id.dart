enum MusicSourceId {
  appleMusic('appleMusic', 'Apple Music', 'com.apple.Music'),
  spotify('spotify', 'Spotify', 'com.spotify.client'),
  none('none', 'No player', '');

  const MusicSourceId(this.apiValue, this.label, this.bundleId);

  final String apiValue;
  final String label;
  final String bundleId;

  static MusicSourceId fromApi(String? value) {
    for (final s in MusicSourceId.values) {
      if (s.apiValue == value) return s;
    }
    return MusicSourceId.none;
  }
}

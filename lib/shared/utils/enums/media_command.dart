/// M1 sends these through scripting, not MediaRemote (spec §2, §9).
enum MediaCommand {
  playPause('playPause', 'Play or pause'),
  next('next', 'Next track'),
  previous('previous', 'Previous track'),
  seek('seek', 'Seek');

  const MediaCommand(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static MediaCommand? fromApi(String? value) {
    for (final c in MediaCommand.values) {
      if (c.apiValue == value) return c;
    }
    return null;
  }
}

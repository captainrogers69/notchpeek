/// `m:ss`, growing an hours field only when there is one. Used by the
/// scrubber and the track time labels.
String formatClock(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final ss = seconds.toString().padLeft(2, '0');

  if (hours == 0) return '$minutes:$ss';
  return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
}

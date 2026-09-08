import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/shared/utils/enums/media_command.dart';

/// Commands only. The *state* of the music comes from `nowPlayingProvider`;
/// this notifier exists so widgets call a named method rather than reaching
/// for a usecase themselves (architecture-playbook §2).
class MusicNotifier extends Notifier<NowPlaying> {
  @override
  NowPlaying build() =>
      // Riverpod 3 spells the nullable read `value`; there is no
      // `valueOrNull`.
      ref.watch(nowPlayingProvider).value ?? const NowPlaying.unavailable();

  void playPause() => _send(MediaCommand.playPause);
  void next() => _send(MediaCommand.next);
  void previous() => _send(MediaCommand.previous);
  void seek(Duration to) => _send(MediaCommand.seek, seekTo: to);

  void _send(MediaCommand command, {Duration? seekTo}) {
    ref.read(sendMediaCommandProvider)(command, seekTo: seekTo);
  }
}

/// Turns the 1 Hz native tick on and off, and never repeats itself — the shell
/// changes state far more often than polling needs to change.
class MediaPollingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool enabled) {
    if (state == enabled) return;
    state = enabled;
    ref.read(setMediaPollingProvider)(enabled);
  }
}

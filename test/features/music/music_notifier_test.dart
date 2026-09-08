import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/features/music/domain/repositories/music_repository.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/shared/utils/enums/media_command.dart';
import 'package:notchpeek/shared/utils/enums/music_source_id.dart';

class _RecordingMusicRepository implements MusicRepository {
  final List<(MediaCommand, Duration?)> commands = [];
  final List<bool> polling = [];
  final List<MusicSourceId> opened = [];

  @override
  Stream<NowPlaying> watch() => const Stream.empty();

  @override
  Future<ApiResponse<bool>> command(
    MediaCommand cmd, {
    Duration? seekTo,
  }) async {
    commands.add((cmd, seekTo));
    return ApiResponse.success(message: 'OK', data: true);
  }

  @override
  Future<ApiResponse<bool>> openPlayer(MusicSourceId source) async {
    opened.add(source);
    return ApiResponse.success(message: 'OK', data: true);
  }

  @override
  Future<ApiResponse<bool>> setPolling(bool enabled) async {
    polling.add(enabled);
    return ApiResponse.success(message: 'OK', data: true);
  }
}

ProviderContainer _container(_RecordingMusicRepository repo) {
  final c = ProviderContainer(
    overrides: [musicRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('each control sends exactly one command', () async {
    final repo = _RecordingMusicRepository();
    final notifier = _container(repo).read(musicNotifierProvider.notifier);

    notifier.playPause();
    notifier.next();
    notifier.previous();
    notifier.seek(const Duration(seconds: 42));
    await Future<void>.delayed(Duration.zero);

    expect(repo.commands.map((c) => c.$1).toList(), [
      MediaCommand.playPause,
      MediaCommand.next,
      MediaCommand.previous,
      MediaCommand.seek,
    ]);
    expect(repo.commands.last.$2, const Duration(seconds: 42));
  });

  test('polling follows whether the shell is showing anything', () async {
    final repo = _RecordingMusicRepository();
    final c = _container(repo);

    c.read(mediaPollingProvider.notifier).set(true);
    c.read(mediaPollingProvider.notifier).set(true);
    c.read(mediaPollingProvider.notifier).set(false);
    await Future<void>.delayed(Duration.zero);

    expect(repo.polling, [true, false], reason: 'no redundant channel calls');
  });
}

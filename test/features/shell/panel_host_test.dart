import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/core/platform/capabilities.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/features/music/domain/repositories/music_repository.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/features/shell/presentation/widgets/panel_host.dart';
import 'package:notchpeek/shared/utils/enums/media_command.dart';

class _RecordingMusicRepository implements MusicRepository {
  final List<bool> polling = [];

  @override
  Stream<NowPlaying> watch() => const Stream.empty();

  @override
  Future<ApiResponse<bool>> command(
    MediaCommand cmd, {
    Duration? seekTo,
  }) async => ApiResponse.success(message: 'OK', data: true);

  @override
  Future<ApiResponse<bool>> setPolling(bool enabled) async {
    polling.add(enabled);
    return ApiResponse.success(message: 'OK', data: true);
  }
}

void main() {
  // Polling must follow what is on screen, not what is subscribed (spec §4).
  // `PanelHost` is mounted only while expanded, so an effect keyed on
  // `isExpanded` could only ever run with `true` — the tick would never stop.
  testWidgets('mounting starts the tick and unmounting stops it', (
    tester,
  ) async {
    final repo = _RecordingMusicRepository();
    final container = ProviderContainer(
      overrides: [
        musicRepositoryProvider.overrideWithValue(repo),
        capabilitiesProvider.overrideWith(
          (ref) => Stream.value(const Capabilities()),
        ),
      ],
    );
    addTearDown(container.dispose);

    Future<void> show(bool mounted) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: DefaultTextStyle(
              style: const TextStyle(decoration: TextDecoration.none),
              child: SizedBox(
                width: 620,
                height: 220,
                child: mounted ? const PanelHost() : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await show(true);
    expect(repo.polling, [true], reason: 'expanding starts the 1 Hz tick');

    await show(false);
    await tester.pump();
    expect(repo.polling, [true, false], reason: 'collapsing must stop it');
  });
}

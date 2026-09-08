import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/core/platform/capabilities.dart';
import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/features/music/domain/repositories/music_repository.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/features/music/presentation/widgets/music_panel.dart';
import 'package:notchpeek/shared/utils/enums/media_command.dart';
import 'package:notchpeek/shared/utils/enums/music_source_id.dart';
import 'package:notchpeek/shared/utils/enums/playback_state.dart';
import 'package:notchpeek/shared/widgets/permission_prompt.dart';

const _playing = NowPlaying(
  available: true,
  source: MusicSourceId.spotify,
  trackId: 'spotify:track:abc',
  title: 'Ada',
  artist: 'Sonu Nigam',
  album: 'Ada',
  duration: Duration(seconds: 240),
  position: Duration(seconds: 61),
  state: PlaybackState.playing,
);

/// Deliberately **not** a `MaterialApp`: production mounts this panel under a
/// `WidgetsApp`, where there is no `Material` and no `Overlay`. Wrapping the
/// test in Material would hide exactly the class of bug that the scrubber hit.
class _RecordingMusicRepository implements MusicRepository {
  final List<(MediaCommand, Duration?)> commands = [];
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
  Future<ApiResponse<bool>> setPolling(bool enabled) async =>
      ApiResponse.success(message: 'OK', data: true);
}

Future<void> _pump(
  WidgetTester tester, {
  required Capabilities caps,
  required NowPlaying track,
  MusicRepository? repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        capabilitiesProvider.overrideWith((ref) => Stream.value(caps)),
        nowPlayingProvider.overrideWith((ref) => Stream.value(track)),
        if (repository != null)
          musicRepositoryProvider.overrideWithValue(repository),
      ],
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: TextStyle(
            fontSize: 13,
            color: NotchColors.primaryText,
            decoration: TextDecoration.none,
          ),
          // `Center` is load-bearing: the root's constraints are tight, and a
          // bare `SizedBox` enforces its size against them, so it would be
          // stretched to the full 800x600 surface and the panel would be laid
          // out at a width it never has in production. The repaint boundary
          // then makes a golden capture the panel rather than the surface.
          child: Center(
            child: RepaintBoundary(
              child: ColoredBox(
                color: NotchColors.panel,
                child: SizedBox(
                  width: NotchSizes.expandedWidth,
                  height: NotchSizes.expandedHeight,
                  child: MusicPanel(),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // Twice, deliberately. `nowPlayingProvider` is first watched inside
  // `_MusicReady`, which only exists once `capabilitiesProvider` has
  // resolved — so the second stream subscribes a frame after the first.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('ready: shows the track, the artist and working controls', (
    tester,
  ) async {
    await _pump(
      tester,
      caps: Capabilities.fromMap(const {
        'scriptingMedia': {'spotify': 'granted'},
      }),
      track: _playing,
    );

    expect(find.text('Ada'), findsWidgets);
    expect(find.text('Sonu Nigam'), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
  });

  testWidgets('ready but paused: offers play rather than pause', (
    tester,
  ) async {
    await _pump(
      tester,
      caps: Capabilities.fromMap(const {
        'scriptingMedia': {'spotify': 'granted'},
      }),
      track: _playing.copyWith(state: PlaybackState.paused),
    );

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('never asked, with a player running: offers Grant Access', (
    tester,
  ) async {
    await _pump(
      tester,
      caps: Capabilities.fromMap(const {
        'scriptingMedia': {'appleMusic': 'notDetermined'},
        'runningPlayers': ['appleMusic'],
      }),
      track: const NowPlaying.unavailable(),
    );

    expect(find.text('Grant Access'), findsOneWidget);
    expect(
      find.text('Open Settings'),
      findsNothing,
      reason: 'that pane has no row for us until a request has been made',
    );
  });

  testWidgets('never asked, no player running: says to start one', (
    tester,
  ) async {
    await _pump(
      tester,
      caps: Capabilities.fromMap(const {
        'scriptingMedia': {'appleMusic': 'notDetermined'},
        'runningPlayers': <String>[],
      }),
      track: const NowPlaying.unavailable(),
    );

    // macOS raises no prompt for a stopped target, so this must not offer
    // "Grant Access" — but it must still offer a way into the pane rather
    // than being a dead end.
    expect(find.textContaining('Open Apple Music or Spotify'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
    expect(find.text('Grant Access'), findsNothing);
  });

  testWidgets('refused: explains and offers Open Settings', (tester) async {
    await _pump(
      tester,
      caps: Capabilities.fromMap(const {
        'scriptingMedia': {'appleMusic': 'denied', 'spotify': 'denied'},
      }),
      track: const NowPlaying.unavailable(),
    );

    expect(find.byType(PermissionPrompt), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('unavailable: renders nothing rather than teasing a feature', (
    tester,
  ) async {
    await _pump(
      tester,
      caps: Capabilities.fromMap(const {
        'scriptingMedia': {'appleMusic': 'absent', 'spotify': 'absent'},
      }),
      track: const NowPlaying.unavailable(),
    );

    expect(find.byType(PermissionPrompt), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  // Two empty states, two different fixes: no player open is answered by
  // opening one, a player open with nothing queued by its own transport.
  testWidgets('player open but nothing queued: shows a live transport', (
    tester,
  ) async {
    await _pump(
      tester,
      caps: Capabilities.fromMap(const {
        'scriptingMedia': {'spotify': 'granted'},
        'runningPlayers': ['spotify'],
      }),
      track: const NowPlaying(available: true, source: MusicSourceId.spotify),
    );

    expect(find.text('Not Playing'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
    expect(
      find.text('Open Spotify'),
      findsNothing,
      reason: 'the player is already open',
    );
  });

  // The payload carries no source when there was nothing to read, which left
  // the thumbnail and the transport with no target at all.
  testWidgets('the empty state targets the running player, not the payload', (
    tester,
  ) async {
    final repo = _RecordingMusicRepository();
    await _pump(
      tester,
      caps: Capabilities.fromMap(const {
        'scriptingMedia': {'spotify': 'granted'},
        'runningPlayers': ['spotify'],
      }),
      // No sourceId: this is what a read of nothing looks like.
      track: const NowPlaying(available: true),
      repository: repo,
    );

    expect(find.text('Not Playing'), findsOneWidget);
    expect(find.text('Spotify'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.music_note));
    await tester.pump();
    expect(repo.opened, [MusicSourceId.spotify]);

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(repo.commands.single.$1, MediaCommand.playPause);
  });

  testWidgets('tapping the track area brings the player forward', (
    tester,
  ) async {
    final repo = _RecordingMusicRepository();
    await _pump(
      tester,
      caps: Capabilities.fromMap(const {
        'scriptingMedia': {'spotify': 'granted'},
      }),
      track: _playing,
      repository: repo,
    );

    await tester.tap(find.text('Sonu Nigam'));
    await tester.pump();

    expect(repo.opened, [MusicSourceId.spotify]);
  });

  testWidgets('pressing play does not also raise the player', (tester) async {
    final repo = _RecordingMusicRepository();
    await _pump(
      tester,
      caps: Capabilities.fromMap(const {
        'scriptingMedia': {'spotify': 'granted'},
      }),
      track: _playing,
      repository: repo,
    );

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();

    expect(repo.commands.single.$1, MediaCommand.playPause);
    expect(repo.opened, isEmpty, reason: 'the button wins the gesture');
  });

  testWidgets(
    'granted but nothing playing: an idle placeholder, not a prompt',
    (tester) async {
      await _pump(
        tester,
        caps: Capabilities.fromMap(const {
          'scriptingMedia': {'spotify': 'granted'},
        }),
        track: const NowPlaying(available: true),
      );

      expect(find.byType(PermissionPrompt), findsNothing);
      expect(find.textContaining('Nothing playing'), findsOneWidget);
    },
  );

  // One test per state, each with its own `pumpWidget`. Three `_pump` calls
  // inside a single test reuse the element tree, so the later overrides never
  // take effect and every capture is the first state — which made all three
  // golden files byte-identical.
  testWidgets('golden: ready', (tester) async {
    await _pump(
      tester,
      caps: Capabilities.fromMap(const {
        'scriptingMedia': {'spotify': 'granted'},
      }),
      track: _playing,
    );
    await expectLater(
      find.byType(MusicPanel),
      matchesGoldenFile('goldens/music_ready.png'),
    );
  });

  testWidgets('golden: never asked', (tester) async {
    await _pump(
      tester,
      caps: Capabilities.fromMap(const {
        'scriptingMedia': {'appleMusic': 'notDetermined'},
        'runningPlayers': ['appleMusic'],
      }),
      track: const NowPlaying.unavailable(),
    );
    await expectLater(
      find.byType(MusicPanel),
      matchesGoldenFile('goldens/music_not_determined.png'),
    );
  });

  testWidgets('golden: no player running', (tester) async {
    await _pump(
      tester,
      caps: Capabilities.fromMap(const {
        'scriptingMedia': {'appleMusic': 'notDetermined'},
        'runningPlayers': <String>[],
      }),
      track: const NowPlaying.unavailable(),
    );
    await expectLater(
      find.byType(MusicPanel),
      matchesGoldenFile('goldens/music_no_player.png'),
    );
  });

  testWidgets('golden: refused', (tester) async {
    await _pump(
      tester,
      caps: Capabilities.fromMap(const {
        'scriptingMedia': {'appleMusic': 'denied', 'spotify': 'denied'},
      }),
      track: const NowPlaying.unavailable(),
    );
    await expectLater(
      find.byType(MusicPanel),
      matchesGoldenFile('goldens/music_denied.png'),
    );
  });

  testWidgets('golden: idle', (tester) async {
    await _pump(
      tester,
      caps: Capabilities.fromMap(const {
        'scriptingMedia': {'spotify': 'granted'},
      }),
      track: const NowPlaying(available: true),
    );
    await expectLater(
      find.byType(MusicPanel),
      matchesGoldenFile('goldens/music_idle.png'),
    );
  });
}

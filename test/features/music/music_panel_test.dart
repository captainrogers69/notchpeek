import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/core/platform/capabilities.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/features/music/presentation/widgets/music_panel.dart';
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
Future<void> _pump(
  WidgetTester tester, {
  required Capabilities caps,
  required NowPlaying track,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        capabilitiesProvider.overrideWith((ref) => Stream.value(caps)),
        nowPlayingProvider.overrideWith((ref) => Stream.value(track)),
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

  testWidgets('needs permission: explains and offers Open Settings', (
    tester,
  ) async {
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

  testWidgets('golden: needs permission', (tester) async {
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

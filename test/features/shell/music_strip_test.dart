import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/features/shell/domain/entities/notch_geometry.dart';
import 'package:notchpeek/features/shell/presentation/widgets/music_strip.dart';
import 'package:notchpeek/shared/utils/enums/playback_state.dart';
import 'package:notchpeek/shared/widgets/artwork_tile.dart';
import 'package:notchpeek/shared/widgets/audio_bars.dart';

const _geometry = NotchGeometry(
  screenWidth: 1470,
  screenHeight: 956,
  notchWidth: 179,
  notchHeight: 32,
  notchLeft: 646,
  scale: 2,
  isVirtual: false,
  displayId: 7,
);

const _track = NowPlaying(
  available: true,
  trackId: 'a',
  title: 'A',
  artist: 'B',
  state: PlaybackState.playing,
);

Future<void> _pump(WidgetTester tester, NowPlaying track) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        nowPlayingProvider.overrideWith((ref) => Stream.value(track)),
      ],
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(width: 320, height: 38, child: MusicStrip()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('the strip clears the notch on both sides', () {
    final strip = _geometry.stripRect();

    expect(strip.width, 320);
    expect(strip.center.dx, _geometry.centerX);
    // Artwork and meter live at the ends; the notch sits between them.
    expect(strip.left, lessThan(_geometry.notchRect.left));
    expect(strip.right, greaterThan(_geometry.notchRect.right));
  });

  testWidgets('artwork one end, level meter the other', (tester) async {
    await _pump(tester, _track);

    expect(find.byType(ArtworkTile), findsOneWidget);
    expect(find.byType(AudioBars), findsOneWidget);

    final artwork = tester.getCenter(find.byType(ArtworkTile));
    final bars = tester.getCenter(find.byType(AudioBars));
    expect(artwork.dx, lessThan(bars.dx));
  });

  // One state per test: re-pumping keeps the first provider override, so
  // asserting both in one test silently checks the same state twice.
  testWidgets('the meter animates while playing', (tester) async {
    await _pump(tester, _track);

    expect(tester.widget<AudioBars>(find.byType(AudioBars)).active, isTrue);
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('the meter rests, and holds no ticker, while paused', (
    tester,
  ) async {
    await _pump(
      tester,
      const NowPlaying(
        available: true,
        trackId: 'a',
        title: 'A',
        state: PlaybackState.paused,
      ),
    );

    expect(tester.widget<AudioBars>(find.byType(AudioBars)).active, isFalse);
    // A resting notch must not keep waking the UI thread.
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('nothing at all when no track is loaded', (tester) async {
    await _pump(tester, const NowPlaying.unavailable());

    expect(find.byType(ArtworkTile), findsNothing);
    expect(find.byType(AudioBars), findsNothing);
  });
}

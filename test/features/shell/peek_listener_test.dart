import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/features/shell/domain/entities/power_state.dart';
import 'package:notchpeek/features/shell/presentation/peek_listener.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';
import 'package:notchpeek/shared/utils/enums/notch_state.dart';
import 'package:notchpeek/shared/utils/enums/peek_kind.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Stream<NowPlaying> tracks,
  Stream<PowerState> power,
) async {
  final container = ProviderContainer(
    overrides: [
      nowPlayingProvider.overrideWith((ref) => tracks),
      powerProvider.overrideWith((ref) => power),
      peekDwellProvider.overrideWithValue(const Duration(seconds: 30)),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const PeekListener(child: SizedBox.shrink()),
    ),
  );
  return container;
}

void main() {
  testWidgets('a new track id peeks', (tester) async {
    final controller = StreamController<NowPlaying>();
    addTearDown(controller.close);
    final c = await _pump(tester, controller.stream, const Stream.empty());

    controller.add(const NowPlaying(available: true, trackId: 'a', title: 'A'));
    await tester.pump();
    controller.add(const NowPlaying(available: true, trackId: 'b', title: 'B'));
    await tester.pump();

    expect(c.read(shellNotifierProvider).state, NotchState.peeking);
    expect(c.read(shellNotifierProvider).peek, PeekKind.trackChange);
    c.read(shellNotifierProvider.notifier).peekExpired();
  });

  testWidgets('the very first track does not peek — that is just startup', (
    tester,
  ) async {
    final controller = StreamController<NowPlaying>();
    addTearDown(controller.close);
    final c = await _pump(tester, controller.stream, const Stream.empty());

    controller.add(const NowPlaying(available: true, trackId: 'a', title: 'A'));
    await tester.pump();

    expect(c.read(shellNotifierProvider).state, NotchState.collapsed);
  });

  testWidgets('a position tick on the same track does not peek', (
    tester,
  ) async {
    final controller = StreamController<NowPlaying>();
    addTearDown(controller.close);
    final c = await _pump(tester, controller.stream, const Stream.empty());

    controller.add(const NowPlaying(available: true, trackId: 'a', title: 'A'));
    await tester.pump();
    controller.add(
      const NowPlaying(
        available: true,
        trackId: 'a',
        title: 'A',
        position: Duration(seconds: 5),
      ),
    );
    await tester.pump();

    expect(c.read(shellNotifierProvider).state, NotchState.collapsed);
  });

  testWidgets('plugging the charger in peeks; unplugging does not', (
    tester,
  ) async {
    final controller = StreamController<PowerState>();
    addTearDown(controller.close);
    final c = await _pump(tester, const Stream.empty(), controller.stream);

    controller.add(
      const PowerState(percent: 50, isCharging: false, isPresent: true),
    );
    await tester.pump();
    controller.add(
      const PowerState(percent: 50, isCharging: true, isPresent: true),
    );
    await tester.pump();
    expect(c.read(shellNotifierProvider).peek, PeekKind.charger);

    c.read(shellNotifierProvider.notifier).peekExpired();
    controller.add(
      const PowerState(percent: 51, isCharging: false, isPresent: true),
    );
    await tester.pump();
    expect(c.read(shellNotifierProvider).state, NotchState.collapsed);
  });
}

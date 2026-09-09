import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/shell/domain/entities/notch_geometry.dart';
import 'package:notchpeek/features/shell/domain/entities/power_state.dart';
import 'package:notchpeek/features/shell/domain/entities/shell_state.dart';
import 'package:notchpeek/features/shell/domain/repositories/shell_repository.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';
import 'package:notchpeek/shared/utils/enums/notch_state.dart';
import 'package:notchpeek/shared/utils/enums/panel_tab.dart';
import 'package:notchpeek/shared/utils/enums/peek_kind.dart';

/// The notifier ticks the trackpad on every morph, which is a channel call.
/// Overridden here so these stay pure unit tests with no binding.
class _FakeShellRepository implements ShellRepository {
  final StreamController<bool> hover = StreamController<bool>.broadcast();
  int haptics = 0;

  @override
  Stream<NotchGeometry> watchGeometry() => const Stream.empty();

  @override
  Stream<bool> watchHover() => hover.stream;

  @override
  Stream<PowerState> watchPower() => const Stream.empty();

  @override
  Future<ApiResponse<bool>> setInteractiveRect(Rect rect) async =>
      ApiResponse.success(message: 'OK', data: true);

  @override
  Future<ApiResponse<bool>> performHaptic() async {
    haptics++;
    return ApiResponse.success(message: 'OK', data: true);
  }

  @override
  Future<ApiResponse<bool>> quit() async =>
      ApiResponse.success(message: 'OK', data: true);
}

/// A channel event reaches the machine through a `StreamProvider`, which is
/// several event-loop turns deep. Poll rather than guess a delay.
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 50 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ProviderContainer _container([_FakeShellRepository? repository]) {
  final container = ProviderContainer(
    overrides: [
      peekDwellProvider.overrideWithValue(Duration.zero),
      shellRepositoryProvider.overrideWithValue(
        repository ?? _FakeShellRepository(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  // Hover arrives from Swift, not from a Flutter `MouseRegion`: `MouseGate`
  // makes the panel mouse-transparent the instant the cursor leaves the rect
  // it was told about, and AppKit sends no `mouseExited` for that, so Flutter
  // would latch "entered" and the shell would never collapse.
  test('a native hover event expands, and losing hover collapses', () async {
    final repo = _FakeShellRepository();
    addTearDown(repo.hover.close);
    final c = _container(repo);
    // The notifier subscribes to hover when it is first built.
    c.read(shellNotifierProvider);

    repo.hover.add(true);
    await _until(() => c.read(shellNotifierProvider).isExpanded);
    expect(c.read(shellNotifierProvider).state, NotchState.expanded);

    repo.hover.add(false);
    await _until(() => c.read(shellNotifierProvider).isCollapsed);
    expect(c.read(shellNotifierProvider).state, NotchState.collapsed);
  });

  test('each morph the user asked for ticks the trackpad once', () {
    final repo = _FakeShellRepository();
    final notifier = _container(repo).read(shellNotifierProvider.notifier);

    notifier.hoverEntered();
    expect(repo.haptics, 1);

    notifier.hoverExited();
    expect(repo.haptics, 2);

    // A peek is the app interrupting the user; it must not buzz them.
    notifier.peekRequested(PeekKind.charger);
    notifier.peekExpired();
    expect(repo.haptics, 2);
  });

  test('starts collapsed on the music tab with no peek', () {
    final state = _container().read(shellNotifierProvider);

    expect(state.state, NotchState.collapsed);
    expect(state.peek, isNull);
    expect(state.tab, PanelTab.music);
    expect(state.showsContent, isFalse);
  });

  test('hover expands from collapsed and from peeking', () {
    final c = _container();
    final notifier = c.read(shellNotifierProvider.notifier);

    notifier.hoverEntered();
    expect(c.read(shellNotifierProvider).state, NotchState.expanded);

    notifier.hoverExited();
    notifier.peekRequested(PeekKind.trackChange);
    notifier.hoverEntered();
    expect(c.read(shellNotifierProvider).state, NotchState.expanded);
    expect(
      c.read(shellNotifierProvider).peek,
      isNull,
      reason: 'expanding consumes the peek',
    );
  });

  test('leaving collapses and clears the peek', () {
    final c = _container();
    final notifier = c.read(shellNotifierProvider.notifier);

    notifier.hoverEntered();
    notifier.hoverExited();

    expect(c.read(shellNotifierProvider).state, NotchState.collapsed);
    expect(c.read(shellNotifierProvider).peek, isNull);
  });

  test('a peek moves collapsed to peeking and records why', () {
    final c = _container();

    c.read(shellNotifierProvider.notifier).peekRequested(PeekKind.charger);

    expect(c.read(shellNotifierProvider).state, NotchState.peeking);
    expect(c.read(shellNotifierProvider).peek, PeekKind.charger);
  });

  test('a peek never interrupts an expanded panel', () {
    final c = _container();
    final notifier = c.read(shellNotifierProvider.notifier);

    notifier.hoverEntered();
    notifier.peekRequested(PeekKind.trackChange);

    expect(c.read(shellNotifierProvider).state, NotchState.expanded);
    expect(c.read(shellNotifierProvider).peek, isNull);
  });

  test('a peek retracts on its own', () async {
    final c = _container();

    c.read(shellNotifierProvider.notifier).peekRequested(PeekKind.trackChange);
    await Future<void>.delayed(Duration.zero);

    expect(c.read(shellNotifierProvider).state, NotchState.collapsed);
  });

  test('a second peek restarts the dwell rather than stacking', () {
    final c = _container();
    final notifier = c.read(shellNotifierProvider.notifier);

    notifier.peekRequested(PeekKind.trackChange);
    notifier.peekRequested(PeekKind.charger);

    expect(c.read(shellNotifierProvider).peek, PeekKind.charger);
    expect(c.read(shellNotifierProvider).state, NotchState.peeking);
  });

  test('peekExpired is ignored unless we are actually peeking', () {
    final c = _container();
    final notifier = c.read(shellNotifierProvider.notifier);

    notifier.hoverEntered();
    notifier.peekExpired();

    expect(c.read(shellNotifierProvider).state, NotchState.expanded);
  });

  test(
    'a forced collapse wins from any state — display unplugged mid-expand',
    () {
      final c = _container();
      final notifier = c.read(shellNotifierProvider.notifier);

      notifier.hoverEntered();
      notifier.forceCollapse();

      expect(c.read(shellNotifierProvider).state, NotchState.collapsed);
    },
  );

  test('selecting a tab keeps the panel open and remembers the choice', () {
    final c = _container();
    final notifier = c.read(shellNotifierProvider.notifier);

    notifier.hoverEntered();
    notifier.tabSelected(PanelTab.calendar);

    expect(c.read(shellNotifierProvider).tab, PanelTab.calendar);
    expect(c.read(shellNotifierProvider).state, NotchState.expanded);
  });

  test('showsContent is true whenever the panel is not collapsed', () {
    const collapsed = ShellState();
    expect(collapsed.showsContent, isFalse);
    expect(collapsed.copyWith(state: NotchState.peeking).showsContent, isTrue);
    expect(collapsed.copyWith(state: NotchState.expanded).showsContent, isTrue);
  });
}

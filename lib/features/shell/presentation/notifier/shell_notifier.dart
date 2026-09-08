import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/core/logging/notch_logger.dart';
import 'package:notchpeek/features/shell/domain/entities/shell_state.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';
import 'package:notchpeek/shared/utils/enums/notch_state.dart';
import 'package:notchpeek/shared/utils/enums/panel_tab.dart';
import 'package:notchpeek/shared/utils/enums/peek_kind.dart';

/// The shell's state machine. Widgets never mutate this directly — they call
/// a named method (architecture-playbook §2).
class ShellNotifier extends Notifier<ShellState> {
  final NotchLogger _log = NotchLogger.forTag('ShellNotifier');
  Timer? _peekTimer;

  @override
  ShellState build() {
    ref.onDispose(() => _peekTimer?.cancel());

    // Hover is an input to the machine, not a widget concern, so the machine
    // subscribes to it. It comes from Swift rather than from a `MouseRegion`
    // because `MouseGate` makes the panel mouse-transparent the instant the
    // cursor leaves the reported rect, and AppKit sends no `mouseExited` for
    // that — Flutter would latch "entered" and the shell would never collapse.
    //
    // Subscribed directly rather than through a `StreamProvider`: this is the
    // only consumer, and one hop fewer is one hop fewer to lose an event in.
    final hover = ref.watch(watchHoverProvider)().listen((inside) {
      if (inside) {
        hoverEntered();
      } else {
        hoverExited();
      }
    });
    ref.onDispose(hover.cancel);

    return const ShellState();
  }

  void hoverEntered() {
    if (state.isExpanded) return;
    _cancelPeek();
    _log.debug('expand');
    state = state.copyWith(state: NotchState.expanded, clearPeek: true);
    _tick();
  }

  void hoverExited() {
    if (state.isCollapsed) return;
    _cancelPeek();
    _log.debug('collapse');
    state = state.copyWith(state: NotchState.collapsed, clearPeek: true);
    _tick();
  }

  /// A peek never interrupts an open panel: the user is already looking at
  /// more than the peek would show.
  void peekRequested(PeekKind kind) {
    if (state.isExpanded) return;

    _cancelPeek();
    _log.debug('peek ${kind.apiValue}');
    state = state.copyWith(state: NotchState.peeking, peek: kind);

    _peekTimer = Timer(ref.read(peekDwellProvider), peekExpired);
  }

  void peekExpired() {
    if (state.state != NotchState.peeking) return;
    _cancelPeek();
    state = state.copyWith(state: NotchState.collapsed, clearPeek: true);
  }

  /// Display disconnected mid-expand, Space switched away, geometry moved.
  void forceCollapse() {
    _cancelPeek();
    if (state.isCollapsed) return;
    _log.debug('forced collapse');
    state = state.copyWith(state: NotchState.collapsed, clearPeek: true);
  }

  void tabSelected(PanelTab tab) {
    if (state.tab == tab) return;
    state = state.copyWith(tab: tab);
  }

  /// One tick of trackpad haptics per morph the user asked for. Deliberately
  /// not fired for [peekRequested] or [peekExpired]: a peek is the app
  /// interrupting the user, and buzzing them for it would be noise.
  void _tick() {
    ref.read(performHapticProvider)();
  }

  void _cancelPeek() {
    _peekTimer?.cancel();
    _peekTimer = null;
  }
}

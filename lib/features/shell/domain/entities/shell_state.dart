import 'package:equatable/equatable.dart';
import 'package:notchpeek/shared/utils/enums/notch_state.dart';
import 'package:notchpeek/shared/utils/enums/panel_tab.dart';
import 'package:notchpeek/shared/utils/enums/peek_kind.dart';

/// Derived values are getters here, never computed in the UI
/// (architecture-playbook §2).
class ShellState extends Equatable {
  const ShellState({
    this.state = NotchState.collapsed,
    this.peek,
    this.tab = PanelTab.music,
  });

  final NotchState state;

  /// Why we are peeking. Null in every other state.
  final PeekKind? peek;

  final PanelTab tab;

  bool get isExpanded => state == NotchState.expanded;
  bool get isCollapsed => state == NotchState.collapsed;

  /// Collapsed means stop work: no polling, no animation, no camera session
  /// (architecture-playbook §9).
  bool get showsContent => state != NotchState.collapsed;

  ShellState copyWith({
    NotchState? state,
    PeekKind? peek,
    bool clearPeek = false,
    PanelTab? tab,
  }) => ShellState(
    state: state ?? this.state,
    peek: clearPeek ? null : (peek ?? this.peek),
    tab: tab ?? this.tab,
  );

  @override
  List<Object?> get props => [state, peek, tab];
}

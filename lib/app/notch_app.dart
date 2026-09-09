import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/features/shell/presentation/peek_listener.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';
import 'package:notchpeek/features/shell/presentation/widgets/notch_shell.dart';
import 'package:notchpeek/features/shell/presentation/widgets/panel_host.dart';
import 'package:notchpeek/shared/utils/enums/notch_state.dart';
import 'package:notchpeek/features/shell/presentation/widgets/music_strip.dart';
import 'package:notchpeek/features/shell/presentation/widgets/peek_content.dart';

/// The root widget. There is no routing package and no navigator: one window,
/// one panel, tab selection is state (architecture-playbook §9).
class NotchApp extends StatelessWidget {
  const NotchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: NotchColors.panel,
      debugShowCheckedModeBanner: false,
      builder: (context, _) => const DefaultTextStyle(
        style: TextStyle(
          fontSize: 13,
          color: NotchColors.primaryText,
          decoration: TextDecoration.none,
        ),
        child: NotchSurface(),
      ),
    );
  }
}

/// Renders nothing until geometry has resolved. **Never flash a misplaced
/// panel** (spec §7) — a full-width transparent canvas with a notch drawn in
/// the wrong place is worse than an empty one.
class NotchSurface extends ConsumerWidget {
  const NotchSurface({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final geometry = ref.watch(geometryProvider);
    final hasTrack = ref.watch(
      nowPlayingProvider.select((t) => t.value?.hasTrack ?? false),
    );

    // Outside the switch, not inside it: peeks have to be listened for before
    // geometry resolves and while the notch is collapsed, and this is the only
    // thing keeping the media channel subscribed.
    return PeekListener(
      child: switch (geometry) {
        AsyncData(:final value) => NotchShell(
          geometry: value,
          showsStrip: hasTrack,
          child: const _ShellContent(),
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

/// The peek body and the full panel are different content, not the same
/// content at two sizes.
class _ShellContent extends ConsumerWidget {
  const _ShellContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(shellNotifierProvider.select((s) => s.state));
    return switch (state) {
      NotchState.expanded => const PanelHost(),
      NotchState.peeking => const PeekContent(),
      // Resting, with something loaded: artwork and a level meter.
      NotchState.collapsed => const MusicStrip(),
    };
  }
}

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';
import 'package:notchpeek/shared/utils/enums/peek_kind.dart';

/// Watches for the events that deserve a peek and asks the shell for one.
/// Wraps the tree rather than living inside a panel, because peeks fire while
/// the panel is collapsed and nothing is mounted.
///
/// This is also the only thing that keeps `nowPlayingProvider` subscribed
/// while collapsed — without it the media channel has no listener and a track
/// change never reaches Dart at all.
class PeekListener extends ConsumerWidget {
  const PeekListener({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A track *change*, not the first track we ever see: at launch there is
    // always a "new" track, and peeking at startup would be noise.
    ref.listen(nowPlayingProvider.select((t) => t.value?.trackId), (
      previous,
      next,
    ) {
      if (previous == null || next == null) return;
      if (previous == next || next.isEmpty) return;
      ref
          .read(shellNotifierProvider.notifier)
          .peekRequested(PeekKind.trackChange);
    });

    // The charging *edge*. Unplugging is not an event worth interrupting for.
    ref.listen(powerProvider.select((p) => p.value?.isCharging), (
      previous,
      next,
    ) {
      if (previous == null || next == null) return;
      if (previous == false && next == true) {
        ref
            .read(shellNotifierProvider.notifier)
            .peekRequested(PeekKind.charger);
      }
    });

    return child;
  }
}

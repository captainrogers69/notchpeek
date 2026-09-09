import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/core/platform/capabilities.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/features/music/presentation/widgets/music_panel.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';
import 'package:notchpeek/features/shell/presentation/widgets/status_row.dart';
import 'package:notchpeek/features/shell/presentation/widgets/tab_strip.dart';
import 'package:notchpeek/shared/utils/enums/capability_state.dart';
import 'package:notchpeek/shared/utils/enums/panel_tab.dart';

/// Which tabs this build, this OS and these permissions can actually show.
/// M1 has one candidate; the list is computed rather than hard-coded so M2–M4
/// only add entries.
final visibleTabsProvider = Provider<List<PanelTab>>((ref) {
  final caps = ref.watch(capabilitiesProvider).value;
  return [
    if (caps == null || caps.music != CapabilityState.absent) PanelTab.music,
  ];
});

/// The expanded panel's contents. Also the one place that turns the native
/// 1 Hz position tick on and off — polling follows what is on screen, not what
/// is subscribed (spec §4).
class PanelHost extends HookConsumerWidget {
  const PanelHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shell = ref.watch(shellNotifierProvider);
    final tabs = ref.watch(visibleTabsProvider);

    // This widget is mounted **only while expanded**, so keying an effect on
    // `isExpanded` could only ever run it with `true` — nothing would ever
    // turn polling back off, and the tick would run forever after the first
    // expand. Mount starts it, unmount stops it.
    //
    // Both legs hop off the build phase. `useEffect` bodies run inside
    // `initHook`, and the teardown runs during unmount; Riverpod rejects a
    // provider mutation in either ("Tried to modify a provider while the
    // widget tree was building"), which silently swallowed every call and
    // left the tick permanently off.
    //
    // The notifier is captured outside the effect too: `ref` must not be read
    // from a teardown that runs once this element is gone.
    final polling = ref.read(mediaPollingProvider.notifier);
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) => polling.set(true));
      return () => Future<void>.microtask(() => polling.set(false));
    }, [polling]);

    return Column(
      children: [
        TabStrip(
          tabs: tabs,
          selected: shell.tab,
          onSelected: ref.read(shellNotifierProvider.notifier).tabSelected,
        ),
        Expanded(
          child: switch (shell.tab) {
            PanelTab.music => const MusicPanel(),
            // M2–M4 add their panels here. Until then a tab that is not built
            // cannot be selected, because `visibleTabsProvider` does not offer
            // it.
            _ => const SizedBox.shrink(),
          },
        ),
        // Padded, unlike the panels, which carry their own. Without it the
        // row sits flush against the shell's rounded corner and gets clipped
        // — which is what happened to the source badge that used to be here.
        const Padding(
          padding: EdgeInsets.only(left: 16, right: 22),
          child: StatusRow(),
        ),
      ],
    );
  }
}

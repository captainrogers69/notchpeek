import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';
import 'package:notchpeek/features/shell/presentation/widgets/notch_shell.dart';

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

    return switch (geometry) {
      AsyncData(:final value) => NotchShell(
        geometry: value,
        // The tab strip and panels land here in Task 21.
        child: const SizedBox.shrink(),
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The bottom strip of the expanded panel. The battery pill lands here in
/// Task 22.
///
/// The source badge that used to sit on the left is gone: naming the player is
/// redundant next to its own artwork, and the row is flush with the panel edge
/// where the shell's rounded corner clips it. It renders nothing rather than
/// reserving height for nothing.
class StatusRow extends ConsumerWidget {
  const StatusRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => const SizedBox.shrink();
}

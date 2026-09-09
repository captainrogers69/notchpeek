import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/features/shell/presentation/widgets/battery_pill.dart';

/// The bottom strip of the expanded panel: the battery pill, right-aligned.
///
/// The source badge that used to sit on the left is gone — naming the player
/// is redundant next to its own artwork.
class StatusRow extends ConsumerWidget {
  const StatusRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => const SizedBox(
    height: 18,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [BatteryPill()],
    ),
  );
}

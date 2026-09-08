import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';
import 'package:notchpeek/shared/utils/enums/peek_kind.dart';
import 'package:notchpeek/shared/widgets/artwork_tile.dart';

/// The peek body: small, one line, gone in four seconds.
class PeekContent extends ConsumerWidget {
  const PeekContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(shellNotifierProvider.select((s) => s.peek));
    final track = ref.watch(nowPlayingProvider).value;

    return Padding(
      // Right side keeps clear of the shell's close button.
      padding: const EdgeInsets.only(left: 10, right: 44),
      child: Row(
        children: [
          if (kind == PeekKind.trackChange)
            ArtworkTile(path: track?.artworkPath, side: 26),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              switch (kind) {
                PeekKind.trackChange => track?.title ?? '',
                PeekKind.charger => 'Charging',
                null => '',
              },
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: NotchColors.primaryText,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

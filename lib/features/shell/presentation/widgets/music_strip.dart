import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/shared/widgets/artwork_tile.dart';
import 'package:notchpeek/shared/widgets/audio_bars.dart';

/// The collapsed notch with a track loaded: artwork on one side, a level meter
/// on the other, and the notch itself in between.
///
/// Both sit hard against the ends because the middle of this strip is the
/// physical notch on hardware that has one — anything drawn there is drawn
/// inside the cutout.
class MusicStrip extends ConsumerWidget {
  const MusicStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(nowPlayingProvider).value;
    if (track == null || !track.hasTrack) return const SizedBox.shrink();

    return Padding(
      // 16, not 10: the shape's concave shoulder cuts in to x = 13 at this
      // height, and anything closer to the end gets sliced by the clipper.
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ArtworkTile(path: track.artworkPath, side: 22),
          AudioBars(active: track.state.isPlaying),
        ],
      ),
    );
  }
}

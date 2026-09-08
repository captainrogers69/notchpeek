import 'dart:io';

import 'package:flutter/material.dart';
import 'package:notchpeek/app/theme.dart';

/// Always a local file — Swift resolved Spotify's URL and Apple Music's bytes
/// to one shape before it crossed. **Never blocks the track update on the
/// image** (spec §7): a missing or half-written file falls back silently.
class ArtworkTile extends StatelessWidget {
  const ArtworkTile({
    required this.path,
    this.side = NotchSizes.artworkSide,
    super.key,
  });

  final String? path;
  final double side;

  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);

    return ClipRRect(
      borderRadius: BorderRadius.circular(NotchRadii.artwork),
      child: SizedBox.square(
        dimension: side,
        child: file != null && file.existsSync()
            ? Image.file(
                file,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const _ArtworkPlaceholder(),
              )
            : const _ArtworkPlaceholder(),
      ),
    );
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: NotchColors.panelEdge,
    child: Center(
      child: Icon(Icons.music_note, color: NotchColors.secondaryText, size: 24),
    ),
  );
}

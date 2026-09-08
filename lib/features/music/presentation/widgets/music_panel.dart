import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/core/platform/capabilities.dart';
import 'package:notchpeek/core/platform/channel_service.dart';
import 'package:notchpeek/core/platform/channels.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/shared/utils/enums/capability_state.dart';
import 'package:notchpeek/shared/widgets/artwork_tile.dart';
import 'package:notchpeek/shared/widgets/empty_state.dart';
import 'package:notchpeek/shared/widgets/marquee_text.dart';
import 'package:notchpeek/shared/widgets/notch_icon_button.dart';
import 'package:notchpeek/shared/widgets/panel_scaffold.dart';
import 'package:notchpeek/shared/widgets/permission_prompt.dart';
import 'package:notchpeek/shared/widgets/scrubber.dart';

/// The only panel in M1. Renders three ways, always
/// (architecture-playbook §4.4).
class MusicPanel extends ConsumerWidget {
  const MusicPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capability = ref.watch(
      capabilitiesProvider.select(
        (c) => c.value?.music ?? CapabilityState.notDetermined,
      ),
    );

    return switch (capability) {
      // Hidden, never teased: neither player is installed.
      CapabilityState.absent => const SizedBox.shrink(),
      CapabilityState.denied || CapabilityState.notDetermined => PanelScaffold(
        child: PermissionPrompt(
          explanation:
              'NotchPeek needs permission to read what Apple Music and '
              'Spotify are playing.',
          actionLabel: 'Open Settings',
          onPressed: () => ref.read(channelServiceProvider).invoke<bool>(
            ControlMethod.requestPermission,
            const {'what': 'automation'},
          ),
        ),
      ),
      CapabilityState.granted => const _MusicReady(),
    };
  }
}

class _MusicReady extends ConsumerWidget {
  const _MusicReady();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track =
        ref.watch(nowPlayingProvider).value ?? const NowPlaying.unavailable();

    // A read that failed is *unavailable*, not idle — the macOS 26 wall is
    // silent, and this is where it would be misdiagnosed (spec §7).
    if (!track.available) {
      return const PanelScaffold(
        child: EmptyState(
          icon: Icons.headset_off,
          message: 'Player unavailable',
        ),
      );
    }

    if (!track.hasTrack) {
      return const PanelScaffold(
        child: EmptyState(icon: Icons.music_note, message: 'Nothing playing'),
      );
    }

    return PanelScaffold(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ArtworkTile(path: track.artworkPath),
          const SizedBox(width: 14),
          Expanded(child: _TrackDetails(track: track)),
        ],
      ),
    );
  }
}

class _TrackDetails extends ConsumerWidget {
  const _TrackDetails({required this.track});

  final NowPlaying track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final music = ref.read(musicNotifierProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: 20,
          child: MarqueeText(
            text: track.title,
            style: const TextStyle(
              color: NotchColors.primaryText,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: NotchColors.secondaryText,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        Scrubber(
          progress: track.progress,
          position: track.position,
          duration: track.duration,
          onSeek: track.canSeek ? (v) => music.seek(track.duration * v) : null,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            NotchIconButton(
              icon: Icons.skip_previous,
              semanticLabel: 'Previous',
              onPressed: music.previous,
            ),
            NotchIconButton(
              icon: track.state.isPlaying ? Icons.pause : Icons.play_arrow,
              size: 28,
              semanticLabel: track.state.isPlaying ? 'Pause' : 'Play',
              onPressed: music.playPause,
            ),
            NotchIconButton(
              icon: Icons.skip_next,
              semanticLabel: 'Next',
              onPressed: music.next,
            ),
          ],
        ),
      ],
    );
  }
}

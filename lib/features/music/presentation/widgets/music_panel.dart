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
    final caps = ref.watch(capabilitiesProvider).value;
    final capability = caps?.music ?? CapabilityState.notDetermined;

    return switch (capability) {
      // Hidden, never teased: neither player is installed.
      CapabilityState.absent => const SizedBox.shrink(),

      // Never been asked. "Open Settings" is the wrong affordance here —
      // there is no row in that pane until the app has actually tried to
      // control a player, which is what the request does. And macOS raises no
      // prompt at all for a player that is not running, so say so rather than
      // offering a button that cannot work.
      CapabilityState.notDetermined => PanelScaffold(
        child: (caps?.playersRunning ?? false)
            ? PermissionPrompt(
                explanation:
                    'NotchPeek needs permission to read what Apple Music '
                    'and Spotify are playing.',
                actionLabel: 'Grant Access',
                onPressed: () => _request(ref, PermissionTarget.players),
              )
            // No prompt is possible yet, so the button goes to the pane
            // instead of pretending to ask. NotchPeek has no row there until
            // its first request, but the way out should never be a dead end.
            : PermissionPrompt(
                explanation:
                    'Open Apple Music or Spotify to grant access, or change '
                    'it in System Settings.',
                actionLabel: 'Open Settings',
                onPressed: () => _request(ref, PermissionTarget.settings),
              ),
      ),

      // Refused. Only System Settings can undo this — macOS offers no API to
      // un-deny, and asking again silently does nothing.
      CapabilityState.denied => PanelScaffold(
        child: PermissionPrompt(
          explanation:
              'NotchPeek was refused permission to read what Apple Music '
              'and Spotify are playing.',
          actionLabel: 'Open Settings',
          onPressed: () => _request(ref, PermissionTarget.settings),
        ),
      ),

      CapabilityState.granted => const _MusicReady(),
    };
  }

  void _request(WidgetRef ref, String what) {
    ref.read(channelServiceProvider).invoke<bool>(
      ControlMethod.requestPermission,
      {'what': what},
    );
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

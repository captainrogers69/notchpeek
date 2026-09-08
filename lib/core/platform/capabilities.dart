import 'package:equatable/equatable.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/core/platform/channel_service.dart';
import 'package:notchpeek/core/platform/channels.dart';
import 'package:notchpeek/shared/utils/enums/build_flavor.dart';
import 'package:notchpeek/shared/utils/enums/capability_state.dart';

/// The single source of truth for what this build, this OS and these
/// permissions can do (architecture-playbook §4.4). The probe reports **OS
/// availability as well as permission state** — that is what makes a panel's
/// absence expressible rather than merely disabled.
class Capabilities extends Equatable {
  const Capabilities({
    this.buildFlavor = BuildFlavor.direct,
    this.osSupportsOnDeviceAI = false,
    this.appleMusic = CapabilityState.notDetermined,
    this.spotify = CapabilityState.notDetermined,
    this.systemWideMediaRead = false,
    this.systemWideMediaCommand = false,
    this.calendar = CapabilityState.notDetermined,
    this.camera = CapabilityState.notDetermined,
    this.playersRunning = false,
  });

  factory Capabilities.fromMap(Map<String, Object?> json) {
    final scripting =
        (json['scriptingMedia'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    return Capabilities(
      buildFlavor: BuildFlavor.fromApi(json['buildFlavor'] as String?),
      osSupportsOnDeviceAI: json['osSupportsOnDeviceAI'] as bool? ?? false,
      appleMusic: CapabilityState.fromApi(scripting['appleMusic'] as String?),
      spotify: CapabilityState.fromApi(scripting['spotify'] as String?),
      systemWideMediaRead: json['systemWideMediaRead'] as bool? ?? false,
      systemWideMediaCommand: json['systemWideMediaCommand'] as bool? ?? false,
      calendar: CapabilityState.fromApi(json['calendar'] as String?),
      camera: CapabilityState.fromApi(json['camera'] as String?),
      playersRunning: json['playersRunning'] as bool? ?? false,
    );
  }

  final BuildFlavor buildFlavor;

  /// macOS 26+, for M4's AI panel.
  final bool osSupportsOnDeviceAI;

  final CapabilityState appleMusic;
  final CapabilityState spotify;

  /// False on macOS 26. Kept so it flips if Apple reopens the read path
  /// (spike §4.4).
  final bool systemWideMediaRead;
  final bool systemWideMediaCommand;

  final CapabilityState calendar; // M2
  final CapabilityState camera; // M3

  /// Whether a player is running *right now*. Permission state alone cannot
  /// drive the panel: macOS raises no prompt for a player that is not running,
  /// so the panel has to be able to say "start one first".
  final bool playersRunning;

  /// The music panel is ready if *either* player is. It is denied only when
  /// both are — one refused player is not a refusal of the feature.
  CapabilityState get music {
    if (appleMusic.isReady || spotify.isReady) return CapabilityState.granted;
    if (appleMusic == CapabilityState.denied &&
        spotify == CapabilityState.denied) {
      return CapabilityState.denied;
    }
    if (appleMusic.isHidden && spotify.isHidden) return CapabilityState.absent;
    return CapabilityState.notDetermined;
  }

  bool get anyPlayerReady => music.isReady;

  @override
  List<Object?> get props => [
    buildFlavor,
    osSupportsOnDeviceAI,
    appleMusic,
    spotify,
    systemWideMediaRead,
    systemWideMediaCommand,
    calendar,
    camera,
    playersRunning,
  ];
}

/// Reports at launch and on change. Seeded from `getCapabilities` so the first
/// frame is not blank, then updated by every `capabilities` system event.
final capabilitiesProvider = StreamProvider<Capabilities>((ref) async* {
  final channels = ref.watch(channelServiceProvider);

  final seed = await channels.invoke<Map<Object?, Object?>>(
    ControlMethod.getCapabilities,
  );
  yield seed.status
      ? Capabilities.fromMap(Map<String, Object?>.from(seed.data!))
      : const Capabilities();

  yield* channels.systemEvents
      .where((e) => e[SystemEventKind.key] == SystemEventKind.capabilities)
      .map(Capabilities.fromMap);
});

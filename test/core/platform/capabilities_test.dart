import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/core/platform/capabilities.dart';
import 'package:notchpeek/shared/utils/enums/build_flavor.dart';
import 'package:notchpeek/shared/utils/enums/capability_state.dart';

void main() {
  test('parses the probe snapshot', () {
    final caps = Capabilities.fromMap(const {
      'buildFlavor': 'direct',
      'osSupportsOnDeviceAI': true,
      'scriptingMedia': {'appleMusic': 'granted', 'spotify': 'denied'},
      'systemWideMediaRead': false,
      'systemWideMediaCommand': true,
      'calendar': 'notDetermined',
      'camera': 'absent',
    });

    expect(caps.buildFlavor, BuildFlavor.direct);
    expect(caps.appleMusic, CapabilityState.granted);
    expect(caps.spotify, CapabilityState.denied);
    expect(caps.systemWideMediaRead, isFalse);
    expect(caps.camera, CapabilityState.absent);
  });

  test('an empty snapshot degrades to notDetermined, never a throw', () {
    final caps = Capabilities.fromMap(const {});

    expect(caps.appleMusic, CapabilityState.notDetermined);
    expect(caps.music, CapabilityState.notDetermined);
    expect(caps.anyPlayerReady, isFalse);
  });

  test('music is ready when either player is', () {
    final caps = Capabilities.fromMap(const {
      'scriptingMedia': {'appleMusic': 'denied', 'spotify': 'granted'},
    });

    expect(caps.music, CapabilityState.granted);
    expect(caps.anyPlayerReady, isTrue);
  });

  test('music is denied only when both players are denied', () {
    final both = Capabilities.fromMap(const {
      'scriptingMedia': {'appleMusic': 'denied', 'spotify': 'denied'},
    });
    expect(both.music, CapabilityState.denied);

    final one = Capabilities.fromMap(const {
      'scriptingMedia': {'appleMusic': 'denied', 'spotify': 'notDetermined'},
    });
    expect(one.music, CapabilityState.notDetermined);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/shared/utils/enums/capability_state.dart';
import 'package:notchpeek/shared/utils/enums/playback_state.dart';

void main() {
  group('PlaybackState', () {
    test('maps the three strings Spotify and Music actually send', () {
      expect(PlaybackState.fromApi('playing'), PlaybackState.playing);
      expect(PlaybackState.fromApi('paused'), PlaybackState.paused);
      expect(PlaybackState.fromApi('stopped'), PlaybackState.stopped);
    });

    test('an unrecognised or empty string is unknown, never a throw', () {
      expect(PlaybackState.fromApi('kPSP'), PlaybackState.unknown);
      expect(PlaybackState.fromApi(''), PlaybackState.unknown);
    });

    test('isPlaying is true only while playing', () {
      expect(PlaybackState.playing.isPlaying, isTrue);
      expect(PlaybackState.paused.isPlaying, isFalse);
      expect(PlaybackState.unknown.isPlaying, isFalse);
    });
  });

  group('CapabilityState', () {
    test('round-trips through apiValue', () {
      for (final s in CapabilityState.values) {
        expect(CapabilityState.fromApi(s.apiValue), s);
      }
    });

    test('an unknown value is notDetermined, the safe default', () {
      expect(
        CapabilityState.fromApi('nonsense'),
        CapabilityState.notDetermined,
      );
    });

    test('absent is the only state a panel hides for', () {
      expect(CapabilityState.absent.isHidden, isTrue);
      expect(CapabilityState.denied.isHidden, isFalse);
      expect(CapabilityState.granted.isReady, isTrue);
    });
  });
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/core/platform/channel_service.dart';
import 'package:notchpeek/core/platform/channels.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const control = MethodChannel(Channels.control);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(control, null));

  test(
    'a successful invoke returns a successful ApiResponse carrying the value',
    () async {
      late MethodCall seen;
      messenger.setMockMethodCallHandler(control, (call) async {
        seen = call;
        return true;
      });

      final result = await ChannelService().invoke<bool>(
        ControlMethod.setInteractiveRect,
        const {'x': 1.0, 'y': 2.0, 'width': 3.0, 'height': 4.0},
      );

      expect(result.status, isTrue);
      expect(result.data, isTrue);
      expect(seen.method, ControlMethod.setInteractiveRect);
      expect(seen.arguments, const {
        'x': 1.0,
        'y': 2.0,
        'width': 3.0,
        'height': 4.0,
      });
    },
  );

  test(
    'a PlatformException becomes an error ApiResponse, never a throw',
    () async {
      messenger.setMockMethodCallHandler(control, (call) async {
        throw PlatformException(code: 'unavailable', message: 'no bridge');
      });

      final result = await ChannelService().invoke<bool>(
        ControlMethod.openSettings,
      );

      expect(result.status, isFalse);
      expect(result.message, contains('no bridge'));
    },
  );

  test(
    'a method the native side does not implement is an error, not a crash',
    () async {
      messenger.setMockMethodCallHandler(control, (call) async => null);

      final result = await ChannelService().invoke<bool>(
        ControlMethod.getCapabilities,
      );

      expect(result.status, isFalse);
    },
  );

  test('channel names are constants and match the Swift side exactly', () {
    expect(Channels.control, 'notchpeek/control');
    expect(Channels.media, 'notchpeek/media');
    expect(Channels.system, 'notchpeek/system');
    expect(Channels.calendar, 'notchpeek/calendar');
  });
}

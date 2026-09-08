import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/core/platform/channel_service.dart';
import 'package:notchpeek/core/platform/channels.dart';

/// `EventChannel.receiveBroadcastStream` registers its handler with
/// `binaryMessenger.setMessageHandler(name, ...)`, and there is exactly **one**
/// handler slot per channel name. So every extra call for the same channel
/// silently unregisters the one before it, and a cancel nulls it for everyone.
///
/// Three consumers share `notchpeek/system` — geometry, hover and
/// capabilities — so this is not theoretical: the third subscriber killed
/// hover, and the notch could expand but never collapse.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = EventChannel(Channels.system);

  late List<MockStreamHandlerEventSink> sinks;
  late int listenCount;

  setUp(() {
    sinks = [];
    listenCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          channel,
          MockStreamHandler.inline(
            onListen: (arguments, sink) {
              listenCount++;
              sinks.add(sink);
            },
          ),
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(channel, null);
  });

  ChannelService service() => ChannelService(system: channel);

  test('every consumer of one channel receives every event', () async {
    final channels = service();

    final first = <Map<String, Object?>>[];
    final second = <Map<String, Object?>>[];
    final subA = channels.systemEvents.listen(first.add);
    final subB = channels.systemEvents.listen(second.add);
    addTearDown(subA.cancel);
    addTearDown(subB.cancel);
    await pumpEventQueue();

    sinks.first.success(<String, Object?>{
      SystemEventKind.key: SystemEventKind.hover,
      SystemEventKind.inside: true,
    });
    await pumpEventQueue();

    expect(
      first,
      hasLength(1),
      reason: 'the first subscriber must not go deaf',
    );
    expect(second, hasLength(1));
  });

  test('one native subscription serves them all', () async {
    final channels = service();

    final subA = channels.systemEvents.listen((_) {});
    final subB = channels.systemEvents.listen((_) {});
    addTearDown(subA.cancel);
    addTearDown(subB.cancel);
    await pumpEventQueue();

    expect(listenCount, 1);
  });

  test('a consumer that subscribes late is given the current state', () async {
    final channels = service();

    final early = <Map<String, Object?>>[];
    final subA = channels.systemEvents.listen(early.add);
    addTearDown(subA.cancel);
    await pumpEventQueue();

    sinks.first.success(<String, Object?>{
      SystemEventKind.key: SystemEventKind.geometry,
      'notchWidth': 200.0,
    });
    await pumpEventQueue();

    // Capabilities subscribes on the first expand, long after geometry has
    // been and gone. Without a replay it would wait for the next one.
    final late = <Map<String, Object?>>[];
    final subB = channels.systemEvents.listen(late.add);
    addTearDown(subB.cancel);
    await pumpEventQueue();

    expect(late, hasLength(1));
    expect(late.single[SystemEventKind.key], SystemEventKind.geometry);
  });

  test('one consumer cancelling does not silence the others', () async {
    final channels = service();

    final survivor = <Map<String, Object?>>[];
    final subA = channels.systemEvents.listen(survivor.add);
    addTearDown(subA.cancel);
    final subB = channels.systemEvents.listen((_) {});
    await pumpEventQueue();

    await subB.cancel();
    await pumpEventQueue();

    sinks.first.success(<String, Object?>{
      SystemEventKind.key: SystemEventKind.hover,
      SystemEventKind.inside: false,
    });
    await pumpEventQueue();

    expect(survivor, hasLength(1));
  });
}

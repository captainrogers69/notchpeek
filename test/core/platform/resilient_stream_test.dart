import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/core/platform/resilient_stream.dart';

void main() {
  test('passes values straight through while the source is healthy', () async {
    final stream = resilientStream<int>(
      open: () => Stream.fromIterable([1, 2, 3]),
      sleep: (_) async {},
    );

    expect(await stream.take(3).toList(), [1, 2, 3]);
  });

  test('reopens the source after it errors, and keeps delivering', () async {
    var opens = 0;
    final stream = resilientStream<int>(
      open: () {
        opens++;
        if (opens == 1) return Stream<int>.error(StateError('channel died'));
        return Stream.fromIterable([7]);
      },
      sleep: (_) async {},
    );

    expect(await stream.first, 7);
    expect(opens, 2);
  });

  test(
    'backs off further on each consecutive failure, then holds at the last step',
    () async {
      final waited = <Duration>[];
      var opens = 0;

      final stream = resilientStream<int>(
        open: () {
          opens++;
          if (opens <= 4) return Stream<int>.error(StateError('down'));
          return Stream.fromIterable([1]);
        },
        backoff: const [Duration(seconds: 1), Duration(seconds: 2)],
        sleep: (d) async => waited.add(d),
      );

      await stream.first;
      expect(waited, const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 2),
        Duration(seconds: 2),
      ]);
    },
  );

  test('a clean close of the source is also treated as a reconnect', () async {
    var opens = 0;
    final stream = resilientStream<int>(
      open: () {
        opens++;
        return opens == 1
            ? const Stream<int>.empty()
            : Stream.fromIterable([9]);
      },
      sleep: (_) async {},
    );

    expect(await stream.first, 9);
  });
}

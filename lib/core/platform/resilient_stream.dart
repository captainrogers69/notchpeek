import 'package:notchpeek/core/logging/notch_logger.dart';

/// Default reconnect schedule. Holds at 8 s rather than growing without bound:
/// a dead `EventChannel` usually means the native side is restarting, and the
/// user is looking at the panel while it happens.
const List<Duration> kDefaultBackoff = [
  Duration(milliseconds: 250),
  Duration(milliseconds: 500),
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
];

/// Wraps a stream factory so an `EventChannel` that dies is reopened rather
/// than terminating the provider that listens to it (spec §7).
///
/// A clean close is treated the same as an error: the native side is the only
/// thing that ends these streams, and it only does so when it goes away.
Stream<T> resilientStream<T>({
  required Stream<T> Function() open,
  List<Duration> backoff = kDefaultBackoff,
  Future<void> Function(Duration) sleep = Future<void>.delayed,
  NotchLogger? logger,
}) async* {
  var attempt = 0;

  while (true) {
    try {
      await for (final value in open()) {
        attempt = 0;
        yield value;
      }
      logger?.debug('stream closed cleanly; reopening');
    } catch (e, s) {
      logger?.error('stream failed; reopening', error: e, stackTrace: s);
    }

    final wait =
        backoff[attempt < backoff.length ? attempt : backoff.length - 1];
    attempt++;
    await sleep(wait);
  }
}

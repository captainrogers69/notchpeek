import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/core/logging/notch_logger.dart';

void main() {
  late List<String> lines;

  setUp(() {
    lines = <String>[];
    NotchLogger.writer = lines.add;
    NotchLogger.useColors = false;
    NotchLogger.globalEnabled = true;
  });

  test('tags every line with the logger tag and the level', () {
    NotchLogger.forTag('MediaDataSourceImpl').success('now playing: t1');

    expect(lines, hasLength(1));
    expect(lines.single, contains('[SUCCESS]'));
    expect(lines.single, contains('[MediaDataSourceImpl]'));
    expect(lines.single, contains('now playing: t1'));
  });

  test('writes nothing when globally disabled', () {
    NotchLogger.globalEnabled = false;

    NotchLogger.forTag('X').debug('quiet');

    expect(lines, isEmpty);
  });

  test('an instance disabled at construction stays quiet while others log', () {
    NotchLogger(tag: 'Chatty', enabled: false).debug('suppressed');
    NotchLogger.forTag('Loud').debug('emitted');

    expect(lines, hasLength(1));
    expect(lines.single, contains('[Loud]'));
  });

  test('error appends the cause and the stack trace as separate lines', () {
    NotchLogger.forTag('Probe').error(
      'scripting read failed',
      error: StateError('boom'),
      stackTrace: StackTrace.fromString('frame0'),
    );

    expect(lines, hasLength(3));
    expect(lines[0], contains('scripting read failed'));
    expect(lines[1], contains('cause: Bad state: boom'));
    expect(lines[2], contains('frame0'));
  });
}

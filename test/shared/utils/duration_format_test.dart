import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/shared/utils/helpers/duration_format.dart';

void main() {
  test('pads seconds but not minutes', () {
    expect(formatClock(const Duration(seconds: 5)), '0:05');
    expect(formatClock(const Duration(minutes: 3, seconds: 7)), '3:07');
    expect(formatClock(const Duration(minutes: 12, seconds: 40)), '12:40');
  });

  test('grows an hours field only past an hour', () {
    expect(formatClock(const Duration(minutes: 59, seconds: 59)), '59:59');
    expect(
      formatClock(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });

  test(
    'a negative duration clamps to zero rather than printing a minus sign',
    () {
      expect(formatClock(const Duration(seconds: -4)), '0:00');
    },
  );
}

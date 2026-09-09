import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/features/shell/data/models/power_state_model.dart';

void main() {
  test('parses a battery payload', () {
    final power = PowerStateModel.toEntity(const {
      'percent': 84,
      'isCharging': true,
      'isPresent': true,
    });

    expect(power.percent, 84);
    expect(power.isCharging, isTrue);
    expect(power.isPresent, isTrue);
  });

  test('a desktop Mac reports no battery rather than 0%', () {
    final power = PowerStateModel.toEntity(const {'isPresent': false});

    expect(power.isPresent, isFalse);
    expect(power.percent, 0);
  });

  test('clamps a nonsense percentage into range', () {
    expect(
      PowerStateModel.toEntity(const {
        'percent': 140,
        'isPresent': true,
      }).percent,
      100,
    );
    expect(
      PowerStateModel.toEntity(const {
        'percent': -5,
        'isPresent': true,
      }).percent,
      0,
    );
  });
}

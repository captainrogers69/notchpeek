import 'package:notchpeek/features/shell/domain/entities/power_state.dart';

abstract final class PowerStateModel {
  static PowerState toEntity(Map<String, Object?> json) => PowerState(
    percent: ((json['percent'] as num?)?.toInt() ?? 0).clamp(0, 100),
    isCharging: json['isCharging'] as bool? ?? false,
    isPresent: json['isPresent'] as bool? ?? false,
  );
}

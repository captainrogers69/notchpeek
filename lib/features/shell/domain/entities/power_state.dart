import 'package:equatable/equatable.dart';

class PowerState extends Equatable {
  const PowerState({
    required this.percent,
    required this.isCharging,
    required this.isPresent,
  });

  final int percent;
  final bool isCharging;

  /// False on a desktop Mac. A machine with no battery is not a machine with
  /// an empty one.
  final bool isPresent;

  bool get isLow => isPresent && !isCharging && percent <= 20;

  @override
  List<Object?> get props => [percent, isCharging, isPresent];
}

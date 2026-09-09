import 'package:notchpeek/features/shell/domain/entities/power_state.dart';
import 'package:notchpeek/features/shell/domain/repositories/shell_repository.dart';

class WatchPower {
  const WatchPower(this._repository);

  final ShellRepository _repository;

  Stream<PowerState> call() => _repository.watchPower();
}

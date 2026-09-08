import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/shell/domain/repositories/shell_repository.dart';

class PerformHaptic {
  const PerformHaptic(this._repository);

  final ShellRepository _repository;

  Future<ApiResponse<bool>> call() => _repository.performHaptic();
}

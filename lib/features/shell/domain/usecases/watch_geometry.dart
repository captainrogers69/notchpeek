import 'package:notchpeek/features/shell/domain/entities/notch_geometry.dart';
import 'package:notchpeek/features/shell/domain/repositories/shell_repository.dart';

/// Thin by design: the layer exists so a panel never reaches past it, not
/// because it holds logic (architecture-playbook §3).
class WatchGeometry {
  const WatchGeometry(this._repository);

  final ShellRepository _repository;

  Stream<NotchGeometry> call() => _repository.watchGeometry();
}

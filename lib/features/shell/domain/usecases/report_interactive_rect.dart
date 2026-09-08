import 'dart:ui';

import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/shell/domain/repositories/shell_repository.dart';

class ReportInteractiveRect {
  const ReportInteractiveRect(this._repository);

  final ShellRepository _repository;

  Future<ApiResponse<bool>> call(Rect rect) =>
      _repository.setInteractiveRect(rect);
}

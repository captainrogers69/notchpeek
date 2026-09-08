import 'dart:ui';

import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/shell/domain/entities/notch_geometry.dart';

abstract class ShellRepository {
  Stream<NotchGeometry> watchGeometry();

  /// True when the cursor is inside the rect last reported by
  /// [setInteractiveRect]. This is the shell's hover signal.
  Stream<bool> watchHover();

  Future<ApiResponse<bool>> setInteractiveRect(Rect rect);
  Future<ApiResponse<bool>> performHaptic();

  /// Terminates the app. The shell's close button is the only way out of an
  /// agent app with no Dock icon and no menu bar.
  Future<ApiResponse<bool>> quit();
}

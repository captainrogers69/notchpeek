import 'dart:ui';

import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/shell/domain/entities/notch_geometry.dart';
import 'package:notchpeek/features/shell/domain/entities/power_state.dart';

abstract class ShellRepository {
  Stream<NotchGeometry> watchGeometry();

  /// True when the cursor is inside the rect last reported by
  /// [setInteractiveRect]. This is the shell's hover signal.
  Stream<bool> watchHover();

  /// Battery percentage and the charging edge.
  Stream<PowerState> watchPower();

  Future<ApiResponse<bool>> setInteractiveRect(Rect rect);
  Future<ApiResponse<bool>> performHaptic();

  /// Terminates the app. The shell's close button is the only way out of an
  /// agent app with no Dock icon and no menu bar.
  Future<ApiResponse<bool>> quit();
}

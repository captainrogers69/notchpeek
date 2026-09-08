import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/features/shell/domain/entities/notch_geometry.dart';

/// Static mapper, null-safe defaults (architecture-playbook §5). A malformed
/// payload degrades to a centred virtual notch rather than throwing — the panel
/// staying usable matters more than the payload being right.
abstract final class NotchGeometryModel {
  static NotchGeometry toEntity(Map<String, Object?> json) {
    final screenWidth = _d(json['screenWidth'], 1440);
    final notchWidth = _d(json['notchWidth'], NotchSizes.virtualNotchWidth);

    return NotchGeometry(
      screenWidth: screenWidth,
      screenHeight: _d(json['screenHeight'], 900),
      notchWidth: notchWidth,
      notchHeight: _d(json['notchHeight'], NotchSizes.virtualNotchHeight),
      notchLeft: _d(json['notchLeft'], (screenWidth - notchWidth) / 2),
      scale: _d(json['scale'], 2),
      isVirtual: json['isVirtual'] as bool? ?? true,
      displayId: (json['displayId'] as num?)?.toInt() ?? 0,
    );
  }

  static double _d(Object? value, double fallback) =>
      (value as num?)?.toDouble() ?? fallback;
}

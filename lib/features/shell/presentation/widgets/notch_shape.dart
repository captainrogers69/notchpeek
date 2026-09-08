import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:notchpeek/app/theme.dart';

/// The notch silhouette: full width at the very top, concave shoulders curving
/// inward just below it, straight sides, rounded bottom corners.
///
/// The box you give it is the **outer** box — its width includes both
/// shoulders, so the flat body below them is `width - 2 * shoulder` wide. Size
/// the box as `bodyWidth + 2 * shoulder` and the body lines up with the notch.
class NotchShape extends CustomClipper<Path> {
  const NotchShape({
    this.shoulder = NotchRadii.shoulder,
    this.bottomRadius = NotchRadii.panelBottom,
  });

  final double shoulder;
  final double bottomRadius;

  static Path build(
    Size size, {
    required double shoulder,
    required double bottomRadius,
  }) {
    final w = size.width;
    final h = size.height;

    // Never let the curves eat each other on a small box.
    final s = math.min(shoulder, w / 2);
    final r = math.min(bottomRadius, math.min(h, (w - 2 * s) / 2));

    return Path()
      ..moveTo(0, 0)
      // Concave top-left: bows up and to the right, carving into the panel.
      ..quadraticBezierTo(s, 0, s, math.min(s, h))
      ..lineTo(s, h - r)
      ..quadraticBezierTo(s, h, s + r, h)
      ..lineTo(w - s - r, h)
      ..quadraticBezierTo(w - s, h, w - s, h - r)
      ..lineTo(w - s, math.min(s, h))
      // Concave top-right.
      ..quadraticBezierTo(w - s, 0, w, 0)
      ..close();
  }

  @override
  Path getClip(Size size) =>
      build(size, shoulder: shoulder, bottomRadius: bottomRadius);

  @override
  bool shouldReclip(NotchShape oldClipper) =>
      oldClipper.shoulder != shoulder ||
      oldClipper.bottomRadius != bottomRadius;
}

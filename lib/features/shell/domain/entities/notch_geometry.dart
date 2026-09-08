import 'dart:math' as math;
import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/shared/utils/enums/notch_state.dart';

/// The fixed geometry the panel is laid out against. All values are logical
/// points in the canvas's own space: the canvas is the full screen width and
/// [NotchSizes.canvasHeight] tall, pinned to the top of the screen, so `y = 0`
/// is the top of the display.
class NotchGeometry extends Equatable {
  const NotchGeometry({
    required this.screenWidth,
    required this.screenHeight,
    required this.notchWidth,
    required this.notchHeight,
    required this.notchLeft,
    required this.scale,
    required this.isVirtual,
    required this.displayId,
  });

  final double screenWidth;
  final double screenHeight;
  final double notchWidth;
  final double notchHeight;
  final double notchLeft;
  final double scale;

  /// True when this machine has no hardware notch and Swift synthesized one.
  final bool isVirtual;

  /// `CGDirectDisplayID`. Two identically sized screens are otherwise
  /// indistinguishable, and moving between them would not register as a
  /// geometry change.
  final int displayId;

  Rect get notchRect => Rect.fromLTWH(notchLeft, 0, notchWidth, notchHeight);

  double get centerX => notchLeft + notchWidth / 2;

  /// The notch rect, inflated so the cursor does not have to hit hardware
  /// exactly. Never inflated above the top of the screen — there is nothing up
  /// there to hover.
  Rect hotZone({double inset = NotchSizes.hotZoneInset}) => Rect.fromLTRB(
    math.max(0, notchLeft - inset),
    0,
    math.min(screenWidth, notchLeft + notchWidth + inset),
    notchHeight + inset,
  );

  /// A rect of [size] hung from the top of the screen and centred on the notch,
  /// pushed back inside the screen if the notch sits near an edge.
  Rect centeredRect(Size size) {
    final left = (centerX - size.width / 2)
        .clamp(0.0, math.max(0.0, screenWidth - size.width))
        .toDouble();
    return Rect.fromLTWH(left, 0, size.width, size.height);
  }

  /// The rect Swift should let the mouse through to, for each shell state
  /// (spec §3.2).
  Rect interactiveRect(NotchState state) => switch (state) {
    NotchState.collapsed => hotZone(),
    NotchState.peeking => centeredRect(
      const Size(NotchSizes.peekWidth, NotchSizes.peekHeight),
    ),
    NotchState.expanded => centeredRect(
      const Size(NotchSizes.expandedWidth, NotchSizes.expandedHeight),
    ),
  };

  @override
  List<Object?> get props => [
    screenWidth,
    screenHeight,
    notchWidth,
    notchHeight,
    notchLeft,
    scale,
    isVirtual,
    displayId,
  ];
}

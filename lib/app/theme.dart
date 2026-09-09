import 'package:flutter/widgets.dart';

/// Opaque near-black. **No `NSVisualEffectView`** — real vibrancy behind an
/// animated non-rectangular panel needs an AppKit mask layer animating against
/// Flutter's clock, which is two clocks and a visible shimmer (spec §2).
abstract final class NotchColors {
  static const Color panel = Color(0xFF0A0A0A);
  static const Color panelEdge = Color(0xFF1C1C1E);
  static const Color primaryText = Color(0xFFF2F2F7);
  static const Color secondaryText = Color(0xFF8E8E93);
  static const Color accent = Color(0xFF0A84FF);
  static const Color positive = Color(0xFF30D158);
  static const Color warning = Color(0xFFFF9F0A);
  static const Color trackInactive = Color(0xFF3A3A3C);
}

abstract final class NotchRadii {
  /// The bottom corners of the expanded panel.
  static const double panelBottom = 22;

  /// The concave flare where the panel leaves the notch.
  static const double shoulder = 14;

  /// The collapsed silhouette's own bottom corners.
  static const double collapsedBottom = 10;
  static const double artwork = 8;
  static const double pill = 999;
}

/// Every number the morph animates with. **No magic numbers in widgets**
/// (architecture-playbook §9) — the morph timings especially.
abstract final class NotchMotion {
  static const Duration open = Duration(milliseconds: 350);
  static const Duration close = Duration(milliseconds: 250);
  static const Curve openCurve = Curves.easeOutQuint;
  static const Curve closeCurve = Curves.easeInQuint;

  /// Content arrives after the box does, so the panel reads as growing rather
  /// than as a cross-fade between two rectangles (spec §5.1).
  static const Duration contentFade = Duration(milliseconds: 180);
  static const Interval contentStagger = Interval(0.35, 1);

  /// How long an unattended peek stays out before retracting itself.
  static const Duration peekDwell = Duration(seconds: 4);
}

abstract final class NotchSizes {
  /// The fixed canvas height. The window is sized once to
  /// `screenWidth x canvasHeight` and never resized (spec §3.1).
  /// **Must match `NotchWindowController.canvasHeight` in Swift.**
  static const double canvasHeight = 420;

  static const double expandedWidth = 620;
  static const double expandedHeight = 220;
  static const double peekWidth = 260;
  static const double peekHeight = 44;

  /// The always-on music strip: the collapsed silhouette, widened so artwork
  /// and a level meter sit either side of the notch. Centred, so it only ever
  /// covers the stretch of menu bar next to the notch — app menus end well to
  /// the left of it and status items begin well to the right.
  static const double stripWidth = 320;

  /// **Must match `NotchGeometry.virtualNotchWidth` / `Height` in Swift.**
  static const double virtualNotchWidth = 200;
  static const double virtualNotchHeight = 32;

  /// The collapsed hot zone is the notch rect inflated by this much, so the
  /// cursor does not have to hit hardware exactly.
  static const double hotZoneInset = 6;

  static const double tabStripHeight = 34;
  static const double artworkSide = 96;
  static const double batteryPillWidth = 46;
}

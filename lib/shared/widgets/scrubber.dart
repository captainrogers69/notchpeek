import 'package:flutter/widgets.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/shared/utils/helpers/duration_format.dart';

/// Position, duration and a seek. `onSeek` receives a fraction in 0..1; a
/// track with no readable duration is not seekable, and says so by disabling.
///
/// The track is hand-drawn rather than a Material `Slider`: this app's root is
/// a `WidgetsApp`, so there is no `Material` and no `Overlay` in the tree, and
/// `Slider` asserts on both. Supplying them just to host a widget whose track,
/// thumb, colors and overlay are all overridden here anyway is more machinery
/// than the thing it hosts.
class Scrubber extends StatelessWidget {
  const Scrubber({
    required this.progress,
    required this.position,
    required this.duration,
    required this.onSeek,
    super.key,
  });

  final double progress;
  final Duration position;
  final Duration duration;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(formatClock(position), style: _clockStyle),
        const SizedBox(width: 8),
        Expanded(
          child: _Track(
            progress: progress.clamp(0.0, 1.0).toDouble(),
            onSeek: onSeek,
          ),
        ),
        const SizedBox(width: 8),
        Text(formatClock(duration), style: _clockStyle),
      ],
    );
  }

  static const TextStyle _clockStyle = TextStyle(
    color: NotchColors.secondaryText,
    fontSize: 11,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

class _Track extends StatelessWidget {
  const _Track({required this.progress, required this.onSeek});

  final double progress;
  final ValueChanged<double>? onSeek;

  /// The bar is 3pt tall but the grab area is not: a 3pt target is a 3pt
  /// target, and this one is dragged.
  static const double _hitHeight = 20;

  @override
  Widget build(BuildContext context) {
    final enabled = onSeek != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        void report(Offset local) {
          final width = constraints.maxWidth;
          if (width <= 0) return;
          onSeek!((local.dx / width).clamp(0.0, 1.0));
        }

        return MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (d) => report(d.localPosition) : null,
            onHorizontalDragUpdate: enabled
                ? (d) => report(d.localPosition)
                : null,
            child: SizedBox(
              height: _hitHeight,
              child: CustomPaint(
                painter: _TrackPainter(progress: progress, enabled: enabled),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TrackPainter extends CustomPainter {
  const _TrackPainter({required this.progress, required this.enabled});

  final double progress;
  final bool enabled;

  static const double _barHeight = 3;
  static const double _thumbRadius = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final radius = Radius.circular(_barHeight / 2);

    final inactive = Paint()..color = NotchColors.trackInactive;
    canvas.drawRRect(
      RRect.fromLTRBR(
        0,
        midY - _barHeight / 2,
        size.width,
        midY + _barHeight / 2,
        radius,
      ),
      inactive,
    );

    final filled = size.width * progress;
    final active = Paint()
      ..color = enabled ? NotchColors.primaryText : NotchColors.secondaryText;
    if (filled > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          0,
          midY - _barHeight / 2,
          filled,
          midY + _barHeight / 2,
          radius,
        ),
        active,
      );
    }

    // No thumb when the track cannot be moved — an affordance that does
    // nothing is worse than none.
    if (enabled) {
      canvas.drawCircle(Offset(filled, midY), _thumbRadius, active);
    }
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.progress != progress || old.enabled != enabled;
}

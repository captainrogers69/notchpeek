import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/features/shell/domain/entities/power_state.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';

/// Hidden entirely on a Mac with no battery.
class BatteryPill extends ConsumerWidget {
  const BatteryPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final power = ref.watch(powerProvider).value;
    if (power == null || !power.isPresent) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Meter(power: power),
        const SizedBox(width: 7),
        Text(
          '${power.percent}%',
          style: const TextStyle(
            color: NotchColors.primaryText,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// A battery: body, terminal nub, and either a proportional fill or a bolt.
///
/// Charging replaces the fill with the bolt and turns the whole glyph green —
/// the level is already spelled out in the number beside it, and two ways of
/// saying it competes with itself.
class _Meter extends StatelessWidget {
  const _Meter({required this.power});

  final PowerState power;

  static const double _bodyWidth = _BatteryMetrics.bodyWidth;
  static const double _bodyHeight = _BatteryMetrics.bodyHeight;
  static const double _nubWidth = 2.5;
  static const double _nubHeight = 5.5;
  static const double _inset = 2;

  Color get _color => power.isCharging
      ? NotchColors.positive
      : power.isLow
      ? NotchColors.warning
      : NotchColors.primaryText;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: _bodyWidth,
          height: _bodyHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: _color, width: 1.5),
              borderRadius: BorderRadius.circular(4.5),
            ),
            // Filled to the level, with the bolt knocked out on top — not a
            // bolt floating in an empty body. One fill for both states; the
            // bolt is an overlay, so the level still reads while charging.
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.all(_inset),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    // `heightFactor` is load-bearing. `Align` hands its child
                    // loose constraints and a `FractionallySizedBox` with
                    // only a `widthFactor` passes the height straight
                    // through, so a childless `DecoratedBox` collapses to
                    // nothing and the meter reads empty at every level.
                    child: FractionallySizedBox(
                      widthFactor: (power.percent / 100).clamp(0.0, 1.0),
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
                // Full body height, border included: `DecoratedBox` paints
                // its border *behind* the child, so the bolt cuts through the
                // outline top and bottom rather than sitting inside it.
                if (power.isCharging)
                  BatteryBolt(color: _color, ring: NotchColors.panel),
              ],
            ),
          ),
        ),
        const SizedBox(width: 1.5),
        SizedBox(
          width: _nubWidth,
          height: _nubHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _color,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared so the bolt can be sized against the body it cuts through.
abstract final class _BatteryMetrics {
  static const double bodyWidth = 27;
  static const double bodyHeight = 14;
}

/// The charging bolt, drawn rather than set: `Icons.bolt` carries its own
/// whitespace inside a 24pt em box, so fitting it to an 11pt slot leaves a
/// sliver. A path fills the space it is given.
class BatteryBolt extends StatelessWidget {
  const BatteryBolt({
    required this.color,
    this.ring,
    this.size = const Size(12, _BatteryMetrics.bodyHeight),
    super.key,
  });

  /// The bolt itself, in the battery's own colour.
  final Color color;

  /// Drawn *under* the bolt as a thick stroke, so a ring of it shows all the
  /// way round. That ring is what separates a green bolt from the green fill
  /// behind it — without it the bolt disappears into the body.
  final Color? ring;

  final Size size;

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: size,
    child: CustomPaint(painter: _BoltPainter(color, ring)),
  );
}

class _BoltPainter extends CustomPainter {
  const _BoltPainter(this.color, this.ring);

  final Color color;
  final Color? ring;

  /// A unit-box zigzag: down-left to the waist, a short step out, then
  /// down-left again to the tip.
  static const List<Offset> _outline = [
    Offset(0.66, 0),
    Offset(0.05, 0.58),
    Offset(0.42, 0.58),
    Offset(0.34, 1),
    Offset(0.95, 0.42),
    Offset(0.58, 0.42),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 0; i < _outline.length; i++) {
      final point = Offset(
        _outline[i].dx * size.width,
        _outline[i].dy * size.height,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    // Ring first, bolt over it: the stroke straddles the outline, so half of
    // it stays visible as a separating edge once the fill lands on top.
    if (ring case final ring?) {
      canvas.drawPath(
        path,
        Paint()
          ..color = ring
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BoltPainter old) =>
      old.color != color || old.ring != ring;
}

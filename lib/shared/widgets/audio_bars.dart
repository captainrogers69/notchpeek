import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:notchpeek/app/theme.dart';

/// A level meter, and an honest fake: macOS exposes no output levels to a
/// third-party app, so this is decorative motion driven by *whether* something
/// is playing rather than by what it sounds like.
///
/// Rests flat when paused instead of animating, so an idle notch costs
/// nothing (the same trap `MarqueeText` fell into).
class AudioBars extends HookWidget {
  const AudioBars({
    required this.active,
    this.bars = 4,
    this.height = 15,
    this.barWidth = 2.5,
    this.gap = 2.5,
    this.color = NotchColors.primaryText,
    super.key,
  });

  final bool active;
  final int bars;
  final double height;
  final double barWidth;
  final double gap;
  final Color color;

  static const Duration _cycle = Duration(milliseconds: 900);

  /// Flat but not invisible when paused.
  static const double _restingFraction = 0.22;

  @override
  Widget build(BuildContext context) {
    final controller = useAnimationController(duration: _cycle);

    useEffect(() {
      if (active) {
        controller.repeat();
      } else {
        controller.stop();
        controller.value = 0;
      }
      return null;
    }, [active]);

    return SizedBox(
      width: bars * barWidth + (bars - 1) * gap,
      height: height,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < bars; i++) ...[
              if (i > 0) SizedBox(width: gap),
              SizedBox(
                width: barWidth,
                height: height * _fraction(i, controller.value),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(barWidth / 2),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Each bar runs a quarter-cycle behind the one before it, so the row reads
  /// as a travelling wave rather than four things blinking in unison.
  double _fraction(int index, double phase) {
    if (!active) return _restingFraction;
    final offset = (phase + index / bars) * 2 * math.pi;
    return _restingFraction +
        (1 - _restingFraction) * (0.5 + 0.5 * math.sin(offset));
  }
}

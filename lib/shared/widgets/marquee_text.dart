import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Scrolls only when the text does not fit.
///
/// The measurement lives here and the animation lives in [_MarqueeBody], so
/// the hook can key on *whether it overflows*. Running the ticker regardless
/// would wake the UI thread forever for text that never moves, and would make
/// every golden containing a title depend on when it was captured.
class MarqueeText extends StatelessWidget {
  const MarqueeText({
    required this.text,
    required this.style,
    this.gap = 40,
    this.cycle = const Duration(seconds: 8),
    super.key,
  });

  final String text;
  final TextStyle style;
  final double gap;
  final Duration cycle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
        )..layout();

        return _MarqueeBody(
          text: text,
          style: style,
          gap: gap,
          cycle: cycle,
          textWidth: painter.width,
          overflows: painter.width > constraints.maxWidth,
        );
      },
    );
  }
}

/// A `HookWidget`, not a `StatefulWidget` (architecture-playbook §9) — and
/// everything it creates is disposed in the hook.
class _MarqueeBody extends HookWidget {
  const _MarqueeBody({
    required this.text,
    required this.style,
    required this.gap,
    required this.cycle,
    required this.textWidth,
    required this.overflows,
  });

  final String text;
  final TextStyle style;
  final double gap;
  final Duration cycle;
  final double textWidth;
  final bool overflows;

  @override
  Widget build(BuildContext context) {
    final controller = useAnimationController(duration: cycle);

    useEffect(() {
      if (overflows) {
        controller.repeat();
      } else {
        controller.stop();
      }
      return null;
    }, [text, cycle, overflows]);

    if (!overflows) {
      return Text(text, style: style, maxLines: 1, overflow: TextOverflow.clip);
    }

    return ClipRect(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final offset = -(textWidth + gap) * controller.value;
          return Transform.translate(
            offset: Offset(offset, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(text, style: style, maxLines: 1),
                SizedBox(width: gap),
                Text(text, style: style, maxLines: 1),
              ],
            ),
          );
        },
      ),
    );
  }
}

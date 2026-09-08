import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:notchpeek/app/theme.dart';

/// Quits the app. This is the **only** way out: an agent app has no Dock icon
/// and no menu bar, so without it a shell that misbehaves can only be killed
/// from a terminal.
///
/// It therefore lives in the shell rather than in any panel, and shows for
/// every state the shell can draw — including the ones that render nothing.
class NotchCloseButton extends HookWidget {
  const NotchCloseButton({required this.onPressed, this.side = 18, super.key});

  final VoidCallback onPressed;
  final double side;

  @override
  Widget build(BuildContext context) {
    final hovered = useState(false);

    return Semantics(
      label: 'Quit NotchPeek',
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => hovered.value = true,
        onExit: (_) => hovered.value = false,
        child: GestureDetector(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: side,
            height: side,
            decoration: BoxDecoration(
              // Dim until pointed at: it must be findable in a bad moment
              // without competing with the content the rest of the time.
              color: hovered.value
                  ? const Color(0xFFFF453A)
                  : NotchColors.trackInactive,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.close,
              size: side * 0.66,
              color: hovered.value
                  ? NotchColors.primaryText
                  : NotchColors.secondaryText,
            ),
          ),
        ),
      ),
    );
  }
}

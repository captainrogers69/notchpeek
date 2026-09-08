import 'package:flutter/widgets.dart';
import 'package:notchpeek/app/theme.dart';

/// The one button shape in the panel. Extracted from `PermissionPrompt` so the
/// permission states and the idle state cannot drift apart.
class NotchPillButton extends StatelessWidget {
  const NotchPillButton({
    required this.label,
    required this.onPressed,
    this.filled = true,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;

  /// Filled for the one action a state is really asking for; outlined when
  /// there are several and none of them is the point.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: filled ? NotchColors.accent : NotchColors.panelEdge,
            borderRadius: BorderRadius.circular(NotchRadii.pill),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                color: filled
                    ? NotchColors.primaryText
                    : NotchColors.secondaryText,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

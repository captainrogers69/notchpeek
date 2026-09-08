import 'package:flutter/material.dart';
import 'package:notchpeek/app/theme.dart';

class NotchIconButton extends StatelessWidget {
  const NotchIconButton({
    required this.icon,
    required this.onPressed,
    this.size = 22,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      label: semanticLabel,
      button: true,
      enabled: enabled,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              icon,
              size: size,
              color: enabled
                  ? NotchColors.primaryText
                  : NotchColors.trackInactive,
            ),
          ),
        ),
      ),
    );
  }
}

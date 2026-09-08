import 'package:flutter/material.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/shared/widgets/notch_pill_button.dart';

/// The **needs-permission** state, shared by every panel. Nine panels need the
/// same three states; nine copies is nine bugs (architecture-playbook §8).
class PermissionPrompt extends StatelessWidget {
  const PermissionPrompt({
    required this.explanation,
    required this.actionLabel,
    required this.onPressed,
    super.key,
  });

  final String explanation;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.lock_outline,
            color: NotchColors.secondaryText,
            size: 22,
          ),
          const SizedBox(height: 10),
          Text(
            explanation,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: NotchColors.secondaryText,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          NotchPillButton(label: actionLabel, onPressed: onPressed),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:notchpeek/app/theme.dart';

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
          _PromptButton(label: actionLabel, onPressed: onPressed),
        ],
      ),
    );
  }
}

class _PromptButton extends StatelessWidget {
  const _PromptButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: NotchColors.accent,
          borderRadius: BorderRadius.circular(NotchRadii.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Text(
            label,
            style: const TextStyle(
              color: NotchColors.primaryText,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

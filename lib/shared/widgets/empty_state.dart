import 'package:flutter/material.dart';
import 'package:notchpeek/app/theme.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({required this.icon, required this.message, super.key});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon, color: NotchColors.secondaryText, size: 22),
      const SizedBox(height: 8),
      Text(
        message,
        style: const TextStyle(color: NotchColors.secondaryText, fontSize: 12),
      ),
    ],
  );
}

import 'package:flutter/widgets.dart';

/// The common padding and layout every panel sits in.
class PanelScaffold extends StatelessWidget {
  const PanelScaffold({
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 12),
    super.key,
  });

  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: trailing == null
        ? child
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: child),
              trailing!,
            ],
          ),
  );
}

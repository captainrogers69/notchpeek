import 'package:flutter/widgets.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/shared/utils/enums/panel_tab.dart';

/// Takes its tabs as a parameter and never enumerates `PanelTab.values`
/// itself. M1 passes one tab and the strip disappears; M4 passes nine, or
/// eight where the AI panel is absent (spec §5).
class TabStrip extends StatelessWidget {
  const TabStrip({
    required this.tabs,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final List<PanelTab> tabs;
  final PanelTab selected;
  final ValueChanged<PanelTab> onSelected;

  @override
  Widget build(BuildContext context) {
    // One tab is not a choice. Do not draw a chooser for it.
    if (tabs.length < 2) return const SizedBox.shrink();

    return SizedBox(
      height: NotchSizes.tabStripHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final tab in tabs)
            _Tab(
              tab: tab,
              isSelected: tab == selected,
              onTap: () => onSelected(tab),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.tab,
    required this.isSelected,
    required this.onTap,
  });

  final PanelTab tab;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          tab.label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected
                ? NotchColors.primaryText
                : NotchColors.secondaryText,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/features/shell/presentation/widgets/tab_strip.dart';
import 'package:notchpeek/shared/utils/enums/panel_tab.dart';

Widget _wrap(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: ColoredBox(color: const Color(0xFF0A0A0A), child: child),
);

/// The root's constraints are tight, so a bare `SizedBox` would be stretched
/// to the full test surface and the golden would capture that surface rather
/// than the strip. `Center` gives it slack; the boundary scopes the capture.
Widget _measured(Widget child, {required double width}) => _wrap(
  Center(
    child: RepaintBoundary(
      child: ColoredBox(
        color: const Color(0xFF0A0A0A),
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);

void main() {
  for (final count in [2, 3, 4]) {
    testWidgets('renders $count tabs without assuming a fixed count', (
      tester,
    ) async {
      final tabs = PanelTab.values.take(count).toList();

      await tester.pumpWidget(
        _wrap(TabStrip(tabs: tabs, selected: tabs.first, onSelected: (_) {})),
      );

      for (final tab in tabs) {
        expect(find.text(tab.label), findsOneWidget);
      }
    });
  }

  testWidgets('a single tab renders no strip at all', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TabStrip(
          tabs: const [PanelTab.music],
          selected: PanelTab.music,
          onSelected: (_) {},
        ),
      ),
    );

    expect(find.text(PanelTab.music.label), findsNothing);
  });

  testWidgets('tapping a tab reports it exactly once', (tester) async {
    final taps = <PanelTab>[];

    await tester.pumpWidget(
      _wrap(
        TabStrip(
          tabs: const [PanelTab.music, PanelTab.calendar],
          selected: PanelTab.music,
          onSelected: taps.add,
        ),
      ),
    );

    await tester.tap(find.text(PanelTab.calendar.label));
    expect(taps, [PanelTab.calendar]);
  });

  for (final count in [2, 3, 4]) {
    testWidgets('golden: $count tabs', (tester) async {
      final tabs = PanelTab.values.take(count).toList();
      await tester.pumpWidget(
        _measured(
          TabStrip(tabs: tabs, selected: tabs.first, onSelected: (_) {}),
          width: 620,
        ),
      );
      await expectLater(
        find.byType(TabStrip),
        matchesGoldenFile('goldens/tab_strip_$count.png'),
      );
    });
  }
}

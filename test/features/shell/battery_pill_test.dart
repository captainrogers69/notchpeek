import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/features/shell/domain/entities/power_state.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';
import 'package:notchpeek/features/shell/presentation/widgets/battery_pill.dart';

Future<void> _pump(WidgetTester tester, PowerState? power) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        powerProvider.overrideWith(
          (ref) => power == null
              ? const Stream<PowerState>.empty()
              : Stream.value(power),
        ),
      ],
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: DefaultTextStyle(
          style: TextStyle(decoration: TextDecoration.none),
          child: Center(
            child: RepaintBoundary(
              child: ColoredBox(
                color: NotchColors.panel,
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: BatteryPill(),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Color _fillColor(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(
      of: find.byType(FractionallySizedBox),
      matching: find.byType(DecoratedBox),
    ),
  );
  return (box.decoration as BoxDecoration).color!;
}

/// The battery body's outline, which is the glyph's colour whether it is
/// showing a fill or a bolt.
Color _bodyColor(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
  return ((box.decoration as BoxDecoration).border! as Border).top.color;
}

void main() {
  testWidgets('hidden entirely on a Mac with no battery', (tester) async {
    await _pump(
      tester,
      const PowerState(percent: 0, isCharging: false, isPresent: false),
    );

    expect(find.byType(FractionallySizedBox), findsNothing);
    expect(find.textContaining('%'), findsNothing);
  });

  // The meter is drawn by a `FractionallySizedBox`, which collapses to zero
  // height unless `heightFactor` is set — so it read empty at every
  // percentage until this was pinned.
  testWidgets('the meter is actually filled, in proportion', (tester) async {
    await _pump(
      tester,
      const PowerState(percent: 75, isCharging: false, isPresent: true),
    );

    expect(find.text('75%'), findsOneWidget);

    final fill = tester.getSize(find.byType(FractionallySizedBox));
    expect(fill.height, greaterThan(0));
    expect(fill.width, greaterThan(0));

    final track = tester.getSize(find.byType(SizedBox).first);
    expect(fill.width / track.width, closeTo(0.75, 0.2));
  });

  // One test per state: `pumpWidget` on an existing tree keeps the old
  // provider overrides, so re-pumping inside a single test silently asserts
  // against the first state three times.
  // Charging keeps the level fill and stacks the bolt on top of it, rather
  // than replacing the level with a bolt floating in an empty body.
  testWidgets('green, filled to the level, with the bolt stacked on top', (
    tester,
  ) async {
    await _pump(
      tester,
      const PowerState(percent: 91, isCharging: true, isPresent: true),
    );

    expect(_bodyColor(tester), NotchColors.positive);
    expect(_fillColor(tester), NotchColors.positive);
    expect(find.byType(BatteryBolt), findsOneWidget);

    final fill = tester.getRect(find.byType(FractionallySizedBox));
    final bolt = tester.getRect(find.byType(BatteryBolt));
    expect(fill.width, greaterThan(0), reason: 'the level still reads');
    // Stacked *over* the fill, not beside it or instead of it.
    expect(fill.overlaps(bolt), isTrue);

    // Full body height, outline included: the bolt cuts through the border
    // rather than sitting inside it.
    final body = tester.getRect(find.byType(DecoratedBox).first);
    expect(bolt.height, body.height);
    expect(bolt.top, body.top);
    expect(bolt.bottom, body.bottom);
  });

  testWidgets('amber when low and not charging', (tester) async {
    await _pump(
      tester,
      const PowerState(percent: 15, isCharging: false, isPresent: true),
    );
    expect(_fillColor(tester), NotchColors.warning);
    expect(find.byType(BatteryBolt), findsNothing);
  });

  testWidgets('plain otherwise', (tester) async {
    await _pump(
      tester,
      const PowerState(percent: 80, isCharging: false, isPresent: true),
    );
    expect(_fillColor(tester), NotchColors.primaryText);
  });

  testWidgets('golden: charging and not charging', (tester) async {
    await _pump(
      tester,
      const PowerState(percent: 91, isCharging: true, isPresent: true),
    );
    await expectLater(
      find.byType(BatteryPill),
      matchesGoldenFile('goldens/battery_charging.png'),
    );
  });

  testWidgets('golden: on battery', (tester) async {
    await _pump(
      tester,
      const PowerState(percent: 76, isCharging: false, isPresent: true),
    );
    await expectLater(
      find.byType(BatteryPill),
      matchesGoldenFile('goldens/battery_on_battery.png'),
    );
  });

  // The bolt crosses unfilled body at a low charge, where a bare knockout
  // would disappear into the background.
  testWidgets('golden: charging at a low level', (tester) async {
    await _pump(
      tester,
      const PowerState(percent: 12, isCharging: true, isPresent: true),
    );
    await expectLater(
      find.byType(BatteryPill),
      matchesGoldenFile('goldens/battery_charging_low.png'),
    );
  });

  // Magnified on purpose. The other goldens render at dpr 1, where the whole
  // bolt is about ten pixels and a completely wrong shape looks like noise —
  // which is exactly how a dark bolt survived several rounds of review when
  // it should have been a green one ringed in dark.
  testWidgets('golden: the charging glyph, magnified', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          powerProvider.overrideWith(
            (ref) => Stream.value(
              const PowerState(percent: 100, isCharging: true, isPresent: true),
            ),
          ),
        ],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextStyle(
            style: const TextStyle(decoration: TextDecoration.none),
            child: Center(
              child: RepaintBoundary(
                child: SizedBox(
                  width: 760,
                  height: 200,
                  child: ColoredBox(
                    color: NotchColors.panel,
                    child: Center(
                      child: Transform.scale(
                        scale: 8,
                        child: const BatteryPill(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(BatteryPill),
      matchesGoldenFile('goldens/battery_charging_zoom.png'),
    );
  });
}

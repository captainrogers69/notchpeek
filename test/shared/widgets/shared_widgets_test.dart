import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/shared/widgets/artwork_tile.dart';
import 'package:notchpeek/shared/widgets/notch_icon_button.dart';
import 'package:notchpeek/shared/widgets/permission_prompt.dart';
import 'package:notchpeek/shared/widgets/scrubber.dart';

Widget _wrap(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: ColoredBox(
    color: const Color(0xFF0A0A0A),
    child: Center(child: child),
  ),
);

void main() {
  testWidgets('the permission prompt explains and offers exactly one action', (
    tester,
  ) async {
    var pressed = 0;
    await tester.pumpWidget(
      _wrap(
        PermissionPrompt(
          explanation: 'NotchPeek needs permission to read Apple Music.',
          actionLabel: 'Open Settings',
          onPressed: () => pressed++,
        ),
      ),
    );

    expect(find.textContaining('needs permission'), findsOneWidget);
    await tester.tap(find.text('Open Settings'));
    expect(pressed, 1);
  });

  testWidgets('a disabled icon button does not fire', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      _wrap(
        const NotchIconButton(
          icon: Icons.skip_next,
          semanticLabel: 'Next',
          onPressed: null,
        ),
      ),
    );

    await tester.tap(find.byType(NotchIconButton));
    expect(pressed, 0);
  });

  testWidgets(
    'the artwork tile falls back to a placeholder when there is no file',
    (tester) async {
      await tester.pumpWidget(_wrap(const ArtworkTile(path: null, side: 96)));

      expect(find.byIcon(Icons.music_note), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets(
    'the artwork tile falls back when the file is missing from disk',
    (tester) async {
      await tester.pumpWidget(
        _wrap(const ArtworkTile(path: '/does/not/exist.jpg', side: 96)),
      );
      await tester.pump();

      expect(find.byIcon(Icons.music_note), findsOneWidget);
    },
  );

  // The track is hand-drawn, not a Material `Slider`: there is no `Material`
  // and no `Overlay` under this app's `WidgetsApp` root, and `Slider` asserts
  // on both. So these assert the behaviour rather than the widget type.
  testWidgets('the scrubber shows both clocks and reports a seek fraction', (
    tester,
  ) async {
    double? seeked;
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 300,
          child: Scrubber(
            progress: 0.25,
            position: const Duration(seconds: 60),
            duration: const Duration(seconds: 240),
            onSeek: (v) => seeked = v,
          ),
        ),
      ),
    );

    expect(find.text('1:00'), findsOneWidget);
    expect(find.text('4:00'), findsOneWidget);

    // The clocks sit at the two ends, so the row's centre is the track's.
    await tester.tapAt(tester.getCenter(find.byType(Scrubber)));
    expect(seeked, isNotNull);
    expect(seeked, closeTo(0.5, 0.02));
  });

  testWidgets('a scrubber with no duration cannot be seeked', (tester) async {
    double? seeked;
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 300,
          child: Scrubber(
            progress: 0,
            position: Duration.zero,
            duration: Duration.zero,
            onSeek: null,
          ),
        ),
      ),
    );

    await tester.tapAt(tester.getCenter(find.byType(Scrubber)));
    await tester.drag(find.byType(Scrubber), const Offset(80, 0));
    expect(seeked, isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/features/shell/presentation/widgets/notch_shape.dart';

Widget _harness(Size size) => Directionality(
  textDirection: TextDirection.ltr,
  child: ColoredBox(
    color: const Color(0xFF202020),
    child: Center(
      child: SizedBox.fromSize(
        size: size,
        child: const ClipPath(
          clipper: NotchShape(),
          child: ColoredBox(color: NotchColors.panel),
        ),
      ),
    ),
  ),
);

void main() {
  test(
    'the path spans the full box at the top and insets by the shoulder below',
    () {
      const size = Size(400, 200);
      final path = NotchShape.build(size, shoulder: 14, bottomRadius: 22);

      expect(
        path.contains(const Offset(200, 1)),
        isTrue,
        reason: 'top centre is inside',
      );
      expect(
        path.contains(const Offset(2, 60)),
        isFalse,
        reason: 'the shoulder is carved away',
      );
      expect(path.contains(const Offset(398, 60)), isFalse);
      expect(
        path.contains(const Offset(200, 199)),
        isTrue,
        reason: 'bottom centre is inside',
      );
    },
  );

  test('the bottom corners are rounded away', () {
    const size = Size(400, 200);
    final path = NotchShape.build(size, shoulder: 14, bottomRadius: 22);

    expect(path.contains(const Offset(15, 199)), isFalse);
    expect(path.contains(const Offset(385, 199)), isFalse);
  });

  test('a box narrower than two shoulders still produces a closed path', () {
    final path = NotchShape.build(
      const Size(10, 40),
      shoulder: 14,
      bottomRadius: 22,
    );

    expect(path.getBounds().isEmpty, isFalse);
  });

  testWidgets('golden: collapsed silhouette', (tester) async {
    await tester.pumpWidget(_harness(const Size(228, 32)));
    await expectLater(
      find.byType(ClipPath),
      matchesGoldenFile('goldens/notch_shape_collapsed.png'),
    );
  });

  testWidgets('golden: expanded silhouette', (tester) async {
    await tester.pumpWidget(_harness(const Size(620, 220)));
    await expectLater(
      find.byType(ClipPath),
      matchesGoldenFile('goldens/notch_shape_expanded.png'),
    );
  });
}

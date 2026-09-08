import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/features/shell/data/models/notch_geometry_model.dart';
import 'package:notchpeek/features/shell/domain/entities/notch_geometry.dart';
import 'package:notchpeek/shared/utils/enums/notch_state.dart';

const _devMachine = NotchGeometry(
  screenWidth: 1470,
  screenHeight: 956,
  notchWidth: 300,
  notchHeight: 32,
  notchLeft: 585,
  scale: 2,
  isVirtual: false,
  displayId: 7,
);

void main() {
  test('the notch rect sits at the top of the canvas', () {
    expect(_devMachine.notchRect, const Rect.fromLTWH(585, 0, 300, 32));
    expect(_devMachine.centerX, 735);
  });

  test(
    'the hot zone inflates sideways and downwards but never above the screen',
    () {
      final zone = _devMachine.hotZone(inset: 6);

      expect(zone.top, 0);
      expect(zone.left, 579);
      expect(zone.right, 891);
      expect(zone.bottom, 38);
    },
  );

  test('a centred rect is centred on the notch, not on the screen', () {
    final rect = _devMachine.centeredRect(const Size(620, 220));

    expect(rect.center.dx, 735);
    expect(rect.top, 0);
    expect(rect.width, 620);
    expect(rect.height, 220);
  });

  test(
    'a centred rect is pushed back on screen when the notch is near an edge',
    () {
      const offCentre = NotchGeometry(
        screenWidth: 800,
        screenHeight: 600,
        notchWidth: 200,
        notchHeight: 32,
        notchLeft: 40,
        scale: 2,
        isVirtual: true,
        displayId: 7,
      );

      final rect = offCentre.centeredRect(const Size(620, 220));

      expect(rect.left, 0);
      expect(rect.right, 620);
    },
  );

  test('the interactive rect is a different shape in each shell state', () {
    expect(
      _devMachine.interactiveRect(NotchState.collapsed),
      _devMachine.hotZone(inset: NotchSizes.hotZoneInset),
    );
    expect(
      _devMachine.interactiveRect(NotchState.peeking).width,
      NotchSizes.peekWidth,
    );
    expect(
      _devMachine.interactiveRect(NotchState.expanded).height,
      NotchSizes.expandedHeight,
    );
  });

  test(
    'parses the channel map, defaulting rather than throwing on a bad payload',
    () {
      final parsed = NotchGeometryModel.toEntity(const {
        'screenWidth': 1470.0,
        'screenHeight': 956.0,
        'notchWidth': 300.0,
        'notchHeight': 32.0,
        'notchLeft': 585.0,
        'scale': 2.0,
        'isVirtual': false,
        'displayId': 7,
      });
      expect(parsed, _devMachine);

      final degenerate = NotchGeometryModel.toEntity(const {});
      expect(degenerate.isVirtual, isTrue);
      expect(degenerate.notchWidth, greaterThan(0));
    },
  );
}

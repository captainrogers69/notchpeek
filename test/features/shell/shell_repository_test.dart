import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/core/platform/channels.dart';
import 'package:notchpeek/features/shell/data/datasources/shell_datasource.dart';
import 'package:notchpeek/features/shell/data/repositories/shell_repository_impl.dart';

class _FakeShellDataSource implements ShellDataSource {
  _FakeShellDataSource(this.events, {this.hoverEvents = const Stream.empty()});

  final Stream<Map<String, Object?>> events;
  final Stream<Map<String, Object?>> hoverEvents;
  final List<Rect> reported = [];
  int haptics = 0;
  int quits = 0;

  @override
  Stream<Map<String, Object?>> watchGeometryEvents() => events;

  @override
  Stream<Map<String, Object?>> watchHoverEvents() => hoverEvents;

  @override
  Stream<Map<String, Object?>> watchPowerEvents() => const Stream.empty();

  @override
  Future<ApiResponse<bool>> performHaptic() async {
    haptics++;
    return ApiResponse.success(message: 'OK', data: true);
  }

  @override
  Future<ApiResponse<bool>> quit() async {
    quits++;
    return ApiResponse.success(message: 'OK', data: true);
  }

  @override
  Future<ApiResponse<bool>> setInteractiveRect(Rect rect) async {
    reported.add(rect);
    return ApiResponse.success(message: 'OK', data: true);
  }
}

void main() {
  test('maps geometry events into entities in order', () async {
    final source = _FakeShellDataSource(
      Stream.fromIterable([
        const {
          'screenWidth': 1470.0,
          'screenHeight': 956.0,
          'notchWidth': 300.0,
          'notchHeight': 32.0,
          'notchLeft': 585.0,
          'scale': 2.0,
          'isVirtual': false,
        },
        const {
          'screenWidth': 2560.0,
          'screenHeight': 1440.0,
          'notchWidth': 200.0,
          'notchHeight': 32.0,
          'notchLeft': 1180.0,
          'scale': 2.0,
          'isVirtual': true,
        },
      ]),
    );

    final entities = await ShellRepositoryImpl(source).watchGeometry().toList();

    expect(entities, hasLength(2));
    expect(entities.first.notchWidth, 300);
    expect(entities.last.isVirtual, isTrue);
  });

  test('forwards the interactive rect straight through', () async {
    final source = _FakeShellDataSource(const Stream.empty());

    final result = await ShellRepositoryImpl(
      source,
    ).setInteractiveRect(const Rect.fromLTWH(1, 2, 3, 4));

    expect(result.status, isTrue);
    expect(source.reported.single, const Rect.fromLTWH(1, 2, 3, 4));
  });

  test('maps hover events to a bare bool, defaulting to "not here"', () async {
    final source = _FakeShellDataSource(
      const Stream.empty(),
      hoverEvents: Stream<Map<String, Object?>>.fromIterable([
        {SystemEventKind.inside: true},
        {SystemEventKind.inside: false},
        // Malformed: reads as "the cursor is not here", which collapses the
        // shell. Getting stuck open is the failure that matters.
        <String, Object?>{},
      ]),
    );

    final hovers = await ShellRepositoryImpl(source).watchHover().toList();

    expect(hovers, [true, false, false]);
  });

  test('forwards a haptic straight through', () async {
    final source = _FakeShellDataSource(const Stream.empty());

    final result = await ShellRepositoryImpl(source).performHaptic();

    expect(result.status, isTrue);
    expect(source.haptics, 1);
  });

  test('the datasource only forwards events of the hover kind', () async {
    final events = Stream<Map<String, Object?>>.fromIterable([
      {SystemEventKind.key: SystemEventKind.geometry, 'notchWidth': 300.0},
      {
        SystemEventKind.key: SystemEventKind.hover,
        SystemEventKind.inside: true,
      },
    ]);

    final forwarded = await ShellDataSourceImpl.filterHover(events).toList();

    expect(forwarded, hasLength(1));
    expect(forwarded.single[SystemEventKind.inside], isTrue);
  });

  test('the datasource only forwards events of the geometry kind', () async {
    final events = Stream<Map<String, Object?>>.fromIterable([
      {SystemEventKind.key: SystemEventKind.power, 'percent': 80},
      {SystemEventKind.key: SystemEventKind.geometry, 'notchWidth': 300.0},
    ]);

    final forwarded = await ShellDataSourceImpl.filterGeometry(events).toList();

    expect(forwarded, hasLength(1));
    expect(forwarded.single['notchWidth'], 300.0);
  });
}

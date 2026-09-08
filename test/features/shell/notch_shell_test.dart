import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/shell/domain/entities/notch_geometry.dart';
import 'package:notchpeek/features/shell/domain/repositories/shell_repository.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';
import 'package:notchpeek/features/shell/presentation/widgets/notch_shell.dart';
import 'package:notchpeek/shared/utils/enums/notch_state.dart';
import 'package:notchpeek/shared/utils/enums/peek_kind.dart';
import 'package:notchpeek/shared/widgets/notch_close_button.dart';

const _geometry = NotchGeometry(
  screenWidth: 1470,
  screenHeight: 956,
  notchWidth: 300,
  notchHeight: 32,
  notchLeft: 585,
  scale: 2,
  isVirtual: false,
  displayId: 7,
);

class _RecordingShellRepository implements ShellRepository {
  final List<Rect> rects = [];
  int quits = 0;

  @override
  Stream<NotchGeometry> watchGeometry() => const Stream.empty();

  @override
  Stream<bool> watchHover() => const Stream.empty();

  @override
  Future<ApiResponse<bool>> performHaptic() async =>
      ApiResponse.success(message: 'OK', data: true);

  @override
  Future<ApiResponse<bool>> quit() async {
    quits++;
    return ApiResponse.success(message: 'OK', data: true);
  }

  @override
  Future<ApiResponse<bool>> setInteractiveRect(Rect rect) async {
    rects.add(rect);
    return ApiResponse.success(message: 'OK', data: true);
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _RecordingShellRepository repo,
) async {
  final container = ProviderContainer(
    overrides: [
      shellRepositoryProvider.overrideWithValue(repo),
      peekDwellProvider.overrideWithValue(const Duration(seconds: 30)),
    ],
  );
  addTearDown(container.dispose);

  // The canvas in production is the full screen width by NotchSizes.canvasHeight.
  // Match it, or the panel renders off the edge of the test surface.
  await tester.binding.setSurfaceSize(
    Size(_geometry.screenWidth, NotchSizes.canvasHeight),
  );
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: NotchShell(geometry: _geometry, child: Text('panel')),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  testWidgets('reports the collapsed hot zone on first frame', (tester) async {
    final repo = _RecordingShellRepository();
    await _pump(tester, repo);

    expect(repo.rects.last, _geometry.interactiveRect(NotchState.collapsed));
  });

  testWidgets('reports the expanded rect once the morph has settled', (
    tester,
  ) async {
    final repo = _RecordingShellRepository();
    final container = await _pump(tester, repo);

    container.read(shellNotifierProvider.notifier).hoverEntered();
    await tester.pumpAndSettle();

    expect(repo.rects.last, _geometry.interactiveRect(NotchState.expanded));
  });

  testWidgets('reports the peek rect while peeking', (tester) async {
    final repo = _RecordingShellRepository();
    final container = await _pump(tester, repo);

    container
        .read(shellNotifierProvider.notifier)
        .peekRequested(PeekKind.trackChange);
    await tester.pumpAndSettle();

    expect(repo.rects.last, _geometry.interactiveRect(NotchState.peeking));

    // The dwell timer would otherwise outlive the widget tree.
    container.read(shellNotifierProvider.notifier).peekExpired();
  });

  testWidgets('hides its child while collapsed and shows it when expanded', (
    tester,
  ) async {
    final repo = _RecordingShellRepository();
    final container = await _pump(tester, repo);

    expect(find.text('panel'), findsNothing);

    container.read(shellNotifierProvider.notifier).hoverEntered();
    await tester.pumpAndSettle();

    expect(find.text('panel'), findsOneWidget);
  });

  // The only way out of an agent app with no Dock icon and no menu bar, so it
  // belongs to the shell: a panel that renders nothing must not be able to
  // take it away.
  testWidgets('the close button shows for every state that draws content', (
    tester,
  ) async {
    final repo = _RecordingShellRepository();
    final container = await _pump(tester, repo);
    final notifier = container.read(shellNotifierProvider.notifier);

    expect(
      find.byType(NotchCloseButton),
      findsNothing,
      reason: 'nothing is drawn while collapsed',
    );

    notifier.hoverEntered();
    await tester.pumpAndSettle();
    expect(find.byType(NotchCloseButton), findsOneWidget);

    notifier.hoverExited();
    await tester.pumpAndSettle();
    notifier.peekRequested(PeekKind.charger);
    await tester.pumpAndSettle();
    expect(
      find.byType(NotchCloseButton),
      findsOneWidget,
      reason: 'a peek is a state too',
    );
    notifier.peekExpired();
  });

  testWidgets('tapping the close button quits the app', (tester) async {
    final repo = _RecordingShellRepository();
    final container = await _pump(tester, repo);

    container.read(shellNotifierProvider.notifier).hoverEntered();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NotchCloseButton));
    await tester.pump();

    expect(repo.quits, 1);
  });

  // An empty panel is exactly when the user most needs the way out.
  testWidgets('the close button survives a child that renders nothing', (
    tester,
  ) async {
    final repo = _RecordingShellRepository();
    final container = ProviderContainer(
      overrides: [
        shellRepositoryProvider.overrideWithValue(repo),
        peekDwellProvider.overrideWithValue(const Duration(seconds: 30)),
      ],
    );
    addTearDown(container.dispose);
    await tester.binding.setSurfaceSize(
      Size(_geometry.screenWidth, NotchSizes.canvasHeight),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: NotchShell(geometry: _geometry, child: SizedBox.shrink()),
        ),
      ),
    );
    container.read(shellNotifierProvider.notifier).hoverEntered();
    await tester.pumpAndSettle();

    expect(find.byType(NotchCloseButton), findsOneWidget);
  });

  testWidgets('golden: collapsed, peeking and expanded', (tester) async {
    final repo = _RecordingShellRepository();
    final container = await _pump(tester, repo);

    await expectLater(
      find.byType(NotchShell),
      matchesGoldenFile('goldens/shell_collapsed.png'),
    );

    container
        .read(shellNotifierProvider.notifier)
        .peekRequested(PeekKind.charger);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(NotchShell),
      matchesGoldenFile('goldens/shell_peeking.png'),
    );

    container.read(shellNotifierProvider.notifier).hoverEntered();
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(NotchShell),
      matchesGoldenFile('goldens/shell_expanded.png'),
    );
  });

  testWidgets('an expiring peek retracts the shell without a pending timer', (
    tester,
  ) async {
    final repo = _RecordingShellRepository();
    final container = await _pump(tester, repo);

    container
        .read(shellNotifierProvider.notifier)
        .peekRequested(PeekKind.charger);
    await tester.pumpAndSettle();
    container.read(shellNotifierProvider.notifier).peekExpired();
    await tester.pumpAndSettle();

    expect(container.read(shellNotifierProvider).state, NotchState.collapsed);
    expect(repo.rects.last, _geometry.interactiveRect(NotchState.collapsed));
  });
}

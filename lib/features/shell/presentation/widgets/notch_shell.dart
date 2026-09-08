import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/features/shell/domain/entities/notch_geometry.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';
import 'package:notchpeek/features/shell/presentation/widgets/notch_shape.dart';
import 'package:notchpeek/shared/utils/enums/notch_state.dart';
import 'package:notchpeek/shared/widgets/notch_close_button.dart';

/// The container, not a panel. It owns notch state, the clipper, the morph and
/// the interactive-rect reporting. Panels render inside it and know nothing
/// about it (architecture-playbook §3).
class NotchShell extends HookConsumerWidget {
  const NotchShell({required this.geometry, required this.child, super.key});

  final NotchGeometry geometry;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shell = ref.watch(shellNotifierProvider);
    final target = geometry.interactiveRect(shell.state);
    final collapsed = geometry.interactiveRect(NotchState.collapsed);

    final controller = useAnimationController(duration: NotchMotion.open);

    final curve = useMemoized(
      () => CurvedAnimation(
        parent: controller,
        curve: NotchMotion.openCurve,
        reverseCurve: NotchMotion.closeCurve,
      ),
      [controller],
    );
    useEffect(() => curve.dispose, [curve]);

    // One controller, retimed per direction: opening is slower and eases out,
    // closing is quicker and eases in.
    useEffect(() {
      controller.duration = shell.isCollapsed
          ? NotchMotion.close
          : NotchMotion.open;
      if (shell.isCollapsed) {
        controller.reverse();
      } else {
        controller.forward();
      }
      return null;
    }, [shell.state]);

    // Push the rect down once the state has settled, on the frame after the
    // change — MouseGate must never be told about a rect that is still moving.
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(reportInteractiveRectProvider)(target);
      });
      return null;
    }, [target]);

    return Align(
      alignment: Alignment.topLeft,
      child: AnimatedBuilder(
        animation: curve,
        builder: (context, _) {
          final width = lerpDouble(collapsed.width, target.width, curve.value)!;
          final height = lerpDouble(
            collapsed.height,
            target.height,
            curve.value,
          )!;
          final radius = lerpDouble(
            NotchRadii.collapsedBottom,
            NotchRadii.panelBottom,
            curve.value,
          )!;

          return Padding(
            padding: EdgeInsets.only(left: geometry.centerX - width / 2),
            child: SizedBox(
              width: width,
              height: height,
              child: ClipPath(
                clipper: NotchShape(bottomRadius: radius),
                child: ColoredBox(
                  color: NotchColors.panel,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AnimatedSwitcher(
                          duration: NotchMotion.contentFade,
                          switchInCurve: NotchMotion.contentStagger,
                          child: shell.showsContent
                              ? KeyedSubtree(
                                  key: const ValueKey('content'),
                                  child: child,
                                )
                              : const SizedBox.shrink(key: ValueKey('empty')),
                        ),
                      ),
                      // Owned by the shell, not by any panel: a panel that
                      // renders nothing — or throws — must not be able to take
                      // the only way out with it. Inset past the concave
                      // shoulder, which cuts in to `x = w - 12` at this height.
                      if (shell.showsContent)
                        Positioned(
                          top: 6,
                          right: 20,
                          child: NotchCloseButton(
                            onPressed: () => ref.read(quitAppProvider)(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

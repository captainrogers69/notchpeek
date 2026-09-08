import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/core/platform/channel_service.dart';
import 'package:notchpeek/features/shell/data/datasources/shell_datasource.dart';
import 'package:notchpeek/features/shell/data/repositories/shell_repository_impl.dart';
import 'package:notchpeek/features/shell/domain/entities/notch_geometry.dart';
import 'package:notchpeek/features/shell/domain/entities/shell_state.dart';
import 'package:notchpeek/features/shell/domain/repositories/shell_repository.dart';
import 'package:notchpeek/features/shell/domain/usecases/perform_haptic.dart';
import 'package:notchpeek/features/shell/domain/usecases/report_interactive_rect.dart';
import 'package:notchpeek/features/shell/domain/usecases/watch_geometry.dart';
import 'package:notchpeek/features/shell/domain/usecases/watch_hover.dart';
import 'package:notchpeek/features/shell/presentation/notifier/shell_notifier.dart';

/// The provider graph *is* the registry — there is no central registration
/// file, and that is the main reason `get_it` is out
/// (architecture-playbook §7). Every one of these is overridable in tests.
final shellDataSourceProvider = Provider<ShellDataSource>(
  (ref) => ShellDataSourceImpl(ref.watch(channelServiceProvider)),
);

final shellRepositoryProvider = Provider<ShellRepository>(
  (ref) => ShellRepositoryImpl(ref.watch(shellDataSourceProvider)),
);

final watchGeometryProvider = Provider<WatchGeometry>(
  (ref) => WatchGeometry(ref.watch(shellRepositoryProvider)),
);

/// Whether the cursor is inside the rect Swift was last told about. Swift is
/// the only side that can answer this: `MouseGate` makes the panel
/// mouse-transparent the moment the cursor leaves, and AppKit sends no
/// `mouseExited` for that, so a Flutter `MouseRegion` would stay stuck
/// "entered" forever. [ShellNotifier] is the only consumer.
final watchHoverProvider = Provider<WatchHover>(
  (ref) => WatchHover(ref.watch(shellRepositoryProvider)),
);

final reportInteractiveRectProvider = Provider<ReportInteractiveRect>(
  (ref) => ReportInteractiveRect(ref.watch(shellRepositoryProvider)),
);

final performHapticProvider = Provider<PerformHaptic>(
  (ref) => PerformHaptic(ref.watch(shellRepositoryProvider)),
);

/// The Swift side is already stream-shaped, so a `StreamProvider` per
/// `EventChannel` is the natural fit (architecture-playbook §2).
final geometryProvider = StreamProvider<NotchGeometry>(
  (ref) => ref.watch(watchGeometryProvider)(),
);

/// How long an unattended peek stays out. A provider rather than a constant
/// so tests can drive the machine without waiting four seconds.
final peekDwellProvider = Provider<Duration>((ref) => NotchMotion.peekDwell);

final shellNotifierProvider = NotifierProvider<ShellNotifier, ShellState>(
  ShellNotifier.new,
);

# M1 — Notch Shell and Music: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a usable macOS notch app — invisible at rest, peeks on events, expands on hover — with working Apple Music and Spotify controls.

**Architecture:** One borderless `NSPanel` sized once to the full screen width and never resized; every expand, collapse and peek is a Flutter animation painted inside that fixed transparent canvas. Swift owns the OS (windowing, geometry, mouse gating, scripting reads, battery, permissions) and normalizes every value at the boundary; Dart owns product decisions through feature-first Clean Architecture with `hooks_riverpod` as both state layer and DI graph. The load-bearing seam is Dart ↔ Swift over one `MethodChannel` and three `EventChannel`s, not Dart ↔ HTTP.

**Tech Stack:** Flutter 3.44.4 / Dart 3.12.2 · `hooks_riverpod` 3.4.3 · `flutter_hooks` 0.21.3 · `dio` 5.11.1 · `equatable` 2.1.0 · Swift 6 / Xcode 26 · AppKit, ScriptingBridge, IOKit, SwiftUI, ServiceManagement · XCTest.

**Spec:** [`docs/specs/m1-shell-and-music.md`](../../specs/m1-shell-and-music.md)
**Rules (outranks the spec on anything structural):** [`docs/playbook/architecture-playbook.md`](../../playbook/architecture-playbook.md)
**Supporting:** [`docs/specs/2026-09-04-spike-system-nowplaying.md`](../../specs/2026-09-04-spike-system-nowplaying.md) · [`docs/risks-and-decisions.md`](../../risks-and-decisions.md)

---

## Global Constraints

Every task's requirements implicitly include this section.

- **OS floor: macOS 26.0.** `MACOSX_DEPLOYMENT_TARGET = 26.0` in all three configs (already applied). **No `@available` annotations anywhere** — every modern API is simply available.
- **State: `hooks_riverpod` only.** No `flutter_bloc`, no `get_it`, no `provider`, no bare `flutter_riverpod`. `Notifier`/`AsyncNotifier` only — **never `StateNotifier`** (deprecated in Riverpod 3).
- **DI is the Riverpod graph.** One provider per service, datasource, repository and usecase, colocated in `<feature>_providers.dart`. No central registration file. **Every dependency overridable in tests** — a class that news up its own collaborator is a bug.
- **Layering: UI → Notifier → UseCase → Repository → DataSource → `ChannelService` / `ApiService`.** A widget never reaches past its notifier. A datasource is the only thing that touches a channel or Dio.
- **Streams flow through every layer.** An `EventChannel` becomes `Stream<Entity>` at the repository and stays a stream up to the `StreamProvider`. Never shortcut a channel into a widget.
- **State classes:** immutable, `copyWith`, `extends Equatable` with real `props`. Derived values are getters on state (`canPlay`, `isBusy`, `hasTrack`) — **never computed in the UI**.
- **Logging: `NotchLogger` only.** No `print`, no `debugPrint`, no bare `dart:developer log`. Levels are `debug` · `success` · `error`. One tag per class, created once as a field. **Datasources always log both outcomes.** **Never log user content** — clipboard text, note bodies, calendar titles, file paths. Log ids, counts and states.
- **Networking:** Dio only, through `ApiService`. Every call returns `ApiResponse<T>`. **No `dartz`, no `Either`, no `Failure` hierarchy. No auth interceptor** — there are no accounts, tokens or 401 flow. Endpoints are constants; no URL literals at call sites.
- **UI:** `StatelessWidget`/`HookWidget` over widget-returning functions — **no `Widget _buildX()` methods, ever**. `HookWidget`/`HookConsumerWidget` over `StatefulWidget`. Extract a widget the moment it is used twice. Narrow rebuilds with `ref.watch(p.select((s) => s.field))`. **No responsive-sizing package, no routing package.** Colors, radii, durations and curves are tokens in `app/theme.dart` — **no magic numbers in widgets**, the morph timings especially.
- **Swift rules that cost real money if broken:** never block the main thread (scripting goes on a background queue); **never shell out to `osascript`** (~130 ms process-spawn cost — use in-process ScriptingBridge); **never send images on a tick** (artwork crosses once per track change, keyed by track id); **poll at 1 Hz while expanded, and not at all while collapsed**. Every Swift module is one file, one purpose, named for what it owns.
- **No business logic in Swift.** Swift normalizes units, shapes and encodings so Dart sees exactly one shape, and owns all storage. Decisions belong in `domain`.
- **Capability gating: every panel renders three ways** — Ready, Needs permission (explanation + Open Settings), Unavailable (hidden, never teased). A panel with only a ready state is incomplete.
- **Naming:** files `snake_case`, classes `PascalCase`, channels `notchpeek/<domain>`. `MusicRepository` (abstract) → `MusicRepositoryImpl`; `MusicRemoteDataSource` → `MusicRemoteDataSourceImpl`. Usecases are verb phrases (`GetNowPlaying`, `TogglePlayback`). Package root `package:notchpeek/…`, root-relative imports over `../../` chains. **No `_revamp` / `_v2` / `_new` suffixes** — the old file is deleted in the same commit.
- **Quality gate, before every commit:** `flutter analyze` at **0 errors** (not "0 new"), `dart format .` clean, `flutter test` green, Xcode build with no new warnings.
- **Commit format:** `feat(scope): …`, `fix(scope): …`, `refactor(scope): …`, `docs(scope): …`, `test(scope): …`.
- **Bundle identity:** `com.capcraft.notchpeek`, product name `NotchPeek`, studio Capcraft. Fixed; do not change.
- **Out of scope for this plan, by the user's explicit decision:** code signing, notarization, Developer ID, Sparkle, download hosting. Spec exit criterion 9 is **deferred** — see `risks-and-decisions.md` R7. `flutter run -d macos` and a local `flutter build macos` are the delivery targets. Everything else in exit criteria 1–8 and 10 is in scope.
- **Also out of scope:** every panel except music; monetization entirely; web players; the MediaRemote command path (spec §9).

---

## File Structure

### Dart — `lib/`

| Path | Responsibility |
|---|---|
| `main.dart` | Bootstrap. Installs `ProviderScope`, nothing else. |
| `app/notch_app.dart` | Root widget. Gates the first frame on resolved geometry. |
| `app/theme.dart` | `NotchColors`, `NotchRadii`, `NotchMotion`, `NotchSizes` tokens. The only place numbers live. |
| `core/logging/notch_logger.dart` | `NotchLogger`, three levels, injectable writer seam. |
| `core/platform/channels.dart` | Channel names and method names. Single source of truth. |
| `core/platform/channel_service.dart` | Typed wrapper over the `MethodChannel` and `EventChannel`s. |
| `core/platform/resilient_stream.dart` | Reconnect-with-backoff wrapper for a dying `EventChannel`. |
| `core/platform/capabilities.dart` | `Capabilities` model + `capabilitiesProvider`. |
| `core/network/errors/api_response.dart` | `ApiResponse<T>` envelope. Wraps channel results too. |
| `core/network/errors/api_error.dart` | `ApiErrorHandler`. Dio → user-readable message. |
| `core/network/endpoints/api_endpoints.dart` | iTunes artwork lookup constants. |
| `core/network/endpoints/api_method.dart` | `ApiMethod` enum. |
| `core/network/interceptor/log_interceptor.dart` | Dio logging through `NotchLogger`. |
| `core/services/api_service.dart` | The only `Dio` instance in the app. |
| `features/shell/domain/entities/notch_geometry.dart` | Screen + notch rects, hot zone, panel rect. |
| `features/shell/domain/entities/shell_state.dart` | The shell's immutable state. |
| `features/shell/domain/repositories/shell_repository.dart` | Abstract: geometry stream, report interactive rect. |
| `features/shell/domain/usecases/watch_geometry.dart` | `WatchGeometry`. |
| `features/shell/domain/usecases/report_interactive_rect.dart` | `ReportInteractiveRect`. |
| `features/shell/data/models/notch_geometry_model.dart` | Channel map → entity. |
| `features/shell/data/datasources/shell_datasource.dart` | Talks to `ChannelService`. |
| `features/shell/data/repositories/shell_repository_impl.dart` | Forwards, maps model → entity. |
| `features/shell/presentation/notifier/shell_notifier.dart` | The state machine. |
| `features/shell/presentation/shell_providers.dart` | The feature's slice of the DI graph. |
| `features/shell/presentation/widgets/notch_shape.dart` | `CustomClipper<Path>` — concave top, rounded bottom. |
| `features/shell/presentation/widgets/notch_shell.dart` | Morph controller, clip, content cross-fade, rect reporting. |
| `features/shell/presentation/widgets/tab_strip.dart` | Variable tab count from the start. |
| `features/shell/presentation/widgets/status_row.dart` | Battery pill + source badge. |
| `features/music/domain/entities/now_playing.dart` | `NowPlaying`. |
| `features/music/domain/repositories/music_repository.dart` | Abstract: watch, command. |
| `features/music/domain/usecases/*.dart` | `WatchNowPlaying`, `TogglePlayback`, `SkipNext`, `SkipPrevious`, `SeekTo`, `FetchArtworkFallback`. |
| `features/music/data/models/now_playing_model.dart` | Channel map → entity. The parsing that gets unit-tested. |
| `features/music/data/datasources/music_datasource.dart` | Channel reads and commands. |
| `features/music/data/datasources/artwork_remote_datasource.dart` | iTunes lookup through `ApiService`. |
| `features/music/data/repositories/music_repository_impl.dart` | Forwards, maps. |
| `features/music/presentation/notifier/music_notifier.dart` | Command dispatch + optimistic state. |
| `features/music/presentation/music_providers.dart` | The feature's DI slice. |
| `features/music/presentation/widgets/music_panel.dart` | Three capability states. |
| `shared/widgets/*.dart` | `PanelScaffold`, `PermissionPrompt`, `NotchIconButton`, `MarqueeText`, `ArtworkTile`, `Scrubber`, `EmptyState`. |
| `shared/utils/enums/*.dart` | `NotchState`, `PeekKind`, `PanelTab`, `PlaybackState`, `CapabilityState`, `MusicSourceId`, `MediaCommand`, `BuildFlavor`. |
| `shared/utils/helpers/duration_format.dart` | `mm:ss` formatting. |

### Swift — `macos/Runner/Notch/`

| Path | Responsibility |
|---|---|
| `Channels.swift` | Channel and method name constants. Mirrors `channels.dart`. |
| `NotchGeometry.swift` | Notch rect resolution, virtual-notch fallback, screen observers. |
| `NotchWindowController.swift` | The `NSPanel`, level, collection behavior, screen follow. |
| `MouseGate.swift` | Local mouse monitor, `ignoresMouseEvents` toggling. |
| `ChannelBridge.swift` | Wires one `MethodChannel` and three `EventChannel`s to the modules. |
| `CapabilityProbe.swift` | What this build, OS and permission set can do. |
| `PowerBridge.swift` | IOKit battery percentage and charging edge. |
| `MusicSource.swift` | `MusicSource` protocol, `NowPlayingPayload`, unit normalization. |
| `SpotifySource.swift` | ScriptingBridge against `com.spotify.client`. |
| `AppleMusicSource.swift` | ScriptingBridge against `com.apple.Music`. |
| `ArtworkCache.swift` | One artwork shape for Dart: a file path, keyed by track id. |
| `MediaBridge.swift` | Active-source selection, 1 Hz gated polling, command dispatch. |
| `SettingsWindow.swift` | Native SwiftUI settings window. |
| `LoginItem.swift` | `SMAppService` launch-at-login. |

### Swift tests — `macos/RunnerTests/`

`NotchGeometryTests.swift` · `MouseGateTests.swift` · `MusicSourceTests.swift` · `MediaBridgeTests.swift`

---

# Phase 0 — Make the repo match the playbook

`lib/` currently carries a partial transplant from the Go2Homes project. `flutter analyze` is at 0, but the code is still shaped for a REST app with accounts. Playbook §12 is the checklist; these five tasks clear it. **Nothing in Week 1 may start before Phase 0 is committed** — a `lib/` that contradicts the playbook makes every later review argue about the wrong thing.

---

### Task 1: Dependencies and package skeleton

**Files:**
- Modify: `pubspec.yaml:38-43`
- Create: `lib/app/`, `lib/core/logging/`, `lib/core/platform/`, `lib/features/shell/{data,domain,presentation}/`, `lib/features/music/{data,domain,presentation}/`, `lib/shared/widgets/`, `lib/shared/utils/{enums,helpers,extensions}/` (each with a `.gitkeep`)
- Create: `test/` mirror directories

**Interfaces:**
- Consumes: nothing.
- Produces: `flutter_hooks` and `hooks_riverpod` importable; `flutter_riverpod` no longer a direct dependency. The directory tree every later task writes into.

- [ ] **Step 1: Replace the dependency block**

In `pubspec.yaml`, replace the four lines under the state-management comment with:

```yaml
  # State management. No codegen: the native side is already stream-shaped, so
  # StreamProvider over each EventChannel is a direct fit (architecture-playbook §2).
  # hooks_riverpod re-exports flutter_riverpod — never depend on the bare package.
  hooks_riverpod: ^3.4.3
  flutter_hooks: ^0.21.3

  # Artwork lookup only. NotchPeek has no backend (architecture-playbook §5).
  dio: ^5.11.1
  equatable: ^2.1.0
```

Note what changed: `flutter_riverpod` is **gone**, `flutter_hooks` is now **explicit** rather than transitive.

- [ ] **Step 2: Resolve and prove nothing imports the removed package**

Run:
```bash
flutter pub get
grep -rn "package:flutter_riverpod" lib test
```
Expected: `pub get` succeeds; `grep` prints nothing (exit 1). If it prints a file, change that import to `package:hooks_riverpod/hooks_riverpod.dart`.

- [ ] **Step 3: Create the directory skeleton**

```bash
mkdir -p lib/app lib/core/logging lib/core/platform \
  lib/features/shell/{data/{models,datasources,repositories},domain/{entities,repositories,usecases},presentation/{notifier,widgets}} \
  lib/features/music/{data/{models,datasources,repositories},domain/{entities,repositories,usecases},presentation/{notifier,widgets}} \
  lib/shared/widgets lib/shared/utils/{enums,helpers,extensions} \
  test/core/{logging,platform} test/features/{shell,music} test/shared/utils
find lib/app lib/core/platform lib/features lib/shared test/core test/features test/shared -type d -empty -exec touch {}/.gitkeep \;
```

- [ ] **Step 4: Verify the gate**

Run: `flutter analyze && dart format --set-exit-if-changed .`
Expected: `No issues found!` and no reformatting.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock lib test
git commit -m "chore(deps): drop bare flutter_riverpod, add flutter_hooks, scaffold playbook tree"
```

---

### Task 2: `NotchLogger` moves to `core/logging` and loses its crash-reporter tail

`lib/utils/helpers/app_logger.dart` already declares a class called `NotchLogger`, but it sits at the wrong path, carries five levels instead of the playbook's three, and holds a `NotchLogSink`/`CrashReporter` indirection for a crash reporter this app does not have. It is also untestable: it writes straight to `dart:developer`.

**Files:**
- Create: `lib/core/logging/notch_logger.dart`
- Delete: `lib/utils/helpers/app_logger.dart` (and the now-empty `lib/utils/`)
- Modify: `lib/core/network/interceptor/log_interceptor.dart:5` (import path)
- Test: `test/core/logging/notch_logger_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum NotchLogLevel { debug, success, error }`
  - `typedef NotchLogWriter = void Function(String line)`
  - `class NotchLogger` with `NotchLogger.forTag(String tag)`, `void debug(String)`, `void success(String)`, `void error(String message, {Object? error, StackTrace? stackTrace})`
  - statics `NotchLogger.globalEnabled` (bool), `NotchLogger.useColors` (bool), `NotchLogger.writer` (`NotchLogWriter`)

- [ ] **Step 1: Write the failing test**

`test/core/logging/notch_logger_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/core/logging/notch_logger.dart';

void main() {
  late List<String> lines;

  setUp(() {
    lines = <String>[];
    NotchLogger.writer = lines.add;
    NotchLogger.useColors = false;
    NotchLogger.globalEnabled = true;
  });

  test('tags every line with the logger tag and the level', () {
    NotchLogger.forTag('MediaDataSourceImpl').success('now playing: t1');

    expect(lines, hasLength(1));
    expect(lines.single, contains('[SUCCESS]'));
    expect(lines.single, contains('[MediaDataSourceImpl]'));
    expect(lines.single, contains('now playing: t1'));
  });

  test('writes nothing when globally disabled', () {
    NotchLogger.globalEnabled = false;

    NotchLogger.forTag('X').debug('quiet');

    expect(lines, isEmpty);
  });

  test('an instance disabled at construction stays quiet while others log', () {
    NotchLogger(tag: 'Chatty', enabled: false).debug('suppressed');
    NotchLogger.forTag('Loud').debug('emitted');

    expect(lines, hasLength(1));
    expect(lines.single, contains('[Loud]'));
  });

  test('error appends the cause and the stack trace as separate lines', () {
    NotchLogger.forTag('Probe').error(
      'scripting read failed',
      error: StateError('boom'),
      stackTrace: StackTrace.fromString('frame0'),
    );

    expect(lines, hasLength(3));
    expect(lines[0], contains('scripting read failed'));
    expect(lines[1], contains('cause: Bad state: boom'));
    expect(lines[2], contains('frame0'));
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/core/logging/notch_logger_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:notchpeek/core/logging/notch_logger.dart'`.

- [ ] **Step 3: Write the logger**

`lib/core/logging/notch_logger.dart`:

```dart
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';

/// The only three levels the playbook allows (§6). `info` and `warning` were
/// dropped deliberately: in practice everything was one of these three.
enum NotchLogLevel { debug, success, error }

/// Where a formatted line ends up. Swapped in tests; `dart:developer` in the
/// app. This seam is why the logger is testable at all.
typedef NotchLogWriter = void Function(String line);

/// The only logging path in NotchPeek. No `print`, no `debugPrint`.
///
/// **Never log user content** — clipboard text, note bodies, calendar titles
/// and file paths are off limits. Log ids, counts and states. That rule is not
/// style: a clipboard-history app that writes clipboard contents to a log has
/// created a security problem.
class NotchLogger {
  /// One tag per class, created once as a field.
  final String tag;

  /// Per-instance mute, for subsystems that would otherwise be chatty.
  final bool enabled;

  /// Debug-only by default. Release builds stay quiet.
  static bool globalEnabled = kDebugMode;
  static bool useColors = true;
  static NotchLogWriter writer = _developerWriter;

  static const String _reset = '\x1B[0m';
  static const String _gray = '\x1B[90m';
  static const String _cyan = '\x1B[36m';
  static const String _red = '\x1B[31m';
  static const String _green = '\x1B[32m';
  static const String _beige = '\x1B[38;5;230m';

  NotchLogger({required this.tag, bool? enabled})
    : enabled = enabled ?? globalEnabled;

  factory NotchLogger.forTag(String tag) => NotchLogger(tag: tag);

  void debug(String message) => _log(NotchLogLevel.debug, message);

  void success(String message) => _log(NotchLogLevel.success, message);

  void error(String message, {Object? error, StackTrace? stackTrace}) {
    _log(NotchLogLevel.error, message);
    if (error != null) _log(NotchLogLevel.error, 'cause: $error');
    if (stackTrace != null) _log(NotchLogLevel.error, '$stackTrace');
  }

  void _log(NotchLogLevel level, String message) {
    if (!enabled || !globalEnabled) return;

    final time = _timestamp(DateTime.now());
    final name = '[${level.name.toUpperCase()}]';

    if (useColors) {
      writer(
        '$_gray$time$_reset ${_colorFor(level)}$name$_reset '
        '$_cyan[$tag]$_reset $message',
      );
    } else {
      writer('[$time] $name [$tag] $message');
    }
  }

  static void _developerWriter(String line) => dev.log(line);

  static String _timestamp(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';

  static String _colorFor(NotchLogLevel level) => switch (level) {
    NotchLogLevel.debug => _beige,
    NotchLogLevel.success => _green,
    NotchLogLevel.error => _red,
  };
}
```

- [ ] **Step 4: Delete the old logger and repoint its one consumer**

```bash
git rm lib/utils/helpers/app_logger.dart
rmdir lib/utils/helpers lib/utils 2>/dev/null || true
```

In `lib/core/network/interceptor/log_interceptor.dart`, change:
```dart
import 'package:notchpeek/utils/helpers/app_logger.dart';
```
to:
```dart
import 'package:notchpeek/core/logging/notch_logger.dart';
```

- [ ] **Step 5: Run the tests and the gate**

Run: `flutter test test/core/logging/notch_logger_test.dart && flutter analyze`
Expected: 4 tests PASS, `No issues found!`.

- [ ] **Step 6: Commit**

```bash
dart format .
git add -A lib test
git commit -m "refactor(logging): move NotchLogger to core/logging, three levels, testable writer"
```

---

### Task 3: Cut the network layer down to the one endpoint this app has

`ApiService` is shaped for a REST backend with a `{success, data, message}` envelope, multipart uploads and auth. NotchPeek has **one** endpoint — the iTunes artwork lookup — and no accounts. Everything else is dead weight that will be cargo-culted if it survives.

**Files:**
- Delete: `lib/core/network/errors/api_failure.dart`, `lib/core/network/errors/api_exceptions.dart`, `lib/core/network/interceptor/dio_interceptor.dart`
- Rewrite: `lib/core/services/api_service.dart`, `lib/core/network/endpoints/api_endpoints.dart`
- Modify: `lib/core/network/interceptor/log_interceptor.dart`, `lib/core/network/errors/api_error.dart`
- Test: `test/core/network/api_service_test.dart`

**Interfaces:**
- Consumes: `NotchLogger` (Task 2), `ApiResponse<T>` and `ApiErrorHandler` (already present).
- Produces:
  - `abstract final class ApiEndpoint` with `static const String itunesBaseUrl` and `static const String search`
  - `class ApiService` with `ApiService({required String baseUrl, Interceptor? logInterceptor})` and `Future<ApiResponse<Map<String, dynamic>>> get(String path, {Map<String, dynamic>? queryParameters})`
  - `final apiServiceProvider = Provider<ApiService>(...)`

- [ ] **Step 1: Delete what the playbook says is dead**

```bash
git rm lib/core/network/errors/api_failure.dart \
       lib/core/network/errors/api_exceptions.dart \
       lib/core/network/interceptor/dio_interceptor.dart
```

`api_failure.dart` and `api_exceptions.dart` are the `Failure`/`Either` model, explicitly out (playbook §5). `dio_interceptor.dart` injects a bearer token and routes a 401 to a login screen — **NotchPeek has no accounts, no tokens and no login screen**, so that logic has no meaning here and is deleted rather than ported.

- [ ] **Step 2: Write the failing test**

`test/core/network/api_service_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/core/network/endpoints/api_endpoints.dart';
import 'package:notchpeek/core/services/api_service.dart';

/// Answers every request from a canned map. Keeps the test off the network.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('a 200 with a JSON body comes back as a successful ApiResponse', () async {
    final service = ApiService(baseUrl: ApiEndpoint.itunesBaseUrl);
    service.debugAdapter = _StubAdapter(200, '{"resultCount":1,"results":[{"artworkUrl100":"https://x/a.jpg"}]}');

    final result = await service.get(ApiEndpoint.search, queryParameters: {'term': 'x'});

    expect(result.status, isTrue);
    expect(result.statusCode, 200);
    expect((result.data!['results'] as List), hasLength(1));
  });

  test('a transport failure comes back as an error ApiResponse, never a throw', () async {
    final service = ApiService(baseUrl: ApiEndpoint.itunesBaseUrl);
    service.debugAdapter = _StubAdapter(503, '');

    final result = await service.get(ApiEndpoint.search);

    expect(result.status, isFalse);
    expect(result.message, isNotEmpty);
  });

  test('the iTunes lookup path is a constant, not a literal', () {
    expect(ApiEndpoint.itunesBaseUrl, 'https://itunes.apple.com');
    expect(ApiEndpoint.search, '/search');
  });
}
```

Add `import 'dart:typed_data';` at the top for `Uint8List`.

- [ ] **Step 3: Run it and watch it fail**

Run: `flutter test test/core/network/api_service_test.dart`
Expected: FAIL — `ApiService` has no `debugAdapter`, and its constructor still demands an `ApiInterceptor`.

- [ ] **Step 4: Rewrite `api_endpoints.dart`**

```dart
/// Every URL in the app. There are two, because NotchPeek has no backend
/// (architecture-playbook §5). No URL literals at call sites.
abstract final class ApiEndpoint {
  /// iTunes Search API. Public, unauthenticated, rate-limited at ~20 calls
  /// per minute — which is far above anything a track change can produce.
  static const String itunesBaseUrl = 'https://itunes.apple.com';

  /// Artwork fallback, used only when neither player hands us an image.
  /// `?term=<artist album>&entity=album&limit=1`.
  static const String search = '/search';
}
```

- [ ] **Step 5: Rewrite `api_service.dart`**

```dart
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/core/network/endpoints/api_endpoints.dart';
import 'package:notchpeek/core/network/errors/api_error.dart';
import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/core/network/interceptor/log_interceptor.dart';

/// The only place a `Dio` instance exists (architecture-playbook §5).
///
/// This is not the app's spine. NotchPeek's data comes from the OS through
/// platform channels; HTTP is here for artwork lookup and nothing else. There
/// is no auth interceptor because there are no accounts.
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(
    baseUrl: ApiEndpoint.itunesBaseUrl,
    logInterceptor: kDebugMode ? ApiLogInterceptor() : null,
  );
});

class ApiService {
  ApiService({required String baseUrl, Interceptor? logInterceptor}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.json,
        headers: const {HttpHeaders.acceptHeader: 'application/json'},
      ),
    );
    if (logInterceptor != null) _dio.interceptors.add(logInterceptor);
  }

  late final Dio _dio;

  /// Test seam. Production code never assigns this.
  @visibleForTesting
  set debugAdapter(HttpClientAdapter adapter) => _dio.httpClientAdapter = adapter;

  /// The only verb this app needs. Add another when a second endpoint exists,
  /// not before.
  Future<ApiResponse<Map<String, dynamic>>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: queryParameters,
      );
      final body = response.data;
      if (body == null) {
        return ApiResponse.error(
          message: 'Empty response.',
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.success(message: 'OK', data: body);
    } on DioException catch (e) {
      return ApiErrorHandler.handleDioError<Map<String, dynamic>>(e);
    } catch (e) {
      return ApiErrorHandler.handleGenericError<Map<String, dynamic>>(e);
    }
  }
}
```

Note what is gone and why: `post`/`put`/`delete`/`multipart` (no endpoint uses them), `postRaw`/`getRaw` (they existed for another backend's inconsistent envelopes), and `_unwrap` (iTunes returns `{resultCount, results}` — there is no `success` field to unwrap).

- [ ] **Step 6: Strip the other project's leftovers from the log interceptor**

In `lib/core/network/interceptor/log_interceptor.dart`:
- Delete the two `Get_Presigned_Url` guards in `onRequest` and `onResponse` (and their commented-out siblings) — that filtered GraphQL presigned-URL traffic which does not exist in this app. The bodies become unconditional.
- Delete the commented-out `apiLogInterceptorProvider` block and the commented-out `_ApiConfiguration` fields.
- Delete the `authorization` / `x-api-key` / `x-device-id` / `x-fingerprint` header exclusions in `_cURLRepresentation` — none of those headers are ever sent. Keep the `cookie` exclusion.

- [ ] **Step 7: Fix the one auth-flavoured message left in `ApiErrorHandler`**

In `lib/core/network/errors/api_error.dart`, the `case 401:` returns `'Session expired. Please login again.'`. There is no session and no login. Replace the message with `'Not authorized.'` and leave the status code at 401.

- [ ] **Step 8: Run the tests and the gate**

Run: `flutter test && flutter analyze`
Expected: all tests PASS, `No issues found!`.

- [ ] **Step 9: Commit**

```bash
dart format .
git add -A lib test
git commit -m "refactor(network): delete Failure/Either and the auth interceptor, cut ApiService to the one endpoint"
```

---

### Task 4: Enums and design tokens

Every raw string that crosses a channel gets wrapped before it is passed around (playbook §8), and every number a widget draws with lives in `app/theme.dart` (playbook §9). Both are cheap now and expensive to retrofit across nine panels later.

**Files:**
- Create: `lib/shared/utils/enums/notch_state.dart`, `peek_kind.dart`, `panel_tab.dart`, `playback_state.dart`, `capability_state.dart`, `music_source_id.dart`, `media_command.dart`, `build_flavor.dart`
- Create: `lib/shared/utils/helpers/duration_format.dart`
- Create: `lib/app/theme.dart`
- Test: `test/shared/utils/enums_test.dart`, `test/shared/utils/duration_format_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces (every enum below exposes `fromApi(String)` returning a safe default, `apiValue`, and `label`):
  - `enum NotchState { collapsed, peeking, expanded }`
  - `enum PeekKind { trackChange, charger }`
  - `enum PanelTab { music, calendar, clipboard, shelf, timer, notes, webcam, game, ai }`
  - `enum PlaybackState { playing, paused, stopped, unknown }` with `bool get isPlaying`
  - `enum CapabilityState { granted, denied, notDetermined, absent }` with `bool get isReady`, `bool get isHidden`
  - `enum MusicSourceId { appleMusic, spotify, none }`
  - `enum MediaCommand { playPause, next, previous, seek }`
  - `enum BuildFlavor { direct, mas }`
  - `String formatClock(Duration d)` → `m:ss`, or `h:mm:ss` past an hour
  - `abstract final class NotchColors / NotchRadii / NotchMotion / NotchSizes`

- [ ] **Step 1: Write the failing tests**

`test/shared/utils/enums_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/shared/utils/enums/capability_state.dart';
import 'package:notchpeek/shared/utils/enums/playback_state.dart';

void main() {
  group('PlaybackState', () {
    test('maps the three strings Spotify and Music actually send', () {
      expect(PlaybackState.fromApi('playing'), PlaybackState.playing);
      expect(PlaybackState.fromApi('paused'), PlaybackState.paused);
      expect(PlaybackState.fromApi('stopped'), PlaybackState.stopped);
    });

    test('an unrecognised or empty string is unknown, never a throw', () {
      expect(PlaybackState.fromApi('kPSP'), PlaybackState.unknown);
      expect(PlaybackState.fromApi(''), PlaybackState.unknown);
    });

    test('isPlaying is true only while playing', () {
      expect(PlaybackState.playing.isPlaying, isTrue);
      expect(PlaybackState.paused.isPlaying, isFalse);
      expect(PlaybackState.unknown.isPlaying, isFalse);
    });
  });

  group('CapabilityState', () {
    test('round-trips through apiValue', () {
      for (final s in CapabilityState.values) {
        expect(CapabilityState.fromApi(s.apiValue), s);
      }
    });

    test('an unknown value is notDetermined, the safe default', () {
      expect(CapabilityState.fromApi('nonsense'), CapabilityState.notDetermined);
    });

    test('absent is the only state a panel hides for', () {
      expect(CapabilityState.absent.isHidden, isTrue);
      expect(CapabilityState.denied.isHidden, isFalse);
      expect(CapabilityState.granted.isReady, isTrue);
    });
  });
}
```

`test/shared/utils/duration_format_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/shared/utils/helpers/duration_format.dart';

void main() {
  test('pads seconds but not minutes', () {
    expect(formatClock(const Duration(seconds: 5)), '0:05');
    expect(formatClock(const Duration(minutes: 3, seconds: 7)), '3:07');
    expect(formatClock(const Duration(minutes: 12, seconds: 40)), '12:40');
  });

  test('grows an hours field only past an hour', () {
    expect(formatClock(const Duration(minutes: 59, seconds: 59)), '59:59');
    expect(formatClock(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });

  test('a negative duration clamps to zero rather than printing a minus sign', () {
    expect(formatClock(const Duration(seconds: -4)), '0:00');
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/shared/`
Expected: FAIL — the imported files do not exist.

- [ ] **Step 3: Write the enums**

`lib/shared/utils/enums/playback_state.dart`:

```dart
/// A raw string from a channel is never passed around unwrapped
/// (architecture-playbook §8).
enum PlaybackState {
  playing('playing', 'Playing'),
  paused('paused', 'Paused'),
  stopped('stopped', 'Stopped'),

  /// Also what a source that could not be read reports. The caller decides
  /// whether that means "nothing playing" or "unavailable" — see spec §7.
  unknown('unknown', 'Unknown');

  const PlaybackState(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static PlaybackState fromApi(String? value) {
    for (final s in PlaybackState.values) {
      if (s.apiValue == value) return s;
    }
    return PlaybackState.unknown;
  }

  bool get isPlaying => this == PlaybackState.playing;
}
```

`lib/shared/utils/enums/capability_state.dart`:

```dart
/// The three ways a panel can render, plus the one that hides it
/// (architecture-playbook §4.4).
enum CapabilityState {
  granted('granted', 'Ready'),
  denied('denied', 'Permission needed'),
  notDetermined('notDetermined', 'Not asked yet'),

  /// Not present in this build or on this OS. **Hidden, never teased.**
  absent('absent', 'Unavailable');

  const CapabilityState(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static CapabilityState fromApi(String? value) {
    for (final s in CapabilityState.values) {
      if (s.apiValue == value) return s;
    }
    return CapabilityState.notDetermined;
  }

  bool get isReady => this == CapabilityState.granted;
  bool get isHidden => this == CapabilityState.absent;
}
```

`lib/shared/utils/enums/notch_state.dart`:

```dart
enum NotchState {
  collapsed('collapsed', 'Collapsed'),
  peeking('peeking', 'Peeking'),
  expanded('expanded', 'Expanded');

  const NotchState(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static NotchState fromApi(String? value) {
    for (final s in NotchState.values) {
      if (s.apiValue == value) return s;
    }
    return NotchState.collapsed;
  }
}
```

`lib/shared/utils/enums/peek_kind.dart`:

```dart
/// The catalogue of events that trigger a peek grows per milestone. M1 ships
/// these two (spec §9).
enum PeekKind {
  trackChange('trackChange', 'Now playing'),
  charger('charger', 'Power');

  const PeekKind(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static PeekKind? fromApi(String? value) {
    for (final k in PeekKind.values) {
      if (k.apiValue == value) return k;
    }
    return null;
  }
}
```

`lib/shared/utils/enums/panel_tab.dart`:

```dart
/// Every panel NotchPeek will ever have. **M1 renders only [music]** — the
/// tab strip takes its tab list as a parameter from the start, so M2–M4 add
/// entries here without touching the strip (spec §5).
enum PanelTab {
  music('music', 'Music'),
  calendar('calendar', 'Calendar'),
  clipboard('clipboard', 'Clipboard'),
  shelf('shelf', 'Shelf'),
  timer('timer', 'Timer'),
  notes('notes', 'Notes'),
  webcam('webcam', 'Camera'),
  game('game', 'Game'),
  ai('ai', 'AI');

  const PanelTab(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static PanelTab fromApi(String? value) {
    for (final t in PanelTab.values) {
      if (t.apiValue == value) return t;
    }
    return PanelTab.music;
  }
}
```

`lib/shared/utils/enums/music_source_id.dart`:

```dart
enum MusicSourceId {
  appleMusic('appleMusic', 'Apple Music', 'com.apple.Music'),
  spotify('spotify', 'Spotify', 'com.spotify.client'),
  none('none', 'No player', '');

  const MusicSourceId(this.apiValue, this.label, this.bundleId);

  final String apiValue;
  final String label;
  final String bundleId;

  static MusicSourceId fromApi(String? value) {
    for (final s in MusicSourceId.values) {
      if (s.apiValue == value) return s;
    }
    return MusicSourceId.none;
  }
}
```

`lib/shared/utils/enums/media_command.dart`:

```dart
/// M1 sends these through scripting, not MediaRemote (spec §2, §9).
enum MediaCommand {
  playPause('playPause', 'Play or pause'),
  next('next', 'Next track'),
  previous('previous', 'Previous track'),
  seek('seek', 'Seek');

  const MediaCommand(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static MediaCommand? fromApi(String? value) {
    for (final c in MediaCommand.values) {
      if (c.apiValue == value) return c;
    }
    return null;
  }
}
```

`lib/shared/utils/enums/build_flavor.dart`:

```dart
/// Reported by `CapabilityProbe`. M1 only ever builds [direct]; the field
/// exists because the MAS build differs in what it may call (spike §4.3).
enum BuildFlavor {
  direct('direct', 'Direct download'),
  mas('mas', 'App Store');

  const BuildFlavor(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static BuildFlavor fromApi(String? value) {
    for (final f in BuildFlavor.values) {
      if (f.apiValue == value) return f;
    }
    return BuildFlavor.direct;
  }
}
```

- [ ] **Step 4: Write the duration helper**

`lib/shared/utils/helpers/duration_format.dart`:

```dart
/// `m:ss`, growing an hours field only when there is one. Used by the
/// scrubber and the track time labels.
String formatClock(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final ss = seconds.toString().padLeft(2, '0');

  if (hours == 0) return '$minutes:$ss';
  return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
}
```

- [ ] **Step 5: Write the design tokens**

`lib/app/theme.dart`:

```dart
import 'package:flutter/widgets.dart';

/// Opaque near-black. **No `NSVisualEffectView`** — real vibrancy behind an
/// animated non-rectangular panel needs an AppKit mask layer animating against
/// Flutter's clock, which is two clocks and a visible shimmer (spec §2).
abstract final class NotchColors {
  static const Color panel = Color(0xFF0A0A0A);
  static const Color panelEdge = Color(0xFF1C1C1E);
  static const Color primaryText = Color(0xFFF2F2F7);
  static const Color secondaryText = Color(0xFF8E8E93);
  static const Color accent = Color(0xFF0A84FF);
  static const Color positive = Color(0xFF30D158);
  static const Color warning = Color(0xFFFF9F0A);
  static const Color trackInactive = Color(0xFF3A3A3C);
}

abstract final class NotchRadii {
  /// The bottom corners of the expanded panel.
  static const double panelBottom = 22;

  /// The concave flare where the panel leaves the notch.
  static const double shoulder = 14;

  /// The collapsed silhouette's own bottom corners.
  static const double collapsedBottom = 10;
  static const double artwork = 8;
  static const double pill = 999;
}

/// Every number the morph animates with. **No magic numbers in widgets**
/// (architecture-playbook §9) — the morph timings especially.
abstract final class NotchMotion {
  static const Duration open = Duration(milliseconds: 350);
  static const Duration close = Duration(milliseconds: 250);
  static const Curve openCurve = Curves.easeOutQuint;
  static const Curve closeCurve = Curves.easeInQuint;

  /// Content arrives after the box does, so the panel reads as growing rather
  /// than as a cross-fade between two rectangles (spec §5.1).
  static const Duration contentFade = Duration(milliseconds: 180);
  static const Interval contentStagger = Interval(0.35, 1);

  /// How long an unattended peek stays out before retracting itself.
  static const Duration peekDwell = Duration(seconds: 4);
}

abstract final class NotchSizes {
  /// The fixed canvas height. The window is sized once to
  /// `screenWidth x canvasHeight` and never resized (spec §3.1).
  static const double canvasHeight = 420;

  static const double expandedWidth = 620;
  static const double expandedHeight = 220;
  static const double peekWidth = 260;
  static const double peekHeight = 44;

  /// The collapsed hot zone is the notch rect inflated by this much, so the
  /// cursor does not have to hit hardware exactly.
  static const double hotZoneInset = 6;

  static const double tabStripHeight = 34;
  static const double artworkSide = 96;
  static const double batteryPillWidth = 46;
}
```

- [ ] **Step 6: Run the tests and the gate**

Run: `flutter test test/shared/ && flutter analyze`
Expected: 6 tests PASS, `No issues found!`.

- [ ] **Step 7: Commit**

```bash
dart format .
git add -A lib test
git commit -m "feat(shared): add channel enums, duration helper and design tokens"
```

---

# Week 1 — The shell

R3 is blunt about this week: **week 1 is the week that decides the deadline.** If the panel is not passing clicks through and morphing by the end of it, the honest move is to say so then, not in week 3.

---

### Task 5: Native scaffolding — project registration, agent-app plist, entitlements

Nothing Swift can be added until the Xcode project will accept new files without a GUI, and `RunnerTests` currently cannot run at all: `TEST_HOST` still points at `notchpeek.app` while `AppInfo.xcconfig` builds `NotchPeek.app`.

**Files:**
- Create: `tool/add_xcode_file.sh`
- Create: `macos/Runner/Notch/Channels.swift`
- Modify: `macos/Runner/Info.plist`, `macos/Runner/DebugProfile.entitlements`, `macos/Runner/Release.entitlements`, `macos/Runner.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `tool/add_xcode_file.sh <path-relative-to-macos/> [target]` — every later native task uses this instead of touching `project.pbxproj` by hand.
  - `enum NotchChannel { static let control/media/system/calendar: String }`
  - `enum ControlMethod { static let setInteractiveRect/mediaCommand/openSettings/requestPermission/getCapabilities: String }`
  - A `RunnerTests` target that actually runs.

**Decision recorded by this task:** the direct-download build **turns the App Sandbox off**. Sandboxed Apple Events require a `com.apple.security.temporary-exception.apple-events` entry per target bundle id, which is a MAS-only construct; the direct build uses `com.apple.security.automation.apple-events` instead. This becomes R11 in `risks-and-decisions.md` in Task 27.

- [ ] **Step 1: Write the project-registration helper**

`tool/add_xcode_file.sh`:

```bash
#!/usr/bin/env bash
# Register a source file with an Xcode target without opening Xcode.
#
#   tool/add_xcode_file.sh Runner/Notch/MouseGate.swift Runner
#   tool/add_xcode_file.sh RunnerTests/MouseGateTests.swift RunnerTests
#
# Path is relative to macos/. Idempotent: re-running is a no-op.
set -euo pipefail

REL="${1:?usage: add_xcode_file.sh <path-relative-to-macos> [target]}"
TARGET="${2:-Runner}"

if [ ! -f "macos/$REL" ]; then
  echo "macos/$REL does not exist — create the file first" >&2
  exit 1
fi

ruby -r xcodeproj -e '
  rel, target_name = ARGV
  project = Xcodeproj::Project.open("macos/Runner.xcodeproj")
  target = project.targets.find { |t| t.name == target_name }
  abort "no target named #{target_name}" if target.nil?

  group = project.main_group
  File.dirname(rel).split("/").each do |segment|
    group = group[segment] || group.new_group(segment, segment)
  end

  name = File.basename(rel)
  ref = group.files.find { |f| f.path == name } || group.new_reference(name)
  target.add_file_references([ref]) unless target.source_build_phase.files_references.include?(ref)

  project.save
  puts "registered #{rel} with #{target_name}"
' "$REL" "$TARGET"
```

Then: `chmod +x tool/add_xcode_file.sh`

- [ ] **Step 2: Fix `TEST_HOST` so the test target can run**

```bash
ruby -r xcodeproj -e '
  project = Xcodeproj::Project.open("macos/Runner.xcodeproj")
  tests = project.targets.find { |t| t.name == "RunnerTests" }
  tests.build_configurations.each do |c|
    c.build_settings["TEST_HOST"] =
      "$(BUILT_PRODUCTS_DIR)/NotchPeek.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/NotchPeek"
  end
  project.save
'
git diff --stat macos/Runner.xcodeproj/project.pbxproj
```
Expected: three `TEST_HOST` lines changed from `notchpeek.app/.../notchpeek` to `NotchPeek.app/.../NotchPeek`.

- [ ] **Step 3: Make it an agent app and declare the Apple Events consent copy**

In `macos/Runner/Info.plist`, add inside the top-level `<dict>`:

```xml
	<key>LSUIElement</key>
	<true/>
	<key>NSAppleEventsUsageDescription</key>
	<string>NotchPeek reads what Apple Music and Spotify are playing so it can show the track and control playback from the notch.</string>
```

`LSUIElement = true` makes this an agent app: no Dock icon, no menu bar of its own (spec §3.1).

- [ ] **Step 4: Set the entitlements for a direct build**

Replace the `<dict>` body of `macos/Runner/DebugProfile.entitlements`:

```xml
	<key>com.apple.security.automation.apple-events</key>
	<true/>
	<key>com.apple.security.cs.allow-jit</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.network.server</key>
	<true/>
```

And `macos/Runner/Release.entitlements`:

```xml
	<key>com.apple.security.automation.apple-events</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
```

`com.apple.security.app-sandbox` is removed from both — see the decision above. `network.server` stays in Debug only; the Flutter debug connection needs it.

- [ ] **Step 5: Write the channel-name constants**

`macos/Runner/Notch/Channels.swift`:

```swift
import Foundation

/// Channel names live in exactly one Swift file and one Dart file
/// (`lib/core/platform/channels.dart`). Never a string literal at a call site.
///
/// Later milestones **extend** this set. They do not redesign it: one method
/// channel for all commands, one event channel per data domain.
enum NotchChannel {
    static let control = "notchpeek/control"
    static let media = "notchpeek/media"
    static let system = "notchpeek/system"
    /// Reserved for M2. Declared now so the set is fixed in M1.
    static let calendar = "notchpeek/calendar"
}

/// Every method Dart may invoke on `NotchChannel.control`.
enum ControlMethod {
    static let setInteractiveRect = "setInteractiveRect"
    static let mediaCommand = "mediaCommand"
    static let openSettings = "openSettings"
    static let requestPermission = "requestPermission"
    static let getCapabilities = "getCapabilities"
}

/// Every event kind that crosses `NotchChannel.system`.
enum SystemEvent {
    static let geometry = "geometry"
    static let power = "power"
    static let capabilities = "capabilities"
}
```

- [ ] **Step 6: Register it and prove the build and the test target both work**

```bash
tool/add_xcode_file.sh Runner/Notch/Channels.swift Runner
flutter build macos --debug
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -destination 'platform=macOS' -quiet
```
Expected: the Flutter build succeeds; `xcodebuild test` reports `TEST SUCCEEDED` running the template's `testExample`. If `xcodebuild` cannot find generated inputs, run `flutter build macos --debug` again first — it writes `macos/Flutter/ephemeral/Flutter-Generated.xcconfig`.

- [ ] **Step 7: Commit**

```bash
git add tool macos
git commit -m "chore(macos): add xcode file helper, fix TEST_HOST, agent-app plist, direct-build entitlements"
```

---

### Task 6: `NotchGeometry` — derive the notch rect, and synthesize one when there isn't a notch

The app must work on every Mac. On notched hardware it happens to hide inside real hardware; everywhere else it synthesizes a notch and runs identically (spec §2, §3.3).

**Files:**
- Create: `macos/Runner/Notch/NotchGeometry.swift`
- Test: `macos/RunnerTests/NotchGeometryTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct NotchMetrics: Equatable` with `screenWidth`, `screenHeight`, `notchWidth`, `notchHeight`, `notchLeft`, `scale`, `isVirtual` (all `CGFloat` except `isVirtual: Bool`), and `var channelMap: [String: Any]`
  - `enum NotchGeometry` with `static func derive(screenFrame:auxLeft:auxRight:safeAreaTop:scale:) -> NotchMetrics` (pure) and `static func metrics(for screen: NSScreen) -> NotchMetrics`
  - `final class NotchGeometryObserver` with `init(onChange: @escaping (NotchMetrics) -> Void)`, `func start()`, `func stop()`, `var current: NotchMetrics?`

- [ ] **Step 1: Write the failing test**

`macos/RunnerTests/NotchGeometryTests.swift`:

```swift
import XCTest
@testable import NotchPeek

final class NotchGeometryTests: XCTestCase {

    /// MacBook Air M2 at its default scaled resolution, the dev machine.
    func testDerivesTheNotchFromTheGapBetweenTheAuxiliaryAreas() {
        let metrics = NotchGeometry.derive(
            screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            auxLeft: CGRect(x: 0, y: 924, width: 585, height: 32),
            auxRight: CGRect(x: 885, y: 924, width: 585, height: 32),
            safeAreaTop: 32,
            scale: 2
        )

        XCTAssertFalse(metrics.isVirtual)
        XCTAssertEqual(metrics.notchLeft, 585)
        XCTAssertEqual(metrics.notchWidth, 300)
        XCTAssertEqual(metrics.notchHeight, 32)
        XCTAssertEqual(metrics.screenWidth, 1470)
    }

    func testOffsetsTheNotchByTheScreenOriginOnASecondDisplay() {
        let metrics = NotchGeometry.derive(
            screenFrame: CGRect(x: 1470, y: 0, width: 1000, height: 800),
            auxLeft: CGRect(x: 1470, y: 768, width: 400, height: 32),
            auxRight: CGRect(x: 2070, y: 768, width: 400, height: 32),
            safeAreaTop: 32,
            scale: 2
        )

        // notchLeft is relative to the screen, not to the global origin.
        XCTAssertEqual(metrics.notchLeft, 400)
        XCTAssertEqual(metrics.notchWidth, 200)
    }

    func testSynthesizesACentredVirtualNotchWhenThereIsNoSafeArea() {
        let metrics = NotchGeometry.derive(
            screenFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            auxLeft: nil,
            auxRight: nil,
            safeAreaTop: 0,
            scale: 2
        )

        XCTAssertTrue(metrics.isVirtual)
        XCTAssertEqual(metrics.notchWidth, 200)
        XCTAssertEqual(metrics.notchHeight, 32)
        XCTAssertEqual(metrics.notchLeft, 1180) // (2560 - 200) / 2
    }

    func testFallsBackToTheVirtualNotchWhenTheAuxiliaryAreasDoNotLeaveAGap() {
        // Seen when a display reports a safe area but no auxiliary split.
        let metrics = NotchGeometry.derive(
            screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            auxLeft: CGRect(x: 0, y: 924, width: 800, height: 32),
            auxRight: CGRect(x: 700, y: 924, width: 770, height: 32),
            safeAreaTop: 32,
            scale: 2
        )

        XCTAssertTrue(metrics.isVirtual)
        XCTAssertEqual(metrics.notchWidth, 200)
    }

    func testChannelMapCarriesEveryFieldDartReads() {
        let metrics = NotchGeometry.derive(
            screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            auxLeft: CGRect(x: 0, y: 924, width: 585, height: 32),
            auxRight: CGRect(x: 885, y: 924, width: 585, height: 32),
            safeAreaTop: 32,
            scale: 2
        )

        let map = metrics.channelMap
        XCTAssertEqual(map["screenWidth"] as? CGFloat, 1470)
        XCTAssertEqual(map["screenHeight"] as? CGFloat, 956)
        XCTAssertEqual(map["notchWidth"] as? CGFloat, 300)
        XCTAssertEqual(map["notchHeight"] as? CGFloat, 32)
        XCTAssertEqual(map["notchLeft"] as? CGFloat, 585)
        XCTAssertEqual(map["scale"] as? CGFloat, 2)
        XCTAssertEqual(map["isVirtual"] as? Bool, false)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
tool/add_xcode_file.sh RunnerTests/NotchGeometryTests.swift RunnerTests
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -destination 'platform=macOS' -quiet
```
Expected: FAIL — `cannot find 'NotchGeometry' in scope`.

- [ ] **Step 3: Write the module**

`macos/Runner/Notch/NotchGeometry.swift`:

```swift
import AppKit

/// Everything Dart needs to lay out the panel, in points, in the screen's own
/// coordinate space. Normalized here so Dart sees exactly one shape
/// (architecture-playbook §4.2).
struct NotchMetrics: Equatable {
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    /// Distance from the screen's left edge to the notch's left edge.
    let notchLeft: CGFloat
    let scale: CGFloat
    /// True when this machine has no hardware notch and we synthesized one.
    let isVirtual: Bool

    var channelMap: [String: Any] {
        [
            "screenWidth": screenWidth,
            "screenHeight": screenHeight,
            "notchWidth": notchWidth,
            "notchHeight": notchHeight,
            "notchLeft": notchLeft,
            "scale": scale,
            "isVirtual": isVirtual,
        ]
    }
}

/// Resolves the notch rect, synthesizes one on machines without hardware, and
/// watches for the two events that invalidate it.
enum NotchGeometry {

    /// The synthetic notch used on every Mac without one. Chosen to match the
    /// proportions of the real thing so the shell behaves identically (spec §2).
    static let virtualNotchWidth: CGFloat = 200
    static let virtualNotchHeight: CGFloat = 32

    /// Pure, and therefore the part that is unit-tested. `auxLeft` and
    /// `auxRight` are `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`,
    /// which are nil on hardware without a notch.
    static func derive(
        screenFrame: CGRect,
        auxLeft: CGRect?,
        auxRight: CGRect?,
        safeAreaTop: CGFloat,
        scale: CGFloat
    ) -> NotchMetrics {
        let width = screenFrame.width
        let height = screenFrame.height

        if safeAreaTop > 0, let left = auxLeft, let right = auxRight {
            let gap = right.minX - left.maxX
            if gap > 0 {
                return NotchMetrics(
                    screenWidth: width,
                    screenHeight: height,
                    notchWidth: gap,
                    notchHeight: safeAreaTop,
                    notchLeft: left.maxX - screenFrame.minX,
                    scale: scale,
                    isVirtual: false
                )
            }
        }

        return NotchMetrics(
            screenWidth: width,
            screenHeight: height,
            notchWidth: virtualNotchWidth,
            notchHeight: virtualNotchHeight,
            notchLeft: (width - virtualNotchWidth) / 2,
            scale: scale,
            isVirtual: true
        )
    }

    static func metrics(for screen: NSScreen) -> NotchMetrics {
        derive(
            screenFrame: screen.frame,
            auxLeft: screen.auxiliaryTopLeftArea,
            auxRight: screen.auxiliaryTopRightArea,
            safeAreaTop: screen.safeAreaInsets.top,
            scale: screen.backingScaleFactor
        )
    }

    /// The screen the panel lives on: the one with a notch if any has one,
    /// otherwise the main screen.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }
}

/// Recomputes geometry when the display arrangement changes or the user
/// switches Space, and reports only actual changes.
final class NotchGeometryObserver {
    private let onChange: (NotchMetrics) -> Void
    private var tokens: [NSObjectProtocol] = []
    private(set) var current: NotchMetrics?

    init(onChange: @escaping (NotchMetrics) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard tokens.isEmpty else { return }

        tokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.recompute() }
        )

        tokens.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.recompute() }
        )

        recompute()
    }

    func stop() {
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens.removeAll()
    }

    func recompute() {
        guard let screen = NotchGeometry.preferredScreen() else { return }
        let metrics = NotchGeometry.metrics(for: screen)
        guard metrics != current else { return }
        current = metrics
        onChange(metrics)
    }

    deinit { stop() }
}
```

- [ ] **Step 4: Register and run the tests**

```bash
tool/add_xcode_file.sh Runner/Notch/NotchGeometry.swift Runner
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -destination 'platform=macOS' -quiet
```
Expected: 5 new tests PASS.

- [ ] **Step 5: Commit**

```bash
git add macos
git commit -m "feat(shell): derive the notch rect, synthesize a virtual notch, observe screen changes"
```

---

### Task 7: The channel set — one method channel, three event channels

The set is fixed here and extended by later milestones rather than redesigned (spec §3.5). Dart's half is a typed wrapper; nothing above `ChannelService` ever names a channel.

**Files:**
- Create: `macos/Runner/Notch/ChannelBridge.swift`
- Create: `lib/core/platform/channels.dart`, `lib/core/platform/channel_service.dart`, `lib/core/platform/resilient_stream.dart`
- Modify: `macos/Runner/AppDelegate.swift`
- Test: `test/core/platform/channel_service_test.dart`, `test/core/platform/resilient_stream_test.dart`

**Interfaces:**
- Consumes: `NotchChannel`/`ControlMethod`/`SystemEvent` (Task 5), `NotchMetrics`/`NotchGeometryObserver` (Task 6), `NotchLogger` (Task 2), `ApiResponse` (Task 3).
- Produces:
  - Dart `abstract final class Channels { static const control/media/system/calendar }`, `abstract final class ControlMethod { … }`, `abstract final class SystemEventKind { static const geometry/power/capabilities }`
  - `class ChannelService` with `Future<ApiResponse<T>> invoke<T>(String method, [Map<String, Object?>? args])`, `Stream<Map<String, Object?>> get systemEvents`, `Stream<Map<String, Object?>> get mediaEvents`
  - `final channelServiceProvider = Provider<ChannelService>(...)`
  - `Stream<T> resilientStream<T>({required Stream<T> Function() open, List<Duration> backoff, Future<void> Function(Duration) sleep, NotchLogger? logger})`
  - Swift `final class ChannelBridge` with `init(messenger: FlutterBinaryMessenger)`, `func start()`, `func sendSystem(_ kind: String, _ payload: [String: Any])`, `func sendMedia(_ payload: [String: Any])`, and settable handlers `onSetInteractiveRect: ((CGRect) -> Void)?`, `onMediaCommand: (([String: Any]) -> Void)?`, `onOpenSettings: (() -> Void)?`, `onGetCapabilities: (() -> [String: Any])?`

- [ ] **Step 1: Write the failing Dart tests**

`test/core/platform/resilient_stream_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/core/platform/resilient_stream.dart';

void main() {
  test('passes values straight through while the source is healthy', () async {
    final stream = resilientStream<int>(
      open: () => Stream.fromIterable([1, 2, 3]),
      sleep: (_) async {},
    );

    expect(await stream.take(3).toList(), [1, 2, 3]);
  });

  test('reopens the source after it errors, and keeps delivering', () async {
    var opens = 0;
    final stream = resilientStream<int>(
      open: () {
        opens++;
        if (opens == 1) return Stream<int>.error(StateError('channel died'));
        return Stream.fromIterable([7]);
      },
      sleep: (_) async {},
    );

    expect(await stream.first, 7);
    expect(opens, 2);
  });

  test('backs off further on each consecutive failure, then holds at the last step', () async {
    final waited = <Duration>[];
    var opens = 0;

    final stream = resilientStream<int>(
      open: () {
        opens++;
        if (opens <= 4) return Stream<int>.error(StateError('down'));
        return Stream.fromIterable([1]);
      },
      backoff: const [Duration(seconds: 1), Duration(seconds: 2)],
      sleep: (d) async => waited.add(d),
    );

    await stream.first;
    expect(waited, const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 2),
      Duration(seconds: 2),
    ]);
  });

  test('a clean close of the source is also treated as a reconnect', () async {
    var opens = 0;
    final stream = resilientStream<int>(
      open: () {
        opens++;
        return opens == 1 ? const Stream<int>.empty() : Stream.fromIterable([9]);
      },
      sleep: (_) async {},
    );

    expect(await stream.first, 9);
  });
}
```

`test/core/platform/channel_service_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/core/platform/channel_service.dart';
import 'package:notchpeek/core/platform/channels.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final control = const MethodChannel(Channels.control);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(control, null));

  test('a successful invoke returns a successful ApiResponse carrying the value', () async {
    late MethodCall seen;
    messenger.setMockMethodCallHandler(control, (call) async {
      seen = call;
      return true;
    });

    final result = await ChannelService().invoke<bool>(
      ControlMethod.setInteractiveRect,
      const {'x': 1.0, 'y': 2.0, 'width': 3.0, 'height': 4.0},
    );

    expect(result.status, isTrue);
    expect(result.data, isTrue);
    expect(seen.method, ControlMethod.setInteractiveRect);
    expect(seen.arguments, const {'x': 1.0, 'y': 2.0, 'width': 3.0, 'height': 4.0});
  });

  test('a PlatformException becomes an error ApiResponse, never a throw', () async {
    messenger.setMockMethodCallHandler(control, (call) async {
      throw PlatformException(code: 'unavailable', message: 'no bridge');
    });

    final result = await ChannelService().invoke<bool>(ControlMethod.openSettings);

    expect(result.status, isFalse);
    expect(result.message, contains('no bridge'));
  });

  test('a method the native side does not implement is an error, not a crash', () async {
    messenger.setMockMethodCallHandler(control, (call) async => null);

    final result = await ChannelService().invoke<bool>(ControlMethod.getCapabilities);

    expect(result.status, isFalse);
  });

  test('channel names are constants and match the Swift side exactly', () {
    expect(Channels.control, 'notchpeek/control');
    expect(Channels.media, 'notchpeek/media');
    expect(Channels.system, 'notchpeek/system');
    expect(Channels.calendar, 'notchpeek/calendar');
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/core/platform/`
Expected: FAIL — neither `channels.dart` nor `channel_service.dart` exists.

- [ ] **Step 3: Write `channels.dart`**

```dart
/// Channel names live in exactly one Dart file and one Swift file
/// (`macos/Runner/Notch/Channels.swift`). Never a string literal at a call
/// site (architecture-playbook §4.1).
abstract final class Channels {
  static const String control = 'notchpeek/control';
  static const String media = 'notchpeek/media';
  static const String system = 'notchpeek/system';

  /// Reserved for M2. Declared now so the set is fixed in M1.
  static const String calendar = 'notchpeek/calendar';
}

abstract final class ControlMethod {
  static const String setInteractiveRect = 'setInteractiveRect';
  static const String mediaCommand = 'mediaCommand';
  static const String openSettings = 'openSettings';
  static const String requestPermission = 'requestPermission';
  static const String getCapabilities = 'getCapabilities';
}

/// Discriminator on every payload that crosses [Channels.system].
abstract final class SystemEventKind {
  static const String key = 'kind';
  static const String geometry = 'geometry';
  static const String power = 'power';
  static const String capabilities = 'capabilities';
}
```

- [ ] **Step 4: Write `resilient_stream.dart`**

```dart
import 'package:notchpeek/core/logging/notch_logger.dart';

/// Default reconnect schedule. Holds at 8 s rather than growing without bound:
/// a dead `EventChannel` usually means the native side is restarting, and the
/// user is looking at the panel while it happens.
const List<Duration> kDefaultBackoff = [
  Duration(milliseconds: 250),
  Duration(milliseconds: 500),
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
];

/// Wraps a stream factory so an `EventChannel` that dies is reopened rather
/// than terminating the provider that listens to it (spec §7).
///
/// A clean close is treated the same as an error: the native side is the only
/// thing that ends these streams, and it only does so when it goes away.
Stream<T> resilientStream<T>({
  required Stream<T> Function() open,
  List<Duration> backoff = kDefaultBackoff,
  Future<void> Function(Duration) sleep = Future<void>.delayed,
  NotchLogger? logger,
}) async* {
  var attempt = 0;

  while (true) {
    try {
      await for (final value in open()) {
        attempt = 0;
        yield value;
      }
      logger?.debug('stream closed cleanly; reopening');
    } catch (e, s) {
      logger?.error('stream failed; reopening', error: e, stackTrace: s);
    }

    final wait = backoff[attempt < backoff.length ? attempt : backoff.length - 1];
    attempt++;
    await sleep(wait);
  }
}
```

- [ ] **Step 5: Write `channel_service.dart`**

```dart
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/core/logging/notch_logger.dart';
import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/core/platform/channels.dart';
import 'package:notchpeek/core/platform/resilient_stream.dart';

final channelServiceProvider = Provider<ChannelService>((ref) => ChannelService());

/// The only place in Dart that touches a platform channel
/// (architecture-playbook §3). Datasources call this; nothing above them does.
///
/// The naming wart is accepted: channel results come back in `ApiResponse<T>`,
/// where "Api" reads oddly. One wrapper at every boundary is worth more than
/// the rename (architecture-playbook §5).
class ChannelService {
  ChannelService({
    MethodChannel? control,
    EventChannel? media,
    EventChannel? system,
  }) : _control = control ?? const MethodChannel(Channels.control),
       _media = media ?? const EventChannel(Channels.media),
       _system = system ?? const EventChannel(Channels.system);

  final MethodChannel _control;
  final EventChannel _media;
  final EventChannel _system;

  final NotchLogger _log = NotchLogger.forTag('ChannelService');

  Future<ApiResponse<T>> invoke<T>(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    try {
      final value = await _control.invokeMethod<T>(method, args);
      if (value == null) {
        _log.error('$method returned null');
        return ApiResponse.error(message: '$method is not available.');
      }
      _log.success(method);
      return ApiResponse.success(message: 'OK', data: value);
    } on PlatformException catch (e, s) {
      _log.error('$method failed', error: e, stackTrace: s);
      return ApiResponse.error(message: e.message ?? 'Platform call failed.');
    } on MissingPluginException catch (e, s) {
      _log.error('$method has no handler', error: e, stackTrace: s);
      return ApiResponse.error(message: '$method is not implemented.');
    }
  }

  Stream<Map<String, Object?>> get systemEvents => _events(_system, 'system');

  Stream<Map<String, Object?>> get mediaEvents => _events(_media, 'media');

  Stream<Map<String, Object?>> _events(EventChannel channel, String tag) {
    return resilientStream<Map<String, Object?>>(
      open: () => channel.receiveBroadcastStream().map(
        (event) => Map<String, Object?>.from(event as Map),
      ),
      logger: NotchLogger.forTag('ChannelService.$tag'),
    );
  }
}
```

- [ ] **Step 6: Run the Dart tests**

Run: `flutter test test/core/platform/ && flutter analyze`
Expected: 8 tests PASS, `No issues found!`.

- [ ] **Step 7: Write the Swift half**

`macos/Runner/Notch/ChannelBridge.swift`:

```swift
import FlutterMacOS
import Foundation

/// Wires one method channel and three event channels to the modules that own
/// the OS. It holds no state and makes no decisions — it is a switchboard.
final class ChannelBridge: NSObject {

    private let control: FlutterMethodChannel
    private let media: FlutterEventChannel
    private let system: FlutterEventChannel

    private let mediaSink = EventSinkBox()
    private let systemSink = EventSinkBox()

    // Set by AppDelegate once the modules exist.
    var onSetInteractiveRect: ((CGRect) -> Void)?
    var onMediaCommand: (([String: Any]) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onRequestPermission: ((String) -> Void)?
    var onGetCapabilities: (() -> [String: Any])?
    /// Called when Dart attaches to or detaches from the media stream, so
    /// polling can stop the moment nobody is listening.
    var onMediaListenChanged: ((Bool) -> Void)?

    init(messenger: FlutterBinaryMessenger) {
        control = FlutterMethodChannel(name: NotchChannel.control, binaryMessenger: messenger)
        media = FlutterEventChannel(name: NotchChannel.media, binaryMessenger: messenger)
        system = FlutterEventChannel(name: NotchChannel.system, binaryMessenger: messenger)
        super.init()
    }

    func start() {
        control.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result)
        }
        mediaSink.onListenChanged = { [weak self] active in
            self?.onMediaListenChanged?(active)
        }
        media.setStreamHandler(mediaSink)
        system.setStreamHandler(systemSink)
    }

    /// Every send hops to the main thread: `FlutterEventSink` is not thread-safe.
    func sendSystem(_ kind: String, _ payload: [String: Any]) {
        var message = payload
        message["kind"] = kind
        systemSink.send(message)
    }

    func sendMedia(_ payload: [String: Any]) {
        mediaSink.send(payload)
    }

    private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        switch call.method {
        case ControlMethod.setInteractiveRect:
            guard let a = call.arguments as? [String: Any],
                  let x = a["x"] as? Double, let y = a["y"] as? Double,
                  let w = a["width"] as? Double, let h = a["height"] as? Double
            else {
                result(FlutterError(code: "badArgs", message: "expected x, y, width, height", details: nil))
                return
            }
            onSetInteractiveRect?(CGRect(x: x, y: y, width: w, height: h))
            result(true)

        case ControlMethod.mediaCommand:
            guard let a = call.arguments as? [String: Any] else {
                result(FlutterError(code: "badArgs", message: "expected a command map", details: nil))
                return
            }
            onMediaCommand?(a)
            result(true)

        case ControlMethod.openSettings:
            onOpenSettings?()
            result(true)

        case ControlMethod.requestPermission:
            let what = (call.arguments as? [String: Any])?["what"] as? String ?? ""
            onRequestPermission?(what)
            result(true)

        case ControlMethod.getCapabilities:
            result(onGetCapabilities?() ?? [:])

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

/// Holds a `FlutterEventSink` across listen/cancel and marshals every send to
/// the main thread.
final class EventSinkBox: NSObject, FlutterStreamHandler {
    private var sink: FlutterEventSink?
    var onListenChanged: ((Bool) -> Void)?

    var isListening: Bool { sink != nil }

    func send(_ payload: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.sink?(payload)
        }
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        onListenChanged?(true)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        onListenChanged?(false)
        return nil
    }
}
```

- [ ] **Step 8: Hold the bridge from `AppDelegate` and push geometry through it**

Replace `macos/Runner/AppDelegate.swift` with:

```swift
import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {

    /// Strong references: nothing else owns these.
    var bridge: ChannelBridge?
    var geometryObserver: NotchGeometryObserver?

    /// An agent app has no windows to close. Quitting is the settings window's
    /// job, not the last window's.
    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    /// Called by `MainFlutterWindow` once the engine exists.
    func attach(messenger: FlutterBinaryMessenger) {
        let bridge = ChannelBridge(messenger: messenger)
        bridge.start()
        self.bridge = bridge

        let observer = NotchGeometryObserver { [weak bridge] metrics in
            bridge?.sendSystem(SystemEvent.geometry, metrics.channelMap)
        }
        observer.start()
        self.geometryObserver = observer
    }
}
```

And in `macos/Runner/MainFlutterWindow.swift`, after `RegisterGeneratedPlugins(registry: flutterViewController)`, add:

```swift
    (NSApp.delegate as? AppDelegate)?.attach(messenger: flutterViewController.engine.binaryMessenger)
```

- [ ] **Step 9: Register, build and verify the round trip by hand**

```bash
tool/add_xcode_file.sh Runner/Notch/ChannelBridge.swift Runner
flutter build macos --debug
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -destination 'platform=macOS' -quiet
```
Expected: build succeeds, existing Swift tests still pass, no new warnings.

- [ ] **Step 10: Commit**

```bash
dart format .
git add -A lib test macos
git commit -m "feat(platform): wire the channel set and add a reconnecting event stream"
```

---

### Task 8: Geometry in Dart, and a bootstrap that never flashes a misplaced panel

"Launched before geometry resolved → render nothing" (spec §7) is the whole reason this task exists before any widget does.

**Files:**
- Create: `lib/features/shell/domain/entities/notch_geometry.dart`, `lib/features/shell/domain/repositories/shell_repository.dart`, `lib/features/shell/domain/usecases/watch_geometry.dart`, `lib/features/shell/domain/usecases/report_interactive_rect.dart`
- Create: `lib/features/shell/data/models/notch_geometry_model.dart`, `lib/features/shell/data/datasources/shell_datasource.dart`, `lib/features/shell/data/repositories/shell_repository_impl.dart`
- Create: `lib/features/shell/presentation/shell_providers.dart`
- Rewrite: `lib/main.dart`; Create: `lib/app/notch_app.dart`
- Delete: `test/widget_test.dart`
- Test: `test/features/shell/notch_geometry_test.dart`, `test/features/shell/shell_repository_test.dart`

**Interfaces:**
- Consumes: `ChannelService` (Task 7), `SystemEventKind` (Task 7), `NotchSizes` (Task 4), `NotchState` (Task 4).
- Produces:
  - `class NotchGeometry extends Equatable` — fields `screenWidth`, `screenHeight`, `notchWidth`, `notchHeight`, `notchLeft`, `scale` (`double`), `isVirtual` (`bool`); getters `Rect get notchRect`, `double get centerX`; methods `Rect hotZone({double inset})`, `Rect centeredRect(Size size)`, `Rect interactiveRect(NotchState state)`
  - `abstract class ShellRepository { Stream<NotchGeometry> watchGeometry(); Future<ApiResponse<bool>> setInteractiveRect(Rect rect); }`
  - `class WatchGeometry { Stream<NotchGeometry> call(); }`, `class ReportInteractiveRect { Future<ApiResponse<bool>> call(Rect rect); }`
  - `NotchGeometryModel.toEntity(Map<String, Object?>) → NotchGeometry`
  - providers: `shellDataSourceProvider`, `shellRepositoryProvider`, `watchGeometryProvider`, `reportInteractiveRectProvider`, `geometryProvider` (`StreamProvider<NotchGeometry>`)

- [ ] **Step 1: Write the failing tests**

`test/features/shell/notch_geometry_test.dart`:

```dart
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
);

void main() {
  test('the notch rect sits at the top of the canvas', () {
    expect(_devMachine.notchRect, const Rect.fromLTWH(585, 0, 300, 32));
    expect(_devMachine.centerX, 735);
  });

  test('the hot zone inflates sideways and downwards but never above the screen', () {
    final zone = _devMachine.hotZone(inset: 6);

    expect(zone.top, 0);
    expect(zone.left, 579);
    expect(zone.right, 891);
    expect(zone.bottom, 38);
  });

  test('a centred rect is centred on the notch, not on the screen', () {
    final rect = _devMachine.centeredRect(const Size(620, 220));

    expect(rect.center.dx, 735);
    expect(rect.top, 0);
    expect(rect.width, 620);
    expect(rect.height, 220);
  });

  test('a centred rect is pushed back on screen when the notch is near an edge', () {
    const offCentre = NotchGeometry(
      screenWidth: 800, screenHeight: 600, notchWidth: 200, notchHeight: 32,
      notchLeft: 40, scale: 2, isVirtual: true,
    );

    final rect = offCentre.centeredRect(const Size(620, 220));

    expect(rect.left, 0);
    expect(rect.right, 620);
  });

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

  test('parses the channel map, defaulting rather than throwing on a bad payload', () {
    final parsed = NotchGeometryModel.toEntity(const {
      'screenWidth': 1470.0, 'screenHeight': 956.0,
      'notchWidth': 300.0, 'notchHeight': 32.0, 'notchLeft': 585.0,
      'scale': 2.0, 'isVirtual': false,
    });
    expect(parsed, _devMachine);

    final degenerate = NotchGeometryModel.toEntity(const {});
    expect(degenerate.isVirtual, isTrue);
    expect(degenerate.notchWidth, greaterThan(0));
  });
}
```

`test/features/shell/shell_repository_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/core/platform/channels.dart';
import 'package:notchpeek/features/shell/data/datasources/shell_datasource.dart';
import 'package:notchpeek/features/shell/data/repositories/shell_repository_impl.dart';

class _FakeShellDataSource implements ShellDataSource {
  _FakeShellDataSource(this.events);

  final Stream<Map<String, Object?>> events;
  final List<Rect> reported = [];

  @override
  Stream<Map<String, Object?>> watchGeometryEvents() => events;

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
          'screenWidth': 1470.0, 'screenHeight': 956.0, 'notchWidth': 300.0,
          'notchHeight': 32.0, 'notchLeft': 585.0, 'scale': 2.0, 'isVirtual': false,
        },
        const {
          'screenWidth': 2560.0, 'screenHeight': 1440.0, 'notchWidth': 200.0,
          'notchHeight': 32.0, 'notchLeft': 1180.0, 'scale': 2.0, 'isVirtual': true,
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

    final result = await ShellRepositoryImpl(source)
        .setInteractiveRect(const Rect.fromLTWH(1, 2, 3, 4));

    expect(result.status, isTrue);
    expect(source.reported.single, const Rect.fromLTWH(1, 2, 3, 4));
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
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/features/shell/`
Expected: FAIL — none of the imported files exist.

- [ ] **Step 3: Write the entity**

`lib/features/shell/domain/entities/notch_geometry.dart`:

```dart
import 'dart:math' as math;
import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/shared/utils/enums/notch_state.dart';

/// The fixed geometry the panel is laid out against. All values are logical
/// points in the canvas's own space: the canvas is the full screen width and
/// [NotchSizes.canvasHeight] tall, pinned to the top of the screen, so `y = 0`
/// is the top of the display.
class NotchGeometry extends Equatable {
  const NotchGeometry({
    required this.screenWidth,
    required this.screenHeight,
    required this.notchWidth,
    required this.notchHeight,
    required this.notchLeft,
    required this.scale,
    required this.isVirtual,
  });

  final double screenWidth;
  final double screenHeight;
  final double notchWidth;
  final double notchHeight;
  final double notchLeft;
  final double scale;

  /// True when this machine has no hardware notch and Swift synthesized one.
  final bool isVirtual;

  Rect get notchRect => Rect.fromLTWH(notchLeft, 0, notchWidth, notchHeight);

  double get centerX => notchLeft + notchWidth / 2;

  /// The notch rect, inflated so the cursor does not have to hit hardware
  /// exactly. Never inflated above the top of the screen — there is nothing up
  /// there to hover.
  Rect hotZone({double inset = NotchSizes.hotZoneInset}) => Rect.fromLTRB(
    math.max(0, notchLeft - inset),
    0,
    math.min(screenWidth, notchLeft + notchWidth + inset),
    notchHeight + inset,
  );

  /// A rect of [size] hung from the top of the screen and centred on the notch,
  /// pushed back inside the screen if the notch sits near an edge.
  Rect centeredRect(Size size) {
    final left = (centerX - size.width / 2).clamp(0.0, math.max(0.0, screenWidth - size.width));
    return Rect.fromLTWH(left, 0, size.width, size.height);
  }

  /// The rect Swift should let the mouse through to, for each shell state
  /// (spec §3.2).
  Rect interactiveRect(NotchState state) => switch (state) {
    NotchState.collapsed => hotZone(),
    NotchState.peeking => centeredRect(
      const Size(NotchSizes.peekWidth, NotchSizes.peekHeight),
    ),
    NotchState.expanded => centeredRect(
      const Size(NotchSizes.expandedWidth, NotchSizes.expandedHeight),
    ),
  };

  @override
  List<Object?> get props => [
    screenWidth, screenHeight, notchWidth, notchHeight, notchLeft, scale, isVirtual,
  ];
}
```

- [ ] **Step 4: Write the model, repository and datasource**

`lib/features/shell/data/models/notch_geometry_model.dart`:

```dart
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/features/shell/domain/entities/notch_geometry.dart';

/// Static mapper, null-safe defaults (architecture-playbook §5). A malformed
/// payload degrades to a centred virtual notch rather than throwing — the panel
/// staying usable matters more than the payload being right.
abstract final class NotchGeometryModel {
  static NotchGeometry toEntity(Map<String, Object?> json) {
    final screenWidth = _d(json['screenWidth'], 1440);
    final notchWidth = _d(json['notchWidth'], NotchSizes.virtualNotchWidth);

    return NotchGeometry(
      screenWidth: screenWidth,
      screenHeight: _d(json['screenHeight'], 900),
      notchWidth: notchWidth,
      notchHeight: _d(json['notchHeight'], NotchSizes.virtualNotchHeight),
      notchLeft: _d(json['notchLeft'], (screenWidth - notchWidth) / 2),
      scale: _d(json['scale'], 2),
      isVirtual: json['isVirtual'] as bool? ?? true,
    );
  }

  static double _d(Object? value, double fallback) =>
      (value as num?)?.toDouble() ?? fallback;
}
```

Add the two constants this needs to `lib/app/theme.dart`'s `NotchSizes`:

```dart
  /// Must match `NotchGeometry.virtualNotchWidth` / `Height` in Swift.
  static const double virtualNotchWidth = 200;
  static const double virtualNotchHeight = 32;
```

`lib/features/shell/data/datasources/shell_datasource.dart`:

```dart
import 'dart:ui';

import 'package:notchpeek/core/logging/notch_logger.dart';
import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/core/platform/channel_service.dart';
import 'package:notchpeek/core/platform/channels.dart';

abstract class ShellDataSource {
  Stream<Map<String, Object?>> watchGeometryEvents();
  Future<ApiResponse<bool>> setInteractiveRect(Rect rect);
}

/// The only place the shell feature touches a channel
/// (architecture-playbook §3).
class ShellDataSourceImpl implements ShellDataSource {
  ShellDataSourceImpl(this._channels);

  final ChannelService _channels;
  final NotchLogger _log = NotchLogger.forTag('ShellDataSourceImpl');

  /// Extracted so the filter is testable without a channel.
  static Stream<Map<String, Object?>> filterGeometry(
    Stream<Map<String, Object?>> events,
  ) => events.where(
    (e) => e[SystemEventKind.key] == SystemEventKind.geometry,
  );

  @override
  Stream<Map<String, Object?>> watchGeometryEvents() {
    _log.debug('subscribing to geometry events');
    return filterGeometry(_channels.systemEvents);
  }

  @override
  Future<ApiResponse<bool>> setInteractiveRect(Rect rect) async {
    final result = await _channels.invoke<bool>(ControlMethod.setInteractiveRect, {
      'x': rect.left,
      'y': rect.top,
      'width': rect.width,
      'height': rect.height,
    });
    if (result.status) {
      _log.success('interactive rect ${rect.width.toStringAsFixed(0)}x${rect.height.toStringAsFixed(0)}');
    } else {
      _log.error('interactive rect rejected: ${result.message}');
    }
    return result;
  }
}
```

`lib/features/shell/domain/repositories/shell_repository.dart`:

```dart
import 'dart:ui';

import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/shell/domain/entities/notch_geometry.dart';

abstract class ShellRepository {
  Stream<NotchGeometry> watchGeometry();
  Future<ApiResponse<bool>> setInteractiveRect(Rect rect);
}
```

`lib/features/shell/data/repositories/shell_repository_impl.dart`:

```dart
import 'dart:ui';

import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/shell/data/datasources/shell_datasource.dart';
import 'package:notchpeek/features/shell/data/models/notch_geometry_model.dart';
import 'package:notchpeek/features/shell/domain/entities/notch_geometry.dart';
import 'package:notchpeek/features/shell/domain/repositories/shell_repository.dart';

class ShellRepositoryImpl implements ShellRepository {
  ShellRepositoryImpl(this._source);

  final ShellDataSource _source;

  @override
  Stream<NotchGeometry> watchGeometry() =>
      _source.watchGeometryEvents().map(NotchGeometryModel.toEntity);

  @override
  Future<ApiResponse<bool>> setInteractiveRect(Rect rect) =>
      _source.setInteractiveRect(rect);
}
```

- [ ] **Step 5: Write the usecases and the provider graph**

`lib/features/shell/domain/usecases/watch_geometry.dart`:

```dart
import 'package:notchpeek/features/shell/domain/entities/notch_geometry.dart';
import 'package:notchpeek/features/shell/domain/repositories/shell_repository.dart';

/// Thin by design: the layer exists so a panel never reaches past it, not
/// because it holds logic (architecture-playbook §3).
class WatchGeometry {
  const WatchGeometry(this._repository);

  final ShellRepository _repository;

  Stream<NotchGeometry> call() => _repository.watchGeometry();
}
```

`lib/features/shell/domain/usecases/report_interactive_rect.dart`:

```dart
import 'dart:ui';

import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/shell/domain/repositories/shell_repository.dart';

class ReportInteractiveRect {
  const ReportInteractiveRect(this._repository);

  final ShellRepository _repository;

  Future<ApiResponse<bool>> call(Rect rect) => _repository.setInteractiveRect(rect);
}
```

`lib/features/shell/presentation/shell_providers.dart`:

```dart
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/core/platform/channel_service.dart';
import 'package:notchpeek/features/shell/data/datasources/shell_datasource.dart';
import 'package:notchpeek/features/shell/data/repositories/shell_repository_impl.dart';
import 'package:notchpeek/features/shell/domain/entities/notch_geometry.dart';
import 'package:notchpeek/features/shell/domain/repositories/shell_repository.dart';
import 'package:notchpeek/features/shell/domain/usecases/report_interactive_rect.dart';
import 'package:notchpeek/features/shell/domain/usecases/watch_geometry.dart';

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

final reportInteractiveRectProvider = Provider<ReportInteractiveRect>(
  (ref) => ReportInteractiveRect(ref.watch(shellRepositoryProvider)),
);

/// The Swift side is already stream-shaped, so a `StreamProvider` per
/// `EventChannel` is the natural fit (architecture-playbook §2).
final geometryProvider = StreamProvider<NotchGeometry>(
  (ref) => ref.watch(watchGeometryProvider)(),
);
```

- [ ] **Step 6: Replace the counter template with the real bootstrap**

`lib/main.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/app/notch_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: NotchApp()));
}
```

`lib/app/notch_app.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';

/// The root widget. There is no routing package and no navigator: one window,
/// one panel, tab selection is state (architecture-playbook §9).
class NotchApp extends StatelessWidget {
  const NotchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: NotchColors.panel,
      debugShowCheckedModeBanner: false,
      builder: (context, _) => const DefaultTextStyle(
        style: TextStyle(
          fontSize: 13,
          color: NotchColors.primaryText,
          decoration: TextDecoration.none,
        ),
        child: NotchSurface(),
      ),
    );
  }
}

/// Renders nothing until geometry has resolved. **Never flash a misplaced
/// panel** (spec §7) — a full-width transparent canvas with a notch drawn in
/// the wrong place is worse than an empty one.
class NotchSurface extends ConsumerWidget {
  const NotchSurface({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final geometry = ref.watch(geometryProvider);

    return switch (geometry) {
      AsyncData(:final value) => NotchShellPlaceholder(geometry: value),
      _ => const SizedBox.shrink(),
    };
  }
}

/// Replaced by the real `NotchShell` in Task 13. Kept as its own widget so the
/// bootstrap has something to render and something to test against now.
class NotchShellPlaceholder extends StatelessWidget {
  const NotchShellPlaceholder({required this.geometry, super.key});

  final Object geometry;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
```

- [ ] **Step 7: Delete the counter widget test**

```bash
git rm test/widget_test.dart
```
It asserts on `MyApp` and a counter, neither of which exists any more.

- [ ] **Step 8: Run everything**

Run: `flutter test && flutter analyze && flutter run -d macos`
Expected: all tests PASS, `No issues found!`, and the app launches showing **nothing** — no Dock icon, no window. That is correct at this point: the panel arrives in Task 9. Quit with `q`.

- [ ] **Step 9: Commit**

```bash
dart format .
git add -A lib test
git commit -m "feat(shell): geometry entity, repository and a bootstrap gated on resolved geometry"
```

---

### Task 9: `NotchWindowController` — one invisible canvas, never resized

The naive approach resizes the `NSWindow` each frame to animate the notch. That janks and desyncs from Flutter's animation clock. Instead: one borderless `NSPanel`, sized once, never resized (spec §3.1).

**Files:**
- Create: `macos/Runner/Notch/NotchWindowController.swift`
- Modify: `macos/Runner/MainFlutterWindow.swift`, `macos/Runner/AppDelegate.swift`

**Interfaces:**
- Consumes: `NotchMetrics`, `NotchGeometry.preferredScreen()` (Task 6).
- Produces: `final class NotchWindowController` with `init(contentViewController: NSViewController)`, `func show()`, `func reposition(for metrics: NotchMetrics)`, `var panel: NSPanel { get }`, `func setInteractiveRect(_ rect: CGRect?)` (delegated to `MouseGate` in Task 10; a stub that stores the rect until then).

- [ ] **Step 1: Write the module**

`macos/Runner/Notch/NotchWindowController.swift`:

```swift
import AppKit

/// Owns the one window this app has: a borderless, non-activating `NSPanel`
/// pinned to the top of the notched screen, sized once to
/// `screenWidth x canvasHeight` and **never resized**. Every expand, collapse
/// and peek is a Flutter animation painted inside it (spec §3.1).
final class NotchWindowController {

    /// Must match `NotchSizes.canvasHeight` in `lib/app/theme.dart`.
    static let canvasHeight: CGFloat = 420

    let panel: NSPanel

    init(contentViewController: NSViewController) {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentViewController = contentViewController
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above the menu bar. The panel must draw over it, not under it.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        // Swallowing every click across the menu bar is the failure mode this
        // app must never have. Default to transparent to the mouse; `MouseGate`
        // opens a hole only where Dart says it is interactive (spec §3.2).
        panel.ignoresMouseEvents = true

        // Dart paints the only visible pixels.
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    func show() {
        panel.orderFrontRegardless()
    }

    /// Called on every geometry change: display added or removed, resolution
    /// changed, Space switched to one on another screen.
    func reposition(for metrics: NotchMetrics) {
        guard let screen = NotchGeometry.preferredScreen() else { return }

        let frame = CGRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - Self.canvasHeight,
            width: metrics.screenWidth,
            height: Self.canvasHeight
        )

        // setFrame, not setFrameSize: the size only ever changes because the
        // *display* changed, never because the panel animated.
        panel.setFrame(frame, display: true)
    }
}
```

- [ ] **Step 2: Hand the Flutter view controller to the panel instead of the nib window**

Replace `macos/Runner/MainFlutterWindow.swift` with:

```swift
import Cocoa
import FlutterMacOS

/// The nib still instantiates this window, but nothing is ever drawn in it.
/// The Flutter view controller is handed to `NotchWindowController`'s panel
/// instead, and this window is ordered out and never shown again.
///
/// An `NSPanel` cannot be substituted for this class in the nib, and
/// `.nonactivatingPanel` is panel-only — so the panel is created in code.
class MainFlutterWindow: NSWindow {
    override func awakeFromNib() {
        let flutterViewController = FlutterViewController()
        RegisterGeneratedPlugins(registry: flutterViewController)

        // Dart paints the only visible pixels: the view must not draw a ground.
        flutterViewController.backgroundColor = .clear

        (NSApp.delegate as? AppDelegate)?.attach(
            flutterViewController: flutterViewController
        )

        super.awakeFromNib()

        setIsVisible(false)
        orderOut(nil)
    }
}
```

- [ ] **Step 3: Own the controller from `AppDelegate` and follow geometry**

In `macos/Runner/AppDelegate.swift`, replace `attach(messenger:)` with:

```swift
    var windowController: NotchWindowController?

    func attach(flutterViewController: FlutterViewController) {
        let controller = NotchWindowController(contentViewController: flutterViewController)
        windowController = controller

        let bridge = ChannelBridge(messenger: flutterViewController.engine.binaryMessenger)
        bridge.start()
        self.bridge = bridge

        let observer = NotchGeometryObserver { [weak self, weak bridge] metrics in
            self?.windowController?.reposition(for: metrics)
            bridge?.sendSystem(SystemEvent.geometry, metrics.channelMap)
        }
        observer.start()
        geometryObserver = observer

        controller.show()
    }
```

Note the order: `reposition` before `sendSystem`, so the window is already in the right place by the time Dart hears about the geometry it should draw for.

- [ ] **Step 4: Register, build, and verify by hand**

```bash
tool/add_xcode_file.sh Runner/Notch/NotchWindowController.swift Runner
flutter run -d macos
```

Verify, and record the result in the commit message:
1. No Dock icon and no app menu bar appear.
2. Nothing is visible on screen — Dart is still drawing `SizedBox.shrink()`, and the panel is transparent.
3. **Clicks anywhere in the menu bar still reach the app underneath** — click the Wi-Fi icon, the clock, and a menu of the frontmost app. This is exit criterion 1 and the single most important behavior in the milestone.
4. `flutter run` reports the geometry event arriving in Dart (add a temporary `NotchLogger` line in `NotchSurface` if you want to see it, then remove it).

- [ ] **Step 5: Commit**

```bash
git add macos
git commit -m "feat(shell): add the never-resized NSPanel canvas above the menu bar"
```

---

### Task 10: `MouseGate` — open a hole in the panel exactly where Dart says

A transparent full-width window would swallow every click across the menu bar. The panel runs `ignoresMouseEvents = true` by default, and Swift flips it off only while the cursor sits inside the rect Dart pushed down (spec §3.2). Driven by a **local** event monitor, which needs **no Accessibility permission**.

**Files:**
- Create: `macos/Runner/Notch/MouseGate.swift`
- Modify: `macos/Runner/AppDelegate.swift`
- Test: `macos/RunnerTests/MouseGateTests.swift`

**Interfaces:**
- Consumes: `NotchWindowController.panel` (Task 9), `ChannelBridge.onSetInteractiveRect` (Task 7).
- Produces:
  - `final class MouseGate` with `init(panel: NSPanel)`, `func start()`, `func stop()`, `func update(interactiveRect: CGRect?)`, `private(set) var isCapturing: Bool`
  - `static func windowRect(fromDartRect:canvasHeight:) -> CGRect` — the flip from Dart's top-left origin to AppKit's bottom-left origin
  - `static func shouldCapture(mouseInWindow:interactiveRect:) -> Bool`

- [ ] **Step 1: Write the failing test**

`macos/RunnerTests/MouseGateTests.swift`:

```swift
import XCTest
@testable import NotchPeek

final class MouseGateTests: XCTestCase {

    /// Dart measures from the top-left of the canvas; AppKit from the
    /// bottom-left of the window. Getting this backwards puts the hole at the
    /// bottom of the screen, where nothing is.
    func testFlipsDartsTopLeftRectIntoWindowCoordinates() {
        let flipped = MouseGate.windowRect(
            fromDartRect: CGRect(x: 585, y: 0, width: 300, height: 32),
            canvasHeight: 420
        )

        XCTAssertEqual(flipped, CGRect(x: 585, y: 388, width: 300, height: 32))
    }

    func testCapturesOnlyInsideTheInteractiveRect() {
        let rect = CGRect(x: 100, y: 300, width: 200, height: 40)

        XCTAssertTrue(MouseGate.shouldCapture(mouseInWindow: CGPoint(x: 150, y: 320), interactiveRect: rect))
        XCTAssertFalse(MouseGate.shouldCapture(mouseInWindow: CGPoint(x: 50, y: 320), interactiveRect: rect))
        XCTAssertFalse(MouseGate.shouldCapture(mouseInWindow: CGPoint(x: 150, y: 200), interactiveRect: rect))
    }

    func testTheEdgeOfTheRectCounts() {
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)

        XCTAssertTrue(MouseGate.shouldCapture(mouseInWindow: CGPoint(x: 0, y: 0), interactiveRect: rect))
        XCTAssertTrue(MouseGate.shouldCapture(mouseInWindow: CGPoint(x: 10, y: 10), interactiveRect: rect))
        XCTAssertFalse(MouseGate.shouldCapture(mouseInWindow: CGPoint(x: 10.1, y: 5), interactiveRect: rect))
    }

    func testNeverCapturesWhenDartHasNotReportedARect() {
        XCTAssertFalse(MouseGate.shouldCapture(mouseInWindow: CGPoint(x: 5, y: 5), interactiveRect: nil))
    }
}
```

`CGRect.contains` excludes the max edge, so `testTheEdgeOfTheRectCounts` forces an inclusive implementation — a cursor resting exactly on the boundary of the hot zone must still open the panel.

- [ ] **Step 2: Run it and watch it fail**

```bash
tool/add_xcode_file.sh RunnerTests/MouseGateTests.swift RunnerTests
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -destination 'platform=macOS' -quiet
```
Expected: FAIL — `cannot find 'MouseGate' in scope`.

- [ ] **Step 3: Write the module**

`macos/Runner/Notch/MouseGate.swift`:

```swift
import AppKit

/// Decides, on every mouse move, whether the panel should accept the mouse or
/// let it fall through to whatever is underneath.
///
/// Uses a **local** event monitor, which needs no Accessibility permission.
/// Nothing in this app should ever prompt at launch.
final class MouseGate {

    private weak var panel: NSPanel?
    private var monitor: Any?
    private var interactiveRect: CGRect?

    private(set) var isCapturing = false

    init(panel: NSPanel) {
        self.panel = panel
    }

    // MARK: - Pure, and therefore tested

    /// Dart measures from the top-left of the canvas; AppKit from the
    /// bottom-left of the window.
    static func windowRect(fromDartRect rect: CGRect, canvasHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: canvasHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Inclusive of the edges: a cursor resting exactly on the boundary of the
    /// hot zone must still open the panel.
    static func shouldCapture(mouseInWindow point: CGPoint, interactiveRect rect: CGRect?) -> Bool {
        guard let rect else { return false }
        return point.x >= rect.minX && point.x <= rect.maxX
            && point.y >= rect.minY && point.y <= rect.maxY
    }

    // MARK: - Wiring

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.evaluate()
            return event
        }
        evaluate()
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Dart's rect, in Dart's coordinate space. `nil` means "capture nothing".
    func update(interactiveRect rect: CGRect?) {
        guard let rect else {
            interactiveRect = nil
            apply(capturing: false)
            return
        }
        interactiveRect = MouseGate.windowRect(
            fromDartRect: rect,
            canvasHeight: NotchWindowController.canvasHeight
        )
        evaluate()
    }

    private func evaluate() {
        guard let panel else { return }
        let mouseInWindow = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        apply(capturing: MouseGate.shouldCapture(
            mouseInWindow: mouseInWindow,
            interactiveRect: interactiveRect
        ))
    }

    private func apply(capturing: Bool) {
        guard capturing != isCapturing else { return }
        isCapturing = capturing
        panel?.ignoresMouseEvents = !capturing
    }

    deinit { stop() }
}
```

A local monitor only fires while this app is active, which an agent app usually is not. The evaluation therefore also runs whenever Dart reports a new rect, and a global `.mouseMoved` monitor is added alongside the local one in the next step — global monitors for mouse-moved events do **not** require Accessibility permission (only keyboard monitoring does).

Add to `start()`, after the local monitor:

```swift
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.evaluate()
        }
```

with a matching `private var globalMonitor: Any?` and removal in `stop()`.

- [ ] **Step 4: Wire it to the bridge**

In `AppDelegate.attach(flutterViewController:)`, after the panel exists:

```swift
        let gate = MouseGate(panel: controller.panel)
        gate.start()
        mouseGate = gate

        bridge.onSetInteractiveRect = { [weak gate] rect in
            gate?.update(interactiveRect: rect)
        }
```

with `var mouseGate: MouseGate?` as a stored property.

- [ ] **Step 5: Run the tests, then verify by hand**

```bash
tool/add_xcode_file.sh Runner/Notch/MouseGate.swift Runner
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -destination 'platform=macOS' -quiet
```
Expected: 4 new tests PASS.

There is nothing to hover yet — the hand check for this lands at the end of Task 13.

- [ ] **Step 6: Commit**

```bash
git add macos
git commit -m "feat(shell): gate the mouse on Dart's interactive rect via a local event monitor"
```

---

### Task 11: The shell state machine

The one piece of M1 logic that is pure, testable without a Mac window, and inherited by every later milestone. Get it wrong and every panel inherits the wrongness.

**Files:**
- Create: `lib/features/shell/domain/entities/shell_state.dart`, `lib/features/shell/presentation/notifier/shell_notifier.dart`
- Modify: `lib/features/shell/presentation/shell_providers.dart`
- Test: `test/features/shell/shell_notifier_test.dart`

**Interfaces:**
- Consumes: `NotchState`, `PeekKind`, `PanelTab` (Task 4), `NotchMotion.peekDwell` (Task 4).
- Produces:
  - `class ShellState extends Equatable` — `NotchState state`, `PeekKind? peek`, `PanelTab tab`; `copyWith`; getters `bool get isExpanded`, `bool get isCollapsed`, `bool get showsContent`
  - `class ShellNotifier extends Notifier<ShellState>` with `void hoverEntered()`, `void hoverExited()`, `void peekRequested(PeekKind kind)`, `void peekExpired()`, `void tabSelected(PanelTab tab)`, `void forceCollapse()`
  - providers: `peekDwellProvider` (`Provider<Duration>`), `shellNotifierProvider` (`NotifierProvider<ShellNotifier, ShellState>`)

- [ ] **Step 1: Write the failing test**

`test/features/shell/shell_notifier_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/features/shell/domain/entities/shell_state.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';
import 'package:notchpeek/shared/utils/enums/notch_state.dart';
import 'package:notchpeek/shared/utils/enums/panel_tab.dart';
import 'package:notchpeek/shared/utils/enums/peek_kind.dart';

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [peekDwellProvider.overrideWithValue(Duration.zero)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('starts collapsed on the music tab with no peek', () {
    final state = _container().read(shellNotifierProvider);

    expect(state.state, NotchState.collapsed);
    expect(state.peek, isNull);
    expect(state.tab, PanelTab.music);
    expect(state.showsContent, isFalse);
  });

  test('hover expands from collapsed and from peeking', () {
    final c = _container();
    final notifier = c.read(shellNotifierProvider.notifier);

    notifier.hoverEntered();
    expect(c.read(shellNotifierProvider).state, NotchState.expanded);

    notifier.hoverExited();
    notifier.peekRequested(PeekKind.trackChange);
    notifier.hoverEntered();
    expect(c.read(shellNotifierProvider).state, NotchState.expanded);
    expect(c.read(shellNotifierProvider).peek, isNull, reason: 'expanding consumes the peek');
  });

  test('leaving collapses and clears the peek', () {
    final c = _container();
    final notifier = c.read(shellNotifierProvider.notifier);

    notifier.hoverEntered();
    notifier.hoverExited();

    expect(c.read(shellNotifierProvider).state, NotchState.collapsed);
    expect(c.read(shellNotifierProvider).peek, isNull);
  });

  test('a peek moves collapsed to peeking and records why', () {
    final c = _container();

    c.read(shellNotifierProvider.notifier).peekRequested(PeekKind.charger);

    expect(c.read(shellNotifierProvider).state, NotchState.peeking);
    expect(c.read(shellNotifierProvider).peek, PeekKind.charger);
  });

  test('a peek never interrupts an expanded panel', () {
    final c = _container();
    final notifier = c.read(shellNotifierProvider.notifier);

    notifier.hoverEntered();
    notifier.peekRequested(PeekKind.trackChange);

    expect(c.read(shellNotifierProvider).state, NotchState.expanded);
    expect(c.read(shellNotifierProvider).peek, isNull);
  });

  test('a peek retracts on its own', () async {
    final c = _container();

    c.read(shellNotifierProvider.notifier).peekRequested(PeekKind.trackChange);
    await Future<void>.delayed(Duration.zero);

    expect(c.read(shellNotifierProvider).state, NotchState.collapsed);
  });

  test('a second peek restarts the dwell rather than stacking', () {
    final c = _container();
    final notifier = c.read(shellNotifierProvider.notifier);

    notifier.peekRequested(PeekKind.trackChange);
    notifier.peekRequested(PeekKind.charger);

    expect(c.read(shellNotifierProvider).peek, PeekKind.charger);
    expect(c.read(shellNotifierProvider).state, NotchState.peeking);
  });

  test('peekExpired is ignored unless we are actually peeking', () {
    final c = _container();
    final notifier = c.read(shellNotifierProvider.notifier);

    notifier.hoverEntered();
    notifier.peekExpired();

    expect(c.read(shellNotifierProvider).state, NotchState.expanded);
  });

  test('a forced collapse wins from any state — display unplugged mid-expand', () {
    final c = _container();
    final notifier = c.read(shellNotifierProvider.notifier);

    notifier.hoverEntered();
    notifier.forceCollapse();

    expect(c.read(shellNotifierProvider).state, NotchState.collapsed);
  });

  test('selecting a tab keeps the panel open and remembers the choice', () {
    final c = _container();
    final notifier = c.read(shellNotifierProvider.notifier);

    notifier.hoverEntered();
    notifier.tabSelected(PanelTab.calendar);

    expect(c.read(shellNotifierProvider).tab, PanelTab.calendar);
    expect(c.read(shellNotifierProvider).state, NotchState.expanded);
  });

  test('showsContent is true whenever the panel is not collapsed', () {
    const collapsed = ShellState();
    expect(collapsed.showsContent, isFalse);
    expect(collapsed.copyWith(state: NotchState.peeking).showsContent, isTrue);
    expect(collapsed.copyWith(state: NotchState.expanded).showsContent, isTrue);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/shell/shell_notifier_test.dart`
Expected: FAIL — `shell_state.dart` does not exist.

- [ ] **Step 3: Write the state**

`lib/features/shell/domain/entities/shell_state.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:notchpeek/shared/utils/enums/notch_state.dart';
import 'package:notchpeek/shared/utils/enums/panel_tab.dart';
import 'package:notchpeek/shared/utils/enums/peek_kind.dart';

/// Derived values are getters here, never computed in the UI
/// (architecture-playbook §2).
class ShellState extends Equatable {
  const ShellState({
    this.state = NotchState.collapsed,
    this.peek,
    this.tab = PanelTab.music,
  });

  final NotchState state;

  /// Why we are peeking. Null in every other state.
  final PeekKind? peek;

  final PanelTab tab;

  bool get isExpanded => state == NotchState.expanded;
  bool get isCollapsed => state == NotchState.collapsed;

  /// Collapsed means stop work: no polling, no animation, no camera session
  /// (architecture-playbook §9).
  bool get showsContent => state != NotchState.collapsed;

  ShellState copyWith({
    NotchState? state,
    PeekKind? peek,
    bool clearPeek = false,
    PanelTab? tab,
  }) => ShellState(
    state: state ?? this.state,
    peek: clearPeek ? null : (peek ?? this.peek),
    tab: tab ?? this.tab,
  );

  @override
  List<Object?> get props => [state, peek, tab];
}
```

- [ ] **Step 4: Write the notifier**

`lib/features/shell/presentation/notifier/shell_notifier.dart`:

```dart
import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/core/logging/notch_logger.dart';
import 'package:notchpeek/features/shell/domain/entities/shell_state.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';
import 'package:notchpeek/shared/utils/enums/notch_state.dart';
import 'package:notchpeek/shared/utils/enums/panel_tab.dart';
import 'package:notchpeek/shared/utils/enums/peek_kind.dart';

/// The shell's state machine. Widgets never mutate this directly — they call
/// a named method (architecture-playbook §2).
class ShellNotifier extends Notifier<ShellState> {
  final NotchLogger _log = NotchLogger.forTag('ShellNotifier');
  Timer? _peekTimer;

  @override
  ShellState build() {
    ref.onDispose(() => _peekTimer?.cancel());
    return const ShellState();
  }

  void hoverEntered() {
    if (state.isExpanded) return;
    _cancelPeek();
    _log.debug('expand');
    state = state.copyWith(state: NotchState.expanded, clearPeek: true);
  }

  void hoverExited() {
    if (state.isCollapsed) return;
    _cancelPeek();
    _log.debug('collapse');
    state = state.copyWith(state: NotchState.collapsed, clearPeek: true);
  }

  /// A peek never interrupts an open panel: the user is already looking at
  /// more than the peek would show.
  void peekRequested(PeekKind kind) {
    if (state.isExpanded) return;

    _cancelPeek();
    _log.debug('peek ${kind.apiValue}');
    state = state.copyWith(state: NotchState.peeking, peek: kind);

    _peekTimer = Timer(ref.read(peekDwellProvider), peekExpired);
  }

  void peekExpired() {
    if (state.state != NotchState.peeking) return;
    _cancelPeek();
    state = state.copyWith(state: NotchState.collapsed, clearPeek: true);
  }

  /// Display disconnected mid-expand, Space switched away, geometry moved.
  void forceCollapse() {
    _cancelPeek();
    if (state.isCollapsed) return;
    _log.debug('forced collapse');
    state = state.copyWith(state: NotchState.collapsed, clearPeek: true);
  }

  void tabSelected(PanelTab tab) {
    if (state.tab == tab) return;
    state = state.copyWith(tab: tab);
  }

  void _cancelPeek() {
    _peekTimer?.cancel();
    _peekTimer = null;
  }
}
```

- [ ] **Step 5: Add the two providers**

Append to `lib/features/shell/presentation/shell_providers.dart`:

```dart
/// How long an unattended peek stays out. A provider rather than a constant
/// so tests can drive the machine without waiting four seconds.
final peekDwellProvider = Provider<Duration>((ref) => NotchMotion.peekDwell);

final shellNotifierProvider = NotifierProvider<ShellNotifier, ShellState>(
  ShellNotifier.new,
);
```

with imports for `app/theme.dart`, `domain/entities/shell_state.dart` and `notifier/shell_notifier.dart`.

- [ ] **Step 6: Run the tests and the gate**

Run: `flutter test test/features/shell/ && flutter analyze`
Expected: 11 tests PASS, `No issues found!`.

- [ ] **Step 7: Commit**

```bash
dart format .
git add -A lib test
git commit -m "feat(shell): add the notch state machine with self-retracting peeks"
```

---

### Task 12: `NotchShape` — the concave shoulders that make it read as hardware

Rounded bottom corners and **concave** top corners where the panel flares out from the notch. That inverted curve is what makes it read as one continuous piece of hardware instead of a floating rectangle (spec §5.1).

**Files:**
- Create: `lib/features/shell/presentation/widgets/notch_shape.dart`
- Test: `test/features/shell/notch_shape_test.dart`
- Create: `test/features/shell/goldens/` (golden output)

**Interfaces:**
- Consumes: `NotchRadii` (Task 4).
- Produces: `class NotchShape extends CustomClipper<Path>` with `const NotchShape({double shoulder, double bottomRadius})`, and `static Path build(Size size, {required double shoulder, required double bottomRadius})`.

- [ ] **Step 1: Write the failing test**

`test/features/shell/notch_shape_test.dart`:

```dart
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
        child: ClipPath(
          clipper: const NotchShape(),
          child: const ColoredBox(color: NotchColors.panel),
        ),
      ),
    ),
  ),
);

void main() {
  test('the path spans the full box at the top and insets by the shoulder below', () {
    const size = Size(400, 200);
    final path = NotchShape.build(size, shoulder: 14, bottomRadius: 22);

    expect(path.contains(const Offset(200, 1)), isTrue, reason: 'top centre is inside');
    expect(path.contains(const Offset(2, 60)), isFalse, reason: 'the shoulder is carved away');
    expect(path.contains(const Offset(398, 60)), isFalse);
    expect(path.contains(const Offset(200, 199)), isTrue, reason: 'bottom centre is inside');
  });

  test('the bottom corners are rounded away', () {
    const size = Size(400, 200);
    final path = NotchShape.build(size, shoulder: 14, bottomRadius: 22);

    expect(path.contains(const Offset(15, 199)), isFalse);
    expect(path.contains(const Offset(385, 199)), isFalse);
  });

  test('a box narrower than two shoulders still produces a closed path', () {
    final path = NotchShape.build(const Size(10, 40), shoulder: 14, bottomRadius: 22);

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
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/shell/notch_shape_test.dart`
Expected: FAIL — `notch_shape.dart` does not exist.

- [ ] **Step 3: Write the clipper**

`lib/features/shell/presentation/widgets/notch_shape.dart`:

```dart
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:notchpeek/app/theme.dart';

/// The notch silhouette: full width at the very top, concave shoulders curving
/// inward just below it, straight sides, rounded bottom corners.
///
/// The box you give it is the **outer** box — its width includes both
/// shoulders, so the flat body below them is `width - 2 * shoulder` wide. Size
/// the box as `bodyWidth + 2 * shoulder` and the body lines up with the notch.
class NotchShape extends CustomClipper<Path> {
  const NotchShape({
    this.shoulder = NotchRadii.shoulder,
    this.bottomRadius = NotchRadii.panelBottom,
  });

  final double shoulder;
  final double bottomRadius;

  static Path build(
    Size size, {
    required double shoulder,
    required double bottomRadius,
  }) {
    final w = size.width;
    final h = size.height;

    // Never let the curves eat each other on a small box.
    final s = math.min(shoulder, w / 2);
    final r = math.min(bottomRadius, math.min(h, (w - 2 * s) / 2));

    return Path()
      ..moveTo(0, 0)
      // Concave top-left: bows up and to the right, carving into the panel.
      ..quadraticBezierTo(s, 0, s, math.min(s, h))
      ..lineTo(s, h - r)
      ..quadraticBezierTo(s, h, s + r, h)
      ..lineTo(w - s - r, h)
      ..quadraticBezierTo(w - s, h, w - s, h - r)
      ..lineTo(w - s, math.min(s, h))
      // Concave top-right.
      ..quadraticBezierTo(w - s, 0, w, 0)
      ..close();
  }

  @override
  Path getClip(Size size) =>
      build(size, shoulder: shoulder, bottomRadius: bottomRadius);

  @override
  bool shouldReclip(NotchShape oldClipper) =>
      oldClipper.shoulder != shoulder || oldClipper.bottomRadius != bottomRadius;
}
```

- [ ] **Step 4: Generate the goldens, then look at them**

Run: `flutter test --update-goldens test/features/shell/notch_shape_test.dart`
Then open `test/features/shell/goldens/notch_shape_collapsed.png` and `..._expanded.png`. **Look at them before committing.** The top edge must be the full width of the image with the shoulders curving inward beneath it; if the curve bulges outward instead, the control points are the wrong way round.

- [ ] **Step 5: Re-run against the committed goldens**

Run: `flutter test test/features/shell/notch_shape_test.dart && flutter analyze`
Expected: 5 tests PASS.

- [ ] **Step 6: Commit**

```bash
dart format .
git add -A lib test
git commit -m "feat(shell): add the NotchShape clipper with concave shoulders"
```

---

### Task 13: `NotchShell` — the morph, and the rect that follows it

One `AnimationController` drives width, height and corner radius through tweens: ~350 ms to open on `easeOutQuint`, 250 ms to close. Content cross-fades staggered behind the container growth, so the box arrives before the contents do (spec §5.1). On every settled state change, Dart measures and pushes the interactive rect down to `MouseGate`.

**Files:**
- Create: `lib/features/shell/presentation/widgets/notch_shell.dart`
- Modify: `lib/app/notch_app.dart` (drop `NotchShellPlaceholder`)
- Test: `test/features/shell/notch_shell_test.dart`

**Interfaces:**
- Consumes: `NotchGeometry` (Task 8), `ShellState`/`ShellNotifier`/`shellNotifierProvider` (Task 11), `NotchShape` (Task 12), `reportInteractiveRectProvider` (Task 8), `NotchMotion`/`NotchSizes`/`NotchColors` (Task 4).
- Produces: `class NotchShell extends HookConsumerWidget` with `const NotchShell({required NotchGeometry geometry, required Widget child, super.key})`.

- [ ] **Step 1: Write the failing test**

`test/features/shell/notch_shell_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/shell/domain/entities/notch_geometry.dart';
import 'package:notchpeek/features/shell/domain/repositories/shell_repository.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';
import 'package:notchpeek/features/shell/presentation/widgets/notch_shell.dart';
import 'package:notchpeek/shared/utils/enums/notch_state.dart';
import 'package:notchpeek/shared/utils/enums/peek_kind.dart';

const _geometry = NotchGeometry(
  screenWidth: 1470, screenHeight: 956, notchWidth: 300, notchHeight: 32,
  notchLeft: 585, scale: 2, isVirtual: false,
);

class _RecordingShellRepository implements ShellRepository {
  final List<Rect> rects = [];

  @override
  Stream<NotchGeometry> watchGeometry() => const Stream.empty();

  @override
  Future<ApiResponse<bool>> setInteractiveRect(Rect rect) async {
    rects.add(rect);
    return ApiResponse.success(message: 'OK', data: true);
  }
}

Future<ProviderContainer> _pump(WidgetTester tester, _RecordingShellRepository repo) async {
  final container = ProviderContainer(
    overrides: [
      shellRepositoryProvider.overrideWithValue(repo),
      peekDwellProvider.overrideWithValue(const Duration(seconds: 30)),
    ],
  );
  addTearDown(container.dispose);

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

  testWidgets('reports the expanded rect once the morph has settled', (tester) async {
    final repo = _RecordingShellRepository();
    final container = await _pump(tester, repo);

    container.read(shellNotifierProvider.notifier).hoverEntered();
    await tester.pumpAndSettle();

    expect(repo.rects.last, _geometry.interactiveRect(NotchState.expanded));
  });

  testWidgets('reports the peek rect while peeking', (tester) async {
    final repo = _RecordingShellRepository();
    final container = await _pump(tester, repo);

    container.read(shellNotifierProvider.notifier).peekRequested(PeekKind.trackChange);
    await tester.pumpAndSettle();

    expect(repo.rects.last, _geometry.interactiveRect(NotchState.peeking));
  });

  testWidgets('hides its child while collapsed and shows it when expanded', (tester) async {
    final repo = _RecordingShellRepository();
    final container = await _pump(tester, repo);

    expect(find.text('panel'), findsNothing);

    container.read(shellNotifierProvider.notifier).hoverEntered();
    await tester.pumpAndSettle();

    expect(find.text('panel'), findsOneWidget);
  });

  testWidgets('a pointer entering the notch expands it', (tester) async {
    final repo = _RecordingShellRepository();
    final container = await _pump(tester, repo);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(_geometry.notchRect.center);
    await tester.pumpAndSettle();

    expect(container.read(shellNotifierProvider).state, NotchState.expanded);
  });

  testWidgets('golden: collapsed, peeking and expanded', (tester) async {
    final repo = _RecordingShellRepository();
    final container = await _pump(tester, repo);

    await expectLater(find.byType(NotchShell), matchesGoldenFile('goldens/shell_collapsed.png'));

    container.read(shellNotifierProvider.notifier).peekRequested(PeekKind.charger);
    await tester.pumpAndSettle();
    await expectLater(find.byType(NotchShell), matchesGoldenFile('goldens/shell_peeking.png'));

    container.read(shellNotifierProvider.notifier).hoverEntered();
    await tester.pumpAndSettle();
    await expectLater(find.byType(NotchShell), matchesGoldenFile('goldens/shell_expanded.png'));
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/shell/notch_shell_test.dart`
Expected: FAIL — `notch_shell.dart` does not exist.

- [ ] **Step 3: Write the shell**

`lib/features/shell/presentation/widgets/notch_shell.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/features/shell/domain/entities/notch_geometry.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';
import 'package:notchpeek/features/shell/presentation/widgets/notch_shape.dart';
import 'package:notchpeek/shared/utils/enums/notch_state.dart';

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

    final controller = useAnimationController(duration: NotchMotion.open);

    // One controller, retimed per direction: opening is slower and eases out,
    // closing is quicker and eases in.
    useEffect(() {
      controller.duration =
          shell.isCollapsed ? NotchMotion.close : NotchMotion.open;
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

    final curve = CurvedAnimation(
      parent: controller,
      curve: NotchMotion.openCurve,
      reverseCurve: NotchMotion.closeCurve,
    );

    final collapsed = geometry.interactiveRect(NotchState.collapsed);

    return Stack(
      children: [
        AnimatedBuilder(
          animation: curve,
          builder: (context, _) {
            final width = lerpDouble(collapsed.width, target.width, curve.value)!;
            final height = lerpDouble(collapsed.height, target.height, curve.value)!;
            final radius = lerpDouble(
              NotchRadii.collapsedBottom,
              NotchRadii.panelBottom,
              curve.value,
            )!;

            return Positioned(
              left: geometry.centerX - width / 2,
              top: 0,
              width: width,
              height: height,
              child: MouseRegion(
                onEnter: (_) => ref.read(shellNotifierProvider.notifier).hoverEntered(),
                onExit: (_) => ref.read(shellNotifierProvider.notifier).hoverExited(),
                child: ClipPath(
                  clipper: NotchShape(bottomRadius: radius),
                  child: ColoredBox(
                    color: NotchColors.panel,
                    child: AnimatedSwitcher(
                      duration: NotchMotion.contentFade,
                      switchInCurve: NotchMotion.contentStagger,
                      child: shell.showsContent
                          ? KeyedSubtree(key: const ValueKey('content'), child: child)
                          : const SizedBox.shrink(key: ValueKey('empty')),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
```

Add `import 'dart:ui' show lerpDouble;` at the top.

- [ ] **Step 4: Render it from the app root**

In `lib/app/notch_app.dart`, delete `NotchShellPlaceholder` and change `NotchSurface`'s data branch to:

```dart
      AsyncData(:final value) => NotchShell(
        geometry: value,
        child: const SizedBox.shrink(),
      ),
```

The child becomes the tab strip and panels in Task 21; for now the shell is an empty box that morphs.

- [ ] **Step 5: Generate goldens, look at them, then run everything**

```bash
flutter test --update-goldens test/features/shell/notch_shell_test.dart
open test/features/shell/goldens/shell_expanded.png
flutter test && flutter analyze
```
Expected: 6 tests PASS after the goldens are written. Check the expanded golden actually shows a wide panel with concave shoulders.

- [ ] **Step 6: The week-1 hand check — this is the one that decides the deadline**

Run: `flutter run -d macos`

Work through all of this and record the result in the commit message:
1. Move the cursor into the notch — the panel expands within ~350 ms with no dropped frames.
2. Move it away — the panel collapses.
3. **Click the Wi-Fi icon, the clock, and the frontmost app's menus.** Every click must reach them.
4. Click *inside* the expanded panel — the click must not fall through, and **the app in front must not lose focus** (that is what `.nonactivatingPanel` buys).
5. Switch Space with Ctrl+←/→ — the panel is present on the new Space.
6. Enter fullscreen in any app — the panel is still reachable.

If 1–3 do not hold, **stop and say so now**, per R3. Everything in M2–M4 is built on this.

- [ ] **Step 7: Commit**

```bash
dart format .
git add -A lib test
git commit -m "feat(shell): morph the notch between collapsed, peek and expanded and report the rect"
```

---

# Week 2 — Media, power, and a panel

Exit condition for the week: **the app is genuinely usable on the dev machine.**

**One deviation from spec §3.5 is introduced here, deliberately.** The spec fixes five control methods, and §4 separately requires that position polling happens "at 1 Hz while expanded, and not at all while collapsed". Nothing in the five carries that signal, and it cannot be inferred from `setInteractiveRect` without the shell leaking its state machine into the channel contract. Week 2 therefore adds a sixth method, `setMediaPolling`. Task 27 reconciles the spec.

Track *changes* do not need polling at all: both players post a distributed notification (`com.apple.Music.playerInfo`, `com.spotify.client.PlaybackStateChanged`). That is what drives the peek while collapsed, for free.

---

### Task 14: `CapabilityProbe` — what this build, this OS and these permissions can actually do

The field set is deliberately wider than M1 needs, because later milestones add to it and the shape should not churn (spec §6).

**Files:**
- Create: `macos/Runner/Notch/CapabilityProbe.swift`
- Create: `lib/core/platform/capabilities.dart`
- Modify: `macos/Runner/Notch/Channels.swift` (add `setMediaPolling`), `lib/core/platform/channels.dart` (same), `macos/Runner/AppDelegate.swift`
- Test: `test/core/platform/capabilities_test.dart`

**Interfaces:**
- Consumes: `CapabilityState`, `BuildFlavor` (Task 4), `ChannelService` (Task 7).
- Produces:
  - Swift `enum CapabilityProbe` with `static func snapshot() -> [String: Any]`, `static func appleEventsState(for bundleId: String) -> String`, `static func requestAppleEvents(for bundleId: String)`
  - Dart `class Capabilities extends Equatable` with `buildFlavor`, `osSupportsOnDeviceAI`, `appleMusic`, `spotify`, `systemWideMediaRead`, `systemWideMediaCommand`, `calendar`, `camera`; getters `CapabilityState get music`, `bool get anyPlayerReady`; `Capabilities.fromMap(Map<String, Object?>)`
  - `final capabilitiesProvider = StreamProvider<Capabilities>(...)`
  - `ControlMethod.setMediaPolling` on both sides

- [ ] **Step 1: Write the failing Dart test**

`test/core/platform/capabilities_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/core/platform/capabilities.dart';
import 'package:notchpeek/shared/utils/enums/build_flavor.dart';
import 'package:notchpeek/shared/utils/enums/capability_state.dart';

void main() {
  test('parses the probe snapshot', () {
    final caps = Capabilities.fromMap(const {
      'buildFlavor': 'direct',
      'osSupportsOnDeviceAI': true,
      'scriptingMedia': {'appleMusic': 'granted', 'spotify': 'denied'},
      'systemWideMediaRead': false,
      'systemWideMediaCommand': true,
      'calendar': 'notDetermined',
      'camera': 'absent',
    });

    expect(caps.buildFlavor, BuildFlavor.direct);
    expect(caps.appleMusic, CapabilityState.granted);
    expect(caps.spotify, CapabilityState.denied);
    expect(caps.systemWideMediaRead, isFalse);
    expect(caps.camera, CapabilityState.absent);
  });

  test('an empty snapshot degrades to notDetermined, never a throw', () {
    final caps = Capabilities.fromMap(const {});

    expect(caps.appleMusic, CapabilityState.notDetermined);
    expect(caps.music, CapabilityState.notDetermined);
    expect(caps.anyPlayerReady, isFalse);
  });

  test('music is ready when either player is', () {
    final caps = Capabilities.fromMap(const {
      'scriptingMedia': {'appleMusic': 'denied', 'spotify': 'granted'},
    });

    expect(caps.music, CapabilityState.granted);
    expect(caps.anyPlayerReady, isTrue);
  });

  test('music is denied only when both players are denied', () {
    final both = Capabilities.fromMap(const {
      'scriptingMedia': {'appleMusic': 'denied', 'spotify': 'denied'},
    });
    expect(both.music, CapabilityState.denied);

    final one = Capabilities.fromMap(const {
      'scriptingMedia': {'appleMusic': 'denied', 'spotify': 'notDetermined'},
    });
    expect(one.music, CapabilityState.notDetermined);
  });
}
```

- [ ] **Step 2: Run it and watch it fail, then write the Dart model**

Run: `flutter test test/core/platform/capabilities_test.dart` → FAIL.

`lib/core/platform/capabilities.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/core/platform/channel_service.dart';
import 'package:notchpeek/core/platform/channels.dart';
import 'package:notchpeek/shared/utils/enums/build_flavor.dart';
import 'package:notchpeek/shared/utils/enums/capability_state.dart';

/// The single source of truth for what this build, this OS and these
/// permissions can do (architecture-playbook §4.4). The probe reports **OS
/// availability as well as permission state** — that is what makes a panel's
/// absence expressible rather than merely disabled.
class Capabilities extends Equatable {
  const Capabilities({
    this.buildFlavor = BuildFlavor.direct,
    this.osSupportsOnDeviceAI = false,
    this.appleMusic = CapabilityState.notDetermined,
    this.spotify = CapabilityState.notDetermined,
    this.systemWideMediaRead = false,
    this.systemWideMediaCommand = false,
    this.calendar = CapabilityState.notDetermined,
    this.camera = CapabilityState.notDetermined,
  });

  final BuildFlavor buildFlavor;

  /// macOS 26+, for M4's AI panel.
  final bool osSupportsOnDeviceAI;

  final CapabilityState appleMusic;
  final CapabilityState spotify;

  /// False on macOS 26. Kept so it flips if Apple reopens the read path
  /// (spike §4.4).
  final bool systemWideMediaRead;
  final bool systemWideMediaCommand;

  final CapabilityState calendar; // M2
  final CapabilityState camera; // M3

  factory Capabilities.fromMap(Map<String, Object?> json) {
    final scripting = (json['scriptingMedia'] as Map?)?.cast<String, Object?>() ?? const {};
    return Capabilities(
      buildFlavor: BuildFlavor.fromApi(json['buildFlavor'] as String?),
      osSupportsOnDeviceAI: json['osSupportsOnDeviceAI'] as bool? ?? false,
      appleMusic: CapabilityState.fromApi(scripting['appleMusic'] as String?),
      spotify: CapabilityState.fromApi(scripting['spotify'] as String?),
      systemWideMediaRead: json['systemWideMediaRead'] as bool? ?? false,
      systemWideMediaCommand: json['systemWideMediaCommand'] as bool? ?? false,
      calendar: CapabilityState.fromApi(json['calendar'] as String?),
      camera: CapabilityState.fromApi(json['camera'] as String?),
    );
  }

  /// The music panel is ready if *either* player is. It is denied only when
  /// both are — one refused player is not a refusal of the feature.
  CapabilityState get music {
    if (appleMusic.isReady || spotify.isReady) return CapabilityState.granted;
    if (appleMusic == CapabilityState.denied && spotify == CapabilityState.denied) {
      return CapabilityState.denied;
    }
    if (appleMusic.isHidden && spotify.isHidden) return CapabilityState.absent;
    return CapabilityState.notDetermined;
  }

  bool get anyPlayerReady => music.isReady;

  @override
  List<Object?> get props => [
    buildFlavor, osSupportsOnDeviceAI, appleMusic, spotify,
    systemWideMediaRead, systemWideMediaCommand, calendar, camera,
  ];
}

/// Reports at launch and on change. Seeded from `getCapabilities` so the first
/// frame is not blank, then updated by every `capabilities` system event.
final capabilitiesProvider = StreamProvider<Capabilities>((ref) async* {
  final channels = ref.watch(channelServiceProvider);

  final seed = await channels.invoke<Map<Object?, Object?>>(
    ControlMethod.getCapabilities,
  );
  yield seed.status
      ? Capabilities.fromMap(Map<String, Object?>.from(seed.data!))
      : const Capabilities();

  yield* channels.systemEvents
      .where((e) => e[SystemEventKind.key] == SystemEventKind.capabilities)
      .map(Capabilities.fromMap);
});
```

- [ ] **Step 3: Add `setMediaPolling` to both channel files**

In `lib/core/platform/channels.dart`, inside `ControlMethod`:

```dart
  /// Not in spec §3.5. Added in M1 because §4's "poll at 1 Hz while expanded,
  /// and not at all while collapsed" needs a signal and none of the five
  /// carries it. Reconciled into the spec by the docs task.
  static const String setMediaPolling = 'setMediaPolling';
```

And the identical constant in `macos/Runner/Notch/Channels.swift`'s `ControlMethod`.

- [ ] **Step 4: Write the probe**

`macos/Runner/Notch/CapabilityProbe.swift`:

```swift
import AppKit
import AVFoundation
import EventKit

/// Answers what this build, this OS version and these permissions can do.
/// Nothing here decides what to *show* — that is a Dart decision.
enum CapabilityProbe {

    static func snapshot() -> [String: Any] {
        [
            "buildFlavor": buildFlavor,
            // The OS floor is macOS 26, so this is unconditionally true. The
            // field stays because M4 reads it and because a lowered floor
            // later must not change the payload's shape (R1).
            "osSupportsOnDeviceAI": true,
            "scriptingMedia": [
                "appleMusic": appleEventsState(for: "com.apple.Music"),
                "spotify": appleEventsState(for: "com.spotify.client"),
            ],
            // Gated on macOS 26: the info dictionary comes back empty, the
            // client is nil, no notifications fire — and it fails *silently*
            // (spike §1). Kept so it flips if Apple reopens the read path.
            "systemWideMediaRead": false,
            // Writes do land, but M1 commands through scripting (spec §2, §9).
            "systemWideMediaCommand": buildFlavor == "direct",
            "calendar": calendarState,
            "camera": cameraState,
        ]
    }

    /// M1 only ever builds `direct`. The MAS build differs in what it may call
    /// (spike §4.3), so the field exists from the start.
    static var buildFlavor: String { "direct" }

    /// `notDetermined` until the user has been asked, then `granted`/`denied`.
    /// An app that is not installed reports `absent` — a panel hides for that,
    /// rather than teasing a player the user does not have.
    static func appleEventsState(for bundleId: String) -> String {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil else {
            return "absent"
        }

        var target = AEAddressDesc()
        let bytes = Array(bundleId.utf8)
        let created = AECreateDesc(
            typeApplicationBundleID, bytes, bytes.count, &target
        )
        guard created == noErr else { return "notDetermined" }
        defer { AEDisposeDesc(&target) }

        // askUserIfNeeded: false — the probe must never prompt. Prompting is
        // `requestAppleEvents`'s job, and only on the user's action.
        switch AEDeterminePermissionToAutomateTarget(
            &target, typeWildCard, typeWildCard, false
        ) {
        case noErr: return "granted"
        case OSStatus(errAEEventNotPermitted): return "denied"
        case OSStatus(procNotFound): return "notDetermined"
        default: return "notDetermined"
        }
    }

    /// Prompts. Called only from the panel's "Open Settings" affordance.
    static func requestAppleEvents(for bundleId: String) {
        var target = AEAddressDesc()
        let bytes = Array(bundleId.utf8)
        guard AECreateDesc(typeApplicationBundleID, bytes, bytes.count, &target) == noErr else { return }
        defer { AEDisposeDesc(&target) }
        _ = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, true)
    }

    /// Opens the pane the user needs. macOS gives no API to un-deny.
    static func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }

    // M2 and M3 read these; they are reported from M1 so the shape never churns.

    private static var calendarState: String {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return "granted"
        case .denied, .restricted, .writeOnly: return "denied"
        default: return "notDetermined"
        }
    }

    private static var cameraState: String {
        guard AVCaptureDevice.default(for: .video) != nil else { return "absent" }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return "granted"
        case .denied, .restricted: return "denied"
        default: return "notDetermined"
        }
    }
}
```

- [ ] **Step 5: Answer `getCapabilities` and push changes**

In `AppDelegate.attach`, after `bridge.start()`:

```swift
        bridge.onGetCapabilities = { CapabilityProbe.snapshot() }

        bridge.onRequestPermission = { what in
            switch what {
            case "appleMusic": CapabilityProbe.requestAppleEvents(for: "com.apple.Music")
            case "spotify": CapabilityProbe.requestAppleEvents(for: "com.spotify.client")
            default: CapabilityProbe.openAutomationSettings()
            }
        }

        // Re-probe when the user comes back from System Settings.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak bridge] _ in
            bridge?.sendSystem(SystemEvent.capabilities, CapabilityProbe.snapshot())
        }
```

- [ ] **Step 6: Build, test, commit**

```bash
tool/add_xcode_file.sh Runner/Notch/CapabilityProbe.swift Runner
flutter test && flutter analyze && flutter build macos --debug
dart format .
git add -A lib test macos
git commit -m "feat(platform): probe build, OS and permission capabilities and stream them to Dart"
```

---

### Task 15: `MusicSource` — the protocol, and the unit normalization that is easy to get wrong

Spotify reports `duration` in **milliseconds** and `player position` in **fractional seconds**. The units disagree *within one source*. Normalize at the boundary and unit-test it — the spec names this specifically (spec §4, §8).

**Files:**
- Create: `macos/Runner/Notch/MusicSource.swift`
- Test: `macos/RunnerTests/MusicSourceTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct NowPlayingPayload: Equatable` — `sourceId`, `trackId`, `title`, `artist`, `album` (`String`), `duration`, `position` (`TimeInterval`), `state` (`String`), `artworkPath` (`String?`); `var channelMap: [String: Any]`
  - `protocol MusicSource: AnyObject` — `var sourceId: String`, `var bundleIdentifier: String`, `var isRunning: Bool`, `func read() -> NowPlayingPayload?`, `func send(command: String, seekTo: TimeInterval?)`
  - `enum MediaUnits` — `static func seconds(fromMilliseconds:) -> TimeInterval`, `static func clamp(position:duration:) -> TimeInterval`, `static func playbackState(fromFourCharCode:) -> String`

- [ ] **Step 1: Write the failing test**

`macos/RunnerTests/MusicSourceTests.swift`:

```swift
import XCTest
@testable import NotchPeek

final class MusicSourceTests: XCTestCase {

    func testConvertsSpotifysMillisecondDurationToSeconds() {
        XCTAssertEqual(MediaUnits.seconds(fromMilliseconds: 240_000), 240, accuracy: 0.001)
        XCTAssertEqual(MediaUnits.seconds(fromMilliseconds: 1), 0.001, accuracy: 0.0001)
        XCTAssertEqual(MediaUnits.seconds(fromMilliseconds: 0), 0)
    }

    func testClampsPositionIntoTheTrack() {
        XCTAssertEqual(MediaUnits.clamp(position: -3, duration: 200), 0)
        XCTAssertEqual(MediaUnits.clamp(position: 240, duration: 200), 200)
        XCTAssertEqual(MediaUnits.clamp(position: 61.5, duration: 200), 61.5, accuracy: 0.001)
    }

    /// A zero duration means "we could not read it". Clamping to it would
    /// report every track as finished.
    func testAZeroDurationDoesNotSwallowThePosition() {
        XCTAssertEqual(MediaUnits.clamp(position: 61.5, duration: 0), 61.5, accuracy: 0.001)
    }

    func testMapsThePlayerStateFourCharCodes() {
        XCTAssertEqual(MediaUnits.playbackState(fromFourCharCode: 0x6B505350), "playing")  // kPSP
        XCTAssertEqual(MediaUnits.playbackState(fromFourCharCode: 0x6B505370), "paused")   // kPSp
        XCTAssertEqual(MediaUnits.playbackState(fromFourCharCode: 0x6B505353), "stopped")  // kPSS
        XCTAssertEqual(MediaUnits.playbackState(fromFourCharCode: 0), "unknown")
    }

    func testChannelMapCarriesSecondsAsDoubles() {
        let payload = NowPlayingPayload(
            sourceId: "spotify",
            trackId: "spotify:track:abc",
            title: "Ada", artist: "Sonu Nigam", album: "Ada",
            duration: MediaUnits.seconds(fromMilliseconds: 240_000),
            position: 61.5,
            state: "playing",
            artworkPath: "/tmp/a.jpg"
        )

        let map = payload.channelMap
        XCTAssertEqual(map["durationSeconds"] as? Double, 240)
        XCTAssertEqual(map["positionSeconds"] as? Double, 61.5)
        XCTAssertEqual(map["trackId"] as? String, "spotify:track:abc")
        XCTAssertEqual(map["state"] as? String, "playing")
        XCTAssertEqual(map["sourceId"] as? String, "spotify")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
tool/add_xcode_file.sh RunnerTests/MusicSourceTests.swift RunnerTests
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -destination 'platform=macOS' -quiet
```
Expected: FAIL — `cannot find 'MediaUnits' in scope`.

- [ ] **Step 3: Write the module**

`macos/Runner/Notch/MusicSource.swift`:

```swift
import Foundation

/// One shape for Dart, whatever the source did. Times are **always seconds**;
/// artwork is **always a local file path**, never bytes and never a remote URL
/// (architecture-playbook §4.2).
struct NowPlayingPayload: Equatable {
    let sourceId: String
    /// Stable per track. The key for the artwork cache, and the thing that
    /// decides whether a peek fires.
    let trackId: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let position: TimeInterval
    let state: String
    let artworkPath: String?

    var channelMap: [String: Any] {
        var map: [String: Any] = [
            "sourceId": sourceId,
            "trackId": trackId,
            "title": title,
            "artist": artist,
            "album": album,
            "durationSeconds": duration,
            "positionSeconds": position,
            "state": state,
        ]
        if let artworkPath { map["artworkPath"] = artworkPath }
        return map
    }

    /// A tick carries no artwork. Artwork crosses once per track change; the
    /// tick fires about twice a second, and shipping an image through it would
    /// eat the app's whole CPU budget (spec §3.5).
    var tickMap: [String: Any] {
        [
            "sourceId": sourceId,
            "trackId": trackId,
            "positionSeconds": position,
            "state": state,
            "isTick": true,
        ]
    }
}

/// `MediaBridge` is the only thing that talks to these. The strategy choice —
/// which player, how it is read — hides behind this protocol.
protocol MusicSource: AnyObject {
    var sourceId: String { get }
    var bundleIdentifier: String { get }
    /// True only if the app is already running. **Never launch a player** to
    /// answer a question about it.
    var isRunning: Bool { get }
    /// Nil means *unavailable*, never *nothing playing* (spec §7).
    func read() -> NowPlayingPayload?
    func send(command: String, seekTo: TimeInterval?)
}

/// The normalizations that belong in Swift so Dart sees one shape. Every one
/// of these is a bug that has already been written somewhere.
enum MediaUnits {

    /// Spotify's `duration of current track` is milliseconds while its
    /// `player position` is fractional seconds. Same object, different units.
    static func seconds(fromMilliseconds ms: Double) -> TimeInterval {
        ms / 1000
    }

    /// A zero duration means "we could not read it" — clamping to it would
    /// report every track as finished.
    static func clamp(position: TimeInterval, duration: TimeInterval) -> TimeInterval {
        if position < 0 { return 0 }
        if duration > 0, position > duration { return duration }
        return position
    }

    /// Both players use the same `EPlS` four-char codes.
    static func playbackState(fromFourCharCode code: UInt32) -> String {
        switch code {
        case 0x6B50_5350: return "playing"  // 'kPSP'
        case 0x6B50_5370: return "paused"   // 'kPSp'
        case 0x6B50_5353: return "stopped"  // 'kPSS'
        default: return "unknown"
        }
    }
}
```

- [ ] **Step 4: Run the tests and commit**

```bash
tool/add_xcode_file.sh Runner/Notch/MusicSource.swift Runner
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -destination 'platform=macOS' -quiet
git add macos
git commit -m "feat(music): add the MusicSource protocol and the boundary unit normalization"
```

---

### Task 16: `SpotifySource` and `AppleMusicSource` — in-process ScriptingBridge, never `osascript`

Measured at ~130 ms per `osascript` round trip, which is process-spawn cost (spike §3). Both sources use in-process `SBApplication` with KVC access, so no generated headers and no Objective-C bridging header are needed — and nothing of theirs is transcribed (R9).

**Files:**
- Create: `macos/Runner/Notch/ScriptingSource.swift`, `macos/Runner/Notch/SpotifySource.swift`, `macos/Runner/Notch/AppleMusicSource.swift`, `macos/Runner/Notch/ArtworkCache.swift`

**Interfaces:**
- Consumes: `MusicSource`, `NowPlayingPayload`, `MediaUnits` (Task 15), `CapabilityProbe.appleEventsState` (Task 14).
- Produces:
  - `class ScriptingSource: MusicSource` — shared base holding the `SBApplication` and the KVC helpers
  - `final class SpotifySource: ScriptingSource`, `final class AppleMusicSource: ScriptingSource`
  - `enum ArtworkCache` with `static func path(forTrackId:) -> String?`, `static func store(data:forTrackId:) -> String?`, `static func download(url:forTrackId:completion:)`, `static func prune(keeping:)`

- [ ] **Step 1: Write the shared base**

`macos/Runner/Notch/ScriptingSource.swift`:

```swift
import AppKit
import ScriptingBridge

/// Shared machinery for the two scripted players. Holds the `SBApplication`
/// and reads properties by key, so no generated `sdef` headers are needed and
/// nothing of the players' own interfaces is transcribed into this repo (R9).
///
/// **Every call here must run off the main thread.** `MediaBridge` owns that
/// queue; this class does not hop for you.
class ScriptingSource: MusicSource {

    let sourceId: String
    let bundleIdentifier: String

    init(sourceId: String, bundleIdentifier: String) {
        self.sourceId = sourceId
        self.bundleIdentifier = bundleIdentifier
    }

    /// Never launches the player: `SBApplication` would happily start it, and
    /// an app that opens Spotify because you looked at the notch is a bug.
    var isRunning: Bool {
        !NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .isEmpty
    }

    private var app: SBApplication? {
        guard isRunning else { return nil }
        let app = SBApplication(bundleIdentifier: bundleIdentifier)
        // A hung player must not hang the poll.
        app?.timeout = 2 * 60 // ticks; 2 seconds
        app?.sendMode = .waitForReply
        return app
    }

    func read() -> NowPlayingPayload? {
        guard let app else { return nil }
        return read(from: app)
    }

    /// Overridden per player.
    func read(from app: SBApplication) -> NowPlayingPayload? { nil }

    func send(command: String, seekTo: TimeInterval?) {
        guard let app else { return }
        switch command {
        case "playPause": app.perform(Selector(("playpause")))
        case "next": app.perform(Selector(("nextTrack")))
        case "previous": app.perform(Selector(("previousTrack")))
        case "seek":
            guard let seekTo else { return }
            app.setValue(seekTo, forKey: positionKey)
        default: break
        }
    }

    /// Spotify calls it `playerPosition`; Music calls it `playerPosition` too,
    /// but the override point stays for the next source that does not.
    var positionKey: String { "playerPosition" }

    // MARK: - KVC helpers

    func string(_ object: NSObject?, _ key: String) -> String {
        (object?.value(forKey: key) as? String) ?? ""
    }

    func double(_ object: NSObject?, _ key: String) -> Double {
        (object?.value(forKey: key) as? NSNumber)?.doubleValue ?? 0
    }

    func fourCharCode(_ object: NSObject?, _ key: String) -> UInt32 {
        (object?.value(forKey: key) as? NSNumber)?.uint32Value ?? 0
    }

    func object(_ object: NSObject?, _ key: String) -> NSObject? {
        object?.value(forKey: key) as? NSObject
    }
}
```

- [ ] **Step 2: Write `SpotifySource`**

`macos/Runner/Notch/SpotifySource.swift`:

```swift
import ScriptingBridge

/// Reads Spotify. Every field the music panel needs is in its scripting
/// dictionary, including artwork — as a URL, not bytes (spike §3).
final class SpotifySource: ScriptingSource {

    init() {
        super.init(sourceId: "spotify", bundleIdentifier: "com.spotify.client")
    }

    override func read(from app: SBApplication) -> NowPlayingPayload? {
        guard let track = object(app, "currentTrack") else { return nil }

        let trackId = string(track, "id")
        guard !trackId.isEmpty else { return nil }

        // The unit trap, in one place: duration is milliseconds, position is
        // fractional seconds, on the same object.
        let duration = MediaUnits.seconds(fromMilliseconds: double(track, "duration"))
        let position = MediaUnits.clamp(
            position: double(app, "playerPosition"),
            duration: duration
        )

        // Artwork is a URL here. Resolving it to a file is the cache's job, and
        // it happens once per track id — never on a tick.
        let artwork = ArtworkCache.resolve(
            trackId: trackId,
            remoteURL: string(track, "artworkUrl")
        )

        return NowPlayingPayload(
            sourceId: sourceId,
            trackId: trackId,
            title: string(track, "name"),
            artist: string(track, "artist"),
            album: string(track, "album"),
            duration: duration,
            position: position,
            state: MediaUnits.playbackState(fromFourCharCode: fourCharCode(app, "playerState")),
            artworkPath: artwork
        )
    }
}
```

- [ ] **Step 3: Write `AppleMusicSource`**

`macos/Runner/Notch/AppleMusicSource.swift`:

```swift
import Foundation
import ScriptingBridge

/// Reads Apple Music. Times are already seconds here; artwork arrives as
/// **bytes**, so the cache writes it out and hands Dart the same file-path
/// shape Spotify's URL ends up as.
///
/// **Not covered by spike 0** — the spike machine's library was empty, so
/// `current track` errored with -1700. This path needs a manual check on a
/// machine with a library or an active subscription (spike §3).
final class AppleMusicSource: ScriptingSource {

    init() {
        super.init(sourceId: "appleMusic", bundleIdentifier: "com.apple.Music")
    }

    override func read(from app: SBApplication) -> NowPlayingPayload? {
        guard let track = object(app, "currentTrack") else { return nil }

        // Music's persistent id is stable across launches; `databaseID` is not
        // unique for streamed tracks, so fall back to a composed key.
        var trackId = string(track, "persistentID")
        if trackId.isEmpty {
            trackId = "\(string(track, "name"))|\(string(track, "artist"))|\(string(track, "album"))"
        }
        guard trackId != "||" else { return nil }

        let duration = double(track, "duration") // already seconds
        let position = MediaUnits.clamp(
            position: double(app, "playerPosition"),
            duration: duration
        )

        let artwork = ArtworkCache.resolve(
            trackId: trackId,
            data: firstArtworkData(of: track)
        )

        return NowPlayingPayload(
            sourceId: sourceId,
            trackId: trackId,
            title: string(track, "name"),
            artist: string(track, "artist"),
            album: string(track, "album"),
            duration: duration,
            position: position,
            state: MediaUnits.playbackState(fromFourCharCode: fourCharCode(app, "playerState")),
            artworkPath: artwork
        )
    }

    /// Only called when the cache misses — pulling image bytes across Apple
    /// Events is the most expensive read in the app.
    private func firstArtworkData(of track: NSObject) -> Data? {
        guard let artworks = track.value(forKey: "artworks") as? SBElementArray,
              let first = artworks.firstObject as? NSObject,
              let data = first.value(forKey: "rawData") as? Data,
              !data.isEmpty
        else { return nil }
        return data
    }
}
```

- [ ] **Step 4: Write the artwork cache**

`macos/Runner/Notch/ArtworkCache.swift`:

```swift
import Foundation
import CryptoKit

/// One artwork shape for Dart: a local file path, keyed by track id. Spotify
/// gives a URL and Apple Music gives bytes; both end up here (spec §4).
///
/// Swift owns storage. Dart never touches persistence
/// (architecture-playbook §4.2).
enum ArtworkCache {

    private static let queue = DispatchQueue(label: "com.capcraft.notchpeek.artwork")

    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("com.capcraft.notchpeek/artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(for trackId: String) -> URL? {
        // Track ids contain colons and slashes. Hash rather than sanitize.
        let digest = SHA256.hash(data: Data(trackId.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory?.appendingPathComponent("\(name).img")
    }

    static func cachedPath(forTrackId trackId: String) -> String? {
        guard let url = fileURL(for: trackId),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url.path
    }

    /// Spotify's path: a remote URL. Returns the cached path immediately if we
    /// have it, and otherwise nil while the download runs — **never block the
    /// track update on the image** (spec §7).
    @discardableResult
    static func resolve(trackId: String, remoteURL: String) -> String? {
        if let hit = cachedPath(forTrackId: trackId) { return hit }
        guard !remoteURL.isEmpty, let url = URL(string: remoteURL) else { return nil }

        queue.async {
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { return }
            store(data: data, forTrackId: trackId)
            onArtworkReady?(trackId)
        }
        return nil
    }

    /// Apple Music's path: raw bytes, already in hand.
    @discardableResult
    static func resolve(trackId: String, data: Data?) -> String? {
        if let hit = cachedPath(forTrackId: trackId) { return hit }
        guard let data, !data.isEmpty else { return nil }
        return store(data: data, forTrackId: trackId)
    }

    /// Set by `MediaBridge`: a late-arriving download re-emits the track so the
    /// panel swaps its placeholder for the real image.
    static var onArtworkReady: ((String) -> Void)?

    @discardableResult
    static func store(data: Data, forTrackId trackId: String) -> String? {
        guard let url = fileURL(for: trackId) else { return nil }
        try? data.write(to: url, options: .atomic)
        return url.path
    }

    /// Keeps the cache from growing without bound over a long session.
    static func prune(keeping limit: Int = 200) {
        queue.async {
            guard let directory,
                  let files = try? FileManager.default.contentsOfDirectory(
                      at: directory,
                      includingPropertiesForKeys: [.contentAccessDateKey]
                  ), files.count > limit
            else { return }

            let sorted = files.sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate) ?? .distantPast
                return a < b
            }
            for url in sorted.prefix(files.count - limit) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
```

- [ ] **Step 5: Register and build**

```bash
for f in ScriptingSource SpotifySource AppleMusicSource ArtworkCache; do
  tool/add_xcode_file.sh "Runner/Notch/$f.swift" Runner
done
flutter build macos --debug
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -destination 'platform=macOS' -quiet
```
Expected: builds clean, existing tests still pass. There is nothing to hand-check yet — `MediaBridge` in Task 17 is what calls these.

- [ ] **Step 6: Commit**

```bash
git add macos
git commit -m "feat(music): read Apple Music and Spotify in-process and normalize artwork to one file shape"
```

---

### Task 17: `MediaBridge` — pick a source, tick while it matters, command it

The only module with an internal strategy choice, and that choice hides behind `MusicSource` (spec §3.4).

**Files:**
- Create: `macos/Runner/Notch/MediaBridge.swift`
- Modify: `macos/Runner/Notch/ChannelBridge.swift` (handle `setMediaPolling`), `macos/Runner/AppDelegate.swift`
- Test: `macos/RunnerTests/MediaBridgeTests.swift`

**Interfaces:**
- Consumes: `MusicSource`, `NowPlayingPayload` (Task 15), `SpotifySource`/`AppleMusicSource`/`ArtworkCache` (Task 16).
- Produces:
  - `final class MediaBridge` — `init(sources: [MusicSource])`, `func start()`, `func stop()`, `var onUpdate: (([String: Any]) -> Void)?`, `func setPolling(_ enabled: Bool)`, `func command(_ payload: [String: Any])`, `func refresh()`
  - `static func select(from sources: [MusicSource]) -> MusicSource?`

- [ ] **Step 1: Write the failing test**

`macos/RunnerTests/MediaBridgeTests.swift`:

```swift
import XCTest
@testable import NotchPeek

private final class StubSource: MusicSource {
    let sourceId: String
    let bundleIdentifier = "stub"
    var isRunning: Bool
    var payload: NowPlayingPayload?
    var sent: [(String, TimeInterval?)] = []

    init(sourceId: String, isRunning: Bool, state: String?) {
        self.sourceId = sourceId
        self.isRunning = isRunning
        if let state {
            payload = NowPlayingPayload(
                sourceId: sourceId, trackId: "\(sourceId)-1", title: "t",
                artist: "a", album: "b", duration: 100, position: 10,
                state: state, artworkPath: nil
            )
        }
    }

    func read() -> NowPlayingPayload? { payload }
    func send(command: String, seekTo: TimeInterval?) { sent.append((command, seekTo)) }
}

final class MediaBridgeTests: XCTestCase {

    func testPrefersASourceThatIsActuallyPlaying() {
        let music = StubSource(sourceId: "appleMusic", isRunning: true, state: "paused")
        let spotify = StubSource(sourceId: "spotify", isRunning: true, state: "playing")

        XCTAssertEqual(MediaBridge.select(from: [music, spotify])?.sourceId, "spotify")
    }

    func testFallsBackToARunningButPausedSource() {
        let music = StubSource(sourceId: "appleMusic", isRunning: true, state: "paused")
        let spotify = StubSource(sourceId: "spotify", isRunning: false, state: nil)

        XCTAssertEqual(MediaBridge.select(from: [music, spotify])?.sourceId, "appleMusic")
    }

    func testIgnoresSourcesThatAreNotRunning() {
        let music = StubSource(sourceId: "appleMusic", isRunning: false, state: "playing")

        XCTAssertNil(MediaBridge.select(from: [music]))
    }

    /// An empty read means *unavailable*, never *nothing playing* — the
    /// macOS 26 wall fails silently, and this is exactly where it would be
    /// misdiagnosed (spike §2, spec §7).
    func testARunningSourceThatReadsNothingIsNotSelected() {
        let music = StubSource(sourceId: "appleMusic", isRunning: true, state: nil)

        XCTAssertNil(MediaBridge.select(from: [music]))
    }

    func testRoutesACommandToTheActiveSource() {
        let spotify = StubSource(sourceId: "spotify", isRunning: true, state: "playing")
        let bridge = MediaBridge(sources: [spotify])

        bridge.command(["command": "seek", "seconds": 42.0])

        XCTAssertEqual(spotify.sent.count, 1)
        XCTAssertEqual(spotify.sent.first?.0, "seek")
        XCTAssertEqual(spotify.sent.first?.1, 42)
    }

    func testAnUnknownCommandIsIgnoredRatherThanCrashing() {
        let spotify = StubSource(sourceId: "spotify", isRunning: true, state: "playing")
        let bridge = MediaBridge(sources: [spotify])

        bridge.command(["command": "selfDestruct"])

        XCTAssertEqual(spotify.sent.count, 1)
        XCTAssertEqual(spotify.sent.first?.0, "selfDestruct", "routing is the bridge's job; validation is the source's")
    }

    func testEmitsAFullPayloadOnTrackChangeAndATickOtherwise() {
        let spotify = StubSource(sourceId: "spotify", isRunning: true, state: "playing")
        let bridge = MediaBridge(sources: [spotify])

        var emitted: [[String: Any]] = []
        bridge.onUpdate = { emitted.append($0) }

        bridge.refresh()
        bridge.refresh()

        XCTAssertEqual(emitted.count, 2)
        XCTAssertNil(emitted[0]["isTick"], "the first read of a track is a full payload")
        XCTAssertEqual(emitted[1]["isTick"] as? Bool, true, "the same track again is a tick")
    }

    func testEmitsAnUnavailablePayloadWhenNoSourceCanBeRead() {
        let bridge = MediaBridge(sources: [StubSource(sourceId: "spotify", isRunning: false, state: nil)])

        var emitted: [[String: Any]] = []
        bridge.onUpdate = { emitted.append($0) }

        bridge.refresh()

        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(emitted[0]["available"] as? Bool, false)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
tool/add_xcode_file.sh RunnerTests/MediaBridgeTests.swift RunnerTests
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -destination 'platform=macOS' -quiet
```
Expected: FAIL — `cannot find 'MediaBridge' in scope`.

- [ ] **Step 3: Write the module**

`macos/Runner/Notch/MediaBridge.swift`:

```swift
import AppKit

/// Selects the active player, emits now-playing updates, and routes transport
/// commands. Holds no product logic: it does not decide what the panel shows.
final class MediaBridge {

    private let sources: [MusicSource]
    /// Every scripting call runs here. **Never on the main thread**
    /// (architecture-playbook §4.3).
    private let queue = DispatchQueue(label: "com.capcraft.notchpeek.media")
    private var ticker: DispatchSourceTimer?
    private var lastTrackId: String?
    private var observers: [NSObjectProtocol] = []

    var onUpdate: (([String: Any]) -> Void)?

    init(sources: [MusicSource]) {
        self.sources = sources
    }

    convenience init() {
        self.init(sources: [AppleMusicSource(), SpotifySource()])
    }

    /// A source that is *playing* wins. Otherwise any running source that can
    /// actually be read. A running source whose read comes back empty is
    /// **unavailable**, not idle (spec §7).
    static func select(from sources: [MusicSource]) -> MusicSource? {
        let readable = sources.filter { $0.isRunning && $0.read() != nil }
        return readable.first { $0.read()?.state == "playing" } ?? readable.first
    }

    func start() {
        // Track changes arrive as distributed notifications, so a collapsed
        // notch costs nothing and still peeks (spec §9, playbook §4.3).
        for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            observers.append(
                DistributedNotificationCenter.default().addObserver(
                    forName: Notification.Name(name), object: nil, queue: nil
                ) { [weak self] _ in
                    self?.queue.async { self?.refresh() }
                }
            )
        }

        ArtworkCache.onArtworkReady = { [weak self] trackId in
            guard let self, self.lastTrackId == trackId else { return }
            // Force the next emit to be a full payload so the panel picks up
            // the image that just landed.
            self.lastTrackId = nil
            self.queue.async { self.refresh() }
        }

        queue.async { [weak self] in self?.refresh() }
    }

    func stop() {
        setPolling(false)
        observers.forEach(DistributedNotificationCenter.default().removeObserver)
        observers.removeAll()
    }

    /// Poll at 1 Hz while the panel is showing, and not at all while it is
    /// collapsed. Position polling is the single most expensive thing the app
    /// does (spike §3).
    func setPolling(_ enabled: Bool) {
        ticker?.cancel()
        ticker = nil
        guard enabled else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.refresh() }
        timer.resume()
        ticker = timer
    }

    func command(_ payload: [String: Any]) {
        guard let command = payload["command"] as? String else { return }
        let seconds = payload["seconds"] as? Double

        queue.async { [weak self] in
            guard let self, let source = MediaBridge.select(from: self.sources) else { return }
            source.send(command: command, seekTo: seconds)
            // Read straight back so the UI does not wait a tick to catch up.
            self.refresh()
        }
    }

    /// Reads the active source once and emits. Full payload on a track change,
    /// a tick otherwise — **artwork never crosses on a tick** (spec §3.5).
    func refresh() {
        guard let source = MediaBridge.select(from: sources),
              let payload = source.read()
        else {
            lastTrackId = nil
            onUpdate?(["available": false])
            return
        }

        if payload.trackId != lastTrackId {
            lastTrackId = payload.trackId
            var map = payload.channelMap
            map["available"] = true
            map["trackChanged"] = true
            onUpdate?(map)
            ArtworkCache.prune()
        } else {
            var map = payload.tickMap
            map["available"] = true
            onUpdate?(map)
        }
    }

    deinit { stop() }
}
```

- [ ] **Step 4: Handle `setMediaPolling` on the bridge and wire it up**

In `ChannelBridge.handle`, add before `default`:

```swift
        case ControlMethod.setMediaPolling:
            let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
            onSetMediaPolling?(enabled)
            result(true)
```

with `var onSetMediaPolling: ((Bool) -> Void)?` alongside the other handlers.

In `AppDelegate.attach`:

```swift
        let media = MediaBridge()
        media.onUpdate = { [weak bridge] payload in bridge?.sendMedia(payload) }
        media.start()
        mediaBridge = media

        bridge.onMediaCommand = { [weak media] payload in media?.command(payload) }
        bridge.onSetMediaPolling = { [weak media] enabled in media?.setPolling(enabled) }
```

with `var mediaBridge: MediaBridge?` as a stored property.

- [ ] **Step 5: Run the tests**

```bash
tool/add_xcode_file.sh Runner/Notch/MediaBridge.swift Runner
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -destination 'platform=macOS' -quiet
```
Expected: 8 new tests PASS.

- [ ] **Step 6: Commit**

```bash
git add macos
git commit -m "feat(music): select the active player, tick at 1 Hz only while showing, route commands"
```

---

### Task 18: The music feature in Dart

**Files:**
- Create: `lib/features/music/domain/entities/now_playing.dart`, `domain/repositories/music_repository.dart`, `domain/usecases/watch_now_playing.dart`, `domain/usecases/send_media_command.dart`, `domain/usecases/set_media_polling.dart`
- Create: `lib/features/music/data/models/now_playing_model.dart`, `data/datasources/music_datasource.dart`, `data/repositories/music_repository_impl.dart`
- Create: `lib/features/music/presentation/music_providers.dart`, `presentation/notifier/music_notifier.dart`
- Test: `test/features/music/now_playing_model_test.dart`, `test/features/music/music_notifier_test.dart`

**Interfaces:**
- Consumes: `ChannelService` (Task 7), `PlaybackState`/`MusicSourceId`/`MediaCommand` (Task 4), `shellNotifierProvider` (Task 11).
- Produces:
  - `class NowPlaying extends Equatable` — `available` (`bool`), `source` (`MusicSourceId`), `trackId`, `title`, `artist`, `album` (`String`), `duration`, `position` (`Duration`), `state` (`PlaybackState`), `artworkPath` (`String?`); getters `bool get hasTrack`, `double get progress`, `bool get canSeek`; `NowPlaying.unavailable()`; `NowPlaying mergeTick(NowPlaying tick)`
  - `NowPlayingModel.toEntity(Map<String, Object?>) → NowPlaying`, `static bool isTick(Map<String, Object?>)`
  - `abstract class MusicRepository` — `Stream<NowPlaying> watch()`, `Future<ApiResponse<bool>> command(MediaCommand, {Duration? seekTo})`, `Future<ApiResponse<bool>> setPolling(bool)`
  - `class MusicNotifier extends Notifier<NowPlaying>` with `void playPause()`, `void next()`, `void previous()`, `void seek(Duration)`
  - providers: `musicDataSourceProvider`, `musicRepositoryProvider`, `watchNowPlayingProvider`, `sendMediaCommandProvider`, `setMediaPollingProvider`, `nowPlayingProvider` (`StreamProvider<NowPlaying>`), `musicNotifierProvider`, `mediaPollingProvider`

- [ ] **Step 1: Write the failing tests**

`test/features/music/now_playing_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/features/music/data/models/now_playing_model.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/shared/utils/enums/music_source_id.dart';
import 'package:notchpeek/shared/utils/enums/playback_state.dart';

const _full = <String, Object?>{
  'available': true,
  'trackChanged': true,
  'sourceId': 'spotify',
  'trackId': 'spotify:track:abc',
  'title': 'Ada',
  'artist': 'Sonu Nigam',
  'album': 'Ada',
  'durationSeconds': 240.0,
  'positionSeconds': 61.5,
  'state': 'playing',
  'artworkPath': '/tmp/a.jpg',
};

void main() {
  test('parses a full payload', () {
    final track = NowPlayingModel.toEntity(_full);

    expect(track.available, isTrue);
    expect(track.source, MusicSourceId.spotify);
    expect(track.title, 'Ada');
    expect(track.duration, const Duration(seconds: 240));
    expect(track.position, const Duration(milliseconds: 61500));
    expect(track.state, PlaybackState.playing);
    expect(track.artworkPath, '/tmp/a.jpg');
    expect(track.hasTrack, isTrue);
  });

  test('an unavailable payload is not the same as nothing playing', () {
    final track = NowPlayingModel.toEntity(const {'available': false});

    expect(track.available, isFalse);
    expect(track.hasTrack, isFalse);
    expect(track.state, PlaybackState.unknown);
  });

  test('recognises a tick and keeps everything the tick does not carry', () {
    expect(NowPlayingModel.isTick(const {'isTick': true}), isTrue);
    expect(NowPlayingModel.isTick(_full), isFalse);

    final full = NowPlayingModel.toEntity(_full);
    final tick = NowPlayingModel.toEntity(const {
      'available': true, 'isTick': true, 'sourceId': 'spotify',
      'trackId': 'spotify:track:abc', 'positionSeconds': 90.0, 'state': 'paused',
    });

    final merged = full.mergeTick(tick);

    expect(merged.title, 'Ada', reason: 'the tick carries no title');
    expect(merged.artworkPath, '/tmp/a.jpg', reason: 'artwork never crosses on a tick');
    expect(merged.position, const Duration(seconds: 90));
    expect(merged.state, PlaybackState.paused);
  });

  test('a tick for a different track is not merged in', () {
    final full = NowPlayingModel.toEntity(_full);
    final other = NowPlayingModel.toEntity(const {
      'available': true, 'isTick': true, 'trackId': 'other', 'positionSeconds': 5.0,
    });

    expect(full.mergeTick(other), full);
  });

  test('progress is a fraction, and a zero duration does not divide by zero', () {
    expect(NowPlayingModel.toEntity(_full).progress, closeTo(0.256, 0.001));

    final noDuration = NowPlayingModel.toEntity(const {
      'available': true, 'trackId': 'x', 'positionSeconds': 10.0, 'durationSeconds': 0.0,
    });
    expect(noDuration.progress, 0);
    expect(noDuration.canSeek, isFalse);
  });

  test('a malformed payload degrades rather than throwing', () {
    final track = NowPlayingModel.toEntity(const {'available': true, 'title': 42});

    expect(track.title, isEmpty);
    expect(track.hasTrack, isFalse);
  });
}
```

`test/features/music/music_notifier_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/features/music/domain/repositories/music_repository.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/shared/utils/enums/media_command.dart';

class _RecordingMusicRepository implements MusicRepository {
  final List<(MediaCommand, Duration?)> commands = [];
  final List<bool> polling = [];

  @override
  Stream<NowPlaying> watch() => const Stream.empty();

  @override
  Future<ApiResponse<bool>> command(MediaCommand cmd, {Duration? seekTo}) async {
    commands.add((cmd, seekTo));
    return ApiResponse.success(message: 'OK', data: true);
  }

  @override
  Future<ApiResponse<bool>> setPolling(bool enabled) async {
    polling.add(enabled);
    return ApiResponse.success(message: 'OK', data: true);
  }
}

ProviderContainer _container(_RecordingMusicRepository repo) {
  final c = ProviderContainer(
    overrides: [musicRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('each control sends exactly one command', () async {
    final repo = _RecordingMusicRepository();
    final notifier = _container(repo).read(musicNotifierProvider.notifier);

    notifier.playPause();
    notifier.next();
    notifier.previous();
    notifier.seek(const Duration(seconds: 42));
    await Future<void>.delayed(Duration.zero);

    expect(repo.commands.map((c) => c.$1).toList(), [
      MediaCommand.playPause, MediaCommand.next,
      MediaCommand.previous, MediaCommand.seek,
    ]);
    expect(repo.commands.last.$2, const Duration(seconds: 42));
  });

  test('polling follows whether the shell is showing anything', () async {
    final repo = _RecordingMusicRepository();
    final c = _container(repo);

    c.read(mediaPollingProvider.notifier).set(true);
    c.read(mediaPollingProvider.notifier).set(true);
    c.read(mediaPollingProvider.notifier).set(false);
    await Future<void>.delayed(Duration.zero);

    expect(repo.polling, [true, false], reason: 'no redundant channel calls');
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/features/music/` → FAIL, nothing exists.

- [ ] **Step 3: Write the entity and model**

`lib/features/music/domain/entities/now_playing.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:notchpeek/shared/utils/enums/music_source_id.dart';
import 'package:notchpeek/shared/utils/enums/playback_state.dart';

class NowPlaying extends Equatable {
  const NowPlaying({
    required this.available,
    this.source = MusicSourceId.none,
    this.trackId = '',
    this.title = '',
    this.artist = '',
    this.album = '',
    this.duration = Duration.zero,
    this.position = Duration.zero,
    this.state = PlaybackState.unknown,
    this.artworkPath,
  });

  /// **False means the read failed, not that nothing is playing.** The
  /// macOS 26 wall fails silently, so this distinction is the difference
  /// between a needs-permission panel and a lying empty one (spec §7).
  final bool available;

  final MusicSourceId source;
  final String trackId;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final Duration position;
  final PlaybackState state;

  /// Always a local file path. Swift resolved Spotify's URL and Apple Music's
  /// bytes to the same shape before it crossed.
  final String? artworkPath;

  const NowPlaying.unavailable() : this(available: false);

  bool get hasTrack => available && trackId.isNotEmpty && title.isNotEmpty;
  bool get canSeek => duration > Duration.zero;
  double get progress => canSeek
      ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
      : 0;

  /// A tick carries position and state only. Everything else is kept.
  NowPlaying mergeTick(NowPlaying tick) {
    if (tick.trackId != trackId) return this;
    return copyWith(
      position: tick.position,
      state: tick.state,
      available: tick.available,
    );
  }

  NowPlaying copyWith({
    bool? available,
    MusicSourceId? source,
    String? trackId,
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    Duration? position,
    PlaybackState? state,
    String? artworkPath,
  }) => NowPlaying(
    available: available ?? this.available,
    source: source ?? this.source,
    trackId: trackId ?? this.trackId,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    album: album ?? this.album,
    duration: duration ?? this.duration,
    position: position ?? this.position,
    state: state ?? this.state,
    artworkPath: artworkPath ?? this.artworkPath,
  );

  @override
  List<Object?> get props => [
    available, source, trackId, title, artist, album,
    duration, position, state, artworkPath,
  ];
}
```

`lib/features/music/data/models/now_playing_model.dart`:

```dart
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/shared/utils/enums/music_source_id.dart';
import 'package:notchpeek/shared/utils/enums/playback_state.dart';

abstract final class NowPlayingModel {
  static bool isTick(Map<String, Object?> json) => json['isTick'] == true;

  static NowPlaying toEntity(Map<String, Object?> json) {
    if (json['available'] != true) return const NowPlaying.unavailable();

    return NowPlaying(
      available: true,
      source: MusicSourceId.fromApi(json['sourceId'] as String?),
      trackId: json['trackId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String? ?? '',
      duration: _duration(json['durationSeconds']),
      position: _duration(json['positionSeconds']),
      state: PlaybackState.fromApi(json['state'] as String?),
      artworkPath: json['artworkPath'] as String?,
    );
  }

  static Duration _duration(Object? seconds) => Duration(
    milliseconds: (((seconds as num?)?.toDouble() ?? 0) * 1000).round(),
  );
}
```

- [ ] **Step 4: Write the repository, datasource, usecases and notifier**

`lib/features/music/domain/repositories/music_repository.dart`:

```dart
import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/shared/utils/enums/media_command.dart';

abstract class MusicRepository {
  Stream<NowPlaying> watch();
  Future<ApiResponse<bool>> command(MediaCommand command, {Duration? seekTo});
  Future<ApiResponse<bool>> setPolling(bool enabled);
}
```

`lib/features/music/data/datasources/music_datasource.dart`:

```dart
import 'package:notchpeek/core/logging/notch_logger.dart';
import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/core/platform/channel_service.dart';
import 'package:notchpeek/core/platform/channels.dart';
import 'package:notchpeek/shared/utils/enums/media_command.dart';

abstract class MusicDataSource {
  Stream<Map<String, Object?>> watchMediaEvents();
  Future<ApiResponse<bool>> command(MediaCommand command, {Duration? seekTo});
  Future<ApiResponse<bool>> setPolling(bool enabled);
}

class MusicDataSourceImpl implements MusicDataSource {
  MusicDataSourceImpl(this._channels);

  final ChannelService _channels;
  final NotchLogger _log = NotchLogger.forTag('MusicDataSourceImpl');

  @override
  Stream<Map<String, Object?>> watchMediaEvents() => _channels.mediaEvents;

  /// Logs ids and states, never titles — a track name is user content
  /// (architecture-playbook §6).
  @override
  Future<ApiResponse<bool>> command(MediaCommand command, {Duration? seekTo}) async {
    final result = await _channels.invoke<bool>(ControlMethod.mediaCommand, {
      'command': command.apiValue,
      if (seekTo != null) 'seconds': seekTo.inMilliseconds / 1000,
    });
    if (result.status) {
      _log.success(command.apiValue);
    } else {
      _log.error('${command.apiValue} failed: ${result.message}');
    }
    return result;
  }

  @override
  Future<ApiResponse<bool>> setPolling(bool enabled) =>
      _channels.invoke<bool>(ControlMethod.setMediaPolling, {'enabled': enabled});
}
```

`lib/features/music/data/repositories/music_repository_impl.dart`:

```dart
import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/music/data/datasources/music_datasource.dart';
import 'package:notchpeek/features/music/data/models/now_playing_model.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/features/music/domain/repositories/music_repository.dart';
import 'package:notchpeek/shared/utils/enums/media_command.dart';

class MusicRepositoryImpl implements MusicRepository {
  MusicRepositoryImpl(this._source);

  final MusicDataSource _source;

  /// Folds ticks into the last full payload here, so nothing above this layer
  /// has to know that two payload shapes exist.
  @override
  Stream<NowPlaying> watch() async* {
    var current = const NowPlaying.unavailable();

    await for (final event in _source.watchMediaEvents()) {
      final parsed = NowPlayingModel.toEntity(event);
      current = NowPlayingModel.isTick(event) ? current.mergeTick(parsed) : parsed;
      yield current;
    }
  }

  @override
  Future<ApiResponse<bool>> command(MediaCommand command, {Duration? seekTo}) =>
      _source.command(command, seekTo: seekTo);

  @override
  Future<ApiResponse<bool>> setPolling(bool enabled) => _source.setPolling(enabled);
}
```

`lib/features/music/domain/usecases/watch_now_playing.dart`, `send_media_command.dart`, `set_media_polling.dart` — each a one-method wrapper in the same shape as Task 8's:

```dart
class WatchNowPlaying {
  const WatchNowPlaying(this._repository);
  final MusicRepository _repository;
  Stream<NowPlaying> call() => _repository.watch();
}

class SendMediaCommand {
  const SendMediaCommand(this._repository);
  final MusicRepository _repository;
  Future<ApiResponse<bool>> call(MediaCommand command, {Duration? seekTo}) =>
      _repository.command(command, seekTo: seekTo);
}

class SetMediaPolling {
  const SetMediaPolling(this._repository);
  final MusicRepository _repository;
  Future<ApiResponse<bool>> call(bool enabled) => _repository.setPolling(enabled);
}
```

`lib/features/music/presentation/notifier/music_notifier.dart`:

```dart
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/shared/utils/enums/media_command.dart';

/// Commands only. The *state* of the music comes from `nowPlayingProvider`;
/// this notifier exists so widgets call a named method rather than reaching
/// for a usecase themselves (architecture-playbook §2).
class MusicNotifier extends Notifier<NowPlaying> {
  @override
  NowPlaying build() =>
      ref.watch(nowPlayingProvider).valueOrNull ?? const NowPlaying.unavailable();

  void playPause() => _send(MediaCommand.playPause);
  void next() => _send(MediaCommand.next);
  void previous() => _send(MediaCommand.previous);
  void seek(Duration to) => _send(MediaCommand.seek, seekTo: to);

  void _send(MediaCommand command, {Duration? seekTo}) {
    ref.read(sendMediaCommandProvider)(command, seekTo: seekTo);
  }
}

/// Turns the 1 Hz native tick on and off, and never repeats itself — the shell
/// changes state far more often than polling needs to change.
class MediaPollingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool enabled) {
    if (state == enabled) return;
    state = enabled;
    ref.read(setMediaPollingProvider)(enabled);
  }
}
```

`lib/features/music/presentation/music_providers.dart`:

```dart
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/core/platform/channel_service.dart';
import 'package:notchpeek/features/music/data/datasources/music_datasource.dart';
import 'package:notchpeek/features/music/data/repositories/music_repository_impl.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/features/music/domain/repositories/music_repository.dart';
import 'package:notchpeek/features/music/domain/usecases/send_media_command.dart';
import 'package:notchpeek/features/music/domain/usecases/set_media_polling.dart';
import 'package:notchpeek/features/music/domain/usecases/watch_now_playing.dart';
import 'package:notchpeek/features/music/presentation/notifier/music_notifier.dart';

final musicDataSourceProvider = Provider<MusicDataSource>(
  (ref) => MusicDataSourceImpl(ref.watch(channelServiceProvider)),
);

final musicRepositoryProvider = Provider<MusicRepository>(
  (ref) => MusicRepositoryImpl(ref.watch(musicDataSourceProvider)),
);

final watchNowPlayingProvider = Provider<WatchNowPlaying>(
  (ref) => WatchNowPlaying(ref.watch(musicRepositoryProvider)),
);

final sendMediaCommandProvider = Provider<SendMediaCommand>(
  (ref) => SendMediaCommand(ref.watch(musicRepositoryProvider)),
);

final setMediaPollingProvider = Provider<SetMediaPolling>(
  (ref) => SetMediaPolling(ref.watch(musicRepositoryProvider)),
);

/// Watched even while collapsed: track changes arrive as distributed
/// notifications and are what fires the peek. The *tick* is what gets gated,
/// through [mediaPollingProvider].
final nowPlayingProvider = StreamProvider<NowPlaying>(
  (ref) => ref.watch(watchNowPlayingProvider)(),
);

final musicNotifierProvider = NotifierProvider<MusicNotifier, NowPlaying>(
  MusicNotifier.new,
);

final mediaPollingProvider = NotifierProvider<MediaPollingNotifier, bool>(
  MediaPollingNotifier.new,
);
```

- [ ] **Step 5: Run the tests and the gate**

Run: `flutter test && flutter analyze`
Expected: 8 new tests PASS, `No issues found!`.

- [ ] **Step 6: Commit**

```bash
dart format .
git add -A lib test
git commit -m "feat(music): add the now-playing feature slice with tick folding and command dispatch"
```

---

### Task 19: Shared widgets

Nine panels need the same three capability states; nine copies is nine bugs. The permission prompt is shared, not per-panel (architecture-playbook §8).

**Files:**
- Create: `lib/shared/widgets/panel_scaffold.dart`, `permission_prompt.dart`, `notch_icon_button.dart`, `marquee_text.dart`, `artwork_tile.dart`, `scrubber.dart`, `empty_state.dart`
- Test: `test/shared/widgets/shared_widgets_test.dart` (+ `goldens/`)

**Interfaces:**
- Consumes: `NotchColors`/`NotchRadii`/`NotchSizes` (Task 4), `formatClock` (Task 4).
- Produces:
  - `PanelScaffold({required Widget child, Widget? trailing, EdgeInsets padding})`
  - `PermissionPrompt({required String explanation, required String actionLabel, required VoidCallback onPressed})`
  - `NotchIconButton({required IconData icon, required VoidCallback? onPressed, double size, String? semanticLabel})`
  - `MarqueeText({required String text, required TextStyle style, double gap, Duration cycle})`
  - `ArtworkTile({required String? path, double side})`
  - `Scrubber({required double progress, required Duration position, required Duration duration, required ValueChanged<double>? onSeek})`
  - `EmptyState({required IconData icon, required String message})`

- [ ] **Step 1: Write the failing test**

`test/shared/widgets/shared_widgets_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/shared/widgets/artwork_tile.dart';
import 'package:notchpeek/shared/widgets/notch_icon_button.dart';
import 'package:notchpeek/shared/widgets/permission_prompt.dart';
import 'package:notchpeek/shared/widgets/scrubber.dart';

Widget _wrap(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: ColoredBox(color: const Color(0xFF0A0A0A), child: Center(child: child)),
);

void main() {
  testWidgets('the permission prompt explains and offers exactly one action', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(_wrap(PermissionPrompt(
      explanation: 'NotchPeek needs permission to read Apple Music.',
      actionLabel: 'Open Settings',
      onPressed: () => pressed++,
    )));

    expect(find.textContaining('needs permission'), findsOneWidget);
    await tester.tap(find.text('Open Settings'));
    expect(pressed, 1);
  });

  testWidgets('a disabled icon button does not fire', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(_wrap(NotchIconButton(
      icon: Icons.skip_next,
      semanticLabel: 'Next',
      onPressed: null,
    )));

    await tester.tap(find.byType(NotchIconButton));
    expect(pressed, 0);
  });

  testWidgets('the artwork tile falls back to a placeholder when there is no file', (tester) async {
    await tester.pumpWidget(_wrap(const ArtworkTile(path: null, side: 96)));

    expect(find.byIcon(Icons.music_note), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('the artwork tile falls back when the file is missing from disk', (tester) async {
    await tester.pumpWidget(_wrap(const ArtworkTile(path: '/does/not/exist.jpg', side: 96)));
    await tester.pump();

    expect(find.byIcon(Icons.music_note), findsOneWidget);
  });

  testWidgets('the scrubber shows both clocks and reports a seek fraction', (tester) async {
    double? seeked;
    await tester.pumpWidget(_wrap(SizedBox(
      width: 300,
      child: Scrubber(
        progress: 0.25,
        position: const Duration(seconds: 60),
        duration: const Duration(seconds: 240),
        onSeek: (v) => seeked = v,
      ),
    )));

    expect(find.text('1:00'), findsOneWidget);
    expect(find.text('4:00'), findsOneWidget);

    await tester.tapAt(tester.getCenter(find.byType(Slider)));
    expect(seeked, isNotNull);
  });

  testWidgets('a scrubber with no duration cannot be dragged', (tester) async {
    await tester.pumpWidget(_wrap(const SizedBox(
      width: 300,
      child: Scrubber(
        progress: 0,
        position: Duration.zero,
        duration: Duration.zero,
        onSeek: null,
      ),
    )));

    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
  });
}
```

- [ ] **Step 2: Run it and watch it fail, then write the widgets**

Run: `flutter test test/shared/widgets/` → FAIL.

`lib/shared/widgets/permission_prompt.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:notchpeek/app/theme.dart';

/// The **needs-permission** state, shared by every panel. Nine panels need the
/// same three states; nine copies is nine bugs (architecture-playbook §8).
class PermissionPrompt extends StatelessWidget {
  const PermissionPrompt({
    required this.explanation,
    required this.actionLabel,
    required this.onPressed,
    super.key,
  });

  final String explanation;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, color: NotchColors.secondaryText, size: 22),
          const SizedBox(height: 10),
          Text(
            explanation,
            textAlign: TextAlign.center,
            style: const TextStyle(color: NotchColors.secondaryText, fontSize: 12),
          ),
          const SizedBox(height: 12),
          _PromptButton(label: actionLabel, onPressed: onPressed),
        ],
      ),
    );
  }
}

class _PromptButton extends StatelessWidget {
  const _PromptButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: NotchColors.accent,
          borderRadius: BorderRadius.circular(NotchRadii.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Text(
            label,
            style: const TextStyle(color: NotchColors.primaryText, fontSize: 12),
          ),
        ),
      ),
    );
  }
}
```

`lib/shared/widgets/artwork_tile.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:notchpeek/app/theme.dart';

/// Always a local file — Swift resolved Spotify's URL and Apple Music's bytes
/// to one shape before it crossed. **Never blocks the track update on the
/// image** (spec §7): a missing or half-written file falls back silently.
class ArtworkTile extends StatelessWidget {
  const ArtworkTile({required this.path, this.side = NotchSizes.artworkSide, super.key});

  final String? path;
  final double side;

  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);

    return ClipRRect(
      borderRadius: BorderRadius.circular(NotchRadii.artwork),
      child: SizedBox.square(
        dimension: side,
        child: file != null && file.existsSync()
            ? Image.file(file, fit: BoxFit.cover, gaplessPlayback: true,
                errorBuilder: (_, _, _) => const _ArtworkPlaceholder())
            : const _ArtworkPlaceholder(),
      ),
    );
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: NotchColors.panelEdge,
    child: Center(
      child: Icon(Icons.music_note, color: NotchColors.secondaryText, size: 24),
    ),
  );
}
```

`lib/shared/widgets/scrubber.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/shared/utils/helpers/duration_format.dart';

/// Position, duration and a seek. `onSeek` receives a fraction in 0..1; a
/// track with no readable duration is not seekable, and says so by disabling.
class Scrubber extends StatelessWidget {
  const Scrubber({
    required this.progress,
    required this.position,
    required this.duration,
    required this.onSeek,
    super.key,
  });

  final double progress;
  final Duration position;
  final Duration duration;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(formatClock(position), style: _clockStyle),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: NotchColors.primaryText,
              inactiveTrackColor: NotchColors.trackInactive,
              thumbColor: NotchColors.primaryText,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(value: progress.clamp(0, 1), onChanged: onSeek),
          ),
        ),
        Text(formatClock(duration), style: _clockStyle),
      ],
    );
  }

  static const TextStyle _clockStyle = TextStyle(
    color: NotchColors.secondaryText,
    fontSize: 11,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
```

Add `import 'dart:ui' show FontFeature;`.

`lib/shared/widgets/notch_icon_button.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:notchpeek/app/theme.dart';

class NotchIconButton extends StatelessWidget {
  const NotchIconButton({
    required this.icon,
    required this.onPressed,
    this.size = 22,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      label: semanticLabel,
      button: true,
      enabled: enabled,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              icon,
              size: size,
              color: enabled ? NotchColors.primaryText : NotchColors.trackInactive,
            ),
          ),
        ),
      ),
    );
  }
}
```

`lib/shared/widgets/marquee_text.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Scrolls only when the text does not fit. A `HookWidget`, not a
/// `StatefulWidget` (architecture-playbook §9) — and everything it creates is
/// disposed in the hook.
class MarqueeText extends HookWidget {
  const MarqueeText({
    required this.text,
    required this.style,
    this.gap = 40,
    this.cycle = const Duration(seconds: 8),
    super.key,
  });

  final String text;
  final TextStyle style;
  final double gap;
  final Duration cycle;

  @override
  Widget build(BuildContext context) {
    final scroll = useScrollController();
    final controller = useAnimationController(duration: cycle);

    useEffect(() {
      controller.repeat();
      return null;
    }, [text, cycle]);

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
        )..layout();

        if (painter.width <= constraints.maxWidth) {
          return Text(text, style: style, maxLines: 1, overflow: TextOverflow.clip);
        }

        return ClipRect(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final offset = -(painter.width + gap) * controller.value;
              return Transform.translate(
                offset: Offset(offset, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(text, style: style, maxLines: 1),
                    SizedBox(width: gap),
                    Text(text, style: style, maxLines: 1),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
```

Remove the unused `scroll` hook if the analyzer flags it; it is not needed by this implementation.

`lib/shared/widgets/panel_scaffold.dart` and `empty_state.dart`:

```dart
/// panel_scaffold.dart — the common padding and layout every panel sits in.
class PanelScaffold extends StatelessWidget {
  const PanelScaffold({
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 12),
    super.key,
  });

  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: trailing == null
        ? child
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: child), trailing!],
          ),
  );
}

/// empty_state.dart
class EmptyState extends StatelessWidget {
  const EmptyState({required this.icon, required this.message, super.key});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon, color: NotchColors.secondaryText, size: 22),
      const SizedBox(height: 8),
      Text(message, style: const TextStyle(color: NotchColors.secondaryText, fontSize: 12)),
    ],
  );
}
```

- [ ] **Step 3: Run the tests and the gate**

Run: `flutter test test/shared/ && flutter analyze`
Expected: 6 tests PASS, `No issues found!`.

- [ ] **Step 4: Commit**

```bash
dart format .
git add -A lib test
git commit -m "feat(shared): add the panel scaffold, permission prompt and music controls"
```

---

### Task 20: The music panel, in all three capability states

**A panel with only a ready state is incomplete and will not pass review** (architecture-playbook §4.4).

**Files:**
- Create: `lib/features/music/presentation/widgets/music_panel.dart`
- Test: `test/features/music/music_panel_test.dart` (+ `goldens/`)

**Interfaces:**
- Consumes: `capabilitiesProvider` (Task 14), `nowPlayingProvider`/`musicNotifierProvider` (Task 18), shared widgets (Task 19), `channelServiceProvider` (Task 7).
- Produces: `class MusicPanel extends HookConsumerWidget` — `const MusicPanel({super.key})`.

- [ ] **Step 1: Write the failing test**

`test/features/music/music_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/core/platform/capabilities.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/features/music/presentation/widgets/music_panel.dart';
import 'package:notchpeek/shared/utils/enums/music_source_id.dart';
import 'package:notchpeek/shared/utils/enums/playback_state.dart';
import 'package:notchpeek/shared/widgets/permission_prompt.dart';

const _playing = NowPlaying(
  available: true,
  source: MusicSourceId.spotify,
  trackId: 'spotify:track:abc',
  title: 'Ada',
  artist: 'Sonu Nigam',
  album: 'Ada',
  duration: Duration(seconds: 240),
  position: Duration(seconds: 61),
  state: PlaybackState.playing,
);

Future<void> _pump(
  WidgetTester tester, {
  required Capabilities caps,
  required NowPlaying track,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        capabilitiesProvider.overrideWith((ref) => Stream.value(caps)),
        nowPlayingProvider.overrideWith((ref) => Stream.value(track)),
      ],
      child: const MaterialApp(
        home: Scaffold(backgroundColor: Color(0xFF0A0A0A), body: MusicPanel()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('ready: shows the track, the artist and working controls', (tester) async {
    await _pump(
      tester,
      caps: Capabilities.fromMap(const {'scriptingMedia': {'spotify': 'granted'}}),
      track: _playing,
    );

    expect(find.text('Ada'), findsWidgets);
    expect(find.text('Sonu Nigam'), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
  });

  testWidgets('ready but paused: offers play rather than pause', (tester) async {
    await _pump(
      tester,
      caps: Capabilities.fromMap(const {'scriptingMedia': {'spotify': 'granted'}}),
      track: _playing.copyWith(state: PlaybackState.paused),
    );

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('needs permission: explains and offers Open Settings', (tester) async {
    await _pump(
      tester,
      caps: Capabilities.fromMap(const {
        'scriptingMedia': {'appleMusic': 'denied', 'spotify': 'denied'},
      }),
      track: const NowPlaying.unavailable(),
    );

    expect(find.byType(PermissionPrompt), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('unavailable: renders nothing rather than teasing a feature', (tester) async {
    await _pump(
      tester,
      caps: Capabilities.fromMap(const {
        'scriptingMedia': {'appleMusic': 'absent', 'spotify': 'absent'},
      }),
      track: const NowPlaying.unavailable(),
    );

    expect(find.byType(PermissionPrompt), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  testWidgets('granted but nothing playing: an idle placeholder, not a prompt', (tester) async {
    await _pump(
      tester,
      caps: Capabilities.fromMap(const {'scriptingMedia': {'spotify': 'granted'}}),
      track: const NowPlaying(available: true),
    );

    expect(find.byType(PermissionPrompt), findsNothing);
    expect(find.textContaining('Nothing playing'), findsOneWidget);
  });

  testWidgets('golden: the three states', (tester) async {
    await _pump(
      tester,
      caps: Capabilities.fromMap(const {'scriptingMedia': {'spotify': 'granted'}}),
      track: _playing,
    );
    await expectLater(find.byType(MusicPanel), matchesGoldenFile('goldens/music_ready.png'));

    await _pump(
      tester,
      caps: Capabilities.fromMap(const {
        'scriptingMedia': {'appleMusic': 'denied', 'spotify': 'denied'},
      }),
      track: const NowPlaying.unavailable(),
    );
    await expectLater(find.byType(MusicPanel), matchesGoldenFile('goldens/music_denied.png'));

    await _pump(
      tester,
      caps: Capabilities.fromMap(const {'scriptingMedia': {'spotify': 'granted'}}),
      track: const NowPlaying(available: true),
    );
    await expectLater(find.byType(MusicPanel), matchesGoldenFile('goldens/music_idle.png'));
  });
}
```

- [ ] **Step 2: Run it and watch it fail, then write the panel**

Run: `flutter test test/features/music/music_panel_test.dart` → FAIL.

`lib/features/music/presentation/widgets/music_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/core/platform/capabilities.dart';
import 'package:notchpeek/core/platform/channel_service.dart';
import 'package:notchpeek/core/platform/channels.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/shared/utils/enums/capability_state.dart';
import 'package:notchpeek/shared/widgets/artwork_tile.dart';
import 'package:notchpeek/shared/widgets/empty_state.dart';
import 'package:notchpeek/shared/widgets/marquee_text.dart';
import 'package:notchpeek/shared/widgets/notch_icon_button.dart';
import 'package:notchpeek/shared/widgets/panel_scaffold.dart';
import 'package:notchpeek/shared/widgets/permission_prompt.dart';
import 'package:notchpeek/shared/widgets/scrubber.dart';

/// The only panel in M1. Renders three ways, always
/// (architecture-playbook §4.4).
class MusicPanel extends ConsumerWidget {
  const MusicPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capability = ref.watch(
      capabilitiesProvider.select((c) => c.valueOrNull?.music ?? CapabilityState.notDetermined),
    );

    return switch (capability) {
      // Hidden, never teased: neither player is installed.
      CapabilityState.absent => const SizedBox.shrink(),
      CapabilityState.denied || CapabilityState.notDetermined => PanelScaffold(
        child: PermissionPrompt(
          explanation:
              'NotchPeek needs permission to read what Apple Music and '
              'Spotify are playing.',
          actionLabel: 'Open Settings',
          onPressed: () => ref
              .read(channelServiceProvider)
              .invoke<bool>(ControlMethod.requestPermission, const {'what': 'automation'}),
        ),
      ),
      CapabilityState.granted => const _MusicReady(),
    };
  }
}

class _MusicReady extends ConsumerWidget {
  const _MusicReady();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(nowPlayingProvider).valueOrNull ?? const NowPlaying.unavailable();

    // A read that failed is *unavailable*, not idle — the macOS 26 wall is
    // silent, and this is where it would be misdiagnosed (spec §7).
    if (!track.available) {
      return const PanelScaffold(
        child: EmptyState(icon: Icons.headset_off, message: 'Player unavailable'),
      );
    }

    if (!track.hasTrack) {
      return const PanelScaffold(
        child: EmptyState(icon: Icons.music_note, message: 'Nothing playing'),
      );
    }

    return PanelScaffold(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ArtworkTile(path: track.artworkPath),
          const SizedBox(width: 14),
          Expanded(child: _TrackDetails(track: track)),
        ],
      ),
    );
  }
}

class _TrackDetails extends ConsumerWidget {
  const _TrackDetails({required this.track});

  final NowPlaying track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final music = ref.read(musicNotifierProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: 20,
          child: MarqueeText(
            text: track.title,
            style: const TextStyle(
              color: NotchColors.primaryText,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: NotchColors.secondaryText, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Scrubber(
          progress: track.progress,
          position: track.position,
          duration: track.duration,
          onSeek: track.canSeek
              ? (v) => music.seek(track.duration * v)
              : null,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            NotchIconButton(
              icon: Icons.skip_previous,
              semanticLabel: 'Previous',
              onPressed: music.previous,
            ),
            NotchIconButton(
              icon: track.state.isPlaying ? Icons.pause : Icons.play_arrow,
              size: 28,
              semanticLabel: track.state.isPlaying ? 'Pause' : 'Play',
              onPressed: music.playPause,
            ),
            NotchIconButton(
              icon: Icons.skip_next,
              semanticLabel: 'Next',
              onPressed: music.next,
            ),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: Generate the goldens, look at them, run everything**

```bash
flutter test --update-goldens test/features/music/music_panel_test.dart
open test/features/music/goldens/music_ready.png
flutter test && flutter analyze
```
Expected: 6 tests PASS.

- [ ] **Step 4: Commit**

```bash
dart format .
git add -A lib test
git commit -m "feat(music): render the music panel in all three capability states"
```

---

### Task 21: Tab strip, status row, and the shell finally has contents

**The tab strip renders a variable number of tabs from the start**, because M4's AI panel is absent below macOS 26 and a fixed tab count would have to be torn out later (spec §5).

**Files:**
- Create: `lib/features/shell/presentation/widgets/tab_strip.dart`, `status_row.dart`, `panel_host.dart`, `peek_content.dart`
- Modify: `lib/app/notch_app.dart`
- Test: `test/features/shell/tab_strip_test.dart` (+ `goldens/`)

**Interfaces:**
- Consumes: `shellNotifierProvider` (Task 11), `capabilitiesProvider` (Task 14), `MusicPanel` (Task 20), `nowPlayingProvider` (Task 18), `mediaPollingProvider` (Task 18).
- Produces:
  - `TabStrip({required List<PanelTab> tabs, required PanelTab selected, required ValueChanged<PanelTab> onSelected})`
  - `StatusRow()` — battery pill and source badge (battery lands in Task 22; renders the source badge only until then)
  - `PanelHost()` — the expanded content: tab strip plus the selected panel, and the thing that drives `mediaPollingProvider`
  - `PeekContent()` — the small peek body
  - `final visibleTabsProvider = Provider<List<PanelTab>>(...)`

- [ ] **Step 1: Write the failing test**

`test/features/shell/tab_strip_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/features/shell/presentation/widgets/tab_strip.dart';
import 'package:notchpeek/shared/utils/enums/panel_tab.dart';

Widget _wrap(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: ColoredBox(color: const Color(0xFF0A0A0A), child: child),
);

void main() {
  for (final count in [2, 3, 4]) {
    testWidgets('renders $count tabs without assuming a fixed count', (tester) async {
      final tabs = PanelTab.values.take(count).toList();

      await tester.pumpWidget(_wrap(TabStrip(
        tabs: tabs,
        selected: tabs.first,
        onSelected: (_) {},
      )));

      for (final tab in tabs) {
        expect(find.text(tab.label), findsOneWidget);
      }
    });
  }

  testWidgets('a single tab renders no strip at all', (tester) async {
    await tester.pumpWidget(_wrap(TabStrip(
      tabs: const [PanelTab.music],
      selected: PanelTab.music,
      onSelected: (_) {},
    )));

    expect(find.text(PanelTab.music.label), findsNothing);
  });

  testWidgets('tapping a tab reports it exactly once', (tester) async {
    final taps = <PanelTab>[];

    await tester.pumpWidget(_wrap(TabStrip(
      tabs: const [PanelTab.music, PanelTab.calendar],
      selected: PanelTab.music,
      onSelected: taps.add,
    )));

    await tester.tap(find.text(PanelTab.calendar.label));
    expect(taps, [PanelTab.calendar]);
  });

  testWidgets('golden: two, three and four tabs', (tester) async {
    for (final count in [2, 3, 4]) {
      final tabs = PanelTab.values.take(count).toList();
      await tester.pumpWidget(_wrap(SizedBox(
        width: 620,
        child: TabStrip(tabs: tabs, selected: tabs.first, onSelected: (_) {}),
      )));
      await expectLater(
        find.byType(TabStrip),
        matchesGoldenFile('goldens/tab_strip_$count.png'),
      );
    }
  });
}
```

- [ ] **Step 2: Run it and watch it fail, then write the widgets**

`lib/features/shell/presentation/widgets/tab_strip.dart`:

```dart
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
  const _Tab({required this.tab, required this.isSelected, required this.onTap});

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
            color: isSelected ? NotchColors.primaryText : NotchColors.secondaryText,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
```

`lib/features/shell/presentation/widgets/panel_host.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/core/platform/capabilities.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/features/music/presentation/widgets/music_panel.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';
import 'package:notchpeek/features/shell/presentation/widgets/status_row.dart';
import 'package:notchpeek/features/shell/presentation/widgets/tab_strip.dart';
import 'package:notchpeek/shared/utils/enums/capability_state.dart';
import 'package:notchpeek/shared/utils/enums/panel_tab.dart';

/// Which tabs this build, this OS and these permissions can actually show.
/// M1 has one candidate; the list is computed rather than hard-coded so M2–M4
/// only add entries.
final visibleTabsProvider = Provider<List<PanelTab>>((ref) {
  final caps = ref.watch(capabilitiesProvider).valueOrNull;
  return [
    if (caps == null || caps.music != CapabilityState.absent) PanelTab.music,
  ];
});

/// The expanded panel's contents. Also the one place that turns the native
/// 1 Hz position tick on and off — polling follows what is on screen, not what
/// is subscribed (spec §4).
class PanelHost extends HookConsumerWidget {
  const PanelHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shell = ref.watch(shellNotifierProvider);
    final tabs = ref.watch(visibleTabsProvider);

    useEffect(() {
      ref.read(mediaPollingProvider.notifier).set(shell.isExpanded);
      return null;
    }, [shell.isExpanded]);

    return Column(
      children: [
        TabStrip(
          tabs: tabs,
          selected: shell.tab,
          onSelected: ref.read(shellNotifierProvider.notifier).tabSelected,
        ),
        Expanded(
          child: switch (shell.tab) {
            PanelTab.music => const MusicPanel(),
            // M2–M4 add their panels here. Until then a tab that is not built
            // cannot be selected, because `visibleTabsProvider` does not offer it.
            _ => const SizedBox.shrink(),
          },
        ),
        const StatusRow(),
      ],
    );
  }
}
```

`lib/features/shell/presentation/widgets/status_row.dart` — the source badge now, the battery pill in Task 22:

```dart
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/shared/utils/enums/music_source_id.dart';

class StatusRow extends ConsumerWidget {
  const StatusRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(
      nowPlayingProvider.select((t) => t.valueOrNull?.source ?? MusicSourceId.none),
    );

    return SizedBox(
      height: 18,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            source == MusicSourceId.none ? '' : source.label,
            style: const TextStyle(color: NotchColors.secondaryText, fontSize: 10),
          ),
          const SizedBox.shrink(),
        ],
      ),
    );
  }
}
```

`lib/features/shell/presentation/widgets/peek_content.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';
import 'package:notchpeek/shared/widgets/artwork_tile.dart';
import 'package:notchpeek/shared/utils/enums/peek_kind.dart';

/// The peek body: small, one line, gone in four seconds.
class PeekContent extends ConsumerWidget {
  const PeekContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(shellNotifierProvider.select((s) => s.peek));
    final track = ref.watch(nowPlayingProvider).valueOrNull;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          if (kind == PeekKind.trackChange)
            ArtworkTile(path: track?.artworkPath, side: 26),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              switch (kind) {
                PeekKind.trackChange => track?.title ?? '',
                PeekKind.charger => 'Charging',
                null => '',
              },
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: NotchColors.primaryText, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Render the real contents from the shell**

In `lib/app/notch_app.dart`, change the shell's child:

```dart
      AsyncData(:final value) => NotchShell(
        geometry: value,
        child: const _ShellContent(),
      ),
```

and add:

```dart
/// The peek body and the full panel are different content, not the same
/// content at two sizes.
class _ShellContent extends ConsumerWidget {
  const _ShellContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expanded = ref.watch(shellNotifierProvider.select((s) => s.isExpanded));
    return expanded ? const PanelHost() : const PeekContent();
  }
}
```

- [ ] **Step 4: Generate goldens, run everything, then check by hand**

```bash
flutter test --update-goldens test/features/shell/tab_strip_test.dart
flutter test && flutter analyze
flutter run -d macos
```

Hand check — **this is exit criterion 4**, with Apple Music and Spotify each playing in turn:
1. Hover the notch: the panel opens showing the current track, artist, artwork and a moving scrubber.
2. Play, pause, next, previous all work, and the panel updates within about a second.
3. Drag the scrubber: the player seeks.
4. Collapse the panel and confirm with Activity Monitor that CPU drops — the 1 Hz tick has stopped.

- [ ] **Step 5: Commit**

```bash
dart format .
git add -A lib test
git commit -m "feat(shell): add the variable tab strip, status row and panel host"
```

---

### Task 22: `PowerBridge`, the battery pill, and the two peeks

The peek *mechanism* shipped in Task 11; this is the catalogue of events that fire it. M1 ships two: track change and charger connect (spec §9).

**Files:**
- Create: `macos/Runner/Notch/PowerBridge.swift`
- Create: `lib/features/shell/domain/entities/power_state.dart`, `lib/features/shell/data/models/power_state_model.dart`, `lib/features/shell/presentation/widgets/battery_pill.dart`, `lib/features/shell/presentation/peek_listener.dart`
- Modify: `lib/features/shell/data/datasources/shell_datasource.dart`, `lib/features/shell/data/repositories/shell_repository_impl.dart`, `lib/features/shell/domain/repositories/shell_repository.dart`, `lib/features/shell/presentation/shell_providers.dart`, `lib/features/shell/presentation/widgets/status_row.dart`, `lib/app/notch_app.dart`, `macos/Runner/AppDelegate.swift`
- Test: `test/features/shell/peek_listener_test.dart`, `test/features/shell/power_state_test.dart`

**Interfaces:**
- Consumes: `ChannelBridge.sendSystem` (Task 7), `shellNotifierProvider` (Task 11), `nowPlayingProvider` (Task 18).
- Produces:
  - Swift `final class PowerBridge` — `init(onChange: @escaping ([String: Any]) -> Void)`, `func start()`, `func stop()`
  - Dart `class PowerState extends Equatable` — `percent` (`int`), `isCharging` (`bool`), `isPresent` (`bool`)
  - `powerProvider` (`StreamProvider<PowerState>`), `BatteryPill()`
  - `PeekListener()` — a widget that watches for the two peek triggers and calls `peekRequested`

- [ ] **Step 1: Write the failing Dart tests**

`test/features/shell/power_state_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/features/shell/data/models/power_state_model.dart';

void main() {
  test('parses a battery payload', () {
    final power = PowerStateModel.toEntity(const {
      'percent': 84, 'isCharging': true, 'isPresent': true,
    });

    expect(power.percent, 84);
    expect(power.isCharging, isTrue);
    expect(power.isPresent, isTrue);
  });

  test('a desktop Mac reports no battery rather than 0%', () {
    final power = PowerStateModel.toEntity(const {'isPresent': false});

    expect(power.isPresent, isFalse);
    expect(power.percent, 0);
  });

  test('clamps a nonsense percentage into range', () {
    expect(PowerStateModel.toEntity(const {'percent': 140, 'isPresent': true}).percent, 100);
    expect(PowerStateModel.toEntity(const {'percent': -5, 'isPresent': true}).percent, 0);
  });
}
```

`test/features/shell/peek_listener_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/features/shell/domain/entities/power_state.dart';
import 'package:notchpeek/features/shell/presentation/peek_listener.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';
import 'package:notchpeek/shared/utils/enums/notch_state.dart';
import 'package:notchpeek/shared/utils/enums/peek_kind.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Stream<NowPlaying> tracks,
  Stream<PowerState> power,
) async {
  final container = ProviderContainer(overrides: [
    nowPlayingProvider.overrideWith((ref) => tracks),
    powerProvider.overrideWith((ref) => power),
    peekDwellProvider.overrideWithValue(const Duration(seconds: 30)),
  ]);
  addTearDown(container.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const PeekListener(child: SizedBox.shrink()),
  ));
  return container;
}

void main() {
  testWidgets('a new track id peeks', (tester) async {
    final controller = StreamController<NowPlaying>();
    final c = await _pump(tester, controller.stream, const Stream.empty());

    controller.add(const NowPlaying(available: true, trackId: 'a', title: 'A'));
    await tester.pump();
    controller.add(const NowPlaying(available: true, trackId: 'b', title: 'B'));
    await tester.pump();

    expect(c.read(shellNotifierProvider).state, NotchState.peeking);
    expect(c.read(shellNotifierProvider).peek, PeekKind.trackChange);
  });

  testWidgets('the very first track does not peek — that is just startup', (tester) async {
    final controller = StreamController<NowPlaying>();
    final c = await _pump(tester, controller.stream, const Stream.empty());

    controller.add(const NowPlaying(available: true, trackId: 'a', title: 'A'));
    await tester.pump();

    expect(c.read(shellNotifierProvider).state, NotchState.collapsed);
  });

  testWidgets('a position tick on the same track does not peek', (tester) async {
    final controller = StreamController<NowPlaying>();
    final c = await _pump(tester, controller.stream, const Stream.empty());

    controller.add(const NowPlaying(available: true, trackId: 'a', title: 'A'));
    await tester.pump();
    controller.add(const NowPlaying(
      available: true, trackId: 'a', title: 'A', position: Duration(seconds: 5),
    ));
    await tester.pump();

    expect(c.read(shellNotifierProvider).state, NotchState.collapsed);
  });

  testWidgets('plugging the charger in peeks; unplugging does not', (tester) async {
    final controller = StreamController<PowerState>();
    final c = await _pump(tester, const Stream.empty(), controller.stream);

    controller.add(const PowerState(percent: 50, isCharging: false, isPresent: true));
    await tester.pump();
    controller.add(const PowerState(percent: 50, isCharging: true, isPresent: true));
    await tester.pump();
    expect(c.read(shellNotifierProvider).peek, PeekKind.charger);

    c.read(shellNotifierProvider.notifier).peekExpired();
    controller.add(const PowerState(percent: 51, isCharging: false, isPresent: true));
    await tester.pump();
    expect(c.read(shellNotifierProvider).state, NotchState.collapsed);
  });
}
```

Add `import 'dart:async';` for `StreamController`.

- [ ] **Step 2: Run them and watch them fail, then write the Swift side**

`macos/Runner/Notch/PowerBridge.swift`:

```swift
import Foundation
import IOKit.ps

/// Battery percentage and the charging edge. Cheap: IOKit posts a run-loop
/// source when anything changes, so there is no polling here at all.
final class PowerBridge {

    private let onChange: ([String: Any]) -> Void
    private var runLoopSource: CFRunLoopSource?
    private var last: [String: Any]?

    init(onChange: @escaping ([String: Any]) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard runLoopSource == nil else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerBridge>.fromOpaque(context).takeUnretainedValue().emit()
        }, context)?.takeRetainedValue() else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
        emit()
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
    }

    private func emit() {
        let snapshot = PowerBridge.snapshot()
        // IOKit fires for things we do not care about. Only report changes.
        guard !NSDictionary(dictionary: snapshot).isEqual(to: last ?? [:]) else { return }
        last = snapshot
        onChange(snapshot)
    }

    /// A Mac with no battery reports `isPresent: false` rather than 0% — a
    /// desktop is not a laptop that is flat.
    static func snapshot() -> [String: Any] {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let description = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any]
        else {
            return ["isPresent": false, "percent": 0, "isCharging": false]
        }

        let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
        let percent = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : 0

        return [
            "isPresent": true,
            "percent": percent,
            "isCharging": (description[kIOPSIsChargingKey] as? Bool) ?? false,
        ]
    }

    deinit { stop() }
}
```

Wire it in `AppDelegate.attach`:

```swift
        let power = PowerBridge { [weak bridge] payload in
            bridge?.sendSystem(SystemEvent.power, payload)
        }
        power.start()
        powerBridge = power
```

with `var powerBridge: PowerBridge?`.

- [ ] **Step 3: Write the Dart side**

`lib/features/shell/domain/entities/power_state.dart`:

```dart
import 'package:equatable/equatable.dart';

class PowerState extends Equatable {
  const PowerState({
    required this.percent,
    required this.isCharging,
    required this.isPresent,
  });

  final int percent;
  final bool isCharging;

  /// False on a desktop Mac. A machine with no battery is not a machine with
  /// an empty one.
  final bool isPresent;

  bool get isLow => isPresent && !isCharging && percent <= 20;

  @override
  List<Object?> get props => [percent, isCharging, isPresent];
}
```

`lib/features/shell/data/models/power_state_model.dart`:

```dart
import 'package:notchpeek/features/shell/domain/entities/power_state.dart';

abstract final class PowerStateModel {
  static PowerState toEntity(Map<String, Object?> json) => PowerState(
    percent: ((json['percent'] as num?)?.toInt() ?? 0).clamp(0, 100),
    isCharging: json['isCharging'] as bool? ?? false,
    isPresent: json['isPresent'] as bool? ?? false,
  );
}
```

Extend `ShellDataSource` / `ShellRepository` with `watchPowerEvents()` / `watchPower()` in exactly the shape geometry already uses, filtering on `SystemEventKind.power`, and add:

```dart
final powerProvider = StreamProvider<PowerState>(
  (ref) => ref.watch(shellRepositoryProvider).watchPower(),
);
```

`lib/features/shell/presentation/widgets/battery_pill.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/app/theme.dart';
import 'package:notchpeek/features/shell/domain/entities/power_state.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';

/// Hidden entirely on a Mac with no battery.
class BatteryPill extends ConsumerWidget {
  const BatteryPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final power = ref.watch(powerProvider).valueOrNull;
    if (power == null || !power.isPresent) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Meter(power: power),
        const SizedBox(width: 5),
        Text(
          '${power.percent}%',
          style: const TextStyle(color: NotchColors.secondaryText, fontSize: 10),
        ),
      ],
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.power});

  final PowerState power;

  @override
  Widget build(BuildContext context) {
    final fill = power.percent / 100;
    final color = power.isCharging
        ? NotchColors.positive
        : power.isLow
        ? NotchColors.warning
        : NotchColors.primaryText;

    return SizedBox(
      width: 22,
      height: 11,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: NotchColors.trackInactive),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fill.clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

Put `const BatteryPill()` in `StatusRow`'s trailing slot, replacing the `SizedBox.shrink()`.

`lib/features/shell/presentation/peek_listener.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/features/music/presentation/music_providers.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';
import 'package:notchpeek/shared/utils/enums/peek_kind.dart';

/// Watches for the events that deserve a peek and asks the shell for one.
/// Wraps the tree rather than living inside a panel, because peeks fire while
/// the panel is collapsed and nothing is mounted.
class PeekListener extends ConsumerWidget {
  const PeekListener({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A track *change*, not the first track we ever see: at launch there is
    // always a "new" track, and peeking at startup would be noise.
    ref.listen(
      nowPlayingProvider.select((t) => t.valueOrNull?.trackId),
      (previous, next) {
        if (previous == null || next == null) return;
        if (previous == next || next.isEmpty) return;
        ref.read(shellNotifierProvider.notifier).peekRequested(PeekKind.trackChange);
      },
    );

    // The charging *edge*. Unplugging is not an event worth interrupting for.
    ref.listen(
      powerProvider.select((p) => p.valueOrNull?.isCharging),
      (previous, next) {
        if (previous == null || next == null) return;
        if (previous == false && next == true) {
          ref.read(shellNotifierProvider.notifier).peekRequested(PeekKind.charger);
        }
      },
    );

    return child;
  }
}
```

Wrap the shell in `lib/app/notch_app.dart`: `PeekListener(child: NotchShell(...))`.

- [ ] **Step 4: Run everything, then check by hand**

```bash
tool/add_xcode_file.sh Runner/Notch/PowerBridge.swift Runner
flutter test && flutter analyze && flutter run -d macos
```

Hand check — **exit criterion 3**:
1. Skip a track in Spotify with the panel collapsed: the notch peeks with the new title and retracts on its own after about four seconds.
2. Plug the charger in: the notch peeks with "Charging".
3. Unplug it: **no peek**.
4. Open the panel: the battery pill shows a plausible percentage and turns green while charging.

- [ ] **Step 5: Commit**

```bash
dart format .
git add -A lib test macos
git commit -m "feat(shell): report battery from IOKit and peek on track change and charger connect"
```

---

### Task 23: The settings window and launch at login

Flutter desktop multi-window is young; a second Flutter engine for a settings pane is cost with no benefit. The settings window is native SwiftUI (spec §2).

**Files:**
- Create: `macos/Runner/Notch/SettingsWindow.swift`, `macos/Runner/Notch/LoginItem.swift`
- Modify: `macos/Runner/AppDelegate.swift`

**Interfaces:**
- Consumes: `ChannelBridge.onOpenSettings` (Task 7), `CapabilityProbe` (Task 14).
- Produces:
  - `final class SettingsWindowController` — `func show()`
  - `enum LoginItem` — `static var isEnabled: Bool { get }`, `static func setEnabled(_ enabled: Bool)`

- [ ] **Step 1: Write the login item helper**

`macos/Runner/Notch/LoginItem.swift`:

```swift
import ServiceManagement

/// Launch at login, via the modern registration — no helper bundle, no
/// `SMLoginItemSetEnabled`, no login-items plist to leave behind.
enum LoginItem {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("NotchPeek: login item change failed: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 2: Write the settings window**

`macos/Runner/Notch/SettingsWindow.swift`:

```swift
import AppKit
import SwiftUI

/// One native window, created lazily and reused. Not a Flutter route: this app
/// has no router and one panel (architecture-playbook §9).
final class SettingsWindowController {

    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "NotchPeek Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        window.makeKeyAndOrderFront(nil)
        // An agent app is not active by default; without this the window opens
        // behind whatever the user was doing.
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SettingsView: View {
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var capabilities = CapabilityProbe.snapshot()

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LoginItem.setEnabled(newValue)
                    }
            }

            Section("Permissions") {
                PermissionRow(name: "Apple Music", state: scripting("appleMusic"))
                PermissionRow(name: "Spotify", state: scripting("spotify"))
                Button("Open Automation Settings") {
                    CapabilityProbe.openAutomationSettings()
                }
            }

            Section {
                Button("Quit NotchPeek") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 300)
        .onAppear { capabilities = CapabilityProbe.snapshot() }
    }

    private func scripting(_ key: String) -> String {
        (capabilities["scriptingMedia"] as? [String: String])?[key] ?? "notDetermined"
    }
}

private struct PermissionRow: View {
    let name: String
    let state: String

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Text(label)
                .foregroundStyle(state == "granted" ? .green : .secondary)
        }
    }

    private var label: String {
        switch state {
        case "granted": return "Allowed"
        case "denied": return "Denied"
        case "absent": return "Not installed"
        default: return "Not asked"
        }
    }
}
```

- [ ] **Step 3: Wire it up and enable launch at login on first run**

In `AppDelegate`:

```swift
    let settingsWindow = SettingsWindowController()

    // in attach(...)
        bridge.onOpenSettings = { [weak self] in
            DispatchQueue.main.async { self?.settingsWindow.show() }
        }

        // Register on first launch only, so a user who turns it off in the
        // settings window stays off.
        if !UserDefaults.standard.bool(forKey: "loginItemConfigured") {
            LoginItem.setEnabled(true)
            UserDefaults.standard.set(true, forKey: "loginItemConfigured")
        }
```

- [ ] **Step 4: Build and check by hand**

```bash
tool/add_xcode_file.sh Runner/Notch/LoginItem.swift Runner
tool/add_xcode_file.sh Runner/Notch/SettingsWindow.swift Runner
flutter build macos --debug
flutter run -d macos
```

Hand check — **exit criterion 8**:
1. From Dart, invoke `openSettings` (temporarily wire it to a tap on the source badge, or call it from the debug console) — the window opens **in front**.
2. The launch-at-login toggle is on, and appears under System Settings → General → Login Items.
3. Turning it off removes it there.
4. The permission rows show the real state for both players.
5. Quit works.

- [ ] **Step 5: Commit**

```bash
git add macos
git commit -m "feat(settings): add the native SwiftUI settings window and launch at login"
```

---

# Week 3 — Hardening, and the two measurements

R3's week 3 originally carried hardening *and* release engineering. Release engineering is out of this plan entirely (R7, and the user's decision), so this week is hardening, the memory baseline, and reconciling the docs with what was actually built.

---

### Task 24: Survive a Space switch, a fullscreen app, and a display unplugged mid-expand

**Exit criterion 7**, and the failure that is most likely to be discovered by a user rather than by us.

**Files:**
- Modify: `macos/Runner/Notch/NotchWindowController.swift`, `macos/Runner/AppDelegate.swift`, `lib/app/notch_app.dart`, `lib/features/shell/presentation/shell_providers.dart`
- Create: `lib/features/shell/presentation/geometry_listener.dart`
- Test: `test/features/shell/geometry_listener_test.dart`

**Interfaces:**
- Consumes: `geometryProvider` (Task 8), `shellNotifierProvider` (Task 11), `NotchGeometryObserver` (Task 6).
- Produces: `GeometryListener({required Widget child})` — forces a collapse whenever the geometry changes underneath an open panel.

- [ ] **Step 1: Write the failing test**

`test/features/shell/geometry_listener_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/features/shell/domain/entities/notch_geometry.dart';
import 'package:notchpeek/features/shell/presentation/geometry_listener.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';
import 'package:notchpeek/shared/utils/enums/notch_state.dart';

const _builtIn = NotchGeometry(
  screenWidth: 1470, screenHeight: 956, notchWidth: 300, notchHeight: 32,
  notchLeft: 585, scale: 2, isVirtual: false,
);
const _external = NotchGeometry(
  screenWidth: 2560, screenHeight: 1440, notchWidth: 200, notchHeight: 32,
  notchLeft: 1180, scale: 2, isVirtual: true,
);

void main() {
  testWidgets('a geometry change while expanded forces a collapse', (tester) async {
    final controller = StreamController<NotchGeometry>();
    final c = ProviderContainer(overrides: [
      geometryProvider.overrideWith((ref) => controller.stream),
      peekDwellProvider.overrideWithValue(const Duration(seconds: 30)),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const GeometryListener(child: SizedBox.shrink()),
    ));

    controller.add(_builtIn);
    await tester.pump();

    c.read(shellNotifierProvider.notifier).hoverEntered();
    expect(c.read(shellNotifierProvider).state, NotchState.expanded);

    controller.add(_external);
    await tester.pump();

    expect(c.read(shellNotifierProvider).state, NotchState.collapsed);
  });

  testWidgets('an identical geometry event does not collapse an open panel', (tester) async {
    final controller = StreamController<NotchGeometry>();
    final c = ProviderContainer(overrides: [
      geometryProvider.overrideWith((ref) => controller.stream),
      peekDwellProvider.overrideWithValue(const Duration(seconds: 30)),
    ]);
    addTearDown(c.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const GeometryListener(child: SizedBox.shrink()),
    ));

    controller.add(_builtIn);
    await tester.pump();
    c.read(shellNotifierProvider.notifier).hoverEntered();
    controller.add(_builtIn);
    await tester.pump();

    expect(c.read(shellNotifierProvider).state, NotchState.expanded);
  });
}
```

- [ ] **Step 2: Write the listener**

`lib/features/shell/presentation/geometry_listener.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:notchpeek/features/shell/presentation/shell_providers.dart';

/// Display disconnected mid-expand, resolution changed, Space switched to
/// another screen: the panel's own rect is now wrong, so collapse and let the
/// user reopen it in the right place (spec §7).
///
/// Riverpod's `select` on the whole entity means an identical re-emit does
/// nothing — the observer already de-duplicates, this is belt and braces.
class GeometryListener extends ConsumerWidget {
  const GeometryListener({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(geometryProvider, (previous, next) {
      final before = previous?.valueOrNull;
      final after = next.valueOrNull;
      if (before == null || after == null || before == after) return;
      ref.read(shellNotifierProvider.notifier).forceCollapse();
    });

    return child;
  }
}
```

Wrap the shell with it in `lib/app/notch_app.dart`, outside `PeekListener`.

- [ ] **Step 3: Follow the active screen on the native side**

In `NotchWindowController`, add:

```swift
    /// Re-assert the window level and collection behavior after a Space or
    /// fullscreen transition. macOS occasionally drops a borderless panel
    /// behind a fullscreen window otherwise.
    func reassert() {
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        panel.orderFrontRegardless()
    }
```

and call it from the geometry observer's callback in `AppDelegate.attach`, right after `reposition(for:)`.

- [ ] **Step 4: Run everything, then the hand matrix**

```bash
flutter test && flutter analyze && flutter run -d macos
```

**Manual matrix** (spec §8) — record the result of each in the commit message:

| Case | Expected |
|---|---|
| Notched built-in display | Panel hides inside the hardware notch at rest |
| Non-notched external display, lid closed | Virtual notch, centred, identical behavior |
| Both displays connected | Panel lives on the notched one |
| Space switch while collapsed | Panel present on the new Space |
| Space switch while **expanded** | Panel collapses, then works normally |
| Fullscreen app | Panel still reachable |
| **Unplug the external display mid-expand** | Panel collapses, reappears correctly positioned |
| Light vs dark menu bar | Panel is opaque near-black in both; no seam |

- [ ] **Step 5: Commit**

```bash
dart format .
git add -A lib test macos
git commit -m "fix(shell): collapse on geometry change and re-assert window level after Space and fullscreen transitions"
```

---

### Task 25: The iTunes artwork fallback

The one endpoint this app has. Used only when neither player hands us an image — **never blocks the track update** (spec §7).

**Files:**
- Create: `lib/features/music/data/datasources/artwork_remote_datasource.dart`, `lib/features/music/domain/usecases/fetch_artwork_fallback.dart`
- Modify: `lib/features/music/presentation/music_providers.dart`, `lib/shared/widgets/artwork_tile.dart`
- Test: `test/features/music/artwork_fallback_test.dart`

**Interfaces:**
- Consumes: `ApiService`/`ApiEndpoint` (Task 3), `NowPlaying` (Task 18).
- Produces:
  - `abstract class ArtworkRemoteDataSource { Future<String?> lookup({required String artist, required String album}); }` + `Impl`
  - `class FetchArtworkFallback { Future<String?> call(NowPlaying track); }`
  - `final artworkFallbackProvider = FutureProviderFamily<String?, String>(...)` keyed by `'artist|album'`

- [ ] **Step 1: Write the failing test**

`test/features/music/artwork_fallback_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:notchpeek/core/network/errors/api_response.dart';
import 'package:notchpeek/features/music/data/datasources/artwork_remote_datasource.dart';

class _StubApiService implements ApiServiceContract {
  _StubApiService(this.response);

  final ApiResponse<Map<String, dynamic>> response;
  final List<Map<String, dynamic>> queries = [];

  @override
  Future<ApiResponse<Map<String, dynamic>>> get(String path, {Map<String, dynamic>? queryParameters}) async {
    queries.add(queryParameters ?? {});
    return response;
  }
}

void main() {
  test('returns the highest-resolution artwork URL iTunes offers', () async {
    final api = _StubApiService(ApiResponse.success(message: 'OK', data: const {
      'resultCount': 1,
      'results': [{'artworkUrl100': 'https://is1.mzstatic.com/image/a/100x100bb.jpg'}],
    }));

    final url = await ArtworkRemoteDataSourceImpl(api)
        .lookup(artist: 'Sonu Nigam', album: 'Ada');

    expect(url, 'https://is1.mzstatic.com/image/a/600x600bb.jpg');
    expect(api.queries.single['term'], 'Sonu Nigam Ada');
    expect(api.queries.single['entity'], 'album');
  });

  test('an empty result set is null, not an error', () async {
    final api = _StubApiService(ApiResponse.success(
      message: 'OK', data: const {'resultCount': 0, 'results': []},
    ));

    expect(await ArtworkRemoteDataSourceImpl(api).lookup(artist: 'a', album: 'b'), isNull);
  });

  test('a transport failure is null, and never throws into the panel', () async {
    final api = _StubApiService(ApiResponse.error(message: 'No internet connection.'));

    expect(await ArtworkRemoteDataSourceImpl(api).lookup(artist: 'a', album: 'b'), isNull);
  });

  test('does not call out at all when there is nothing to search for', () async {
    final api = _StubApiService(ApiResponse.error(message: 'unused'));

    expect(await ArtworkRemoteDataSourceImpl(api).lookup(artist: '', album: ''), isNull);
    expect(api.queries, isEmpty);
  });
}
```

This test requires `ApiService` to be substitutable. Add to `lib/core/services/api_service.dart`:

```dart
/// The surface a datasource depends on, so `ApiService` is overridable in
/// tests without a fake `Dio` (architecture-playbook §7).
abstract class ApiServiceContract {
  Future<ApiResponse<Map<String, dynamic>>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  });
}
```
and change `class ApiService` to `class ApiService implements ApiServiceContract`, and `apiServiceProvider` to `Provider<ApiServiceContract>`.

- [ ] **Step 2: Write the datasource and usecase**

`lib/features/music/data/datasources/artwork_remote_datasource.dart`:

```dart
import 'package:notchpeek/core/logging/notch_logger.dart';
import 'package:notchpeek/core/network/endpoints/api_endpoints.dart';
import 'package:notchpeek/core/services/api_service.dart';

abstract class ArtworkRemoteDataSource {
  Future<String?> lookup({required String artist, required String album});
}

class ArtworkRemoteDataSourceImpl implements ArtworkRemoteDataSource {
  ArtworkRemoteDataSourceImpl(this._api);

  final ApiServiceContract _api;
  final NotchLogger _log = NotchLogger.forTag('ArtworkRemoteDataSourceImpl');

  @override
  Future<String?> lookup({required String artist, required String album}) async {
    final term = [artist, album].where((s) => s.isNotEmpty).join(' ');
    if (term.isEmpty) return null;

    final response = await _api.get(
      ApiEndpoint.search,
      queryParameters: {'term': term, 'entity': 'album', 'limit': 1},
    );

    if (!response.status) {
      // Logs the outcome, not the search term — a track title is user content.
      _log.error('artwork lookup failed: ${response.message}');
      return null;
    }

    final results = response.data?['results'];
    if (results is! List || results.isEmpty) {
      _log.debug('artwork lookup: no match');
      return null;
    }

    final url = (results.first as Map)['artworkUrl100'] as String?;
    if (url == null) return null;

    _log.success('artwork lookup: match');
    // iTunes serves any size from the same path. 100px is unusably small
    // behind a 96pt tile on a 2x display.
    return url.replaceAll('100x100bb', '600x600bb');
  }
}
```

`lib/features/music/domain/usecases/fetch_artwork_fallback.dart`:

```dart
import 'package:notchpeek/features/music/data/datasources/artwork_remote_datasource.dart';
import 'package:notchpeek/features/music/domain/entities/now_playing.dart';

class FetchArtworkFallback {
  const FetchArtworkFallback(this._source);

  final ArtworkRemoteDataSource _source;

  /// Null whenever the player already gave us an image — the fallback is a
  /// fallback, not a preference.
  Future<String?> call(NowPlaying track) {
    if (track.artworkPath != null) return Future.value(null);
    return _source.lookup(artist: track.artist, album: track.album);
  }
}
```

Add the providers, and have `ArtworkTile` accept an optional `fallbackUrl` it renders with `Image.network` when `path` is null.

- [ ] **Step 3: Run everything and commit**

```bash
flutter test && flutter analyze
dart format .
git add -A lib test
git commit -m "feat(music): fall back to the iTunes artwork lookup when neither player has an image"
```

---

### Task 26: Measure idle memory and record the M1 baseline

**Exit criterion 10**, and one of the two most likely to be skipped. R4 sets the budget at **300 MB idle**, and every later milestone is measured against the number recorded here.

**Files:**
- Modify: `docs/specs/m1-shell-and-music.md` (record the number in §10)

- [ ] **Step 1: Build a release binary**

```bash
flutter build macos --release
open build/macos/Build/Products/Release/
```
Launch `NotchPeek.app` from Finder — not `flutter run`. A debug build carries the VM, the observatory and unstripped symbols, and measuring it would record a number no user will ever have.

- [ ] **Step 2: Measure idle, three times**

Leave the app collapsed and untouched for five minutes, with both players closed. Then:

```bash
ps -caxm -orss=,comm= | grep -i notchpeek
```

Record the RSS in MB. Repeat after a Space switch and after opening and closing the panel ten times — a number that climbs across those is a leak, not a baseline.

- [ ] **Step 3: Measure expanded, for M2's sake**

Open the panel with Spotify playing and hold it open for a minute. Record that number too; M2 compares against it.

- [ ] **Step 4: Write the numbers into the spec**

Replace exit criterion 10 in `docs/specs/m1-shell-and-music.md` with the measured figures:

```markdown
10. **Idle memory under 300 MB** — measured at **<N> MB** idle and **<M> MB**
    expanded with music playing, on a MacBook Air M2 running macOS 26.5.1,
    release build, 2026-09-<DD>. This is the baseline every later milestone is
    measured against (R4).
```

**If idle is over 300 MB, stop and say so.** The fix is not to ship over budget quietly; R4's escalation is M4's cut list, and a breach this early means the shell itself is wrong.

- [ ] **Step 5: Commit**

```bash
git add docs/specs/m1-shell-and-music.md
git commit -m "docs(m1): record the measured idle and expanded memory baseline"
```

---

### Task 27: Reconcile the docs with what was actually built

Docs are tracked and committed, including the playbook (architecture-playbook §11). Four documents are now out of date, and one is still a placeholder.

**Files:**
- Modify: `docs/risks-and-decisions.md`, `docs/playbook/architecture-playbook.md`, `docs/specs/m1-shell-and-music.md`, `docs/README.md`
- Rewrite: `docs/playbook/testing-playbook.md`
- Modify: `README.md`

- [ ] **Step 1: Close R10 and tick playbook §12**

R10 says "`lib/` does not compile — 105 analyzer errors". That was already stale when this plan was written: `flutter analyze` reported 0. Phase 0 finished the rest of the list. Mark R10 **closed**, with the note that the analyzer count was fixed in commit `642fea9` and the structural items in Phase 0 of this plan.

Tick every box in playbook §12 and replace the section's opening line with a statement that the repo now matches the playbook.

- [ ] **Step 2: Record the new decisions this plan made**

Add to `docs/risks-and-decisions.md`:

- **R11 — App Sandbox: off for the direct build.** Decided in Task 5. Sandboxed Apple Events need a `temporary-exception` entry per target bundle id, which is a MAS construct; the direct build uses `com.apple.security.automation.apple-events`. Consequence: the MAS build, if it ever happens, needs the sandbox back **and** the temporary exceptions, and that is a change to entitlements only, not to code.
- **R7 — amended.** Release engineering is deferred by decision, not by oversight: v1 is delivered as a local build until there is a working model. Exit criterion 9 is deferred with it. Nothing in the code depends on it.

- [ ] **Step 3: Reconcile spec §3.5 with the sixth control method**

M1 §3.5 fixes five methods on `notchpeek/control`. The build has six: `setMediaPolling` was added in Week 2 because §4's "poll at 1 Hz while expanded, and not at all while collapsed" needs a signal and none of the five carries it. Add it to the table with that reason, so the next milestone does not treat it as an accident.

- [ ] **Step 4: Write the testing playbook**

`docs/playbook/testing-playbook.md` has been a placeholder waiting for the seams to settle. They have. Write it from what this milestone actually built:

- **What has a test, and what does not.** Logic that can be tested without a Mac window has one: state machines, geometry maths, parsing, unit normalization, enum mapping, rect maths. Native window behavior is verified by hand, because it cannot be automated.
- **The four layers in practice.** Dart unit (pure functions and notifiers, `ProviderContainer` with overrides), Dart widget and golden (panels in all three capability states, the shell in three states, the tab strip at two/three/four tabs), Swift unit (`RunnerTests`, pure functions and stubbed `MusicSource`s), and the manual matrix.
- **Fixtures and fakes.** Every dependency is overridable because the provider graph is the registry; a class that news up its own collaborator is a bug. Name the patterns this plan used: `_Fake…DataSource`, `_Recording…Repository`, `_Stub…` for Swift `MusicSource`s, `TestDefaultBinaryMessengerBinding` for method channels, `NotchLogger.writer` for log capture.
- **Goldens.** Where they live, when to regenerate (`--update-goldens`), and the rule that a regenerated golden must be **looked at** before it is committed.
- **The manual matrix**, copied from Task 24's table, as the thing to run before any release.
- **The gate**, restating architecture-playbook §11.

- [ ] **Step 5: Update both READMEs**

`README.md` is still the `flutter create` template. Replace it with what NotchPeek is, the OS floor, how to run it (`flutter run -d macos`), how to run the tests (Dart and Xcode), and a pointer to `docs/README.md`.

In `docs/README.md`, update the "Near-term target" paragraph: R10 is closed, and the three-week M1 excludes signing and notarization by decision.

- [ ] **Step 6: Verify and commit**

Run: `flutter analyze && flutter test && dart format --set-exit-if-changed .`

```bash
git add -A docs README.md
git commit -m "docs: close R10, record R11, reconcile the channel set and write the testing playbook"
```

---

## Self-Review

Run against the spec after the plan is written, before execution starts.

**Spec coverage.** Every section of `m1-shell-and-music.md` maps to a task:

| Spec | Task |
|---|---|
| §2 opaque near-black panel | 4 (tokens), 13 (applied) |
| §2 native SwiftUI settings | 23 |
| §2 virtual notch on non-notched Macs | 6 |
| §2 scripting, not MediaRemote | 16, 17 |
| §3.1 one invisible canvas, never resized | 9 |
| §3.2 mouse passthrough | 10 |
| §3.3 notch geometry + observers | 6, 24 |
| §3.4 Swift modules | 6, 9, 10, 14, 16, 17, 22, 23 |
| §3.5 channel set | 5, 7 (+ the `setMediaPolling` delta, reconciled in 27) |
| §4 spike consequences: no `osascript`, unit normalization, artwork shape | 15, 16, 17 |
| §5 Dart architecture | 1, 8, 18 |
| §5.1 morph and `NotchShape` | 12, 13 |
| §5.2 data flow | 8, 13, 18 |
| §6 capability probe, three render states | 14, 20 |
| §7 error handling (all seven rows) | 7 (channel death), 8 (pre-geometry), 17 (empty read), 20 (denied consent, idle), 24 (display change), 25 (artwork) |
| §8 testing | every task; consolidated in 27 |
| §9 deferred items | untouched, by design |
| §10 exit criteria 1–8, 10 | 13 (1, 2), 22 (3), 21 (4), 20 (5), 24 (6, 7), 23 (8), 26 (10) |
| §10 exit criterion 9 (signed, notarized) | **deferred by decision** — recorded in 27 |

**Type consistency.** `NowPlayingPayload.channelMap` (Swift) emits `durationSeconds`/`positionSeconds`/`state`/`trackId`/`sourceId`/`artworkPath`/`available`/`isTick`/`trackChanged`; `NowPlayingModel.toEntity` (Dart) reads exactly those keys. `NotchMetrics.channelMap` emits `screenWidth`/`screenHeight`/`notchWidth`/`notchHeight`/`notchLeft`/`scale`/`isVirtual`; `NotchGeometryModel.toEntity` reads exactly those. `NotchWindowController.canvasHeight` (420) equals `NotchSizes.canvasHeight`, and `NotchGeometry.virtualNotchWidth`/`Height` (200/32) equal `NotchSizes.virtualNotchWidth`/`Height` — Task 24's hand matrix is where a drift between them would show.

**Known gaps, stated rather than hidden.**

1. **Apple Music is unverified by any spike.** The spike machine's library was empty, so `current track` errored with -1700 and the Music path was never exercised (spike §3). Task 16 writes it from the scripting dictionary; Task 21's hand check is the first time it runs. If `persistentID` is unavailable for streamed tracks, the composed fallback key is what carries it — and if that is wrong, artwork will thrash on every tick. **Watch for that specifically.**
2. **`SBApplication` KVC key names are unverified.** `currentTrack`, `playerPosition`, `playerState`, `artworkUrl`, `artworks`/`rawData` are taken from the published scripting dictionaries, not from a running probe. If any is wrong the read returns nil and the panel shows "Player unavailable" — which is the correct failure, but the wrong reason. Check `sdef /Applications/Spotify.app` and `sdef /System/Applications/Music.app` when a field comes back empty.
3. **Goldens are machine-specific.** They were generated on the dev machine. A different macOS or Flutter version will produce diffs that are not regressions.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-08-m1-shell-and-music.md`. Two execution options:

1. **Subagent-Driven (recommended)** — a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — tasks executed in this session with checkpoints for review.

The native tasks (5, 6, 9, 10, 16, 17, 22, 23) end in hand checks that only a person at the machine can do, so those checkpoints are real either way.

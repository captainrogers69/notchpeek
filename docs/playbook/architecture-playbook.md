# NotchPeek — Architecture Playbook

**The first thing to read before writing any code.** When a choice touches architecture, state, layering, naming or the Swift boundary, this document decides it. Nothing else overrides it — not the milestone specs, not a convenient shortcut, not what the reference projects did.

If a rule here is wrong, change the rule in a commit, then follow it. Do not work around it silently.

Adapted from two reference playbooks kept in `reference/` — Toskie (Bloc · GraphQL · get_it) and Go2Homes (Riverpod · REST). Neither stack survives intact, because NotchPeek is not a mobile CRUD app: **it is a macOS agent app whose data comes from the operating system through platform channels, not from a server.** Every deviation below is deliberate.

Marks used: **[locked]** = decided, do not relitigate. **[todo]** = the direction, not yet true in the repo; see §12.

---

## 1. What kind of app this is

Read this before the rules, because it explains all of them.

| | Reference projects | NotchPeek |
|---|---|---|
| Data source | HTTP backend | **the OS, via Swift platform channels** |
| Network use | everything | artwork fetch, and later licensing |
| Navigation | screen stack, `go_router` | one panel, tabs, no routes |
| Layout | responsive to device size | fixed geometry from the notch |
| Accounts | login, tokens, 401 handling | **none** |
| Swift code | none | ~35–40% of the app |

So the load-bearing boundary is **Dart ↔ Swift**, not Dart ↔ HTTP. The layering below is ordinary Clean Architecture; what changes is that the thing at the bottom of the stack is usually a channel, not a REST call.

## 2. State management **[locked]**

**`hooks_riverpod` only.** No `flutter_bloc`, no `get_it`, no `provider`, no bare `flutter_riverpod`.

| Scope | Use |
|---|---|
| Single-widget ephemeral state | **`flutter_hooks`** — `useState`, `useMemoized`, `useEffect` |
| Anything reusable, or with logic | **Riverpod `Notifier` / `AsyncNotifier`** |
| A stream from Swift | **`StreamProvider`** over the channel |
| A one-shot read | **`FutureProvider`** — do not reach for `AsyncNotifier` |

Rules:

- `Notifier`/`AsyncNotifier` only. **Never `StateNotifier`** — it is deprecated in Riverpod 3.
- State classes are immutable with `copyWith`, and extend `Equatable` with real `props`.
- Expose derived getters on state (`canPlay`, `isBusy`, `hasEvents`). **Never compute in the UI.**
- Never expose a notifier's mutation to widgets. The widget calls a named public method.
- **The Swift side is already stream-shaped**, so a `StreamProvider` per `EventChannel` is the natural fit and keeps panels free of lifecycle code.

## 3. Architecture — feature-first Clean Architecture **[locked]**

Each feature is `lib/features/<name>/` with three layers:

```
data/          models · datasources · repositories (impl)
domain/        entities · repositories (abstract) · usecases
presentation/  notifier · widgets
```

Flow: **UI → Notifier → UseCase → Repository → DataSource → `ChannelService` or `ApiService`**

- **UseCase** — one public `call(...)`, a thin wrapper over the repo. Thin is fine and expected: most reads here are pass-throughs. The layer exists so a panel never reaches past it, not because it holds logic.
- **Repository** — abstract in `domain`, impl in `data`, forwarding to a datasource. Maps `Model → Entity`.
- **DataSource** — the **only** place that talks to `ChannelService` or `ApiService`.
- **Streams flow through every layer too.** An `EventChannel` becomes `Stream<Entity>` at the repository and stays a stream up to the `StreamProvider`. Do not shortcut a channel straight into a widget.
- Panels never import from another feature's `data/` or `domain/`. Cross-feature sharing goes through `shared/`.

### Layout

```
lib/
  main.dart                       bootstrap; wait for geometry before first frame
  app/
    notch_app.dart                root widget
    theme.dart                    colors, radii, motion tokens
  core/
    logging/notch_logger.dart     NotchLogger
    platform/
      channels.dart               channel names — the single source of truth
      channel_service.dart        typed wrapper over Method/EventChannels
      capabilities.dart           Capability model, probe result
    network/
      errors/api_response.dart    ApiResponse<T>
      errors/api_error.dart       ApiErrorHandler
      endpoints/                  api_endpoints.dart, api_method.dart
      interceptor/                log interceptor
    services/api_service.dart     Dio client
  features/
    shell/                        the notch container: state machine, shape, morph, tabs
    music/ calendar/ clipboard/ shelf/ timer/ notes/ webcam/ game/ ai/
  shared/
    widgets/                      reusable widgets
    utils/                        helpers · enums · extensions
```

`features/shell/` is the container, not a panel. It owns notch state, the clipper, the morph controller, the tab strip and the interactive-rect reporting. Panels render inside it and know nothing about it.

## 4. The Swift boundary **[locked]**

The most NotchPeek-specific section, and the one with no equivalent in either reference playbook.

### 4.1 Channel set

Channel names live in **one** Dart file (`core/platform/channels.dart`) and **one** Swift file. Never a string literal at a call site.

| Channel | Kind | Direction |
|---|---|---|
| `notchpeek/control` | Method | Dart → Swift |
| `notchpeek/media` | Event | Swift → Dart |
| `notchpeek/system` | Event | Swift → Dart |
| `notchpeek/calendar` | Event | Swift → Dart |

Later milestones **extend** this set. They do not redesign it. One method channel for all commands; one event channel per data domain.

### 4.2 What belongs in Swift

Swift owns the OS and nothing else:

- Windowing, geometry, mouse gating, native views, permissions.
- Reading system state — media, calendar, battery, pasteboard, files, camera.
- **Normalization at the boundary.** Units, shapes and encodings are fixed in Swift so Dart sees exactly one shape. Two live examples: Spotify reports `duration` in milliseconds and `player position` in fractional seconds — normalize before crossing; artwork arrives as a URL from Spotify and as bytes from Apple Music — resolve to one shape before crossing.
- Storage. Swift owns every database. Dart never touches persistence, so migrations stay in one language.

**No business logic in Swift.** Decisions belong in `domain`. If a Swift module is making a product decision, it is in the wrong layer.

### 4.3 Rules that cost real money if broken

- **Never block the main thread.** Scripting and EventKit calls go on a background queue.
- **Never shell out to `osascript`.** Measured at ~130 ms per round trip — that is process-spawn cost. Use in-process ScriptingBridge.
- **Never send images on a tick.** Artwork crosses once per track change, keyed by track id. The position tick fires about twice a second.
- **Poll at 1 Hz while expanded, and not at all while collapsed.**
- **Every Swift module is one file, one purpose**, named for what it owns: `NotchWindowController`, `NotchGeometry`, `MouseGate`, `MediaBridge`, `PowerBridge`, `CapabilityProbe`.

### 4.4 Capability gating

`CapabilityProbe` is the single source of truth for what this build, this OS and these permissions can do. **Every panel renders three ways:**

1. **Ready** — the real widget.
2. **Needs permission** — an explanation plus an Open Settings button.
3. **Unavailable** — not present in this build or on this OS. **Hidden, never teased.**

A panel with only a ready state is incomplete and will not pass review.

## 5. Networking **[locked, and small]**

Be honest about the scale: NotchPeek has **no backend**. This section governs artwork fetching today, and licensing when monetization arrives. It is not the app's spine.

- **Dio only**, through `ApiService` (`core/services/api_service.dart`). No `http`, no raw `HttpClient`.
- `ApiService` is exposed as a Riverpod provider and is the **only** place a `Dio` instance exists.
- Every call returns **`ApiResponse<T>`** (`status` / `message` / `data` / `statusCode`). One wrapper, at every repo boundary.
- **No `dartz`, no `Either`, no `Failure` hierarchy.** Both reference playbooks converged on this; the pasted `api_failure.dart` and `api_exceptions.dart` are dead and get deleted (§12).
- Transport errors map through `ApiErrorHandler` to a user-readable message. A raw `DioException` never reaches a widget.
- Parse with static mappers: `Model.fromJson(Map) → Entity`, null-safe defaults (`json['x'] as String? ?? ''`).
- Endpoints are constants in `core/network/endpoints/api_endpoints.dart`. No URL literals at call sites.
- **No auth interceptor.** There are no accounts, no tokens and no 401 flow. The pasted interceptor's session-expiry logic belongs to a different app and is removed (§12).

**Naming wart, accepted:** `ApiResponse<T>` also wraps channel results, where "Api" reads oddly. Keeping the name costs nothing and a rename costs a sweep; if it grates later, §12 has the item.

## 6. Logging **[locked]**

**`NotchLogger`**, and nothing else. No `print`, no bare `dart:developer log`, no `debugPrint`.

```dart
final _log = NotchLogger.forTag('MusicDataSourceImpl');

_log.success('now playing: ${track.id}');
_log.error('scripting read failed', error: e);
```

- Levels: `debug` · `success` · `error`. One tag per class, created once as a field.
- **Datasources always log** — both outcomes. That is where failures actually happen.
- **Debug-only by default.** Release builds stay quiet.
- **Never log user content.** Clipboard text, note bodies, calendar titles and file paths are off limits. Log ids, counts and states.

That last rule is not style. A clipboard-history app that writes clipboard contents to a log has created a security problem.

## 7. Dependency injection **[locked]**

**Riverpod is the DI layer. No `get_it`.**

- One `Provider` per service, datasource, repository and usecase, colocated with the feature in `<feature>_providers.dart`.
- `ref.read(...)` for one-off calls, `ref.watch(...)` for reactive rebuilds.
- Never construct a `ProviderContainer` by hand outside tests.
- No central registration file. The provider graph *is* the registry — this is the main reason `get_it` is out.
- **Every dependency is overridable in tests.** A class that news up its own collaborator is a bug.

## 8. Helpers and reuse **[locked]**

If logic could be reused, extract it. Stateless, static, testable.

- `shared/utils/helpers/` — permissions, formatters, validators, debouncing, duration formatting.
- **Enums are the important one.** `shared/utils/enums/`, each with an extension exposing `fromApi(String)`, `apiValue` and `label`. **A raw string from a channel or an API is never passed around unwrapped.** Playback state, capability state, peek kind, tab id — all enums.
- Extensions for cross-cutting sugar in `shared/utils/extensions/`.
- **Reusable widgets:** used more than once → promote to `shared/widgets/`. Scrubber, artwork tile, icon button, marquee text, empty state, permission prompt, panel scaffold.
- The **permission-prompt widget is shared, not per-panel.** Nine panels need the same three states; nine copies is nine bugs.

## 9. UI rules **[locked]**

- **`StatelessWidget` / `HookWidget` over widget-returning functions** — always, however small. **No `Widget _buildX()` methods.**
- **`HookWidget` / `HookConsumerWidget` over `StatefulWidget`** — always, however complex. `StatefulWidget` only when a lifecycle or gesture recognizer genuinely needs it.
- Extract a widget the moment it is used twice.
- Segregate into small `const` `StatelessWidget`s to scope rebuilds.
- Narrow rebuilds with `ref.watch(provider.select((s) => s.field))`. Never watch whole state to read one field.
- Dispose everything created in a hook:
  ```dart
  final ctrl = useMemoized(() => SomeController(), const []);
  useEffect(() => ctrl.dispose, const []);
  ```
- **No responsive sizing package.** No `sizer`, no `context.res`. This is a fixed-geometry desktop panel: dimensions come from native geometry plus tokens in `app/theme.dart`.
- **No `go_router`, no routing package.** One window, one panel. Tab selection is Riverpod state; settings is a **native SwiftUI window**, not a Flutter route.
- Colors, radii, durations and curves are tokens in `app/theme.dart`. **No magic numbers in widgets** — the morph timings especially.
- Panels never assume they are visible. Collapsed means stop work: no polling, no animation, no camera session.

## 10. Naming **[locked]**

- Files `snake_case`; classes `PascalCase`; channel names `notchpeek/<domain>`.
- Layer suffixes are explicit: `MusicRepository` (abstract) → `MusicRepositoryImpl`; `MusicRemoteDataSource` → `MusicRemoteDataSourceImpl`.
- Usecases are verb phrases: `GetNowPlaying`, `TogglePlayback`, `ClearClipboard`.
- Notifiers end in `Notifier`; providers end in `Provider`.
- Swift modules are named for what they own (§4.3).
- Package root is `package:notchpeek/...`. Prefer root-relative imports (`/core/...`, `/features/...`) over `../../` chains.
- **No `_revamp` / `_v2` / `_new` suffixes.** When something is replaced, the old file is deleted in the same commit.

## 11. Quality gate **[locked]**

- **`flutter analyze` at 0 errors** before any commit. Not "0 new errors" — zero.
- `dart format .` clean.
- Xcode build with no new warnings.
- Tests pass. Test *strategy* is the testing playbook's job, but the gate is here: **logic that can be tested without a Mac window has a test.** State machines, geometry maths, parsing, unit normalization, enum mapping.
- Commits: `feat(scope): …`, `fix(scope): …`, `refactor(scope): …`, `docs(scope): …`.
- Docs are **tracked and committed** — including this one.

## 12. Housekeeping — the repo does not match this playbook yet

`lib/` currently carries a partial transplant from the Go2Homes project: **105 analyzer errors**, imports of `package:gohomes/...`, and dependencies on features that do not exist here. Nothing new should be built on top of it until this list is clear.

- [ ] **Add dependencies:** `hooks_riverpod`, `flutter_hooks`, `dio`, `equatable`. Remove bare `flutter_riverpod` (`hooks_riverpod` re-exports it).
- [ ] **Rewrite imports** `package:gohomes/…` → `package:notchpeek/…`.
- [ ] **Delete `core/network/errors/api_failure.dart` and `api_exceptions.dart`** — the `Failure`/`Either` model is explicitly out (§5).
- [ ] **Rewrite `core/network/interceptor/dio_interceptor.dart`.** It reads a bearer token, clears a session and routes to a login screen. NotchPeek has no accounts. It should keep only generic error mapping, or be deleted outright.
- [ ] **Fix `ApiService`'s `baseUrl`** — it reads `ServiceBase.apiBaseUrl` from the other project. Replace with a config constant.
- [ ] **Write `NotchLogger`** (§6) and point `log_interceptor.dart` at it instead of the missing `AppLogger`.
- [ ] **Strip GraphQL and presigned-URL leftovers** from `log_interceptor.dart` (`Get_Presigned_Url` filters).
- [ ] **Fill `api_endpoints.dart`** with the iTunes artwork lookup, the only real endpoint M1 needs.
- [ ] **Replace `main.dart`** — still the Flutter counter template.
- [ ] **Get `flutter analyze` to 0** and keep it there.

`reference/toskie-conventions.md` and `reference/go2homes-conventions.md` are kept for provenance only. They describe other projects' stacks. **Never cite them as authority here.**

## 13. Still to come

- **`testing-playbook.md`** — written after this document settles. This playbook fixes the seams that make testing possible (§7 overridable providers, §3 layering, §4.2 logic out of Swift); the testing playbook decides coverage, fixtures, goldens and the manual matrix.

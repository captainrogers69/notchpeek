# Go2Homes Mobile — Coding Conventions

How we build in this project. Follow these for every new feature, revamp, or fix.
Items marked **[project]** are conventions already established in this codebase.
Items marked **[target]** are the direction we're migrating toward — not yet true everywhere, adopt them for new/touched code.

Adapted from a reference playbook (Bloc + GraphQL + get_it) for this project's actual stack: **Riverpod + flutter_hooks, REST**. Every choice below was a deliberate decision, not a copy-paste — see "Status & housekeeping" at the bottom for what's still in flight.

See also: [Components & Helpers Catalog](component-catalog.md) — **not yet adapted for this project**, still reflects the reference codebase. Don't treat it as authoritative until it's rewritten.

---

## 1. State Management

Pick the smallest tool that fits:

| Scope                                                          | Use                                                             |
| -------------------------------------------------------------- | --------------------------------------------------------------- |
| Single-screen ephemeral state                                  | **`flutter_hooks`** (`useState`, `useMemoized`, `useEffect`, …) |
| Anything reusable (controller, mid-scale, large-scale feature) | **Riverpod `Notifier` / `AsyncNotifier`**                       |

One tier above hooks, not three — Riverpod's `Notifier`/`AsyncNotifier` covers what the reference playbook splits across `ChangeNotifier` → `Cubit` → `Bloc`. No `flutter_bloc`.

- **[target]** New/touched controllers use `Notifier`/`AsyncNotifier`, not `StateNotifier`. **[project]** Existing `StateNotifier`-based controllers (`auth_notifier.dart`, `property_notiifer.dart`, etc.) predate this convention — leave them as-is until the feature they belong to is migrated; don't write new `StateNotifier` usages.
- State classes stay immutable with a `copyWith` (matches the existing `state = state.copyWith(...)` pattern) — expose derived getters (`canSubmit`, `isBusy`) instead of computing in the UI.
- Never expose a notifier's internal mutation directly to widgets — keep a public method on the notifier that the UI calls.
- One-off/fetch-once reads that don't need a full notifier can stay a plain `FutureProvider` (e.g. `guideListFutureProvider`) — don't reach for `AsyncNotifier` when a `FutureProvider` already does the job.

---

## 2. Architecture — Feature-First, 3-Layer

**[target]** Each feature = `lib/features/<name>/` with three layers, matching the reference playbook exactly:

```
data/          models · datasources · repositories (impl)
domain/        entities · repositories (abstract) · usecases
presentation/  notifier (Notifier/AsyncNotifier) · screens · widgets
```

Flow: **UI → Notifier/AsyncNotifier → UseCase → Repository → DataSource → `ApiService`**.

- **UseCase**: one public `call(...)`, thin wrapper over the repo.
- **Repository**: abstract in `domain`, impl in `data` forwarding to the datasource.
- **DataSource**: the only place that talks to `ApiService`.
- **[project]** This is a _gradual_ migration. Existing code stays under `lib/screens/<feature>/` + shared `lib/data/{models,repo,services}` untouched until that feature is actively rebuilt. No `_revamp`/`_v2` suffix, no parallel old/new copies — when a feature moves to `lib/features/<name>/`, the old location is deleted in the same change.
- No GraphQL layer — this backend is REST-only, so there's no feature-owned GraphQL directory (unlike the reference playbook).

---

## 3. Networking & Data

- **[target]** `lib/core/services/api_service.dart` (Dio-based) is the primary networking home going forward, superseding `lib/data/manager/service_base.dart` (the `http` package) as features migrate. It's currently GraphQL-shaped (leftover from the reference port) and needs rewriting for REST — **that rewrite happens after this playbook is settled**, not yet done. Until then, use `ServiceBase` for anything not yet migrated.
- **[target]** Dio is the standard HTTP client going forward. `ServiceBase`/`http` gets retired feature-by-feature, not in one pass.
- Return **`ApiStatus<T>`** (`Success` / `Error` / `Loading`, currently in `lib/utils/helpers/api_status.dart`) — the one canonical response wrapper, at every repo boundary. **[target]** `lib/core/network/errors/{ApiResponse,ApiError,ApiFailure,ApiExceptions}` (also leftover from the reference port) get replaced by `ApiStatus<T>`, and `ApiStatus<T>` itself moves into `lib/core/network/` as part of that cleanup.
- This backend's envelope is REST JSON: `{"success": bool, "data": ..., "message": ...}` — check `success == true` before treating a response as data (matches the existing `parseGuideListResponse`-style parsers).
- Parse via static mappers: `Model.fromJson(Map) → Model`, null-safe defaults (`json['x'] as String? ?? ''`) — matches `GuideModel`, `MediaModel`, `PropertiesDetailedModel` already.
- Log with `dart:developer`'s `log(msg, name: "<Context>")` — the existing project-wide convention (no dedicated logger helper exists; don't invent one without deciding that separately).

---

## 4. Dependency Injection

- **No `get_it`.** Riverpod's own provider graph _is_ the DI layer.
- One `Provider`/`Provider.family` per repo, service, or notifier (matches the existing pattern, e.g. `guideRepoProvider = Provider<GuideRepository>((ref) => GuideRepository(ref))`).
- Resolve with `ref.read(...)` for one-off calls, `ref.watch(...)` for reactive rebuilds. Never construct a `ProviderContainer` manually outside tests.
- Under the 3-layer structure, domain usecases/repos get exposed the same way — one `Provider` each, colocated with the feature (e.g. a `<name>_providers.dart` in the feature's `data/` or `presentation/` layer) — there's no separate DI-registration file convention to maintain, unlike `get_it`'s per-feature `core/di/<feature>_di.dart`.

---

## 5. Helpers — always a shared static class

If logic could be reused, extract it. Keep it stateless + testable.

- **[project]** `lib/utils/helpers/` — permissions, media (`KFileUploader`), validators, snackbars/dialogs (`app_helpers.dart`), date/api utils.
- **[project]** Enums in `lib/utils/enums/` (e.g. `EnumPropertyActionType`, `EnumPropertyListerType`) — extend with `fromApi`/`apiValue`/`label`-style helpers where the enum crosses the API boundary. Never pass raw API strings around unwrapped.
- Extensions for cross-cutting sugar (context/responsive, string, etc.) — no dedicated `extensions/` folder exists yet; colocate under `lib/utils/` if one gets introduced.

---

## 6. Reusable Widgets — build once, reuse

If a widget is used more than once, promote it to `lib/components/` (this project's shared-widget home — dialogs, appbars, buttons, media pickers, etc.).

Full inventory: [component-catalog.md](component-catalog.md) — **still reflects the reference project, needs a separate rewrite pass** before it's trustworthy here.

---

## 7. UI Rules

- **`StatelessWidget`/`HookWidget` over widget-returning functions** — always, no matter how small. No `Widget _buildX()` methods.
- **`HookWidget`/`HookConsumerWidget` over `StatefulWidget`** — always, no matter how complex. Use `StatefulWidget` only when a lifecycle/recognizer genuinely needs it.
- **Extract common widgets** when used more than once.
- **Segregate into small `const` `StatelessWidget`s** to scope rebuilds.
- **[project]** Control rebuilds: `const` constructors; `ref.watch(provider.select((s) => s.field))` for narrow rebuilds instead of watching the whole state.
- **[project]** Responsive via the `sizer` package (`.w` / `.h` / `.sp`, already used throughout, e.g. `property_appbar.dart`); typography/colors via `Kstyles` / `KColors` (`lib/utils/constants/`).
- **[project]** Dispose everything created in hooks:
  ```dart
  final ctrl = useMemoized(() => SomeController(), const []);
  useEffect(() => ctrl.dispose, const []);
  ```

---

## 8. Routing

- **[project]** `go_router`, centralized in `lib/data/services/routing_service.dart`. **Kept as-is, deliberately not migrating to a typed routes enum.**
- Each screen exposes `static const String id`, used directly as both the `GoRoute` name and path.
- Args pass through `state.extra` as a raw `Map<String, dynamic>` or anonymous record — not a typed args class. This is the project's convention; don't introduce a parallel typed-args pattern for new routes.

---

## 9. Images & Media

- **[project]** No S3/presigned URLs. Media is referred to by a direct URL string returned from the upload endpoint and stored as-is — images resolve synchronously; video URLs are the backend's deterministic HLS (`.m3u8`) URL, populated once transcoding reaches `READY`.
- Uploads via `KFileUploader.handleFilePick(folderName, isPickingVideo)` (`lib/utils/helpers/k_fileuploader.dart`). Video upload never blocks on transcode — it returns `videoId` immediately (`MediaModel.videoId` / `videoStatus`); publish/save flows must not wait on readiness.
- **Always guard video playback**: check `MediaModel.url` / `videoStatus` before handing a URL to `VideoPlayerController` — treat empty/`PENDING`/`PROCESSING`/`FAILED` as not-yet-playable and fall back to a placeholder (see `lib/components/video_status_icon.dart`) rather than attempting playback and hanging.
- Render images with `CacheImage` (`lib/components/cache_image.dart`); video with `video_player`, passing `formatHint: VideoFormat.hls` for `.m3u8` URLs.

---

## 10. Naming & Files

- Files `snake_case`; classes `PascalCase`.
- Repo/service method names describe the action (`listGuides`, `addGuide`, `uploadVideoToBackend`).
- **[project]** Package root is `package:gohomes/...`; prefer root-relative imports (`/data/...`, `/screens/...`, `/components/...`) as already used throughout, over long relative `../../` chains.

---

## 11. Quality Gate

- `flutter analyze` at **0 errors** before any PR (pre-existing unrelated `info`-level lints are tracked separately, not a blocker); `dart format .`.
- Commits: `feat(scope): …`, `fix(scope): …`, `refactor(scope): …`.
- Reference/integration docs (like this one, and the `docs/*.md` files already in this repo) **are** tracked and committed — unlike the reference playbook's convention, this project keeps them in version control.

---

## Status & housekeeping (not yet done, tracked here so it isn't lost)

- [ ] Rewrite `lib/core/services/api_service.dart` for REST (Dio), replacing the leftover `sendGraphQlRequest`.
- [ ] Replace `lib/core/network/errors/{ApiResponse,ApiError,ApiFailure,ApiExceptions}` with `ApiStatus<T>`; move `ApiStatus<T>` into `lib/core/network/`.
- [ ] Remove the unused `flutter_bloc` dependency from `pubspec.yaml` (zero usages in the codebase; superseded by Riverpod `Notifier`/`AsyncNotifier` per §1).
- [ ] Rewrite `component-catalog.md` for this project (still reference-project content).
- [ ] Migrate `ServiceBase`/`http` call sites to the new Dio-based `ApiService` as each feature is touched (§3).

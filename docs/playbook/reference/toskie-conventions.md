# Toskie Mobile — Coding Conventions

How we build in this project. Follow these for every new feature, revamp, or fix.
Items marked **[project]** are conventions already established in this codebase.

See also: [Components & Helpers Catalog](component-catalog.md).

---

## 1. State Management

Pick the smallest tool that fits:

| Scope                                   | Use                                                   |
| --------------------------------------- | ----------------------------------------------------- |
| Single-screen ephemeral state           | **`flutter_hooks`** (`useState`, `useMemoized`, …)    |
| Small reusable logic / controllers      | **`ChangeNotifier`** (e.g. `ToskieEnhanceController`) |
| Mid-level, independent/reusable feature | **`Cubit`**                                           |
| Large-scale, event-driven feature       | **`Bloc`**                                            |

- **[project]** Register `Cubit`/`Bloc` as `registerFactory`; use `registerFactoryParam` when the cubit needs a runtime arg.
- **[project]** State classes extend `Equatable` with a proper `props`; expose derived getters (`canSubmit`, `isBusy`) instead of computing in the UI.
- **[project]** Never expose a `ChangeNotifier`'s protected `notifyListeners()` to widgets — add a public method.

---

## 2. Architecture — Feature-First Clean Architecture

Each feature = `lib/features/<name>/` with three layers:

```
data/          graphql · models · datasources · repositories (impl)
domain/        entities · repositories (abstract) · usecases
presentation/  cubit|bloc · screens · widgets
```

Flow: **UI → Cubit/Bloc → UseCase → Repository → DataSource → `ApiService`**.

- **UseCase**: one public `call(...)`, thin wrapper over the repo.
- **Repository**: abstract in `domain`, impl in `data` forwarding to the datasource.
- **DataSource**: the only place that talks to `ApiService`.
- **[project]** GraphQL is **feature-owned** — each feature keeps its own `data/graphql/*.dart`; do **not** import from `core/network/graphql/mutations.dart`.
- **[project]** Newer modules are suffixed `_revamp` (migration target); build new work there.

---

## 3. Networking & Data **[project]**

- All GraphQL goes through **`ApiService.sendGraphQlRequest(query, operationName, variables)`** → returns **`ApiResponse`** (`status` / `data` / `message`). **No direct `GraphQLClient` / `GraphQLService` / provider.**
- Return `ApiResponse<T>`. **Do not use `dartz` `Either`/`Failure`** (legacy — being removed).
- Parse via static mappers: `Model.fromJson(Map) → Entity`; guard with `whereType<Map>()` + null-safe defaults.
- Envelope check: `payload == null || payload['status'] != true` → `ApiResponse.error(...)`.
- Log in datasources with **`ToskieLogger.forTag("<Impl>")`** (`.success` / `.error`).

---

## 4. Dependency Injection **[project]**

- One file per feature: `core/di/<feature>_di.dart`; call it once in `dependency_injection.dart`.
- `registerLazySingleton` for datasources / repos / usecases; `registerFactory` / `registerFactoryParam` for cubits/blocs.
- Resolve with `getIt<T>()`.

---

## 5. Helpers — always a shared static class

If logic could be reused, extract it. Keep it stateless + testable.

- Permissions, processing/compression, API helpers, debouncing, validators, date utils, snackbars.
- **Enums (most important):** `lib/shared/utils/enums/` with an extension exposing `fromApi(String)`, `apiValue`, `label`. Never pass raw API strings around.
- **Extensions** for cross-cutting sugar (context/responsive, string, etc.).

---

## 6. Reusable Widgets — build once, reuse

If a widget is used more than once, promote it to a shared/common widget:
date picker, text fields, labels, profile avatar, avatar picker, bottom sheets, dialogs, app bars.

See the full list in [component-catalog.md](component-catalog.md).

---

## 7. UI Rules

- **Stateless over widget-returning functions** — always, no matter how small. No `Widget _buildX()` methods.
- **`HookWidget` over `StatefulWidget`** — always, no matter how complex. Use `StatefulWidget` only when a lifecycle/recognizer genuinely needs it.
- **Extract common widgets** when used more than once.
- **Segregate into small `const` `StatelessWidget`s** to scope rebuilds.
- **[project]** Control rebuilds: `const` constructors; `BlocBuilder(buildWhen:)` / `context.select`.
- **[project]** Responsive via `context.res(...)`; typography via `GoogleFonts.poppins(...)`.
- **[project]** Dispose everything created in hooks:
  ```dart
  final ctrl = useMemoized(() => SomeController(), const []);
  useEffect(() => ctrl.dispose, const []);
  ```

---

## 8. Routing **[project]**

- `go_router` only. Routes as an `AppRoute` enum (`getPath` / `getName`) in `route_name.dart` + built in `route_config.dart`.
- Pass arguments via a **typed args class** through `state.extra` (e.g. `SinglePostArgs`, `ConversationArgs`).

---

## 9. Images & Media **[project]**

- Refer to media by **S3 key**; resolve to a URL via `PresignedUrlCubit` (`prefetch` on load, `resolve` at render, `put` after upload).
- Render with `ProfileImage` (avatars) / `CachedImageHolder` (generic).
- Uploads via `media_upload` `UploadMedia`; picking via `MediaPicker`.

---

## 10. Naming & Files

- Files `snake_case`; classes `PascalCase`.
- Datasource/repo/usecase names describe the action (`GetSinglePost`, `RemoveStory`).
- **[project]** Feature modules end in `_revamp` when they're the migration target.

---

## 11. Quality Gate

- `flutter analyze` at **0 errors** before any PR; `dart format .`.
- Commits: `feat(scope): …`, `fix(scope): …`, `refactor(scope): …`.
- Plans / design docs are untracked `.md` (feature-local `docs/`), not committed.

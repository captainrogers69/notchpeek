# M2 — Calendar, clipboard, file shelf, hotkeys

**Date:** 2026-09-04
**Status:** draft
**Depends on:** M1 complete. Every panel here slots into the M1 shell unchanged.
**Ships as:** a daily-driver utility.

---

## 1. Goal

Three panels that make the app worth leaving running, plus the global hotkeys that make it worth reaching for.

The panels are ordered by risk: calendar first because it proves the M2 channel pattern end to end against a permissioned system API; clipboard second because it owns the app's first real database; file shelf last because drag-and-drop across the Flutter/AppKit boundary is the least predictable part.

### In scope

Calendar panel, clipboard history, file shelf with previews, user-configurable global hotkeys.

### Out of scope

Timer, notes, webcam (M3). Web players, game, AI (M4). Monetization, in this and every milestone.

## 2. Calendar

| Aspect | Decision |
|---|---|
| Source | EventKit, today's events only |
| Native module | `CalendarBridge` — auth, today's events, store-changed observer |
| Channel | `notchpeek/calendar`, reserved in M1, used here |
| Permission | `NSCalendarsFullAccessUsageDescription`; sandbox entitlement `com.apple.security.personal-information.calendars` |
| Per-calendar toggles | Yes — NotchNest ships them and a user with a shared work calendar needs them |
| Refresh | Observer-driven, never polled |

Renders in all three capability states from M1 §6. Denied calendar access is the single most likely permission refusal in the app, so the needs-permission state here has to be genuinely good rather than a stub.

## 3. Clipboard history

The app's first real persistence, and the one whose schema will move. NotchNest shipped a `ClipboardMigrationManager` by version 1.2.5, which means their schema already changed under real users. Treat that as a warning, not trivia.

| Aspect | Decision |
|---|---|
| Capture | Poll `NSPasteboard.changeCount` from Swift; never poll contents |
| Storage | Local database owned by Swift, with an explicit migration path **from the first version** |
| Item types | Plain text and URLs in M2. Images deferred — they turn a small database into a large one |
| Search | Dart-side filter over a paged list |
| Actions | Re-copy, delete, clear all |
| Retention | Fixed cap, oldest evicted. Configurable in settings |

### Two things to get right

**Excluded content.** Password managers mark pasteboard items with `org.nspasteboard.ConcealedType` and similar hints. Those must never be recorded. A clipboard history that captures passwords is a security incident, not a feature, so the exclusion rule is a requirement here rather than a later refinement.

**Storage boundary.** Swift owns the database; Dart never touches storage. The channel carries pages of already-filtered rows. That keeps the migration problem in one language.

## 4. File shelf

Drag files onto the notch, hold them, drag them out again.

| Aspect | Decision |
|---|---|
| Drop target | AppKit — the panel's own view registers dragged types, not Flutter |
| Held items | References, not copies. Sandbox needs `com.apple.security.files.user-selected.read-write` |
| Preview | QuickLook thumbnails generated in Swift, sent as images |
| Drag out | AppKit-initiated drag session |
| Persistence | Shelf contents survive relaunch; a missing file renders as missing, never crashes |

**Why AppKit owns the drop.** Flutter's macOS drag-and-drop does not cover the promise-file and file-URL flows a shelf needs, and the drop target has to work while the panel is collapsed — that is, while Flutter is not showing an interactive surface at all. So the drop zone is a native view layered with the Flutter view, and Dart only renders the resulting list.

This is the first place a native view and the Flutter canvas share a rect. Whatever pattern works here is the pattern M4 reuses for the web players, so it is worth writing down when it lands.

## 5. Global hotkeys

Not in any earlier plan. Found in NotchNest's bundle (`KeyboardShortcuts`), and power users treat configurable shortcuts as table stakes.

| Aspect | Decision |
|---|---|
| Registration | Swift, `NSEvent` global hotkey registration |
| Configurable | Yes, in the settings window, with conflict detection |
| Default actions | Toggle expand, open clipboard, open shelf |
| Storage | Alongside settings, synced (M3 adds iCloud sync) |
| Permission | None — hotkey registration needs no Accessibility |

## 6. Channels added

M1's channel set is extended, not redesigned.

| Channel | Direction | Carries |
|---|---|---|
| `notchpeek/calendar` (Event) | Swift → Dart | today's events, auth state changes |
| `notchpeek/clipboard` (Event) | Swift → Dart | new item added, list invalidated |
| `notchpeek/shelf` (Event) | Swift → Dart | items added or removed, thumbnails ready |
| `notchpeek/control` (Method) | Dart → Swift | adds `clipboardPage`, `clipboardCopy`, `clipboardDelete`, `shelfRemove`, `shelfBeginDrag`, `setHotkey` |

## 7. Error handling

| Failure | Response |
|---|---|
| Calendar access denied | Needs-permission state with an Open Settings button |
| Calendar store changes while expanded | Observer refreshes in place; no flicker |
| Pasteboard item is concealed | Silently skipped, never stored |
| Clipboard database migration fails | Fall back to an empty store, keep the app alive, report once |
| Shelf item's file was deleted or moved | Row renders as missing with a remove action |
| QuickLook thumbnail fails | Generic file-type icon |
| Hotkey already taken by another app | Conflict shown at assignment time, not silently swallowed |

## 8. Testing

**Dart unit** — clipboard search and paging logic; shelf list reducers; hotkey conflict detection; event-list grouping and all-day handling.

**Dart widget** — goldens for each panel in all three capability states; clipboard list empty, one page, and paging; shelf with a missing file.

**Swift unit** — pasteboard change detection including the concealed-type exclusion; **a migration test that opens a previous-version database and migrates it**; calendar event mapping from synthetic `EKEvent`s.

**Manual** — drag in and out of Finder and of a browser; deny then grant calendar access without relaunching; hotkey conflicts against a running app.

## 9. Exit criteria

1. Today's events appear within a second of expanding, and update in place when the calendar changes elsewhere.
2. Denying calendar access produces a clear, actionable panel.
3. Copying text anywhere on the system puts it in the clipboard panel; concealed items provably never appear.
4. A database written by a previous build opens and migrates, verified by test.
5. Files dragged from Finder land on the collapsed notch and can be dragged back out to another app.
6. A deleted file on the shelf degrades to a missing row, never a crash.
7. All three default hotkeys work, are reassignable, and report conflicts.
8. **Idle and expanded memory recorded** and compared against the M1 baseline; still under the 300 MB budget (`../risks-and-decisions.md` R4).

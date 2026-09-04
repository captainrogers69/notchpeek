# M3 — Timer, notes, webcam, settings sync

**Date:** 2026-09-04
**Status:** draft
**Depends on:** M2 complete.
**Ships as:** feature-complete against NotchNest except the hard tail — web players, game and AI, all in M4.

---

## 1. Goal

Three self-contained panels and the settings sync that makes a two-Mac user's life better. This is the lowest-risk milestone in the set: nothing here needs a new permission model except the camera, and nothing here is architecturally novel.

Which makes it the right place to spend effort on polish rather than plumbing.

### In scope

Timer with notifications, notes, webcam mirror, iCloud settings sync, and the peek-event catalogue.

### Out of scope

Web players, game, AI, i18n, Sparkle (all M4). Monetization, in this and every milestone.

## 2. Timer

NotchNest calls these **"sprints"** rather than pomodoros, and the name is better — it avoids a trademarked-sounding term and reads as work rather than as a technique.

| Aspect | Decision |
|---|---|
| Model | Work interval, break interval, repeat count. Configurable |
| Ownership | **Dart owns the countdown**; Swift owns only notifications and sound |
| Completion | Local notification plus a sound; needs `NSUserNotificationsUsageDescription` |
| Collapsed state | Remaining time shows in the collapsed notch — the timer's whole point is glanceability |
| Persistence | Survives relaunch mid-sprint by storing the end timestamp, never a remaining-seconds counter |

**Why Dart owns the countdown.** A timer is pure logic with a UI attached; it belongs where it is testable without a simulator. Swift is involved only where the OS is: notifications and sound.

**Why an end timestamp, not a counter.** A counter drifts across sleep, and a MacBook sleeps constantly. Storing the absolute end time makes wake-up correctness free.

## 3. Notes

| Aspect | Decision |
|---|---|
| Scope | Plain-text scratch notes. No rich text, no attachments, no folders |
| Storage | Same local database as the clipboard, separate table, same migration discipline |
| Ownership | Swift owns storage; Dart owns editing |
| Autosave | Debounced on edit; no save button |
| Search | Reuses the clipboard panel's filter, not a second implementation |

Deliberately the smallest possible notes feature. NotchNest shipped a `NotesMigrationManager`, so even their minimal notes changed shape once. Keeping the model plain text is what stops that happening twice.

## 4. Webcam mirror

| Aspect | Decision |
|---|---|
| Source | AVFoundation, front camera, preview only |
| Native module | `CameraBridge` — session lifecycle, device availability |
| Rendering | Native `AVCaptureVideoPreviewLayer` in a view layered with Flutter, **not** frames pushed through a channel |
| Permission | `NSCameraUsageDescription`; entitlement `com.apple.security.device.camera` |
| Lifecycle | Session starts on panel open, **stops on panel close** |
| Recording | None. Preview only, no capture, no disk writes |

**Why a native layer, not channel frames.** Pushing video frames over a `MethodChannel` at 30 fps would consume the CPU budget the position tick already strains. The preview layer draws itself; Dart just reserves the rect.

**Why the session must stop on close.** A camera session left running keeps the green indicator light on. A notch app that appears to watch you permanently is a product failure regardless of what the code does.

This reuses the native-view-sharing-a-rect pattern established by M2's file shelf, and it is the last rehearsal before M4's web players do the same thing under harder constraints.

## 5. Settings sync

| Aspect | Decision |
|---|---|
| Mechanism | `NSUbiquitousKeyValueStore` |
| Entitlement | `com.apple.developer.ubiquity-kvstore-identifier` |
| Scope | Preferences only — never clipboard history, notes content, or shelf items |
| Conflict | Last write wins. Settings do not warrant merge logic |
| Failure | Signed out of iCloud degrades to local-only, silently |

Cheap, and it is what NotchNest does. The scope limit matters: syncing clipboard history across machines is a different product with a different privacy conversation.

## 6. Peek events

The peek mechanism shipped in M1. The catalogue completes here.

| Event | Peek content |
|---|---|
| Track change | artwork, title, artist |
| Charger connected or disconnected | battery percentage and state |
| Sprint complete | which sprint, and what is next |
| Low battery | percentage, with a warning treatment |

Peeks are queued, never stacked — one at a time, each retracting before the next. Two simultaneous peeks is the bug that makes an app like this feel broken.

## 7. Channels added

| Channel | Direction | Carries |
|---|---|---|
| `notchpeek/notes` (Event) | Swift → Dart | note list invalidated |
| `notchpeek/control` (Method) | Dart → Swift | adds `notifySprintComplete`, `notesSave`, `notesDelete`, `cameraStart`, `cameraStop`, `setCameraRect` |
| `notchpeek/system` (Event) | Swift → Dart | extended with low-battery edge and settings-changed-remotely |

## 8. Error handling

| Failure | Response |
|---|---|
| Notification permission denied | Timer still works; completion is visual only, and the panel says so once |
| Machine sleeps mid-sprint | End timestamp makes wake-up correct with no special case |
| Camera permission denied | Needs-permission state |
| No camera present | **Unavailable** state — panel hidden, not teased |
| Camera in use by another app | Explanatory state; retry when the panel reopens |
| iCloud signed out | Local-only, silent |
| Notes database migration fails | Empty store, app stays alive, reported once |

## 9. Testing

**Dart unit** — sprint state machine including pause, resume and skip; end-timestamp arithmetic **across a simulated sleep**; notes autosave debounce; peek queue ordering with overlapping events.

**Dart widget** — goldens for each panel in all three capability states; collapsed notch showing remaining time; each peek kind.

**Swift unit** — notification scheduling; camera session start and stop against a stubbed device; notes migration from a previous-version database; KV-store change handling.

**Manual** — close the lid mid-sprint and reopen it; deny notifications then grant them; camera indicator light goes out when the panel closes; change a setting on one Mac and watch it arrive on another.

## 10. Exit criteria

1. A sprint runs, notifies, sounds, and shows remaining time in the collapsed notch.
2. Sleeping the machine mid-sprint produces a correct remaining time on wake.
3. Notes persist, autosave with no save button, and survive a migration test.
4. Webcam mirrors the front camera, and **the camera indicator light goes out when the panel closes**.
5. A Mac with no camera hides the panel rather than showing a broken one.
6. A setting changed on one Mac appears on another; signing out of iCloud degrades silently.
7. Peeks queue rather than stack, verified with a track change and a charger event fired together.
8. **Idle and expanded memory recorded** against the M1 baseline, with the camera panel measured separately; still under 300 MB (`../risks-and-decisions.md` R4).

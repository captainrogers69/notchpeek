# NotchNest — technical breakdown

**Date:** 2026-09-04
**Subject:** NotchNest 1.2.5, Mac App Store build, 34 MB
**Method:** static inspection — `Info.plist`, code-signing entitlements, linked frameworks, bundled resources, type names recovered from the binary.
**Purpose:** learn what shipped and what the App Store allowed, then name the places where a Flutter build cannot copy a SwiftUI one.

---

## 1. Shape of the app

| Property | Value |
|---|---|
| UI stack | SwiftUI over AppKit |
| Minimum OS | macOS **14.0** |
| App class | agent app — `LSUIElement = true`, no Dock icon |
| Sandbox | **on**, full App Store sandbox |
| Bundle size | 34 MB |
| Team / identity | `25DZLP69MU`, `com.silverseahog.notchnestapp` |

Shell types: `TopNotchViewModel`, `TopNotchViewCoordinator`, `NotchSizeManager`, `PopoverPanel`, `TabSelectionView`. So the same division our own design reached independently — one coordinator owning the notch window, a view model owning state, a separate manager for notch dimensions.

Mouse handling: `LocalEventMonitor` and `RunLoopLocalEventMonitor`. Local monitors, not global ones, and no Accessibility entitlement anywhere in the bundle — they never ask for Accessibility permission. Same conclusion our design reached: `.mouseMoved` monitoring needs no scary prompt.

## 2. Permissions, and what the App Store allowed

The entitlement set is the single most useful artifact in the bundle, because it is a list of things Apple approved.

| Entitlement | Purpose |
|---|---|
| `com.apple.security.app-sandbox` | required for MAS |
| `com.apple.security.automation.apple-events` | send Apple Events at all |
| **`com.apple.security.temporary-exception.apple-events`** → `com.apple.Music`, `com.spotify.client` | script exactly those two apps |
| `com.apple.security.personal-information.calendars` | EventKit |
| `com.apple.security.device.camera` | webcam panel |
| `com.apple.security.files.user-selected.read-write` | file shelf |
| `com.apple.security.network.client` | artwork lookups, web players |
| `com.apple.developer.ubiquity-kvstore-identifier` | iCloud settings sync |
| mach-lookup: `…-spks`, `…-spki` | Sparkle updater XPC |

**The load-bearing finding: the temporary-exception route works.** A sandboxed App Store app can read now-playing from Music and Spotify by naming them in a temporary exception. Our spike proved the system-wide read path is closed; this proves the per-app path is not just possible but *shippable on MAS*. Every media feature we planned survives on both channels.

Two corollaries:

- The exception is **per bundle id**, so every additional scriptable player is another entitlement line and another review justification.
- `NSAppleEventsUsageDescription` in their `Info.plist` reads *"Grant access to display information about currently playing music"* — the user-facing consent copy. We need our own equivalents for Apple Events, calendar, camera and notifications.

**No MediaRemote.** No private framework appears in the linkage — expected, since it would be an automatic MAS rejection. Note that a `dlopen` of MediaRemote would not appear in static linkage either, so this is not proof they never touch it in a direct build; it is proof the MAS build does not link it.

## 3. Persistence

Two stacks side by side, both with explicit migration paths:

| Data | Store | Evidence |
|---|---|---|
| Clipboard history | Core Data | `ClipboardItem.momd`, `ClipboardMigrationManager` |
| Notes | SwiftData | `NotesMigrationManager` |
| Settings | `UserDefaults` via the `Defaults` library, synced by iCloud KV | `Defaults_Defaults.bundle` |

The presence of *two* migration managers in a 1.2.5 release says the schemas already changed under real users. Worth taking as a warning: clipboard and notes are the features whose data model will move, so their persistence layer should be the one we design most carefully.

## 4. Third-party dependencies

| Library | Role |
|---|---|
| **Luminare** | the settings UI — `LuminareModalView`, `LuminareListItem`, `LuminareTrafficLightedWindowView`, `LuminareCroppedSectionItem` |
| **Defaults** | typed `UserDefaults` |
| **KeyboardShortcuts** | user-configurable global hotkeys |
| **Sparkle** | direct-download updates |
| Firebase Core / Analytics / Crashlytics, GoogleUtilities, GoogleDataTransport, nanopb, Promises | instrumentation |

Most of the 34 MB is Google. The app's own code is a small fraction of the bundle.

`KeyboardShortcuts` matters for parity: user-assignable global hotkeys are a feature we have not specified anywhere, and it is the kind of thing power users treat as table stakes.

## 5. Where Flutter cannot simply copy this

Four places. Two are solved, one needs a decision, one is a genuine unknown.

### 5.1 Hosting a `WKWebView` — needs a platform view

The YouTube Music and QQ Music panels are live web players. Flutter draws to its own canvas; a `WKWebView` is a real `NSView` that must be composited into it. Flutter macOS supports platform views, but the composited path is slower than a pure Flutter layer and interacts badly with clipping — and our notch panel is an animated, non-rectangular clip.

Likely shape: keep the web player in a **separate native window** positioned under the expanded panel, or accept a rectangular sub-region inside the panel where clipping is not applied. This is the single biggest Flutter-versus-Swift cost in the parity list, and it should get its own spike before M4 is planned.

### 5.2 A SpriteKit game — reimplement, don't embed

The game is `SpriteKitGameView`. Embedding SpriteKit inside Flutter means the same platform-view problem for a surface that must hold 60 fps. Flutter draws games perfectly well on its own (`CustomPainter`, or `flame`), so the game should be **rebuilt in Dart** rather than hosted. Parity here is parity of the *feature*, not of the technology.

### 5.3 Vibrancy — decide once, early

`NSVisualEffectView` blur cannot be drawn by Flutter. Real vibrancy behind an animated non-rectangular panel needs an AppKit mask layer animating in lockstep with Flutter's clock: two clocks, visible shimmer. The recommendation stands from the archived design — **ship an opaque near-black panel**, which is what the mockup shows and what most notch apps use. Decide it now, because retrofitting vibrancy later means rebuilding the shell.

### 5.4 On-device AI is a hard OS split

`FoundationModels` exists only on macOS 26. NotchNest's 14.0 floor therefore forces availability annotations and an absent-not-degraded AI panel on older systems.

**We avoid this entirely by shipping a macOS 26 floor** (see `../risks-and-decisions.md`, R1). The trade is reach for simplicity: no availability branching, no pre-26 test matrix, but a much smaller addressable market than theirs. The capability probe still reports OS availability, and the tab strip still renders a variable tab count — both are cheap, and both stop a future floor change from being a rewrite.

## 6. Carried forward

Confirmed by this teardown, and already in our plan:

1. Agent app, `LSUIElement`, no Dock icon.
2. Local event monitors for hover; never request Accessibility.
3. Per-app scripting for media — and it clears App Store review with a temporary exception.
4. One coordinator + view model + geometry manager for the shell.
5. Sparkle present in both builds, inert on MAS.

New, from this teardown, not previously specified:

6. **User-configurable global hotkeys** (their `KeyboardShortcuts`) — a parity gap we had not written down.
7. **iCloud settings sync** — cheap with `NSUbiquitousKeyValueStore`, and it makes a two-Mac user's life better.
8. **Migration managers from day one** for clipboard and notes, because their schemas provably move.
9. **A named vibrancy decision**, resolved before the shell is built rather than after.

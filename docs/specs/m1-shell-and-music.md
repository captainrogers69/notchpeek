# M1 — Notch shell and music

**Date:** 2026-09-04
**Status:** draft
**Target:** macOS 26.0+, Apple Silicon and Intel. Dev machine: MacBook Air M2 (notched), macOS 26.5.1, Flutter 3.44.4 / Dart 3.12.2.
**Budget:** ship in **3 weeks**. See `../risks-and-decisions.md` R3 for the week-by-week cut.
**Ships as:** a usable notch app — invisible at rest, peek on events, expand on hover, with working music controls.

Supersedes the native-core sections of `archive/2026-09-04-notchpeek-v1-design.md`. Reads with `../research/notchnest-technical.md` and `2026-09-04-spike-system-nowplaying.md`.

---

## 1. Goal

One milestone, one sentence: **the notch behaves, and it plays music.**

Everything in M2–M4 is a panel that slots into what this milestone builds. If the shell is wrong, every later milestone inherits the wrongness, so this is the only milestone where the hard problem is the *container* rather than the contents.

### In scope

Native window and geometry, mouse passthrough, the morph animation, notch silhouette, tab strip, battery pill, settings window, capability probe, and the music panel against Apple Music and Spotify.

### Out of scope

Every other panel. Monetization entirely — no StoreKit, no paywall, no metering, in this or any milestone doc. Web-based players (M4). MediaRemote command path (§9).

## 2. Decisions locked here

These four are cheap to decide now and expensive to change later. They are locked as part of M1, not deferred.

| Decision | Choice | Why now |
|---|---|---|
| **Panel background** | **Opaque near-black. No `NSVisualEffectView`.** | Real vibrancy behind an animated non-rectangular panel needs an AppKit mask layer animating against Flutter's clock — two clocks, visible shimmer. Retrofitting vibrancy later means rebuilding the shell, so the decision cannot wait. This is also what the mockup shows. |
| **Settings window** | Native SwiftUI window, not Flutter | Flutter desktop multi-window is young. A second Flutter engine for a settings pane is cost with no benefit. |
| **Non-notched Macs** | Synthesize a virtual notch, ~200×32, centred | The app must work on every Mac. On notched hardware it happens to hide inside real hardware. |
| **Media command path** | Scripting, not MediaRemote, in M1 | Scripting commands work for both target players and on both distribution channels. MediaRemote buys us players with no scripting dictionary — real, but not needed for two sources. See §9. |

## 3. Native core

The crux. Everything else is a widget rendered inside what this section builds.

### 3.1 One invisible canvas, never resized

The naive approach resizes the `NSWindow` each frame to animate the notch. That janks and desyncs from Flutter's animation clock.

Instead: **one** borderless `NSPanel`, sized once to `screenWidth × ~420pt`, pinned to the top of the notched screen. It never changes size. Every expand, collapse and peek is a Flutter animation painted inside that fixed transparent canvas.

```
styleMask          = [.borderless, .nonactivatingPanel]   // NSPanel → never steals focus
isOpaque           = false
backgroundColor    = .clear
hasShadow          = false
level              = .mainMenu + 1                        // above the menu bar
collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
isMovable          = false
```

`LSUIElement = true` in `Info.plist` makes this an agent app: no Dock icon, no menu bar of its own. Confirmed as the right shape by NotchNest, which does the same.

The Flutter side of transparency: window `isOpaque = false` plus a clear `FlutterViewController` background, so Dart paints the only visible pixels.

### 3.2 Mouse passthrough

A transparent full-width window would swallow every click across the menu bar. So the panel runs `ignoresMouseEvents = true` by default, and Swift flips it off only while the cursor sits inside the rect Dart says it is currently interactive in.

Dart owns that rect and pushes it down on every state change:

- collapsed → the notch hot-zone (notch rect, inflated a few points)
- peeking → the pill rect
- expanded → the full panel rect

Driven by a **local** event monitor on `.mouseMoved`, which needs **no Accessibility permission**. NotchNest uses local monitors and requests no Accessibility entitlement either — independent confirmation that nothing scary needs to prompt at launch.

### 3.3 Notch geometry

Read `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea` — the regions flanking the notch — and derive the notch rect from the gap between them.

If `safeAreaInsets.top == 0` there is no notch (external display, an Air driving a Studio Display, pre-2021 hardware). Synthesize the virtual notch from §2 and run identically.

Observers on `NSApplication.didChangeScreenParametersNotification` and `NSWorkspace.activeSpaceDidChangeNotification` recompute geometry and move the panel to the active screen.

### 3.4 Swift modules

| Module | Owns |
|---|---|
| `NotchWindowController` | the NSPanel, window level, collection behavior, screen follow |
| `NotchGeometry` | notch rect resolution, virtual-notch fallback, screen observers |
| `MouseGate` | local mouse monitor, `ignoresMouseEvents` toggling against Dart's rect |
| `MediaBridge` | `MusicSource` protocol, `AppleMusicSource` / `SpotifySource`, active-source selection |
| `PowerBridge` | IOKit battery percentage and charging edge, drives the peek |
| `CapabilityProbe` | what this build, this OS version and these permissions can actually do |
| `SettingsWindow` | the native SwiftUI settings window |

Each module answers three questions on its own: what it does, how you use it, what it depends on. `MediaBridge` is the only one with an internal strategy choice, and that choice hides behind `MusicSource`.

### 3.5 Channels

One `MethodChannel` for commands, three `EventChannel`s for streams. The set is fixed here and extended by later milestones rather than redesigned.

| Channel | Direction | Carries |
|---|---|---|
| `notchpeek/control` (Method) | Dart → Swift | `setInteractiveRect`, `mediaCommand`, `openSettings`, `requestPermission`, `getCapabilities` |
| `notchpeek/media` (Event) | Swift → Dart | now-playing track, playback state, position ticks |
| `notchpeek/system` (Event) | Swift → Dart | geometry changes, battery and charging, capability changes |
| `notchpeek/calendar` (Event) | Swift → Dart | reserved for M2 |

**Artwork crosses once per track change, keyed by track id — never on the position tick.** The tick fires about twice a second; shipping an image through it would eat the app's whole CPU budget.

## 4. Media, as the spike found it

`docs/specs/2026-09-04-spike-system-nowplaying.md` measured this on the dev machine. Two rules fall out of it:

1. **Reads are per-app scripting only.** System-wide now-playing is gated on macOS 26: the info dictionary comes back empty, the client is nil, no notifications fire. It fails **silently**, so `MediaBridge` must treat an empty reply as *unavailable*, never as *nothing playing*.
2. **Never shell out to `osascript`.** Measured at ~130 ms per round trip, which is process-spawn cost. `MediaBridge` uses in-process ScriptingBridge. Even so, position polling is the most expensive thing the app does — poll at 1 Hz while expanded, stop entirely while collapsed.

Two normalizations belong in Swift, not Dart, so Dart sees one shape:

| Problem | Rule |
|---|---|
| Spotify reports `duration` in **milliseconds** and `player position` in **fractional seconds** | normalize to `Duration` at the bridge boundary; unit-test it |
| Spotify gives artwork as a **URL**, Apple Music as **bytes** | fetch, cache by track id, hand Dart one shape |

Consent copy needed in `Info.plist`: `NSAppleEventsUsageDescription`. For the App Store build later, the temporary-exception entitlements for `com.apple.Music` and `com.spotify.client` — proven shippable by NotchNest.

## 5. Dart architecture

Structure, layering, state management, DI and naming are governed by **[`../playbook/architecture-playbook.md`](../playbook/architecture-playbook.md)**, not by this document. Read it first. What follows is only which features M1 creates inside that structure.

```
lib/
  main.dart                       bootstrap; wait for geometry before first frame
  app/                            notch_app.dart, theme.dart (colors, radii, motion tokens)
  core/
    logging/                      NotchLogger
    platform/                     channels.dart, channel_service.dart, capabilities.dart
    network/ services/            ApiResponse, ApiErrorHandler, Dio ApiService (artwork only)
  features/
    shell/                        the container — state machine, notch shape, morph,
                                  tab strip, status row, interactive-rect reporting
      data/ domain/ presentation/
    music/                        the only panel in M1
      data/ domain/ presentation/
  shared/
    widgets/                      scrubber, artwork tile, icon button, marquee text,
                                  permission prompt, panel scaffold
    utils/                        helpers, enums, extensions
```

`features/shell/` is the container, not a panel. Panels render inside it and know nothing about it.

Per the playbook: **`hooks_riverpod` only**, `Notifier`/`AsyncNotifier` (never `StateNotifier`), a `StreamProvider` per `EventChannel`, Riverpod as the DI layer with no `get_it`, and no routing package — tab selection is state, settings is a native SwiftUI window.

**The tab strip renders a variable number of tabs from the start.** M4's AI panel is absent below macOS 26, so a fixed tab count would have to be torn out later.

### 5.1 The morph

One `AnimationController` in `NotchShell` drives width, height and corner radius through tweens. About 350 ms to open on `easeOutQuint`, 250 ms to close. Content cross-fades with an `AnimatedSwitcher` staggered slightly behind the container growth, so the box arrives before the contents do.

`NotchShape` is a custom clipper: rounded bottom corners and **concave** top corners where the panel flares out from the notch. That inverted curve is what makes it read as one continuous piece of hardware instead of a floating rectangle.

### 5.2 Data flow

```
Swift stream → EventChannel → Dart Stream → StreamProvider → panel widget
widget → controller → MethodChannel → Swift
shell state change → post-frame measure → setInteractiveRect → MouseGate
```

## 6. Capability probe

Reports at launch and on change. The field set is deliberately wider than M1 needs, because later milestones add to it and the shape should not churn.

```
{
  buildFlavor:            direct | mas,
  osSupportsOnDeviceAI:   bool,     // macOS 26+, for M4
  scriptingMedia:         { appleMusic: granted | denied | notDetermined,
                            spotify:    granted | denied | notDetermined },
  systemWideMediaRead:    bool,     // false on macOS 26; kept so it flips if Apple reopens it
  systemWideMediaCommand: bool,
  calendar:               granted | denied | notDetermined,   // M2
  camera:                 granted | denied | notDetermined | absent   // M3
}
```

The probe reports **OS availability as well as permission state**. That is what makes the AI panel's absence expressible.

**Every panel renders three ways**, from M1 onward:

1. **Ready** — the real widget.
2. **Needs permission** — an explanation and an Open Settings button.
3. **Unavailable** — the feature does not exist in this build or on this OS. Hidden, not teased.

## 7. Error handling

| Failure | Response |
|---|---|
| Scripting read returns empty | Treat as *unavailable*, not *nothing playing*. Render the needs-permission state. |
| Apple Events consent denied | Music panel renders needs-permission. Requires `NSAppleEventsUsageDescription`. |
| Neither player running | Idle artwork placeholder. |
| `EventChannel` dies | Dart reconnects with exponential backoff. |
| Display disconnected mid-expand | Collapse, recompute geometry, reposition to the active screen. |
| Launched before geometry resolved | Render nothing. Never flash a misplaced panel. |
| Artwork fetch fails | Placeholder; never block the track update on the image. |

## 8. Testing

Per TDD: tests first on the pure logic. Native window behavior is verified by hand, because it cannot be automated.

**Dart unit** — notch state machine transitions; interactive-rect maths; virtual-notch fallback; position-tick throttling; `NowPlaying` parsing; **the ms-versus-seconds normalization**.

**Dart widget** — golden tests for collapsed, peek and expanded shell; the music panel in all three capability states; the tab strip at two, three and four tabs.

**Swift unit** (XCTest in `RunnerTests`) — geometry derivation from synthetic screen values; `MouseGate` hit-testing; `MusicSource` selection against a stubbed source.

**Manual matrix** — notched vs non-notched hardware; external display; Space switch; fullscreen app; light vs dark menu bar. The dev machine is on 26.5.1, which is the floor, so no second OS is needed.

## 9. Deferred, deliberately

- **MediaRemote command path.** The spike proved `MRMediaRemoteSendCommand` works unsigned, unentitled and unprompted, and it controls players with no scripting dictionary. It is also a private framework, so it is direct-build only. Worth adding once more sources exist; not worth the dual code path for two scriptable players. Revisit in M4.
- **Live-activity peeks beyond charging and track change.** The peek mechanism ships in M1; the catalogue of events that trigger it grows per milestone.

## 10. Exit criteria

M1 is done when all of these are true:

1. At rest, the notch is visually indistinguishable from stock hardware, and clicks anywhere in the menu bar reach the app underneath.
2. Hover expands within 350 ms; leaving collapses. No frame drops on the dev machine.
3. Track change and charger connect each produce a peek that retracts on its own.
4. Music panel controls Apple Music and Spotify: play, pause, next, previous, seek.
5. Denying Apple Events consent produces the needs-permission state, not a crash or an empty panel.
6. Works on a non-notched display via the virtual notch.
7. Survives a Space switch, a fullscreen app, and unplugging an external display mid-expand.
8. Settings window opens, and the app launches at login.
9. **Signed, notarized and installable** from a download — not just `flutter run` on the dev machine. See `../risks-and-decisions.md` R7.
10. **Idle memory under 300 MB**, recorded here as the baseline every later milestone is measured against.

Criteria 9 and 10 are the two most likely to be skipped and the two most expensive to skip.

# Torana — MacBook notch app, v1 design

**Date:** 2026-09-04
**Status:** draft, awaiting review
**Target:** macOS 26+, Apple Silicon. Dev machine: MacBook Air M2 (notched), macOS 26.5.1, Flutter 3.44.4 / Dart 3.12.2.

---

## 1. What this is

**Torana** (तोरण) — the ornamental arch spanning the top of an entrance, as at Sanchi. The Sanskrit name for exactly what this app is: a beam across the top of an opening. Verified clear of Mac software and of the eleven notch apps currently shipping.

A notch companion for MacBook. At rest the notch looks stock. Hover it and a dark panel drops open with widgets: music, calendar, and later a focus timer, an AI scratchpad and a camera mirror. System events (track change, charger plugged in) briefly widen the notch into a small "live activity" pill that then retracts.

Reference design: `docs/design/initial-mockup.png` — the expanded state, five panels side by side, with a tab bar, battery readout, settings and close in the top chrome.

### Decisions locked during brainstorming

| Decision | Choice | Why |
|---|---|---|
| UI stack | Flutter + Swift platform layer | Keeps the existing scaffold; Flutter's animation control suits the morph. ~35-40% of the app is Swift regardless of stack. |
| Distribution | Both: Mac App Store build + direct download build | Reach plus capability. Direct is the real product; MAS is a reduced funnel. |
| v1 panels | Notch shell, music, calendar | Focus timer, AI panel, camera deferred — the shell is the hard part and everything else slots into it. |
| Music source | Hybrid, runtime-selected | System-wide now-playing where allowed, AppleScript to Spotify/Music as fallback. Panel degrades, never dies. |
| Idle behavior | Invisible at rest, hover to expand, peek on events | Zero visual footprint when unused. |

### Out of scope for v1

Focus timer, AI/notes panel, camera mirror, file shelf/tray, notification mirroring, iPhone mirroring, multi-monitor notch on every display simultaneously.

---

## 2. Native core

The crux of the app. Everything else is a widget rendered inside what this section builds.

### 2.1 One big invisible canvas, never resized

The naive approach animates the notch by resizing the `NSWindow` each frame. That janks and desyncs from Flutter's animation clock.

Instead: **one** borderless `NSPanel`, sized once to `screenWidth × ~420pt` and pinned to the top of the notched screen. It never changes size. Every expand, collapse and peek is a Flutter animation painted inside that fixed transparent canvas.

```
styleMask          = [.borderless, .nonactivatingPanel]   // NSPanel → never steals focus
isOpaque           = false
backgroundColor    = .clear
hasShadow          = false
level              = .mainMenu + 1                        // above the menu bar
collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
isMovable          = false
```

`LSUIElement = true` in `Info.plist` makes this an agent app: no Dock icon, no menu bar of its own. Settings opens as a separate ordinary window.

### 2.2 Mouse passthrough

A transparent full-width window would swallow every click across the menu bar. So the panel runs `ignoresMouseEvents = true` by default and Swift flips it off only while the cursor sits inside the rect Dart is currently interactive in.

Dart owns that rect and pushes it down on every state change:

- collapsed → the notch hot-zone (notch rect, inflated a few points)
- peeking → the pill rect
- expanded → the full panel rect

`NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)` drives the check. `.mouseMoved` requires **no Accessibility permission**, so nothing scary prompts at launch.

### 2.3 Notch geometry, and Macs without a notch

Read `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea` — the regions flanking the notch — and derive the notch rect from the gap between them.

If `safeAreaInsets.top == 0` there is no notch (external display, Air driving a Studio Display, older hardware). In that case **synthesize a virtual notch** of ~200×32 centred at the top of the screen and run identically. The app works on every Mac; on notched hardware it happens to hide inside real hardware.

Observers on `NSApplication.didChangeScreenParametersNotification` and `NSWorkspace.activeSpaceDidChangeNotification` recompute geometry and move the panel to the active screen.

### 2.4 Swift modules

| Module | Owns |
|---|---|
| `NotchWindowController` | the NSPanel, window level, collection behavior, screen follow |
| `NotchGeometry` | notch rect resolution, virtual-notch fallback, screen observers |
| `MouseGate` | global mouse monitor, `ignoresMouseEvents` toggling against Dart's rect |
| `MediaBridge` | `MusicSource` protocol + `SystemWideSource` / `AppleScriptSource`, fallback ladder |
| `CalendarBridge` | EventKit auth, today's events, store-changed observer |
| `PowerBridge` | IOKit battery percentage and charging edge, drives the peek |
| `CapabilityProbe` | what this build and these permissions can actually do — single source of truth for MAS-vs-direct gating |

### 2.5 Channels

One `MethodChannel` for commands and three `EventChannel`s for streams.

| Channel | Direction | Carries |
|---|---|---|
| `macpro/control` (Method) | Dart → Swift | `setInteractiveRect`, `mediaCommand(play/pause/next/prev/seek)`, `openSettingsPane`, `requestPermission`, `getCapabilities` |
| `macpro/media` (Event) | Swift → Dart | now-playing track, playback state, position ticks |
| `macpro/calendar` (Event) | Swift → Dart | today's events, auth state changes |
| `macpro/system` (Event) | Swift → Dart | geometry changes, battery/charging, capability changes |

**Artwork crosses once per track change, keyed by track id — never on the position tick.** The tick fires roughly twice a second; shipping a JPEG through it would consume the app's entire CPU budget.

---

## 3. Dart architecture

### 3.1 Layout

```
lib/
  main.dart                    bootstrap; wait for geometry before first frame
  app/
    notch_app.dart             root widget
    theme.dart                 colors, radii, motion tokens
  shell/
    notch_shell.dart           the morphing container, owns shell state
    notch_state.dart           collapsed | peek(kind) | expanded
    notch_shape.dart           CustomClipper — notch silhouette, concave top corners
    interactive_rect.dart      measures current rect, pushes to Swift
    tab_bar.dart               home / tray / game / clipboard tabs
    status_row.dart            battery, settings, close
  panels/
    music/                     MusicPanel, MusicController, NowPlaying model
    calendar/                  CalendarPanel, CalendarController, CalendarEvent model
  platform/
    channels.dart              typed wrappers over the four channels
    capabilities.dart          Capability enum, probe result
    media_source.dart          NowPlaying stream
    calendar_source.dart
    power_source.dart
  ui/                          shared: scrubber, artwork tile, icon button, marquee text
```

State management: **Riverpod**, no codegen. The native side is already stream-shaped, so `StreamProvider` over each `EventChannel` is a direct fit and keeps panels free of lifecycle code.

### 3.2 The morph

A single `AnimationController` in `NotchShell` drives width, height and corner radius through tweens. Roughly 350ms to open on `easeOutQuint`, 250ms to close. Panel content cross-fades with an `AnimatedSwitcher` staggered slightly behind the container growth, so the box arrives before the contents do.

`NotchShape` is a custom clipper: rounded bottom corners, and **concave** top corners where the panel flares out from the notch — that inverted curve is what makes it read as one continuous piece of hardware rather than a floating rectangle.

### 3.3 Data flow

```
Swift stream → EventChannel → Dart Stream → StreamProvider → panel widget
widget → controller → MethodChannel → Swift
shell state change → post-frame measure → setInteractiveRect → MouseGate
```

---

## 4. Capability gating and the two builds

`CapabilityProbe` reports, at launch and on change:

```
{
  buildFlavor:      mas | direct,
  systemWideMedia:  bool,
  appleScriptMedia: bool,
  calendar:         granted | denied | notDetermined,
  camera:           granted | denied | notDetermined | absent
}
```

Build flavor comes from `--dart-define=FLAVOR=` plus separate Xcode configurations and entitlements files.

**Every panel renders three ways:**

1. **Ready** — the real widget.
2. **Needs permission** — an explanation and an Open Settings button, exactly the state already drawn in the mockup's camera panel.
3. **Unavailable** — the feature does not exist in this build. The MAS build **hides** these rather than teasing a button that cannot work.

---

## 5. Error handling

| Failure | Response |
|---|---|
| System-wide now-playing throws or returns nothing | `MediaBridge` demotes to `AppleScriptSource`, emits a capability change. UI shows a source badge change, never an error. |
| AppleScript consent denied | Music panel renders the needs-permission state. Requires `NSAppleEventsUsageDescription`. |
| EventChannel dies | Dart reconnects with exponential backoff. |
| Nothing playing | Idle artwork placeholder — the grey note tile in the mockup. |
| Display disconnected mid-expand | Collapse, recompute geometry, reposition to the active screen. |
| App launched before geometry resolved | Render nothing. Never flash a misplaced panel. |

---

## 6. Testing

**Dart unit** — notch state machine transitions, interactive-rect maths, virtual-notch fallback, position-tick throttling, `NowPlaying` parsing.

**Dart widget** — golden tests for collapsed, peek and expanded shell; each panel in all three capability states.

**Swift unit** (XCTest in `RunnerTests`) — geometry derivation from synthetic screen values, `MouseGate` hit-testing, the `MusicSource` fallback ladder against a stubbed system source.

**Manual matrix** — cannot be automated: notched vs non-notch hardware, external display, Space switch, fullscreen app, light vs dark menu bar.

Per TDD: tests first on the pure logic — state machine, geometry maths, fallback ladder. Native window behavior is verified by hand.

---

## 7. Build order

0. **Spike** — confirm whether system-wide now-playing is reachable on macOS 26. Timeboxed. Not fatal either way, since the AppleScript fallback is the guaranteed path.
1. **Shell, native** — panel, window level, geometry, passthrough.
2. **Shell, Dart** — state machine, morph animation, notch shape, tab bar, status row.
3. **Capability probe + dual flavor plumbing.**
4. **Calendar panel** — lowest risk, proves the channel pattern end to end.
5. **Music panel** — AppleScript source first because it is guaranteed; system-wide layered on top.
6. **Peek events** — track change, charging.
7. **Settings window, launch at login, packaging.**

---

## 8. Competitive landscape

This market is crowded. Eleven Mac notch apps were found while checking name availability, several of them mature. Differentiation matters more than the feature list, because the feature list is already commoditised.

| App | Position |
|---|---|
| **Alcove** | $5 one-time. Dynamic Island feel: music, AirPods battery, charging animations, short notifications. The only one supporting multiple simultaneous live activities, and it works on the lock screen. The bar to clear. |
| **Perch** (Dynamic Notch Island) | Mac App Store. Music, weather, camera, calendar, timer, clipboard snippets, file tray. Handles non-notched Macs. Feature-for-feature the closest to our mockup. |
| **Canopy** | Direct download. Notifications, media controls, file utilities. Productivity-leaning. |
| **NotchNook** | Paid, one of the most established. |
| **The Boring Notch** | Open source, free, Swift. The reference implementation everyone forks. |
| **Brow** | Free. Screenshots, focus timer, system monitor, file drop, menu bar manager. |
| **MediaMate**, **Notchmeister**, **NotchNest**, **Notchy**, **Seam** | Various free and paid, mostly single-purpose. |
| **TopNotch** | Inverse product — hides the notch rather than using it. |

**Implication for v1.** Building music + calendar + timer + AI + camera reaches parity with Perch and Canopy and beats nothing. Before implementation starts, Torana needs one defensible answer to "why this instead of Alcove". Candidates worth deciding between: superior live-activity handling (Alcove's own differentiator, so a hard fight), a genuinely better-designed expanded panel, or a widget the others lack. **This is an open decision, not a settled one.**

## 9. Open questions

- **Premium** — what is behind "Explore Premium"? Which panels or features are paid, and what licensing backend (Paddle / LemonSqueezy / Gumroad)?
- **Rate App** — where does it point for the direct build, which has no App Store listing?
- **Bundle id** — `com.example.macpro` must become a real reverse-domain id, e.g. `com.<yourdomain>.torana`, before signing.
- **Updates** — Sparkle for the direct build?

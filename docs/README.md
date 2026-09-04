# NotchPeek docs

**Target:** full NotchNest feature parity, macOS 26.0+, Flutter with a Swift platform layer. Direct download first, App Store later. **v1 ships free — monetization is out of scope in every milestone doc.**

## Read in this order

| Doc | What it answers |
|---|---|
| [`risks-and-decisions.md`](risks-and-decisions.md) | Every call that shapes the build, and what is still open. Newer than the milestone docs where they disagree |
| [`info/identity.md`](info/identity.md) | What the app and studio are called, bundle id, store-account constraints |
| [`research/notchnest-features.md`](research/notchnest-features.md) | What we are matching: 11 panels, 4 media sources, free-vs-paid mechanics |
| [`research/notchnest-business.md`](research/notchnest-business.md) | How they price and distribute it, and what to carry or reject |
| [`research/notchnest-technical.md`](research/notchnest-technical.md) | How they built it, what the App Store allowed, where Flutter cannot copy SwiftUI |
| [`specs/2026-09-04-spike-system-nowplaying.md`](specs/2026-09-04-spike-system-nowplaying.md) | Spike 0: system-wide now-playing is gated; reads use per-app scripting |
| [`specs/m1-shell-and-music.md`](specs/m1-shell-and-music.md) | The native core, and music. The hard milestone |
| [`specs/m2-calendar-clipboard-shelf.md`](specs/m2-calendar-clipboard-shelf.md) | Calendar, clipboard, file shelf, global hotkeys |
| [`specs/m3-timer-notes-webcam.md`](specs/m3-timer-notes-webcam.md) | Timer, notes, webcam, settings sync |
| [`specs/m4-web-players-game-ai.md`](specs/m4-web-players-game-ai.md) | Web players, game, AI, i18n, updates. Opens with a spike |

Every milestone ships as a usable app. Each one lists its own exit criteria.

**Near-term target:** M1 shipped in **3 weeks** — see `risks-and-decisions.md` R3 for the week-by-week cut, and R7 for the signing and notarization work that gates it.

## Conventions

- **`research/`** describes NotchNest. Evidence from static bundle inspection; inference is labelled as such. We match features, never code or assets.
- **`specs/`** describes NotchPeek. One doc per milestone, plus dated spike reports.
- **`specs/archive/`** is superseded. Never plan work from it.
- A spike report is closed when written and is not edited afterwards. When a spike contradicts a spec, the spec changes.

## Still to come

- **The coding playbook** — architecture and coding practices. Governs *how* we build; these docs govern *what*. Until it lands, M1 §3.4 and §5 are provisional (R2).
- **Spike 1** — `WKWebView` compositing inside the notch panel. Gates M4's web players (R8). See M4 §2.
- **Monetization** — deferred until there is a working model, then decided against real usage (R5).

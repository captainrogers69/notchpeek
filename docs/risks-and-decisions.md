# Risks and decisions

**Date:** 2026-09-04
**Purpose:** one place for the calls that shape the build, and the risks still outstanding. Every entry is either **decided** — with its consequence written down — or **open**, with the thing that would close it.

When a milestone doc and this document disagree, this document is newer.

---

## Index

| # | Topic | Status |
|---|---|---|
| R1 | OS floor | **decided** — macOS 26.0 |
| R2 | Playbook will revise M1's architecture | **closed** — playbook written, M1 reconciled |
| R3 | Scope versus a 3-week ship | **decided** — 3 weeks buys M1, not parity |
| R4 | Memory budget | **decided** — 300 MB |
| R5 | Monetization | **deferred** — after a working model |
| R6 | Differentiation | **open** |
| R7 | Release engineering | **open** — blocks any ship date |
| R8 | `WKWebView` compositing | **open** — gates M4 |
| R9 | IP boundary | **decided** — parity, then diverge |
| R10 | `lib/` does not compile | **open** — blocks all Dart work |

---

## R1 — OS floor: macOS 26.0

**Concern raised:** NotchNest ships a 14.0 floor. Matching features but not reach means losing on machines we refuse to run on. But the AI panel needs `FoundationModels`, which is 26-only, so a 14.0 floor forces availability branching and a two-OS test matrix we have no second machine for.

**Decided:** ship **macOS 26.0**. Few enough users are on 14/15 to justify the simplicity.

**Consequences, all good:**

- No availability annotations anywhere. The AI panel stops being an OS split (M4 §5).
- No second OS in the test matrix. The dev machine at 26.5.1 *is* the floor, so M1's old "verify on macOS 14" exit criterion is gone — and with it the concern that we had no way to test it.
- Every modern API is simply available.

**Consequence to watch:** the addressable market is materially smaller than NotchNest's. If that becomes the growth constraint, lowering the floor later means adding availability branching to the AI panel only — the tab strip already renders a variable tab count and the capability probe already reports OS availability, both kept deliberately so this is not a rewrite.

**Applied:** `MACOSX_DEPLOYMENT_TARGET = 26.0` in all three configs.

## R2 — The playbook will revise M1's architecture

**Closed.** `../playbook/architecture-playbook.md` is written and is now the authority on structure, state, layering, DI and naming. **When any choice touches architecture, that document is read first** — ahead of the milestone specs, which describe features, not conventions.

What it settled: `hooks_riverpod` locked (no `flutter_bloc`, no `get_it`, no `StateNotifier`), feature-first Clean Architecture in three layers, Riverpod as the DI graph, `NotchLogger` as the only logging path, Dio behind a single `ApiService`, and a Swift-boundary section with no equivalent in either reference playbook.

**Reconciled:** M1 §5's flat tree was replaced by the playbook's feature-first layout and now defers to it rather than restating it. M1 §3.4's Swift module names already matched playbook §4.3.

**Left open by it:** §12 of the playbook — the repo does not match the playbook yet. See R10.

## R3 — Scope versus a 3-week ship

**Concern:** full NotchNest parity is 11 panels, 4 media sources and 8 locales. That is not three weeks of work.

**Decided:** the 3-week target is real, and what it buys is **M1 — the shell and music — shipped**. Parity remains the destination, reached through M2–M4 after that. This is not a reduction in ambition; it is naming which milestone the deadline applies to.

### The three weeks

| Week | Work | Done when |
|---|---|---|
| **1** | Native shell: `NSPanel`, transparency, window level, collection behavior, `NotchGeometry` + virtual-notch fallback, `MouseGate`, channel skeleton. Dart: state machine, morph animation, `NotchShape`. | Hover expands and collapses smoothly; clicks anywhere else in the menu bar pass through |
| **2** | `MediaBridge` (ScriptingBridge → Apple Music, Spotify), `PowerBridge`, `CapabilityProbe`. Dart: music panel, tab strip, status row, battery pill, peek on track change and charger. Native settings window. | The app is genuinely usable on the dev machine |
| **3** | Hardening: three capability states per panel, Space switch, fullscreen, display change mid-expand. Unit + golden tests. Memory measured against R4. Signing, notarization, a downloadable build. | M1 exit criteria met |

### What had to give

Week 3 originally carried both hardening *and* release engineering. First-time notarization plus a Sparkle appcast is easily most of a week on its own (see R7), which would eat the hardening.

**So: Sparkle moves out of the 3-week ship.** The first release is a notarized download with no auto-updater; the updater lands in M2. Users of a v0.1 shell can update by hand.

**Watch for:** week 1 is the week that decides the deadline. If the panel is not passing clicks through and morphing by the end of it, the honest move is to say so then, not in week 3.

## R4 — Memory budget: 300 MB

**Concern:** an always-on utility that costs half a gigabyte gets uninstalled regardless of its feature list. Flutter's engine is resident permanently, and M4 adds two WebKit instances plus a camera session on top.

**Decided: 300 MB idle**, measured and defended.

| Gate | Requirement |
|---|---|
| M1 | Idle footprint recorded as the baseline. Must be under 300 MB |
| M2 | Idle and expanded, compared to the M1 baseline |
| M3 | Camera panel measured separately — a video session is the single largest step |
| M4 | Worst case: both web players resident. **This is the measurement most likely to breach 300 MB** |

If M4 breaches it, the fix is in M4 §12's cut list — web players are the cost, and QQ Music goes first — not in shipping over budget quietly.

## R5 — Monetization

**Deferred, with a trigger:** v1 ships free. Monetization and pricing tiers get worked out **as soon as there is a working model**, not at some indefinite later date.

No StoreKit, paywall or metering appears in any milestone doc, so adding it is additive rather than a retrofit. `docs/research/notchnest-business.md` §6 holds the evidence for that conversation: NotchNest rents at $1.99/month with a 3-day trial and a metered free tier, Alcove sells outright at $5, and those are incompatible theories of what a notch utility is worth.

**Closes when:** M1 ships and the pricing decision is made against real usage.

## R6 — Differentiation

**Open.** The archived spec flagged "why this instead of Alcove" and it is still unanswered. Parity with NotchNest plus free is a position, but a thin one — NotchNest's $1.99/month is already close to free, so price alone is not a moat.

The sharper half is **privacy**: NotchNest ships Firebase Analytics, Crashlytics *and* Google ad-conversion endpoints with consent-mode flags, in a paid, permanently-resident utility. Shipping with no advertising SDKs is a claim we can make out loud and they cannot.

**Closes when:** a positioning decision is written down. Not blocking M1 — the shell is identical either way — but it should be settled before the app has a landing page.

## R7 — Release engineering

**Open, and it gates any ship date.** None of this is written down anywhere yet, and all of it is required before a stranger can run the app.

| Dependency | State | Note |
|---|---|---|
| Apple Developer Program membership | assumed active | `docs/info/identity.md` implies enrollment |
| **Developer ID Application certificate** | unverified | different from the App Store certificate; required for direct distribution |
| **Notarization** | not set up | a Gatekeeper requirement, not optional. Needs an app-specific password or API key in CI |
| **Hardened runtime** | not configured | required for notarization, and it interacts with Apple Events entitlements |
| Download hosting | undecided | `notchpeek.app` is **unregistered** (identity doc §2). **GitHub Releases works for v0.1 and removes the domain from the critical path** |
| Sparkle appcast | deferred to M2 | see R3. When it lands, the appcast URL is a **permanent** commitment — old installs poll it forever |
| `LSUIElement` + launch at login | specified, not built | M1 exit criterion 8 |

**Do first:** confirm the Developer ID certificate exists and notarize a throwaway build. A one-hour check in week 1 that prevents a week-3 surprise.

## R8 — `WKWebView` compositing

**Open. Gates M4's web players**, and it is the one parity item that cannot be scoped from outside.

Flutter draws to its own canvas; a `WKWebView` is a real `NSView`. Compositing a platform view into an animated, non-rectangular, clipped surface is slower than a pure Flutter layer and fights the clip — and the notch panel is animated, non-rectangular and clipped.

Three candidates, in M4 §2, cheapest first: a native view over a rectangular sub-region, a separate synchronized window, or a Flutter platform view. **Spike 1 answers it. If none is acceptable, cutting the web players is the honest outcome** — recorded, with reasons.

Two rehearsals happen first, deliberately: M2's file shelf and M3's camera preview both put a native view and the Flutter canvas in one rect. Whatever pattern works there is what spike 1 starts from.

## R9 — IP boundary

**Decided:** build to parity first, then diverge significantly once there is a working app. Parity is the reference point, not the destination.

Features are not protectable and the research docs describe behavior only, so the approach is sound. Three things stay clean regardless:

1. **No code.** Nothing is decompiled or transcribed. The research docs are built from `Info.plist`, entitlements, resource listings and type names.
2. **No assets.** Their `ARCADE_N.TTF` is a licensed font; their sounds and icons are theirs. We source our own.
3. **No pixel-copying.** Matching a feature is fine; reproducing their exact layout is not. Our own mockup (`design/initial-mockup.png`) already differs.

**Watch for:** the divergence in R9 and the positioning in R6 are the same conversation. Parity is what makes the app credible; what comes after parity is what makes it ours.

## R10 — `lib/` does not compile

**Open, and it blocks every line of Dart work.** `lib/` carries a partial transplant from the Go2Homes project: a Dio `ApiService`, error types, and two interceptors.

**`flutter analyze` reports 105 errors.** Causes, in order of size:

1. `dio`, `hooks_riverpod`, `flutter_hooks` and `equatable` are not in `pubspec.yaml` — only bare `flutter_riverpod` is.
2. Imports reference `package:gohomes/…`.
3. `dio_interceptor.dart` imports four files that do not exist here — a local storage service, a routing service, a login screen and a profile notifier.
4. `log_interceptor.dart` imports an `AppLogger` that does not exist.
5. `ApiService` reads its `baseUrl` from `ServiceBase`, a class from the other project.

**Two of these are not mechanical fixes.** The auth interceptor implements bearer-token injection and a 401 → clear-session → route-to-login flow. **NotchPeek has no accounts, no tokens and no login screen**, so that logic has no meaning here and is deleted rather than ported. Likewise `log_interceptor.dart` filters GraphQL presigned-URL traffic that does not exist in this app.

The full item list is playbook §12. **Closes when `flutter analyze` reports 0 errors.**

**Sequence:** this is week-1 work in R3, before the shell. A partially-broken `lib/` makes every later analyzer run useless, because real errors hide among the 105.
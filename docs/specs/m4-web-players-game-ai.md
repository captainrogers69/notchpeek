# M4 — Web players, game, AI, i18n, updates

**Date:** 2026-09-04
**Status:** draft, and **less certain than M1–M3 by design**
**Depends on:** M3 complete, and on spike 1 (§2) before the web-player work is planned in detail.
**Ships as:** full NotchNest parity.

---

## 1. Goal

The hard tail: everything whose cost could not be estimated from the shell outward. Three of the five items here are genuinely novel for a Flutter build rather than a SwiftUI one, so this milestone opens with a spike and its scope is explicitly revisable.

### In scope

YouTube Music and QQ Music players, the game, the AI panel, localization, Sparkle updates, and the MediaRemote command path deferred from M1.

### Out of scope

Monetization, in this and every milestone.

## 2. Spike 1, before anything else

**Question: can a `WKWebView` be composited into the notch panel acceptably?**

This is the one parity item that cannot be scoped from the outside. Flutter draws to its own canvas; a `WKWebView` is a real `NSView`. Compositing a platform view into an animated, non-rectangular, clipped Flutter surface is slower than a pure Flutter layer and interacts badly with clipping — and the notch panel is animated, non-rectangular and clipped.

Three candidate shapes, cheapest first:

| Option | Shape | Cost if it works |
|---|---|---|
| **A** | Native view layered with the Flutter view, occupying a **rectangular** sub-region of the expanded panel where the clip does not apply | Reuses the pattern M2's shelf and M3's camera already established. No new mechanism |
| **B** | The web player lives in a **separate borderless window** positioned under the expanded panel, shown and hidden with it | Two windows to keep in sync during the morph, but no compositing problem at all |
| **C** | Flutter platform view (`AppKitView`) inside the panel | Cleanest to write, most likely to stutter during the morph |

Timeboxed. Output is an answer and a recommendation, not code we keep. **If none of the three is acceptable, the honest outcome is to cut the web players from parity** and record why — better than shipping a panel that stutters every time the notch opens.

## 3. Web players

Assuming the spike clears one option.

| Aspect | Decision |
|---|---|
| Services | YouTube Music (`music.youtube.com`), QQ Music (`y.qq.com`) |
| Mechanism | We host the player. **No permission needed** — there is no other process to ask about |
| Sign-in | The user signs in once, inside our app |
| State | Cookies persist per service; sign-in survives relaunch |
| Now-playing | Read from the page, not from any system API |
| Lifecycle | The web view is created on first use and **kept alive** thereafter — a reload would stop playback |

**Why this is worth the trouble.** It is the sharpest idea in NotchNest. Our spike proved the system-wide now-playing read path is dead; hosting the player sidesteps the wall rather than fighting it, and it works identically on both distribution channels with no entitlement at all. Their own UI says it plainly: *"Built-in player — no permission needed. Open it once to sign in."*

**Honest risks.** A resident WebKit instance per service is the largest memory line in the app. The layout depends on a third party's web player staying stable, and it will change without warning. QQ Music also carries region and sign-in friction that our likely audience may never hit — it is the lowest-value item in this milestone and the first thing to cut if the milestone runs long.

## 4. Game

**Rebuilt in Dart. Not embedded.**

NotchNest's game is SpriteKit. Hosting SpriteKit inside Flutter means a platform view holding 60 fps inside an animated clip — the §2 problem, at a harder frame budget, for the least important feature in the app.

Flutter draws games perfectly well on its own. So: a small game in Dart, using `CustomPainter` or a Flutter game library, sized to the expanded panel. Parity here is parity of the **feature**, not of the technology.

Scope discipline: one simple game, no leaderboard, no persistence beyond a high score. Its purpose is delight, and delight does not need a backend.

## 5. AI panel

| Aspect | Decision |
|---|---|
| Model | Apple's on-device model via `FoundationModels` |
| OS floor | `FoundationModels` is macOS 26 only — **and so is our app**, so no split |
| Probe | `CapabilityProbe.osSupportsOnDeviceAI`, kept anyway: Apple Intelligence can be unavailable or switched off on a machine that is on 26 |
| Network | None. On-device only |
| Scope | Short prompts against a scratchpad. No history, no documents, no tool use |

The variable-tab-count tab strip built in M1 is what makes this expressible without tearing the shell apart. That was the reason for building it that way.

**What the 26 floor bought us.** No availability annotations, no second OS in the test matrix, no absent-tab path to verify. This panel is the single biggest beneficiary of that decision (`../risks-and-decisions.md` R1).

**Still to handle:** being on macOS 26 does not guarantee the model is usable — Apple Intelligence can be unsupported on the hardware, not downloaded, or switched off. That is a runtime unavailable state, not a compile-time one.

## 6. Localization

NotchNest ships eight locales — en, de, fr, ar, zh-Hans, es-MX, pt-BR, pt-PT — but its `Localizable.strings` holds **7 strings**. The rest of its UI is inline English. So their i18n is mostly scaffolding, and **parity on localization is far cheaper than the locale list suggests.**

Our approach:

| Aspect | Decision |
|---|---|
| Mechanism | Flutter's own localization; all UI strings externalized from the start of M1, not retrofitted here |
| Locales at parity | The same eight |
| RTL | Arabic means the shell layout must mirror. **Test the notch shape mirrored** — the concave corners are the part that breaks |
| Swift-side strings | Permission explanations and notification bodies also need localizing |

The one genuinely non-trivial piece is RTL in a shape-clipped, precisely-positioned panel. Budget for it rather than discovering it.

## 7. Sparkle updates

| Aspect | Decision |
|---|---|
| Channel | Direct build only; inert in a future App Store build |
| Appcast | Hosted on the product domain |
| One codebase | Sparkle present in both builds, doing nothing on MAS — exactly what NotchNest does |

**The permanent commitment:** old installs poll the appcast URL forever. Losing that domain silently breaks updates for everyone who has not upgraded. Pick the domain once and hold it — see `../info/identity.md` §2.

## 8. MediaRemote command path

Deferred from M1 §9, revisited here now that more sources exist.

Spike 0 proved `MRMediaRemoteSendCommand` works unsigned, unentitled and unprompted — it actually paused Spotify. It controls players with **no scripting dictionary**, which is its real value: browsers, VLC, anything.

| Aspect | Decision |
|---|---|
| Use | Transport commands only. Reads stay on scripting — reads are gated |
| Channel | Direct build only. A private framework is an automatic App Store rejection |
| Structure | Behind the same command interface as the scripting path, selected by `buildFlavor` |
| Probe | `systemWideMediaCommand`, defined in M1 §6 |

## 9. Error handling

| Failure | Response |
|---|---|
| Web player fails to load | Retry with a visible offline state; never a blank rectangle |
| Web player layout changed upstream | Now-playing degrades to "playing / paused" only; controls stay usable |
| Not signed in | Explanatory state with a sign-in prompt, matching the needs-permission pattern |
| `FoundationModels` unavailable at runtime despite OS 26 | Unavailable state; the tab hides |
| Sparkle cannot reach the appcast | Silent; retry next launch. Never a modal |
| RTL layout breaks the notch shape | Caught by mirrored golden tests, not by users |

## 10. Testing

**Dart unit** — game logic; localization key coverage (every key resolves in all eight locales); command-path selection by build flavor.

**Dart widget** — mirrored goldens for the shell and every panel under RTL; web-player panel in loading, offline, signed-out and playing states; the tab strip with the AI tab both present and absent.

**Swift unit** — `FoundationModels` availability branching; MediaRemote command dispatch against a stub; appcast URL construction.

**Manual** — sign in to each web service and play; **the AI panel with Apple Intelligence switched off**; a real Sparkle update from an older build to a newer one; the app in Arabic.

## 11. Exit criteria

1. Spike 1 answered and its recommendation recorded in this document before the web-player work starts.
2. Both web players sign in, play, and survive relaunch with the session intact.
3. The morph animation does not stutter with a web player resident — measured, not eyeballed.
4. The game runs in Dart at a steady frame rate inside the expanded panel.
5. AI panel works, and degrades to a clear unavailable state when Apple Intelligence is off or unsupported.
6. All eight locales resolve every key; the shell renders correctly mirrored in Arabic.
7. A Sparkle update installs successfully from a previous build.
8. **Memory recorded with both web players resident** — the worst case for the whole app. This is the measurement most likely to breach the 300 MB budget; if it does, use §12's cut list rather than shipping over (`../risks-and-decisions.md` R4).

## 12. What may be cut

Stated in advance so cutting is a decision rather than a failure:

- **QQ Music** — lowest value for our likely audience, and it carries region and sign-in friction. First cut.
- **The game** — pure delight, zero utility. Second cut.
- **Web players entirely** — only if spike 1 finds no acceptable option. Record the reasoning if so.

The AI panel, localization and Sparkle are not cuttable: the first is a real differentiator on capable machines, and the other two are how the app reaches and keeps users.

# NotchNest — feature breakdown

**Date:** 2026-09-04
**Subject:** NotchNest 1.2.5, `com.silverseahog.notchnestapp`, Mac App Store build
**Method:** static inspection of the installed bundle — `Info.plist`, entitlements, resources, and type names recovered from the binary. No runtime observation, no decompilation.
**Purpose:** know exactly what parity means before committing to it.

> Scope note: this describes *what the app does*. None of its code or assets are reused.
> Where something is inferred rather than observed, it says so.

---

## 1. The panels

Eleven surfaces. Evidence column is the type name or resource found in the bundle.

| # | Panel | What it does | Data source | Evidence |
|---|---|---|---|---|
| 1 | **Home** | Default tab. Now-playing plus quick controls. | media layer | `NotchHomeView` |
| 2 | **Music** | Now-playing, transport, artwork, scrubber. Four sources. | see §2 | `PlayerManager` |
| 3 | **Calendar** | Today's events inline; per-calendar toggles. | EventKit | `CalendarView`, `CalendarToggleRow` |
| 4 | **Clipboard** | Clipboard history, searchable, re-copy from list. | polls `NSPasteboard`, persists to Core Data | `ClipboardMonitor`, `ClipboardItem`, `ClipboardTab`, `ClipboardItem.momd` |
| 5 | **File shelf** | Drag files onto the notch, hold them, drag out again. Preview in place. | user-selected files + QuickLook | `NotchShelfView`, `DropPanelView`, `DropItemView`, `DropItem` |
| 6 | **Timer** | Pomodoro. Called **"sprints"**, not pomodoros. Completion sound + notification. | local | `TimerView`, `TimerManager`, 3 `.wav` files, `Localizable.stringsdict` |
| 7 | **Notes** | Quick scratch notes, persisted. | SwiftData | `NotesView`, `NotesMigrationManager` |
| 8 | **Webcam** | Mirror the front camera in the notch. | AVFoundation | `WebcamView`, `WebcamManager`, camera entitlement |
| 9 | **Game** | A SpriteKit mini-game with an arcade font. Play count metered on free tier. | local | `SpriteKitGameView`, `GamePlayLimitManager`, `ARCADE_N.TTF` |
| 10 | **AI** | On-device model panel. Gated by a flag. | `FoundationModels` | `isAIEnabled`, linked framework |
| 11 | **Battery pill** | Charge level and charging state in the collapsed notch. | IOKit | `NotchBatteryPill`, `BatteryAlertBridge`, `isCharging` |

Supporting surfaces, not panels: `OnboardingView` (first run), `SettingsView` + `SettingsTab`, `TraySettingsView`, `TabSelectionView` (the tab strip), `RateAppHeaderBtnView` + `AppStoreReviewManager` (review prompt), `UpdateMenuBarItem` (Sparkle update check), `FeatureLimitUpgradeView` (paywall).

## 2. Music: four sources, two mechanisms

The most interesting engineering in the app, and the part worth copying.

| Source | Mechanism | Permission cost |
|---|---|---|
| **Apple Music** | ScriptingBridge to `com.apple.Music`; artwork resolved through `itunes.apple.com/lookup` | Apple Events consent prompt |
| **Spotify** | ScriptingBridge to `com.spotify.client` | Apple Events consent prompt |
| **YouTube Music** | **embedded `WKWebView` loading `music.youtube.com`** | **none** |
| **QQ Music** | **embedded `WKWebView` loading `y.qq.com`** | **none** |

Evidence: `SpotifyManager`, `YouTubeMusicEngine` / `YouTubeMusicManager`, `QQMusicEngine` / `QQMusicManager`, `WKWebView` (22 references), and the entitlement `com.apple.security.temporary-exception.apple-events` listing exactly `com.apple.Music` and `com.spotify.client`.

**The trick.** For the two services with no scriptable Mac app, NotchNest *becomes* the player. Its own UI string says it plainly:

> "Built-in player — no permission needed. Open it once to sign in."

Because the app hosts the playback itself, there is no other process to ask permission about, and no now-playing API to be locked out of. Our spike proved the system-wide read path is dead on macOS 26; this sidesteps that wall rather than fighting it.

Cost of the trick: a WebKit instance resident per web source, the user must sign in inside our app, and the layout depends on a third party's web player staying stable.

## 3. Free versus paid

The free tier is **metered, not locked**. Users reach features and then run out of them.

| Mechanism | Evidence | Reading |
|---|---|---|
| Play-count metering | `GamePlayLimitManager` | the game is counted, not blocked |
| Generic limit paywall | `FeatureLimitUpgradeView` | one shared "you hit the limit" screen |
| Per-row Pro markers | `PremiumFeatureRowView`, `PremiumIndicator`, `premiumGradient` | Pro features are *visible* in the free build, marked, not hidden |
| Feature flag | `isAIEnabled` | AI is switchable, likely Pro and OS-gated both |
| Upgrade entry point | `enableUpgradeButton` | upgrade CTA is itself conditional |

Exact thresholds are not recoverable from the bundle. The shape is clear: show everything, meter the expensive things, keep one upgrade screen.

## 4. Reach

- **Eight locales:** en, de, fr, ar, zh-Hans, es-MX, pt-BR, pt-PT. Arabic implies right-to-left layout support.
- **Almost no string catalog.** `Localizable.strings` holds **7 strings**; the rest of the UI is inline English literals. So the eight `.lproj` folders are largely scaffolding — the app is not meaningfully localized yet, despite shipping the locales. The one genuinely localized area is the media-player error states.
- QQ Music plus zh-Hans is a deliberate reach into a market most notch apps ignore.

## 5. What parity actually costs us

Grouped by risk rather than by panel, because that is what drives the milestone split.

| Group | Panels | Hard part |
|---|---|---|
| Native shell | battery pill, tab strip | notch geometry, window level, mouse gating, morph animation |
| Permissioned | music (Apple/Spotify), calendar, webcam | TCC prompts, consent-denied states, per-app scripting |
| Self-contained | timer, notes, clipboard, game | persistence and migration only |
| Embedded web | YouTube Music, QQ Music | a `WKWebView` hosted inside a Flutter app — see the technical doc |
| OS-gated | AI | `FoundationModels` is macOS 26 only. Our own floor is also 26, so this stops being a split for us |

Two of these are genuinely new problems for a Flutter build rather than a Swift one: hosting a `WKWebView` behind Flutter's canvas, and drawing a SpriteKit game inside it. Both are addressed in `notchnest-technical.md` §5.

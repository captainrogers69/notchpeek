# Spike 0 — is system-wide now-playing reachable on macOS 26?

**Date:** 2026-09-04
**Status:** closed, decisive
**Machine:** MacBook Air M2, macOS 26.5.1 (25F80), Xcode 26.6, Swift 6.3.3
**Answer:** **reads are gated, writes are not.** Design `MediaBridge` around per-app scripting for *reading* and `MediaRemote` for *controlling*.

---

## 1. Result

`MediaRemote.framework` still exists and still exports every symbol we wanted. The read path returns nothing anyway; the command path works with no signature, no entitlement and no permission prompt.

| Probe | Symbol | Result |
| --- | --- | --- |
| Framework load | `dlopen` on `/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote` | ok |
| Symbol export | `MRMediaRemoteGetNowPlayingInfo`, `…ApplicationIsPlaying`, `…RegisterForNowPlayingNotifications`, `…GetNowPlayingClient`, `MRNowPlayingClientGetBundleIdentifier`, `MRMediaRemoteSendCommand`, `MRMediaRemoteSetElapsedTime` | all **found** |
| Read info | `MRMediaRemoteGetNowPlayingInfo` | callback fires, **0 keys** |
| Read owner | `MRMediaRemoteGetNowPlayingClient` | **nil** |
| Read events | `MRMediaRemoteRegisterForNowPlayingNotifications` + real track change | **no notifications** |
| **Write** | `MRMediaRemoteSendCommand(1, nil)` — pause | **returned `true`, Spotify actually paused** |

Restoring with `MRMediaRemoteSendCommand(0, nil)` resumed it. So the OS *does* have a live now-playing session pointed at Spotify — the writes prove it — and that session is simply unreadable by us. This is the Apple-side wall, not a missing session and not a code-signing problem.

## 2. How the confounders were eliminated

An empty dict has three innocent explanations. All three were ruled out.

1. **"Nothing was playing."** Ruled out: Spotify was confirmed `playing` via AppleScript immediately before each run (`Ada — Sonu Nigam`, then `Heyy Babyy — Neeraj Shridhar`).
2. **"The binary is unsigned / has no bundle identity."** Ruled out: re-run as a proper `.app` bundle with `CFBundleIdentifier = com.capcraft.mrprobe`, ad-hoc `codesign`ed. Byte-identical result.
3. **"There is no system session for a third-party player."** Ruled out by the write path landing. A command cannot reach Spotify through a session that does not exist.

Note also that **nothing prompted**. No TCC dialog, no Accessibility request. The wall is silent — reads just come back empty, which is exactly how this would be misdiagnosed as "nothing playing" in production.

## 3. What the fallback actually gives us

Spotify's scripting dictionary covers every field the music panel needs, including artwork:

| Field | Source | Note |
| --- | --- | --- |
| title / artist / album | `name`/`artist`/`album of current track` | — |
| duration | `duration of current track` | **milliseconds** |
| position | `player position` | **seconds, fractional** — units differ from duration, easy bug |
| artwork | `artwork url of current track` | an `i.scdn.co` **URL, not bytes** — needs a fetch + cache |
| track identity | `id of current track` | `spotify:track:…`, a stable key for the artwork cache in spec §2.5 |
| state | `player state` | `playing` / `paused` / `stopped` |
| shuffle / repeat | `shuffling`, `repeating` | free extras |

**Cost:** ~130 ms per `osascript` round trip, measured over three runs. That is process-spawn cost, not Apple Events cost — `MediaBridge` must use in-process `NSAppleScript`/ScriptingBridge, never shell out. Even so, polling position at the spec's ~2 Hz is the single most expensive thing the app will do.

**Apple Music was not testable here:** the local library is empty (`count of tracks = 0`), so `current track` errors with `-1700`. The Music source path needs a separate manual check on a machine with a library or an active subscription.

## 4. Consequences for the design spec

1. **§1 "Music source: hybrid, runtime-selected" survives, but inverts.** Scripting is not the fallback; it is the only read path. Delete the "system-wide now-playing where allowed" primary — on this OS there is no "where allowed" for reading.
2. **§2.4 `MediaBridge` splits read from write.** `MusicSource` (read) is per-app scripting only. Transport commands should go through `MRMediaRemoteSendCommand`, which is app-agnostic, needs no per-app consent, and works even for players with no scripting dictionary. Keep a scripted-command fallback for the MAS build.
3. **The MAS build cannot use `MediaRemote` at all** — private framework, automatic rejection. So MAS gets scripted commands, direct gets `MediaRemote`. This is now a real, concrete difference between the two flavors, and `CapabilityProbe` must report it.
4. **§4 `CapabilityProbe` field rename.** `systemWideMedia: bool` is misleading — it was never one capability. Split into `systemWideMediaRead` (false on macOS 26, keep the probe so it flips if Apple reopens it) and `systemWideMediaCommand`.
5. **Artwork is a URL for Spotify and bytes for Music.** The §2.5 "artwork crosses once per track change, keyed by track id" rule holds, but the payload type is source-dependent. Normalize in Swift; hand Dart one shape.
6. **Position and duration units disagree** between Spotify's own fields. Normalize to one unit at the bridge boundary and unit-test it — this is exactly the kind of thing spec §6 lists under "`NowPlaying` parsing".

## 5. Reproducing

Throwaway probes, not committed: `mrprobe.swift` (symbol inventory + info read) and `mrprobe2.swift` (client / notifications / command split), built with `swiftc -O`. Re-run only if a macOS update might have reopened the read path — the probes print `RESULT: A|B|C` for exactly that check.

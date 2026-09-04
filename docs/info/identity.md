# Naming and identity

**Date:** 2026-09-04
**Status:** decided, pending domain verification
**Scope:** app name, studio name, bundle identifier, store publisher identity. Product design is a separate document.

---

## 1. Decisions

| Field                   | Value                        | Status                       |
| ----------------------- | ---------------------------- | ---------------------------- |
| App name                | **NotchPeek**                | decided                      |
| Studio / developer name | **Capcraft**                 | decided                      |
| Bundle identifier       | **`com.capcraft.notchpeek`** | decided                      |
| Studio site             | capcraft.dev (or .com)       | **verify at registrar**      |
| Product site            | notchpeek.app                | **verify at registrar**      |
| App Store Provider      | Mayank Yadav                 | fixed by Apple, not a choice |

The prefix is account-wide: every future app is `com.capcraft.<app>`.

### Why NotchPeek

Names the behavior rather than the contents. The ~35 competitors are named for what they hold — deck, box, pad, hub, nest, nook — while the chosen interaction model is invisible at rest, peek on events, expand on hover. Zero software collisions.

### Why Capcraft

Keeps the Steve Rogers thread privately without touching Marvel IP. "Craft" reads as a small independent shop, and unlike "kit" it does not mimic Apple's own framework naming (AppKit, EventKit) — which matters, because the developer name is public. Zero collisions.

---

## 2. Do before first release

1. **Register `capcraft.dev`.** Search found nothing, but search cannot see parked domains. Confirm at a registrar.
2. **Register `notchpeek.app`.** The direct-download build needs a website, and the Sparkle appcast will live here. **Pick a domain you will hold forever** — old installs poll that appcast URL indefinitely, so losing it silently breaks updates for everyone who has not upgraded.
3. **Reserve `com.capcraft.notchpeek`** in App Store Connect and Play Console, before either listing exists.
4. **Decide on a legal entity before the first paid release.** See §3.

---

## 3. Store identity rules

Constraints, not preferences. Both verified against store documentation.

### Apple

Three distinct fields, routinely confused:

| Field              | Shows                                                       | Changeable              |
| ------------------ | ----------------------------------------------------------- | ----------------------- |
| **Provider**       | the legal entity — your legal name on an individual account | no                      |
| **Developer name** | a trade name, account-wide, the blue link on the listing    | yes, with documentation |
| App name           | the product                                                 | yes                     |

Enrolled as an individual, **your legal name is the Provider**, permanently. Apple's documentation states that sole proprietors enrol as individuals and are listed under their personal legal name, and that [Apple does not accept DBAs, fictitious business names or trade names for organization enrollment](https://developer.apple.com/help/account/membership/updating-your-account-information/). An organization account requires a real registered legal entity plus a D-U-N-S number.

The **developer name is a separate field** and can be a trade name. Live proof: the AllEvents listing shows developer **Amitech** with **Provider: Ruchit Patel**, an individual. Obtaining one means contacting Apple Developer Support with documentation proving you trade under that name — in India, a registered sole proprietorship: GST registration, an Udyam/MSME certificate, or a shop-and-establishment licence in the trade name.

One trade name per account. [You cannot hold two brand names, even registered trademarks or DBAs](https://developer.apple.com/forums/thread/47878) — it covers every app you ship. So it must be a studio name, never a product name.

**Consequence:** shipping as "Capcraft" requires a registered sole proprietorship in that name. Shipping as "Mayank Yadav" requires nothing. The developer name can be changed later; the bundle id cannot.

### Google Play

Developer name is a display field you choose and can change at any time, but Play also shows your **legal name and country** beside it.

**Privacy warning:** [merchant accounts — any developer selling paid apps or in-app purchases — must display their full address publicly on the listing](https://support.google.com/googleplay/android-developer/answer/10840893?hl=en). As an individual, that is your home address. This, not branding, is the real reason indie developers incorporate. Decide before the first paid release, not after.

### Both stores

- Use the **same identifier** on both.
- Lowercase ASCII, dot-separated, no hyphens. Play requires a valid Java package, so no segment may begin with a digit.
- **Permanent.** Play never allows an `applicationId` to change; a new id is a new app with zero installs and zero reviews. Apple never allows a bundle id to be reused.

---

## 4. Names rejected, and why

Roughly 60 names were checked. Recorded so this is not repeated.

### App names

| Rejected                                                                                                           | Reason                                                                                      |
| ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------- |
| Brim                                                                                                               | [Brim Data](https://www.brimdata.io) — funded, Mac, established — plus three App Store apps |
| Mantel, Visor, Marquee, Perch, Canopy, Brow, Arca, Umbra, Kerf, Spanda, Bindu, Netra, Vedika, Chatra, Limen, Nimbo | all taken; several by direct notch-app competitors                                          |
| Awning, Lintel, Cornice, Gavaksha, Jharokha, Kapota, Torana                                                        | verified clean, set aside in favour of a plainer name                                       |
| NotchDeck, NotchShelf, NotchPad, Notchly, Notchmate, NotchBox, NotchDock, NotchHub, MacNotch                       | all shipping products                                                                       |

**Torana** (तोरण, the ornamental arch spanning an entrance) was locked briefly before the direction changed to a plainer name.

### Studio names

| Rejected                                                               | Reason                                                                                                                                                                                                                                                                                          |
| ---------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| com.rogers                                                             | claims rogers.com — Rogers Communications, an active telecom                                                                                                                                                                                                                                    |
| Mynk, Maytech, Mayank Labs                                             | [funded fintech](https://www.crunchbase.com/organization/mynk); three separate Maytech companies; Mayank Digital Labs                                                                                                                                                                           |
| Mayk, Bulwark, Aegis, Compass Labs, Rampart, Dogtag, Stalwart, Redoubt | all live companies or products                                                                                                                                                                                                                                                                  |
| Quarterdeck, Halyard, Helmsman, Skipper, Binnacle                      | the entire nautical pool is taken; Skipper is itself a Mac app                                                                                                                                                                                                                                  |
| capcode                                                                | [capcode.io](https://capcode.io/) is Capital Code; also a sailing app, a VS Code extension and an MVC framework — and _capcode_ is [the standard term for a pager's address in POCSAG paging](https://www.rfwireless-world.com/terminology/cap-code-paging-systems), making the word unrankable |
| capforge, capstack                                                     | [90-person bookkeeping firm](https://capforge.com/); [$12M fintech](https://pitchbook.com/profiles/company/530853-13)                                                                                                                                                                           |
| mayank.dev                                                             | almost certainly taken — other developers with the name have fallen back to mayankt.dev and mayank.is-a.dev                                                                                                                                                                                     |

Verified clean but not chosen: captainworks, brooklyncode, brooklynlabs, brooklynbuilt, valorlabs, capkit.

### The pattern

**Every common English word is taken.** Every name that survived is a two-word compound. That is the only registrable shape left — worth assuming rather than rediscovering.

Search cannot prove a domain is free. It surfaces companies and products, not parked domains. Always confirm at a registrar before committing.

# NotchNest — business breakdown

**Date:** 2026-09-04
**Subject:** NotchNest 1.2.5, Mac App Store build
**Method:** static inspection of the bundle — StoreKit configuration, entitlements, embedded URLs, receipt presence.
**Purpose:** understand how a solo developer monetizes a notch app, so our own pricing decision is informed rather than guessed.

---

## 1. Price and packaging

Subscription only. No one-time purchase, no lifetime tier.

| Product | ID | Price | Period | Trial |
|---|---|---|---|---|
| Monthly | `com.silverseahog.notchnestapp.monthly` | **$1.99** | P1M | **3 days free** |
| Yearly | `com.silverseahog.notchnestapp.yearly` | **$11.99** | P1Y | none |

Subscription group **"NotchNest Premium"** (`21714027`). Yearly is 50% off monthly-times-twelve — a hard push toward annual. Neither product is family-shareable. Storefront on file is USA.

Source: `Resources/NotchNestProducts.storekit`. That file is the local StoreKit *testing* configuration, so treat the numbers as the developer's intent; live App Store pricing could differ.

**App Store id `6747612321`.** Manage-subscriptions deep link ships in the binary (`apps.apple.com/account/subscriptions`), so cancellation is handled by Apple, not in-app.

## 2. Funnel

Reconstructed from the surfaces present:

```
install → OnboardingView → free use, Pro rows visible and marked
        → hit a metered limit (e.g. GamePlayLimitManager)
        → FeatureLimitUpgradeView
        → 3-day free trial → monthly, or upsell to yearly
```

Design choices worth noting:

- **Nothing is hidden.** `PremiumFeatureRowView` and `PremiumIndicator` mean Pro features appear in the free build, labelled. The pitch is aspiration, not discovery.
- **Metering, not locking.** The user experiences the feature, then loses it. Higher conversion pressure than a hard gate, and more goodwill than a teaser.
- **One paywall.** A single `FeatureLimitUpgradeView` serves every limit. Cheap to build, cheap to change.
- **Review prompt is a product surface.** `AppStoreReviewManager` plus a dedicated `RateAppHeaderBtnView` in the header — ratings are treated as a growth lever, not an afterthought.

## 3. Distribution: both channels, one codebase

| Signal | Meaning |
|---|---|
| `_MASReceipt/receipt` | this build came from the Mac App Store |
| `com.apple.security.app-sandbox = true` | full sandbox, as MAS requires |
| mach-lookup exceptions for `…-spks`, `…-spki` | **Sparkle** XPC service names — the direct-download updater |

Sparkle's plumbing is present in a Mac App Store build, which means one codebase and one target serve both channels, with the updater simply inert on MAS. That is the cheap way to run dual distribution, and it is what we should copy.

Web presence: `trynotchnest.silverseahog.com` (marketing, `index.html`, `privacy-policy.html`) and `notchnest.silverseahog.com` with a `/health` endpoint — so there is a backend, however small. Support runs through a personal Gmail address embedded in an error-report `mailto:` link.

## 4. Instrumentation

A full Google stack:

- **Firebase Analytics** + `GoogleAppMeasurement` (with `GoogleService-Info.plist` shipped in the bundle)
- **Firebase Crashlytics**
- Apple ad-attribution (`api-adservices.apple.com`) and Google ad-conversion endpoints
- Consent-mode flags present: `isAdStorageDenied`, `isAdUserDataDenied`, `allowPersonalizedAds`

So: a paid, sandboxed utility that also carries advertising-attribution SDKs. Defensible for measuring paid acquisition, but it is a real privacy surface in an app that sits on your screen permanently, and it is worth deciding *against* deliberately rather than by omission.

Other operational choices: **iCloud key-value store** for settings sync across a user's Macs (`com.apple.developer.ubiquity-kvstore-identifier`), and `com.apple.security.network.client` for the artwork lookups and the web players.

## 5. Positioning

- **Solo developer.** Team `25DZLP69MU`, studio name "silverseahog", support via personal email. Same shape as our own Capcraft plan.
- **macOS 14.0 floor**, three years of hardware. Reach chosen over API convenience — the constraint we matched.
- **34 MB, agent app** (`LSUIElement`), no Dock icon.
- **Breadth as the pitch.** Eleven panels at $1.99/month is a volume play: be the notch app that does everything, price it below thinking-about-it.

## 6. What this means for NotchPeek

Decided: **v1 ships free**, monetization deferred. This document exists so that decision is revisited with evidence rather than re-argued from scratch.

When we do revisit it, three things from NotchNest are worth carrying and one is worth rejecting:

1. **Carry: the metered free tier.** Show everything, count the expensive things, one upgrade screen.
2. **Carry: Sparkle-in-both-builds.** One codebase, updater inert on MAS.
3. **Carry: yearly priced as a steep discount.** Their 50% cut is aggressive and clearly deliberate.
4. **Reject: the ad-attribution SDKs.** Crash reporting is defensible; advertising identifiers in a permanently-resident menu-bar-class app are not, and shipping without them is a genuine differentiator we can state out loud.

The open pricing question for later: NotchNest rents at $1.99/month while Alcove — the app the old spec named as the bar to clear — sells outright at $5. Those are incompatible theories of what a notch utility is worth, and we will have to pick one.

# NotchPeek — Testing Playbook

**Status: not written yet.** Deliberately. The architecture playbook comes first, because what is testable is decided by the seams, and the seams are architecture.

Read [`architecture-playbook.md`](architecture-playbook.md) first. It already fixes the three things this document will depend on:

- **§7** — every dependency is a Riverpod provider, so every dependency is overridable in a test.
- **§3** — layering, so logic sits in `domain` where it needs no Mac window to exercise.
- **§4.2** — no business logic in Swift, so the untestable-without-a-window surface stays as small as possible.

Until this document exists, the rule from the architecture playbook's quality gate (§11) applies on its own:

> Logic that can be tested without a Mac window has a test. State machines, geometry maths, parsing, unit normalization, enum mapping.

## What this document will decide

- Coverage expectations per layer, and what is deliberately left uncovered.
- Fixtures and fakes: how a fake `ChannelService` is shaped, and where fixtures live.
- Golden tests: which shell and panel states are goldens, and how the three capability states (§4.4) are covered.
- Swift-side XCTest scope: geometry derivation, mouse-gate hit testing, source selection.
- The manual matrix — the cases no automation reaches: real notch hardware, external displays, Space switches, fullscreen apps, permission dialogs.
- What runs in CI versus what runs by hand before a release.

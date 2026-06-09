# ADR 0001 — Watch manifest minApiLevel is 5.2.0 (not 6.0.0)

**Status:** accepted · 2026-06-10

## Context

Architecture NFR6 describes the target device as "Fenix 8 (CIQ API 6.0, firmware
≥12.35)", and Story 1.1 AC2 says the watch app "targets CIQ API 6.0". Building
locally against API 6.0 requires Connect IQ SDK 9.x.

CI runs the watch unit tests via `matco/action-connectiq-tester`, whose image
(`ghcr.io/matco/connectiq-tester`) hardcodes **SDK 8.4.0**. In 8.4.0 the
`fenix847mm` device supports up to **CIQ API 5.2.0**, so a manifest requiring
6.0.0 fails to compile in CI: `Device 'fenix847mm' does not support API Level
'6.0.0'`. No 9.x tester image is published (their build notes device-file
downloads as an unsolved TODO).

This pits "API 6.0" against the AR3 requirement of green CI from the first commit.

## Decision

Set the manifest `minApiLevel` to **5.2.0**.

`minApiLevel` is a *minimum* (compatibility floor), not a target. The Fenix 8 is
an API-6.0 device and runs an app whose floor is 5.2.0 without issue, and nothing
in the codebase yet uses an API-6.0-only feature. This keeps CI green on the
standard, zero-maintenance action.

Local development still uses SDK 9.1.0; only the declared floor changed.

## Consequences

- ✅ CI is green from the first commit with the stock action — no custom image to build or maintain.
- ✅ Full Fenix 8 support is unchanged.
- ⚠️ Minor deviation from AC2/NFR6's literal "API 6.0".
- 🔁 **Revisit when** we first need an API-6.0-only feature: bump `minApiLevel` to
  6.0.0 *and* move CI to an SDK-9.x runner (custom image, or a newer tester image
  once one exists). Track alongside the hardware gates.

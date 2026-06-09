# Reconciliation: Fenix 8 Constraints Research vs PRD + Addendum

**Input:** `_bmad-output/planning-artifacts/research/technical-fenix-8-watch-app-constraints-research-2026-06-06.md`
**Against:** `prd.md` and `addendum.md` (prd-garmin_RSVP-2026-06-06)
**Date:** 2026-06-06

## Method

Read all three documents in full. Walked every substantive claim, number, constraint, risk, and decision in the research report and checked whether it is reflected in the PRD's requirements/risks or the addendum's technical depth. This is a technical research report, so most implementation detail correctly lives in the addendum or downstream architecture docs. Below I flag only items that change requirements, risks, or scope, or that represent hard constraints/numbers the documents omitted or got subtly wrong. Phrasing differences are ignored.

## Summary verdict

The PRD and addendum carried the research faithfully on the headline findings: 768 KB watch-app heap (NFR2, addendum §1), 128 KB = data-field-not-watch-app (addendum §1), Storage 32 KB/value + ~100 KB total (NFR3, addendum §3), 50 ms timer floor + 700/1000 WPM headroom (NFR1, addendum §4), background sync 5-min/32 KB (addendum §3), AMOLED screen-on as the #1 risk with the ActivityRecording mitigation and dim-AON fallback (R1, addendum §4), input mapping (addendum §4), firmware ≥12.35 (NFR6, addendum §1), and "don't hold the whole novel in RAM / stream a window" (addendum §6).

A small number of substantive items were dropped. Two of them touch a requirement or a risk the documents currently state with more confidence than the research supports.

## Gaps that should be carried

### G1 — AON 10% luminance budget may break FR4's "dim always-on" floor (MEDIUM, requirement-affecting)

The research raises an explicit open question (Input §"Risks and Open Questions", and §"AMOLED screen-on"): if the screen drops to always-on, AON keeps only ~10% of pixels lit on a luminance budget, and **a single bright word with a coloured pivot may or may not fit that budget — it may render dim or black in AON.**

PRD **FR4** states the acceptable degraded fallback as: "display drops to dim always-on and a single button press restores it," and R1 names that degraded mode as "the floor." But the research says the floor itself is uncertain — RSVP's bright-single-word rendering might not be legible (or even visible) in AON at all. This is not registered anywhere in the PRD or addendum. It means FR4's stated floor and R1's fallback ladder ("→ if even that fails, premise rework") may be reached one rung sooner than assumed.

Recommendation: add an open question / risk note that the dim-AON fallback's legibility is itself unvalidated, and fold it into Gate V1.

### G2 — Activity-app state loss on carousel navigation is a registered hazard, not just a mitigation (MEDIUM, risk-not-registered)

Input §"Lifecycle" and Key Finding #11: navigating to the watch-face/glance carousel from a running activity app **stops the activity and loses app state** (the session is saved as on a crash; Epix2/Fenix7 lineage). The PRD's eager-persistence requirement (FR13) and addendum §4's debounce-and-force-persist pattern are the correct mitigation and are present — but the underlying hazard is never named as a risk, and the research explicitly calls it "a real UX wrinkle." Because the chosen architecture is the activity-app/ActivityRecording path (addendum §4), this hazard is directly on the happy path: a user glancing at their watch face mid-read drops the session. Worth registering so the abrupt-termination assumption is traceable to its cause.

### G3 — `Attention.backlight(true)` throws after ~1 minute (LOW, hard constraint behind R1)

Input §"AMOLED screen-on": on burn-in-protected AMOLED, forcing the backlight on for ~1 minute throws an exception — this is the concrete mechanism that makes the naive "just keep the backlight on" approach illegal and forces the ActivityRecording strategy. The PRD/addendum carry the conclusion ("a normal watch-app cannot keep the display lit") but not the specific constraint. Minor, since the conclusion is what drives design, but the number is the load-bearing fact and is cheap to record in the addendum.

### G4 — `PersistedContent` cannot store book text (LOW, decision-not-carried)

Input §"PersistedContent is NOT a text cache" and Key Finding #4: `Toybox.PersistedContent` only exposes FIT/GPX courses/waypoints/workouts and cannot cache arbitrary book text. This is a negative API decision (an option ruled out). The addendum's "Options Considered & Set Aside" (§6) records other rejected options but not this one. Low impact because the chosen storage design (flat files on phone, Storage for position, in-RAM window) is already correct, but it pre-empts a contributor reaching for PersistedContent as a watch-side text cache.

## Items intentionally NOT flagged (correctly dropped or downstream)

- **App-list-launched apps time out and need a self-run inactivity timer + `System.exit()`** (Input §"App-type decision"). Moot under the chosen activity-app registration; correctly omitted.
- **`onPartialUpdate` unavailable on AMOLED** (Key Finding #6). Addendum §4 specifies full-`onUpdate` single-word redraw; the partial-update detail is not needed. Implementation-level; downstream.
- **Only one temporal background event active at a time** (Key Finding #10). Refinement of the 5-min/32 KB constraint already in addendum §3; architecture detail.
- **`StorageFullException` exact name** (Key Finding #3). NFR3/addendum §3 carry the caps; the exception name is downstream implementation.
- **Widget slot empty on Fenix 8 / CIQ moved to glance+app model** (Key Finding #2). The "full watch-app, not widget" decision is carried (NFR/addendum §1); the rationale detail is downstream.
- **Word-stream sizing table, BMFont custom fonts, glyph-width precompute, burn-in jitter** — all present in addendum §2/§4.
- **Battery "activity-grade" qualitative note** (Input §"Battery"). PRD R4 + §3 counter-metric (≤10%/hr) cover it as a validation gate.
- **CIQ 8 / System 7 forward-looking platform reporting** — low-confidence, not requirement-affecting.

## No numeric contradictions found

Every hard number in the research that the PRD/addendum chose to carry matches: 768 KB heap, 128 KB data-field, 32 KB/value, ~100 KB total Storage, 50 ms timer floor, 5-min background interval, 32 KB background heap, 700→1000 WPM headroom, firmware ≥12.35, ~703 KB whole-novel estimate. NFR2's ≤600 KB peak target sits correctly inside the 768 KB budget. FR3's 100–900 WPM range does not conflict with the research's 300–700 timing examples.

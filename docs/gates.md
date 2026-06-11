# Hardware Validation Gates

Single status page for the four hardware-feasibility gates on the real Fenix 8.
Gate-blocked work (hardening the playback/transfer designs, story-splitting their epics)
references this page. See architecture §"Validation gates" (AR27–AR31).

> **Hardware access unblocked (2026-06-10):** USB sideload to the real Fenix 8 works
> (watch-side USB Mode → MTP; procedure in [setup.md](setup.md)). Story 1.1's scaffold
> was sideloaded and ran on the watch. The gates below can now run on hardware.

| Gate | What it proves | Status | Result |
|------|----------------|--------|--------|
| **V1** | AMOLED screen-on for ≥60-min hands-off reading (+ dim-AON fallback legibility) | **passed-dim** (2026-06-11) | Lit-dim & legible 61 min hands-off; never OFF; one-button restore works. FR4 satisfied in its fallback form |
| **V2** | Reliable repeated phone→watch sends (Android first-send bug defeated); bridge sufficiency (OQ2) | not started | — |
| **V3** | Per-message chunk-size ceiling (`BLE_REQUEST_TOO_LARGE` threshold) | not started | — |
| **V4** | 1-hour reading session battery drain vs ≤10%/hour target | not started | — |

## V1 — Hands-off screen-on (Story 1.3)
_Procedure:_ minimal spike opening an `ActivityRecording.Session`; verify the display stays lit
and legible ≥60 min with no interaction; test dim-AON fallback legibility on the ~10% budget.
_Status:_ **passed-dim** (2026-06-11, real Fenix 8 47 mm). _Result:_ FR4 satisfied in its
sanctioned fallback form (dim always-on, restored by one button press). Premise-rework flag:
**not raised**.

**Method.** Spike `GateV1View`/`GateV1Delegate` opening `ActivityRecording.createSession`
(`SPORT_GENERIC`, always discarded on exit). Hard prerequisite: watch setting
**System → Display & Brightness → During Activity → Always On** (with it Off the screen goes
black after timeout, native and CIQ alike). Run conditions: watch off-wrist on a table,
passcode disabled, no interaction for 60 min. Evidence: `AppBase.onDisplayModeChanged`
transition log persisted to Storage, exported via println on next launch.

**Measured timeline** (`elapsed`, HIGH = full bright, LOW = dim-lit, OFF = black):
- `00:00` session start (HIGH) → `00:14` HIGH→LOW — dim onset, matching the expected ~15 s.
- LOW continuously thereafter; two brief HIGH blips (`39:54`, `58:23`, ~8 s each, cause
  unconfirmed — possible table bump or phone notification), each self-recovered to LOW.
- `60:04`+ observer interaction: **one button press restored full brightness** (FR4 restore ✓).
- **Display mode never reached OFF in 61:00.**

**Fallback legibility (AC2).** Dim word at arm's length: **legible** in indoor daylight
("pretty good"). Dedicated outdoor/direct-sun judgment not performed — carry as a UX
spot-check into Epic 3; does not affect the verdict.

**Notes.** Battery: 28% start, no observed drop at end (read 32% after ~3 min on USB charger) —
≈0% net drain; the real measurement is gate V4 (Story 3.9). Backlight probe: a single
`Attention.backlight(true)` call mid-dim returned without `BacklightOnTooLongException`;
sustained use untested — not a pass path.

**Verdict matrix** (observed row in bold):

| Observed | Verdict | Consequence |
|---|---|---|
| **Lit (even dim) + legible for 60 min, one-button restore works** | **V1 passed (dim-AON via activity session) — FR4 satisfied in its fallback form** | **Epic 3 `ActivitySessionStrategy` = activity session + user-setting instruction; UX designs for dim legibility** |
| Stays full-bright 60 min | V1 passed (bright) | Same module, better UX headroom |
| Screen blanks but dim word legible when manually woken | Primary failed; fallback per AC2 | Decide if press-to-wake reading is viable |
| Both paths fail | Premise-rework flag | Epic 3 must NOT harden |

**Product implication (carry to Epic 3).** `ActivitySessionStrategy.mc` implements the
activity-session path: open a generic recording session on playback start to enter the
During-Activity display profile, and the app must instruct users to enable
**During Activity → Always On**. PlaybackView/UX must design for dim legibility. Gate outcome
swaps a module, not the architecture (architecture §Frontend Architecture).

## V2 — Transfer reliability & bridge sufficiency (Story 1.4)
_Procedure:_ many sequential chunk sends over the managed Communications API
(`watch_connectivity_garmin`); measure success rate; decide keep-bridge vs custom MethodChannel (OQ2).
_Status:_ not started. _Result:_ —

## V3 — Chunk-size calibration (Story 1.5)
_Procedure:_ sweep chunk sizes upward from ≤1 KB on the V2 harness; find the
`BLE_REQUEST_TOO_LARGE` (-102) threshold; record the safe working size.
_Status:_ not started. _Result:_ —

## V4 — Reading-session battery (Story 3.9)
_Procedure:_ 60-min continuous session on hardware (screen on, sync connected); measure drain.
_Status:_ not started. _Result:_ —

# Hardware Validation Gates

Single status page for the four hardware-feasibility gates on the real Fenix 8.
Gate-blocked work (hardening the playback/transfer designs, story-splitting their epics)
references this page. See architecture §"Validation gates" (AR27–AR31).

| Gate | What it proves | Status | Result |
|------|----------------|--------|--------|
| **V1** | AMOLED screen-on for ≥60-min hands-off reading (+ dim-AON fallback legibility) | not started | — |
| **V2** | Reliable repeated phone→watch sends (Android first-send bug defeated); bridge sufficiency (OQ2) | not started | — |
| **V3** | Per-message chunk-size ceiling (`BLE_REQUEST_TOO_LARGE` threshold) | not started | — |
| **V4** | 1-hour reading session battery drain vs ≤10%/hour target | not started | — |

## V1 — Hands-off screen-on (Story 1.3)
_Procedure:_ minimal spike opening an `ActivityRecording.Session`; verify the display stays lit
and legible ≥60 min with no interaction; test dim-AON fallback legibility on the ~10% budget.
_Status:_ not started. _Result:_ —

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

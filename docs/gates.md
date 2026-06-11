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
| **V2** | Reliable repeated phone→watch sends (Android first-send bug defeated); bridge sufficiency (OQ2) | **passed** (2026-06-11) | 400/400 first-try ack-confirmed sends (200 × 2 encodings); bug not observed; OQ2 = keep stock plugin, base64 transport ([ADR 0002](decisions/0002-oq2-companion-bridge.md)) |
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

**Notes.** Battery: 28% start; end-of-run drain **not measured** — the only post-run reading
(32%) was taken after ~3 min on a USB charger and is unusable. The real measurement is gate V4
(Story 3.9). Backlight probe: a single `Attention.backlight(true)` call mid-dim, pressed
**after the 60-min hands-off window** (not a candidate cause for the in-run HIGH blips),
returned without `BacklightOnTooLongException`; sustained use untested — not a pass path.

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
_Status:_ **passed** (2026-06-11, real Fenix 8 47 mm ↔ Samsung SM-S938B / Android 16, wireless
via Garmin Connect Mobile). _Result:_ 400/400 ack-confirmed first-try sends; first-send bug not
observed; OQ2 resolved = **keep `watch_connectivity_garmin` (stock), base64-String transport**
([ADR 0002](decisions/0002-oq2-companion-bridge.md)). Premise-rework flag: **not raised**.

**Method.** Phone harness `companion/lib/gate_v2/` (`GateV2Runner` over plugin 0.1.13, which pins
Garmin Android SDK 2.0.3): N=200 sequential `chunkData` envelopes per run, offset-addressed
(`off += 100`, fixed fingerprint), ~900 B SPEC §5 payload (100 records), one send in flight,
10 s timeout per send, retry-same-chunk on failure, re-init + resend after 3 consecutive failures.
**Success = the watch's ack arrived back on the phone** — never the SDK's `SUCCESS` callback
(documented to lie). Watch spike `GateV2View`/`PaceTurnerApp` validates every chunk through the
unchanged `Protocol.validateEnvelope` + `StreamDecoder.decodeChunk` and acks via
`Communications.transmit`. Wireless only — SDK 2.0.3's tethered/ADB bug would pollute simulator
measurement.

**Measured** (per run; N=200 each):

| Run | Transport for `p` | First-try acks | Retried / failed | Timeouts | Exceptions | Re-inits | Wall-clock |
|---|---|---|---|---|---|---|---|
| A | base64 `String` (~1200 B wire) | **200/200** | 0 / 0 | 0 | none | 0 | 178 490 ms → **~892 ms/chunk** (~1.0 KB/s payload) |
| B | `List<int>` (900 elements) | **200/200** | 0 / 0 | 0 | none | 0 | 293 074 ms → **~1465 ms/chunk** (~0.6 KB/s payload) |

- The documented "first-send-works-then-fails" signature (hung future, no callback) did not appear
  in 400 consecutive wireless sends; the timeout → re-init → resend defense never activated (its
  re-init arm therefore remains hardware-unproven — see ADR 0002 consequences).
- Encoding verdict: base64-String wins decisively — the SDK's per-element array serialization costs
  ~64% more wall-clock than base64's 33% size inflation. Run B's watch live counters were zeroed
  mid-run by a START press (~chunk 72): final watch display `R:128 V:128 A:129` covers the
  post-reset window (`A` leads `V` by one in-flight ack callback straddling the reset); phone-side
  ack accounting spans the full run and is the authoritative AC1 measure.
- Bonus evidence: watch→phone ack channel (Epic 4's position-sync direction) lossless across both
  runs; no `FAILURE_MESSAGE_TOO_LARGE` / `BLE_REQUEST_TOO_LARGE (-102)` at ~1 KB (V3 starts its
  sweep from a known-good size).
- Run artifact: one aborted Run B attempt was a **phone-side app freeze** (Android 16 froze the
  backgrounded debug app — Dart timers stop entirely), not a transfer failure. Direct evidence for
  Epic 4's foreground-service requirement.

**Verdict matrix** (observed row in bold):

| Observed | Verdict | Consequence |
|---|---|---|
| **High first-try ack rate, bug not observed, defense unneeded** | **V2 passed — keep bridge (base64 transport; fork unjustified on measured overhead)** | **Epic 4 hardens on `watch_connectivity_garmin`; TransferEngine embeds timeout+retry+re-init anyway (FR20 designs for failure), in ONE place (architecture §Process Patterns)** |
| Bug observed; defense recovers deterministically | V2 passed-with-defense | Defense mandatory and validated; bridge keep/fork per criteria |
| Bug observed; plugin re-init does NOT recover | V2 bridge-insufficient — OQ2 = custom bridge / fork-with-shutdown | correct-course adds bridge-build to Epic 4; re-verify V2 |
| Unrecoverable even at SDK level | Premise-rework flag | Epic 4 must NOT harden (R2 worst case) |

**Product implication (carry to Epic 4).** `ciq_bridge.dart` wraps the stock plugin with the
base64-String transcode at the seam; `TransferEngine` inherits the validated defense pattern
(serialize, timeout, idempotent retry, re-init escalation, ack-only success) in one place.
Transfers run under a foreground service (freeze evidence above). Add ProGuard
`-keep class com.garmin.** { *; }` before any release build (plugin ships no keeps).

## V3 — Chunk-size calibration (Story 1.5)
_Procedure:_ sweep chunk sizes upward from ≤1 KB on the V2 harness; find the
`BLE_REQUEST_TOO_LARGE` (-102) threshold; record the safe working size.
_Status:_ not started. _Result:_ —

## V4 — Reading-session battery (Story 3.9)
_Procedure:_ 60-min continuous session on hardware (screen on, sync connected); measure drain.
_Status:_ not started. _Result:_ —

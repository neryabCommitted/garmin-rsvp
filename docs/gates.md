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
| **V3** | Per-message chunk-size ceiling (`BLE_REQUEST_TOO_LARGE` threshold) | **passed** (2026-06-13) | Transport ceiling = phone serializer cap (α) 16 384 B serialized; safe working chunk **11 584 B binary / 15 448 B wire** (~1158 words). Tighter real limit: watch decode-watchdog → Epic 4 decodes incrementally, not in the BLE callback |
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
  post-reset window (`A` leading `V` is consistent with one in-flight ack callback straddling
  the reset — the mechanism is inferred, not verified); phone-side ack accounting spans the
  full run and is the authoritative AC1 measure.
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
_Procedure:_ sweep chunk sizes upward from ≤1 KB on the V2 harness; find the size-class
rejection threshold (α phone-serializer cap / β `BLE_REQUEST_TOO_LARGE -102`); record the safe
working chunk size in binary bytes, base64-wire bytes, and ~words/chunk.
_Status:_ **passed** (2026-06-13, real Fenix 8 47 mm / firmware 22.35, API 6.0.2 ↔ Samsung
SM-S938B / Android 16, wireless via Garmin Connect Mobile). _Result:_ two binding constraints found
— a **phone-side transport ceiling** and, more tightly, a **watch-side decode-time watchdog**. Safe
working chunk size **11 584 B binary / 15 448 B wire** (transport); Epic 4 must additionally decode
**incrementally** (never a whole chunk in the BLE callback). Premise-rework flag: **not raised**
(V2 already proved the channel; this is calibration).

**Method.** Same harness, sweep mode: `GateV2Runner.runSweep` (`companion/lib/gate_v2/`) sends
**M=3 sends per size, all must ack to step up**; geometric-coarse (×2 from a 768 B known-good floor)
to the first reproduced rejection, then **bisect** the last-good→first-fail gap. Each rejection is
**re-tested once** to separate a reproducible ceiling from the Story-1.4 mode-a silent hang (c).
Size is parametrized by **target SPEC §5 binary bytes** (word length × count via `encodeChunk`),
lifting the fixed-N record cap so the sweep can cross the 16 384 B serializer cap. Transport =
**base64-String only** (ADR 0002). Per-send outcome is classified `{ack, sizeError(code),
genericError(code), silentTimeout, successNoAckTimeout}`, recording whether the send future
completed before the ack timeout (deferred-work item #2 resolved). Cancel/Stop seam added
(deferred-work item #1 resolved). **Wireless on real hardware only** (SDK 2.0.3 tethered bug).

> **Two-run history — the watchdog finding (AR15 vindicated).** The first sweep attempt **crashed
> the watch app** at a multi-KB chunk: `Watchdog Tripped Error — Code Executed Too Long` in
> `StreamDecoder.decodeChunk`/`isValidUtf8` (device `CIQ_LOG.YML`). The spike originally decoded the
> **whole chunk synchronously in the BLE receive callback** (Story 1.4's integrity proof). On real
> hardware the firmware watchdog (a per-callback instruction budget, ~120k–240k cycles, **device-
> varying and absent in the simulator** — exactly AR15) kills the app; the kill is **uncatchable**,
> so no receive guard can survive it. The Connect IQ community's only fix is to **slice heavy work
> across timer ticks** (no threads). The watch was changed to **lighten-receive** — O(1) structural
> validation + a bounded-prefix integrity touch + received-size witness + ack, **no full decode in
> the callback** — which both (a) lets the sweep find the true *transport* ceiling, and (b) records
> the watchdog as a first-class Epic-4 constraint. `processMessage` (full decode) remains the
> host/CI integrity proof, where there is no watchdog.

**The rejection classes** (attribution is the gate's whole point):
- **(α) `FAILURE_MESSAGE_TOO_LARGE`** — SDK 2.0.3 serializer cap, **16 384 serialized bytes**,
  phone-side, before BLE. **This is the operative transport ceiling** (hit first, as predicted).
- **(β) `BLE_REQUEST_TOO_LARGE` (-102)** — undocumented BLE per-message cap. **Above α** here: the
  watch *received and acked* a 12 288 B chunk (witness below), so β is higher than α and never bit.
- **(c) silent hang (mode a)** — not observed in this sweep.
- **(watchdog)** — watch-side decode-time limit; **tighter than α** but only when decoding in the
  callback, which Epic 4 will not do.

**Measured** (29 sends; geometric coarse 768→6144 clean, 12288 rejected, then bisected):

| Quantity | Binary bytes | base64-wire bytes |
|---|---|---|
| Last size that ack-confirmed all M=3 sends | 12 096 | 16 128 |
| First size whose rejection reproduced (α) | 12 288 | 16 384 |
| **Safe working chunk size** (last-good − 512 B margin) | **11 584** | **15 448** |

- Rejection class: **α — phone-side serializer cap**, code verbatim: `[FAILURE_MESSAGE_TOO_LARGE]`.
  First-fail wire size is **exactly 16 384 B** = the documented SDK 2.0.3 cap.
- Safe-working margin: **512 B** (BLE round-trip variance + envelope-dict overhead headroom below
  the binding cap).
- **~words/chunk** at the safe working size: **~1 158** (at ~10 B/word = 5-byte SPEC §5 header +
  ~5-char average word). Epic 4's 200–500-word boundary chunker (AR23) sits **far under** this — a
  500-word chunk (~5 KB) has comfortable headroom on the transport side.
- Watch received-size witness: **`rcv:12288B`**, R/V/A **29/29/29** (zero loss). The watch received
  and acked a 12 288 B chunk that the phone's serializer *rejected* — confirming **β (BLE) > α
  (phone)** and that α is the operative transport ceiling. (At the 16 384 B boundary the plugin
  reports `FAILURE_MESSAGE_TOO_LARGE` to the phone even though the watch still received the message;
  the phone's ack-matching correctly discards the un-acked-from-its-view send — counted as the
  rejection.)

**Verdict matrix** (observed row in bold):

| Observed | Verdict | Consequence (Epic 4) |
|---|---|---|
| Clean BLE ceiling (β, `-102`) found below the phone cap | V3 calibrated — BLE-bounded | chunk size = safe-working (BLE-bound); fork to native bytes won't help |
| **Phone serializer cap (α) hit first, β BLE cap above it** | **V3 calibrated — transport-cap-bounded at 16 384 B serialized; safe working 11 584 B binary** | **`transfer_engine` chunk-size hook ≤ 11 584 B binary; ADR 0002 escape hatch (SDK 2.4.0 native bytes) would raise α if ever needed — not needed at 200–500-word chunks** |
| Only a silent hang (c) appears, no size-class rejection | V3 conservative — not BLE-bounded | Adopt a conservative size with margin; re-measure in Epic 4 |
| No rejection at all below the hard cap | V3 conservative — cap-bounded | Adopt the cap-bounded size; chunk to taste within it |

**Product implication (carry to Epic 4).** Two calibrated constraints, both with large headroom for
the planned 200–500-word (~2–5 KB) chunk:
1. **Transport:** keep a single `chunkData` message ≤ **11 584 B binary** (15 448 B wire) — the
   `transfer_engine` chunk-size calibration hook (AR23, architecture lines 423/514) adopts this; the
   provisional numbers there are now empirical.
2. **Decode (the tighter, hardware-only constraint):** `ChunkedWordSource` **must not decode a whole
   chunk in the BLE receive callback** — decode incrementally / timer-sliced (Connect IQ has no
   threads; the synchronous decode trips the watchdog well below 11 584 B). Persist the raw chunk on
   receipt, decode lazily during reading. This is the binding real-world limit on *how* chunks are
   processed, even though chunk *size* can be large.

> V3 is a **calibration**, not a pass/fail premise check — V2 already proved the channel (§V2:
> 400/400). The safe working size + the decode-incrementally constraint satisfy AC1; no
> premise-rework flag raised.

## V4 — Reading-session battery (Story 3.9)
_Procedure:_ 60-min continuous session on hardware (screen on, sync connected); measure drain.
_Status:_ not started. _Result:_ —

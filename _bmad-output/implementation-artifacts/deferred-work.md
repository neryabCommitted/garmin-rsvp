# Deferred Work

## Deferred from: code review of 1-2-protocol-spec-md-and-mirrored-constants (2026-06-10)

- `chunkData` payload check in `decodeEnvelope` is `Uint8List`-exact (`companion/lib/protocol/envelope_codec.dart:280-286`) — rejects byte-valued `List<int>`, the shape platform channels commonly deliver. Decide accept-and-convert vs document-the-edge when wiring `companion/lib/data/ciq_bridge.dart` in Epic 4. The watch side imposes no equivalent constraint.

## Deferred from: code review of 1-3-gate-v1-hands-off-screen-on-feasibility-hardware (2026-06-11)

- Gate-V1 spike robustness patterns (`watch/source/PaceTurnerApp.mc`) — acceptable for the completed one-shot spike, must NOT carry into Epic 3 `ActivitySessionStrategy.mc` / display modules: (1) `session.start()` Boolean ignored — a `false` return leaves the UI "active" without the During-Activity display profile, silently invalidating any session-dependent behavior; (2) `createSession` can throw `Lang.InvalidOptionsException` — wrap session creation; (3) `Storage.setValue` unguarded in a system callback (`onDisplayModeChanged`) — `StorageFullException` would crash on the very event being recorded; (4) state recording active outside session lifetime — gate callbacks on `isSessionActive()`, reset anchor+log together; (5) exception catches type-narrowed to one class in button handlers; (6) unbounded in-memory/persisted log growth; (7) no debounce on session toggle (Dev Notes' rapid-cycle firmware-freeze warning); (8) `System.getTimer()` wraparound → negative elapsed arithmetic. Sources: blind+edge review layers, Story 1.3 code review.

## Deferred from: code review of 1-4-gate-v2-transfer-reliability-bridge-sufficiency-hardware (2026-06-11)

- ~~Gate-V2 harness has no cancel path~~ — **RESOLVED in Story 1.5**: `GateV2Runner.cancel()` (cooperative, checked at each step/attempt boundary) + a Stop button in `gate_v2_screen.dart`; both `run` and `runSweep` return a partial, well-formed summary on cancel. A wedged native send still cannot be force-killed (documented limit). Epic 4's `TransferEngine` inherits the seam.
- ~~Gate-V2 timeout evidence can't distinguish silent-hang vs SUCCESS-without-ack~~ — **RESOLVED in Story 1.5**: the sweep classifies each send `{ack, sizeError(code), genericError(code), silentTimeout, successNoAckTimeout}` and records whether the send future completed before the ack timeout, with per-step size/index in `SweepStep`. (The fixed-N `run` path keeps its single `timeoutCount`, which suffices for the reliability count it measures.)

## Forward to Epic 4 — from gate V3 (Story 1.5, 2026-06-13) — BINDING constraint for Story 4.1

- **The watch must NOT decode a whole chunk synchronously in the BLE receive callback.** Gate V3 proved on real hardware (Fenix 8 fw 22.35) that a full per-word decode of a multi-KB chunk in the receive callback trips the firmware **watchdog** (`Watchdog Tripped Error — Code Executed Too Long`, in `StreamDecoder.decodeChunk`/`isValidUtf8`). The watchdog is a per-callback instruction budget (~120k–240k cycles, device-varying) and the kill is **uncatchable** — no try/catch survives it. **It is absent in the simulator/CI** (AR15), so unit tests and the CI image will *not* catch a regression here. The spike worked around it with "lighten-receive" (ack-on-receipt, O(1) validate, no in-callback decode) — see `watch/source/GateV2View.mc` `receiveLight` for the pattern.
  - **Story 4.1 design rules** (`ProtocolClient` + `ChunkedWordSource`, epics.md:761):
    1. `ProtocolClient` (receive path): validate fingerprint/offset/length/bounds + **commit raw chunk bytes to Storage** — decode nothing in the BLE callback. (The ACs already say "before commit" + raw bucket storage — keep it raw.)
    2. `ChunkedWordSource` (serve path): decode only a **bounded heap window** on demand (`wordAt`/`prefetchAround`), and keep each decode slice under the watchdog budget. If a window is still too large, **timer-slice** the decode across ticks (Connect IQ has no threads — the community-standard fix; Garmin-forum confirmed).
  - **Transport size is NOT the binding limit** — V3 measured the transport ceiling at 11 584 B safe (16 384 B serializer cap, α); the watchdog bites well below that *only when decoding in-callback*. Chunk size (200–500 words, ~2–5 KB) is comfortably under transport; the real rule is *how* you decode, not *how big* the chunk is.
  - Full details + the verdict matrix: `docs/gates.md` §V3. Anchors AR12 ("decoded reading window") and AR15 ("simulator lies about … watchdog").

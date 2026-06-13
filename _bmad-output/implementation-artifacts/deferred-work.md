# Deferred Work

## Deferred from: code review of 1-2-protocol-spec-md-and-mirrored-constants (2026-06-10)

- `chunkData` payload check in `decodeEnvelope` is `Uint8List`-exact (`companion/lib/protocol/envelope_codec.dart:280-286`) — rejects byte-valued `List<int>`, the shape platform channels commonly deliver. Decide accept-and-convert vs document-the-edge when wiring `companion/lib/data/ciq_bridge.dart` in Epic 4. The watch side imposes no equivalent constraint.

## Deferred from: code review of 1-3-gate-v1-hands-off-screen-on-feasibility-hardware (2026-06-11)

- Gate-V1 spike robustness patterns (`watch/source/PaceTurnerApp.mc`) — acceptable for the completed one-shot spike, must NOT carry into Epic 3 `ActivitySessionStrategy.mc` / display modules: (1) `session.start()` Boolean ignored — a `false` return leaves the UI "active" without the During-Activity display profile, silently invalidating any session-dependent behavior; (2) `createSession` can throw `Lang.InvalidOptionsException` — wrap session creation; (3) `Storage.setValue` unguarded in a system callback (`onDisplayModeChanged`) — `StorageFullException` would crash on the very event being recorded; (4) state recording active outside session lifetime — gate callbacks on `isSessionActive()`, reset anchor+log together; (5) exception catches type-narrowed to one class in button handlers; (6) unbounded in-memory/persisted log growth; (7) no debounce on session toggle (Dev Notes' rapid-cycle firmware-freeze warning); (8) `System.getTimer()` wraparound → negative elapsed arithmetic. Sources: blind+edge review layers, Story 1.3 code review.

## Deferred from: code review of 1-4-gate-v2-transfer-reliability-bridge-sufficiency-hardware (2026-06-11)

- Gate-V2 harness has no cancel path: `GateV2Runner` exposes no cancel API, `gate_v2_screen.dart` has no Stop button, and N is unbounded (`gate_v2_screen.dart:77`) — a stuck run is only killable via app kill (how the aborted Run B attempt actually ended). Add a cancel seam when Story 1.5 (gate V3 sweep) reuses this harness; Epic 4's `TransferEngine` must have one from day one.
- Gate-V2 timeout evidence can't distinguish the two signatures the story says to identify: silent-hang (mode a, send future never completed) vs SDK-SUCCESS-without-ack both land in one `timeoutCount` bucket (`gate_v2_runner.dart:428-432`), and timeout chunk indices aren't recorded. Sharpen for Story 1.5, where a timeout during the size sweep must be attributable.

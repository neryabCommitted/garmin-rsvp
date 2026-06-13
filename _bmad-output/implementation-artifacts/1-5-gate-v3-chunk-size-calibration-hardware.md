---
baseline_commit: e25aa33
---

# Story 1.5: Gate V3 — chunk-size calibration (hardware)

Status: ready-for-dev

## Story

As a developer,
I want the empirical per-message size ceiling on Fenix 8,
so that the transfer engine ships with a calibrated chunk size instead of a guess.

## Acceptance Criteria

1. **Given** the V2 transfer harness
   **When** chunk sizes are swept upward from a conservative ≤1 KB
   **Then** the `BLE_REQUEST_TOO_LARGE` (-102) threshold is found
   **And** the safe working chunk size is recorded.

2. **Given** the calibrated value
   **When** it is captured
   **Then** it is recorded in `docs/gates.md` as the V3 result
   **And** it is referenced by the transfer engine's chunk-size config (Epic 4).

> **Threshold definition for AC1 (the gate's whole point — read before writing sweep code).** The "ceiling" is **size-class rejection**, which can surface in *three* distinguishable ways and the sweep MUST tell them apart (this is the deferred-work evidence-sharpening item, now load-bearing):
> - **(α) Phone-side, before BLE** — `FAILURE_MESSAGE_TOO_LARGE`: the plugin's pinned SDK 2.0.3 rejects a *serialized* payload > **16 384 bytes** in its own serializer. Surfaces as a `PlatformException` → `SpikeSendException(code)` → recorded verbatim in `exceptionCodes`. For the base64-String transport (ADR 0002), "serialized size" ≈ the base64 string length ≈ `ceil(binaryBytes/3)*4` plus envelope-dict overhead — so this cap bites at roughly **~12 KB of SPEC §5 binary payload**.
> - **(β) Watch-side BLE** — `BLE_REQUEST_TOO_LARGE` (-102): the *undocumented* per-message BLE ceiling, which "may be lower" than (α). How a watch-side BLE reject surfaces to the phone is itself a finding — it may come back as a send-error code, or it may mean the watch never receives the message and never acks → the phone sees a **silent timeout**. Either way it must be attributed to the exact payload size that triggered it.
> - **(c) Silent-hang reliability bug (mode a from Story 1.4)** — a hung send future with no callback, unrelated to size. A timeout at a size *below* a clean lower bound is suspect-(c), not the ceiling. The sweep must not misreport a one-off hang as the size ceiling: re-test the same size before concluding.
>
> The recorded result is **three numbers + a signature**: last size that ack-confirmed, first size that was rejected, the rejection class (α/β/c), and the **safe working chunk size** (last-good with a margin), each expressed in **both** SPEC §5 binary bytes **and** base64-wire bytes, plus a translation to **~words/chunk** for Epic 4's 200–500-word boundary chunker (AR23).

## Tasks / Subtasks

- [ ] Task 1: Sweep mode + cancel in the V2 runner (companion) (AC: 1) — **extend the existing harness in place; do not fork a parallel gate_v3 runner**
  - [ ] Add a size-sweep capability to `companion/lib/gate_v2/gate_v2_runner.dart`. The runner already owns chunk size (via `recordsPerChunk`) and the codec path; generalize it so a run can step payload size upward instead of holding it fixed. Keep the existing fixed-N reliability run working (Story 1.4's evidence path is not broken). Pure Dart, **no Flutter imports** — testable with the existing `FakeBridge`.
  - [ ] **Parametrize size by target payload bytes, not record count.** `encodeChunk` (`companion/lib/protocol/stream_codec.dart`) accepts words of 1–255 UTF-8 bytes (SPEC §5), so a target byte size is hit by choosing word length × count — this lifts the implicit ~9 KB ceiling the 999-record cap imposes and lets the sweep reach and cross the ~12 KB base64 / 16 384 B serialized cap. Generate **size-stable-but-content-varying** filler per chunk (keep the Story-1.4 property: cross-chunk misdelivery/reorder cannot decode silently as the right chunk). Stay SPEC §5-valid (`orpPivot < wordLen`, `wordLen` 1–255).
  - [ ] **Sweep schedule:** start ≤1 KB (a known-good size — Story 1.4 ran ~900 B cleanly), step upward (e.g. +1 KB linear, or geometric — see Dev Notes → Sweep design). At each size send **M sends** (default M=3) and require all M to ack before stepping up; on the **first size where a send is rejected**, record last-good + first-failing, **re-test that size once** to rule out the (c) silent-hang, then stop. Cap the sweep at a hard max (default ~20 KB binary / past the phone cap) so it terminates even if no ceiling appears below the SDK serializer cap.
  - [ ] **Per-step outcome classification** (the deferred evidence-sharpening): for every send record `{stepSize, chunkIndex, outcome}` where outcome ∈ `{ack, sizeErrorCode(codeVerbatim), genericException(codeVerbatim), silentTimeout}`. Split the Story-1.4 single `timeoutCount` bucket: a timeout now carries its size and index, and is labelled silent-hang-suspect vs (the runner cannot see SDK-SUCCESS-without-ack directly, but it CAN record whether the send future *completed* before the ack timeout — record that bit so α/β/c stay separable). Match size-class codes case-insensitively against a small known set (`TOO_LARGE`, `MESSAGE_TOO_LARGE`, `-102`, `BLE_REQUEST_TOO_LARGE`) and tag them `sizeError` vs generic.
  - [ ] **Cancel seam (deferred-work item #1, now required):** add a `cancel()` API to `GateV2Runner` (cooperative — checked at each step/attempt boundary; a wedged native send cannot be force-killed, document that limit as Story 1.4 already documented for the pending call). A cancelled run returns a partial, well-formed summary (not an exception). N / sweep length stays bounded by construction.
  - [ ] **Transport = base64-String only** (ADR 0002 decided it; Run B `List<int>` is not re-run — note why in Dev Notes). Record per step **both** the SPEC §5 binary byte size and the base64-wire byte size, because the phone cap (α) is on the wire/serialized size while the BLE cap (β) is on the message — Epic 4 must size against the binding one.
  - [ ] Extend `GateV2Summary` (or add a `GateV3SweepSummary`) with: `lastGoodBytes`, `firstFailBytes` (binary + wire each), `rejectionClass`, `safeWorkingBytes` (last-good − margin), `perStep` records, and a `transcript()` producing the gates.md-ready block. Keep the existing summary fields intact for the reliability path.
  - [ ] Tests in `companion/test/gate_v2/gate_v2_runner_test.dart` (extend; mirrors `lib/`): `FakeBridge` scripted to error with a `TOO_LARGE` code at a threshold size → sweep stops, last-good/first-fail/class correct; scripted silent-hang (future never completes) at a size → timeout attributed to that size+index, re-test confirms, class = (c)-suspect; `cancel()` mid-sweep → partial summary, no throw; size→records generation hits the requested byte size within tolerance and stays SPEC §5-valid; existing Story-1.4 fixed-N tests stay green. `flutter analyze` clean under strict options; protocol conformance tests stay green.

- [ ] Task 2: Sweep controls + Stop button in the harness screen (companion) (AC: 1)
  - [ ] Extend `companion/lib/gate_v2/gate_v2_screen.dart`: a **mode toggle** (reliability run | size sweep), sweep parameters (start size, step, max, M sends/size — sensible defaults pre-filled), a live readout (current step size in binary+wire bytes, last-good, last error code/class, sends acked at current size), and a **Stop button** wired to `runner.cancel()` (visible whenever a run is in flight). Final summary view stays selectable/transcribable. Keep the phone awake via `flutter run` over USB (no wakelock dep — Story 1.4 precedent).
  - [ ] The `GarminSpikeBridge` adapter is reused unchanged (base64 transport already lives in the runner's `_transcode`). `initialize()` keeps its 10 s timeout guard. No new pubspec deps.
  - [ ] Update `companion/test/widget_test.dart` smoke test if the screen's constructor/controls change shape (it must still pump without platform channels).

- [ ] Task 3: Watch side — accept and report larger chunks without crashing (companion + watch) (AC: 1)
  - [ ] The watch receive path (`watch/source/GateV2View.mc` `GateV2.processMessage`, `watch/source/PaceTurnerApp.mc` `onPhoneMessage`) must survive **larger** payloads than Story 1.4's ~900 B with no fixed-size assumption: `arrayToByteArray` allocates to `arr.size()` (fine), `isPlausibleBase64` scans the full string (fine), `base64ToByteArray` → `StringUtil.convertEncodedString` and `StreamDecoder.decodeChunk` are already bounds-checked. **Confirm** (don't assume) no buffer/loop caps a larger chunk, and that the broad-catch receive guard still records evidence rather than crashing if a large decode fails. NFR2 heap (≤600 KB) is not a gate concern for a disposable spike, but a decode that allocates a multi-KB ByteArray must not OOM-crash the run — bound it / catch broadly (already the pattern).
  - [ ] Add **free evidence**: track and display the **max payload byte size the watch successfully decoded** this run (extend the counters line / evidence string in `GateV2.evidenceString`). This is the watch's independent witness of the largest message that actually crossed BLE — corroborates the phone-side last-good. Keep it a bounded counter (no growing log; logging-budget discipline AR25).
  - [ ] Keep the two-press reset (Run separation) and generation-tagged acks from Story 1.4 — a size sweep is still one sideload, multiple runs.
  - [ ] Extend `watch/source-test/GateV2Test.mc`: a large well-formed base64 fixture round-trips through `processMessage` (never feed `convertEncodedString` malformed input — uncatchable SDK 8.4.0 system error, Story 1.2 lesson); max-decoded-size accounting is pure-tested. Verify all three local targets green at Strict `-l 3` (normal, `-r`, `-t`), then run the suite in the exact CI image (`ghcr.io/matco/connectiq-tester:latest`, SDK 8.4.0, `fenix847mm`) before pushing. Protocol baseline tests stay green.

- [ ] Task 4: Hardware sweep, record V3, wire the calibrated size forward (AC: 1, 2) — **human-in-the-loop (Nerya holds the phone)**
  - [ ] Prerequisites (same as Story 1.4 Task 3): Android phone with **Garmin Connect Mobile installed and paired to the Fenix 8**; watch app sideloaded per `docs/setup.md` (USB Mode → MTP, `gio copy`, unplug — sideload the **normal** build for crash symbols); companion via `flutter run`; watch app foregrounded for the whole run; phone unlocked/awake. **WIRELESS on real hardware only** — the simulator/tethered path misreports this whole area (SDK 2.0.3 tethered bug; AR15 spirit).
  - [ ] Run the size sweep (base64 transport) from ≤1 KB upward. Record: **last-good size, first-failing size, rejection class (α phone-cap / β BLE-102 / c silent-hang), the error code verbatim**, and the watch's max-decoded-size witness — each in binary + base64-wire bytes. If the **phone cap (α) is hit before any watch BLE cap (β)**, that is the operative ceiling for the base64 transport and must be reported as such (with the note that a fork to SDK 2.4.0 native bytes would move it — ADR 0002 escape hatch). Probe the (c) ambiguity deliberately: any timeout gets its size re-tested.
  - [ ] Compute the **safe working chunk size** = last-good minus a margin (state the margin and its rationale — BLE variance / envelope overhead headroom), expressed as binary bytes, wire bytes, and **~words/chunk** so Epic 4's chunker (200–500 words on sentence/paragraph boundaries) can adopt it directly.
  - [ ] Update `docs/gates.md`: flip the V3 table row (status + result) and expand **§V3** — procedure (sweep schedule, transport, M/size), the measured last-good/first-fail/class with codes verbatim, the safe working size in all three units, the watch witness, and the **Epic 4 implication** (the value lands in `transfer_engine`'s chunk-size calibration hook — architecture line 423 / AR23; provisional chunk/bucket numbers, line 514, are now empirical). Use the §V1/§V2 sections as the format precedent; include a verdict matrix (observed row bold) covering: clean BLE ceiling found / phone-cap-first / silent-hang-confounded / no ceiling below cap.
  - [ ] If the sweep cannot find a stable ceiling (only the (c) silent-hang appears, no size-class rejection) — record that the chunk size is **transport-cap-bounded, not BLE-bounded**, adopt a conservative size with margin below the phone cap, and note it for Epic 4 re-measurement. Do **not** raise a premise-rework flag for this gate — V2 already passed; V3 is a calibration, and a conservative-but-working size satisfies AC1's "safe working chunk size is recorded."
  - [ ] Update sprint-status: `1-5-gate-v3-chunk-size-calibration-hardware` → review (code-review flips it to done).

## Dev Notes

### Scope discipline (prevent creep)

V3 is a **calibration sweep on the existing V2 harness + a recorded number** — the smallest of the three hardware gates. Explicitly NOT here:
- **No new Epic 4 modules.** No `transfer_engine.dart`, `ciq_bridge.dart`, `ProtocolClient.mc`, `ChunkedWordSource.mc`, `StorageKeys.mc`. V3 produces the *number* those modules will consume; it does not build the chunk-size config object — it records the value in `docs/gates.md`, which Epic 4's AR23 calibration hook reads.
- **No parallel `gate_v3/` harness.** Extend `companion/lib/gate_v2/` in place (the deferred-work items name those exact files as Story 1.5's reuse target). One harness, two modes.
- **No SPEC.md change.** SPEC §4.2 already says `n` is "bounded only by transport message-size limits" — V3 measures that limit; it does not encode it in the protocol. No new message type, no transport-encoding section.
- **No Run B (`List<int>`).** ADR 0002 decided base64-String. The sweep characterizes the *decided* transport's ceiling; re-running the rejected encoding adds no decision value.
- **No release hardening** (ProGuard keeps, foreground service, wakelock) — Story 1.4 / ADR 0002 already logged them forward for Epic 4. Debug build, `flutter run`, strict-clean + CI-green is the bar (Story 1.3/1.4 precedent).
- One file's worth of net-new logic (sweep + cancel in the runner) + UI controls + watch witness. No new deps, no new manifest permissions (Communications already in from Story 1.4).

### Why this is "passed" territory, not "risk" territory

Gate V2 (Story 1.4) already proved the channel: 400/400 ack-confirmed sends, bug not observed, no `TOO_LARGE`/-102 at ~1 KB (`docs/gates.md` §V2 bonus evidence — "V3 starts its sweep from a known-good size"). V3 is not re-litigating reliability; it is finding the *upper bound* of a channel known to work at the bottom. The deliverable is a calibrated chunk size with margin, not a pass/fail premise check.

### Sweep design (the one real design choice)

The sweep trades resolution against run time. Two viable shapes (dev picks; default = **coarse-then-fine**):
- **Linear** (+1 KB/step): simple, ~12–20 steps to the cap, even resolution. Good default if each step is cheap (M=3 sends × ~1–2 s = a few s/step).
- **Coarse-then-fine** (geometric to first failure, then bisect the last-good→first-fail gap): fewer hardware sends, sharper threshold. Recommended — the bisection pins the ceiling to within the margin you'd apply anyway.

Either way: **M sends per size, all must ack to advance; first rejection → re-test once (rule out (c)) → record → stop (or bisect).** Keep M small (the gate needs the ceiling, not a reliability sample at each size — that was V2's job).

### The three rejection classes (why attribution is the whole gate)

From Story 1.4 research (agent-verified incl. SDK bytecode disassembly), confirmed in `docs/gates.md` §V2 and ADR 0002:
- **(α) `FAILURE_MESSAGE_TOO_LARGE`** — SDK 2.0.3 serializer hard cap at **16 384 serialized bytes**, *before* BLE. Deterministic, phone-side, arrives as a `PlatformException` code. For base64-String this bites at ~12 KB binary. **This is very likely the ceiling you actually hit first** with the stock plugin — record it as such; it is a real, bounding number for Epic 4.
- **(β) `BLE_REQUEST_TOO_LARGE` (-102)** — the undocumented BLE per-message cap, "may be lower" than (α). If it exists below (α), it's the operative ceiling. Watch for whether it returns a code phone-side or just suppresses delivery (→ silent timeout — then attribution depends on the size monotonicity: a clean fail at size S after clean acks at S−step, reproduced, is the ceiling even if it presents as a timeout).
- **(c) silent-hang (mode a)** — the Story 1.4 reliability bug; size-independent. A timeout that does NOT reproduce at the same size, or appears below a previously-clean larger size, is (c) noise, not the ceiling. Re-test discipline separates them.

### Reuse map — what exists, consume it, don't rebuild

- `GateV2Runner` (`gate_v2_runner.dart`) — owns the send/ack/timeout/retry/defense loop, `_transcode` (base64), `_fillerRecords`, `GateV2Summary.transcript()`. **Extend** for sweep + cancel; keep the fixed-N path.
- `encodeChunk` / `WordRecord` (`stream_codec.dart`) — builds SPEC §5 payloads; words 1–255 bytes → your size lever. `chunkDataEnvelope` (`envelope_codec.dart`) — builds the `{t,v,fp,off,n,p}` dict. `ProtocolKeys` (`protocol_keys.dart`) — keys; **never inline protocol strings**.
- `GarminSpikeBridge` (`gate_v2_screen.dart`) — the real bridge adapter; reused unchanged.
- Watch: `GateV2.processMessage` + the `PaceTurnerApp.onPhoneMessage` guarded receive/ack path + `GateV2View` counters + two-press reset + generation-tagged acks — all reused; you add a max-decoded-size witness.
- `FakeBridge` in `gate_v2_runner_test.dart` — already scripts throw/hang/wrong-offset/duplicate-ack via `reinitBehavior` and friends; extend it to script a size-keyed `TOO_LARGE` and a size-keyed hang.

### Previous story intelligence (Stories 1.2/1.3/1.4 Dev Agent Records)

- **CI ceiling is real:** tester image is SDK 8.4.0 / `fenix847mm` / API 5.2.0 cap. Everything used here (`registerForPhoneAppMessages` 1.4.0, `transmit` 1.0.0, `convertEncodedString`) compiles under it — but verify in the exact image (`docker run --rm -v $PWD/watch:/work -w /work ghcr.io/matco/connectiq-tester:latest fenix847mm`). Story 1.2 found an SDK-8.4.0-only **uncatchable** error in `StringUtil.convertEncodedString` on malformed base64 — the `isPlausibleBase64` guard (already in `GateV2View.mc`) is the shield; **never feed it garbage in tests, even large fixtures**.
- All three watch build targets at Strict `-l 3`; needing the level lowered is a defect. `monkey.jungle` already links `source-test/`; new files/fixtures need no jungle edit.
- Strict-mode patterns that recur: untyped `Dictionary` reads need `as Lang.Object?` then a cast; invariant generics need bare `as Array` casts at call sites (Story 1.4 hit both); persist evidence as a compact **String**, not nested arrays (Storage value-type polys differ across SDK 8.4.0/9.1.0).
- **The two Story-1.4 deferred items are this story's load-bearing work, not optional polish:** (1) cancel path — a size sweep that triggers the silent-hang at a large size has no Stop today, only app-kill (how Run B's aborted attempt actually ended); (2) timeout attribution — Story 1.4's single `timeoutCount` bucket cannot tell a size-rejection-as-timeout from the (c) hang, and a V3 timeout *must* be attributable to a size. Both are in `deferred-work.md` (2026-06-11) pointing at `gate_v2_runner.dart` and `gate_v2_screen.dart`. Implement them; then prune those two bullets from `deferred-work.md`.
- The V1 robustness deferral list (`deferred-work.md`) items 3 (unguarded `Storage.setValue` in a system callback), 5 (type-narrowed catches in handlers), 6 (unbounded log growth) bind this spike's receive callback exactly as they did 1.4's — a crash mid-sweep destroys the evidence. They are already satisfied in `PaceTurnerApp.mc`; keep them satisfied when you touch the witness counter.
- `envelope_codec.dart`'s `chunkData` payload check is `Uint8List`-exact (`decodeEnvelope`, deferred-work 2026-06-10) — still irrelevant here: the phone *builds* envelopes (doesn't decode chunk-bearing ones), and the watch decodes via `Protocol.validateEnvelope`, not the Dart codec. Stays deferred to Epic 4's `ciq_bridge`.
- Android-16 background-freeze artifact (Story 1.4): the debug companion's Dart timers stop entirely when backgrounded — keep the phone foregrounded and screen-awake for the whole sweep, or a timeout you're attributing is actually a frozen-app artifact, not a transport finding.

### Run protocol (the dev agent cannot hold the phone)

Task 4 is a hardware run executed by Nerya (phone + watch on the table). The dev agent delivers: a sideloadable Strict-clean watch build (with the max-decoded-size witness) and a runnable companion with sweep controls + Stop button + the prerequisites/observation checklist (per-step ack/reject, threshold size, rejection class, codes verbatim) — then transcribes results into `docs/gates.md` and this story's Dev Agent Record. Do **not** simulate or guess hardware numbers; the simulator misreports this area.

### Project Structure Notes

- New: none required (extend in place). Optional: a `companion/test/` case file split if the runner test grows unwieldy — prefer extending `gate_v2_runner_test.dart`.
- Modified: `companion/lib/gate_v2/gate_v2_runner.dart` (sweep mode + cancel + classified outcomes), `companion/lib/gate_v2/gate_v2_screen.dart` (mode toggle, sweep params, Stop button), `companion/test/gate_v2/gate_v2_runner_test.dart` (sweep/cancel/classification tests), `companion/test/widget_test.dart` (if screen shape changes), `watch/source/GateV2View.mc` + `watch/source/PaceTurnerApp.mc` (max-decoded-size witness), `watch/source-test/GateV2Test.mc` (large-fixture round-trip + witness test), `docs/gates.md` (V3 row + §V3), `_bmad-output/implementation-artifacts/deferred-work.md` (prune the two 1.4 items as resolved), `_bmad-output/implementation-artifacts/sprint-status.yaml`.
- These remain **disposable spike files** in `gate_v2/` — deliberately not the Epic 4 `services/transfer/`, `data/`, `sync/` modules. V3's output is a number Epic 4 consumes, not a module it inherits.
- Conventions: Dart `snake_case.dart`, tests mirror `lib/`; Monkey C `PascalCase.mc`, private `_camelCase`, module consts `UPPER_SNAKE`; protocol constants only via `protocol_keys.dart`/`Protocol.mc`, never inline; Monkey C logging budget — state/errors only, never per-message in the hot path.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.5] — story + ACs verbatim; AR29 (V3 empirically calibrates per-message chunk size, `BLE_REQUEST_TOO_LARGE` undocumented, start ≤1 KB), AR23 (transfer engine's V3 chunk-size calibration hook), AR31 (gates.md single status page)
- [Source: _bmad-output/planning-artifacts/architecture.md:71] — BLE channel: <1 KB/s, 1–2 s round trips, ≤3 concurrent, **undocumented per-message cap (start ≤1 KB, calibrate — gate V3)**
- [Source: _bmad-output/planning-artifacts/architecture.md:423,514] — `transfer_engine` chunk-size calibration hook (V3); provisional chunk/bucket numbers until V3's empirical calibration
- [Source: _bmad-output/planning-artifacts/architecture.md:232,465] — residency/bucket sizing ↔ V3 calibration; gates V1–V4 use `transfer_engine` calibration hooks, `docs/gates.md` tracks
- [Source: protocol/SPEC.md §4.2,§4.3,§5,§1.1] — `n` "bounded only by transport message-size limits"; chunkData binary payload; record = 5 + wordLen (wordLen 1–255) → the size lever; §1.1 ByteArray transport API 6.0+
- [Source: docs/gates.md §V2] — V2 passed, 400/400; **no TOO_LARGE/-102 at ~1 KB → V3 sweeps from a known-good floor**; §V1/§V2 are the format precedent for §V3
- [Source: docs/decisions/0002-oq2-companion-bridge.md] — base64-String transport decided; 16 384-byte SDK serializer cap; "revisit when V3 finds a chunk-size ceiling where base64's 33% inflation meaningfully caps throughput — fork to SDK 2.4.0 native bytes is the first option"
- [Source: _bmad-output/implementation-artifacts/deferred-work.md (2026-06-11)] — the two 1.4 items (cancel path; timeout-attribution / silent-hang-vs-SUCCESS-without-ack / record indices) are explicitly scoped to "when Story 1.5 reuses this harness" — implement and prune
- [Source: _bmad-output/implementation-artifacts/1-4-gate-v2-transfer-reliability-bridge-sufficiency-hardware.md#Dev Agent Record] — harness shape, FakeBridge, evidence-as-String, two-press reset + generation tokens, CI-image discipline, hardware run protocol, Android-16 freeze artifact
- [Source: docs/setup.md] — build at Strict, CI-image test command, MTP sideload (normal build for crash symbols)

## Dev Agent Record

### Agent Model Used

### Implementation Plan

### Debug Log References

### Completion Notes List

### File List

---
baseline_commit: b252047
---

# Story 1.5: Gate V3 — chunk-size calibration (hardware)

Status: review

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

- [x] Task 1: Sweep mode + cancel in the V2 runner (companion) (AC: 1) — **extend the existing harness in place; do not fork a parallel gate_v3 runner**
  - [x] Add a size-sweep capability to `companion/lib/gate_v2/gate_v2_runner.dart`. The runner already owns chunk size (via `recordsPerChunk`) and the codec path; generalize it so a run can step payload size upward instead of holding it fixed. Keep the existing fixed-N reliability run working (Story 1.4's evidence path is not broken). Pure Dart, **no Flutter imports** — testable with the existing `FakeBridge`. → `runSweep()` added alongside `run()`; both share `_transcode`/codec/ack path; no Flutter imports.
  - [x] **Parametrize size by target payload bytes, not record count.** `encodeChunk` (`companion/lib/protocol/stream_codec.dart`) accepts words of 1–255 UTF-8 bytes (SPEC §5), so a target byte size is hit by choosing word length × count — this lifts the implicit ~9 KB ceiling the 999-record cap imposes and lets the sweep reach and cross the ~12 KB base64 / 16 384 B serialized cap. Generate **size-stable-but-content-varying** filler per chunk (keep the Story-1.4 property: cross-chunk misdelivery/reorder cannot decode silently as the right chunk). Stay SPEC §5-valid (`orpPivot < wordLen`, `wordLen` 1–255). → `_recordsForBytes` tiles to EXACTLY the target (6–260 B records, no remainder stranding); `_fillerWord` rotates ASCII by a per-send seed; orpPivot 0 on ASCII lead bytes.
  - [x] **Sweep schedule:** start ≤1 KB … geometric … M sends … first rejection → re-test once → stop … hard max. → geometric-coarse (×2 from 768 B floor) then **bisect** the last-good→first-fail gap; M default 3, all must ack to step up; first rejection re-tested once; hard cap default 20 KB.
  - [x] **Per-step outcome classification** (the deferred evidence-sharpening) … `{ack, sizeError, genericError, silentTimeout, successNoAckTimeout}` … record whether the send future completed … size-class codes case-insensitive. → `SweepSendOutcome` + `SweepStep{targetBytes,binaryBytes,wireBytes,sendIndex,outcome,futureCompleted,isRetest,codeVerbatim}`; `_isSizeError` matches `TOO_LARGE`/`-102` case-insensitively; `_classify` → α/β/(c)/generic.
  - [x] **Cancel seam (deferred-work item #1, now required):** `cancel()` API … cooperative … partial well-formed summary. → `GateV2Runner.cancel()` checked at each step/attempt boundary in both `run` and `runSweep`; wedged-native-send limit documented; partial `GateV2Summary`/`GateV3SweepSummary` (`cancelled` flag) returned, no throw.
  - [x] **Transport = base64-String only** (ADR 0002) … record both binary and base64-wire size. → sweep forces `base64String`; `SweepStep` carries both; `_wireBytesFor` computes wire for non-sent sizes (safe-working).
  - [x] Extend with `GateV3SweepSummary`: `lastGoodBytes`/`firstFailBytes` (binary+wire), `rejectionClass`, `rejectionCode`, `safeWorkingBytes` (last-good − margin), `safeWorkingWords`, `perStep`, `transcript()`. `GateV2Summary` fields intact (one optional `cancelled` field added, default false).
  - [x] Tests in `companion/test/gate_v2/gate_v2_runner_test.dart`: `FakeBridge.bySize` scripts a size-keyed `TOO_LARGE` (β & α), size-keyed hang (transient-noise & reproduced-(c)), `successNoAck`-reproduced (β); `cancel()` mid-sweep → partial, no throw; size generation exact + SPEC §5-valid; geometric schedule; single-shot guard; existing Story-1.4 fixed-N tests stay green. `flutter analyze` clean; protocol conformance green. **(companion: 77/77, analyze clean.)**

- [x] Task 2: Sweep controls + Stop button in the harness screen (companion) (AC: 1)
  - [x] Extend `companion/lib/gate_v2/gate_v2_screen.dart`: **mode toggle** (V2 reliability | V3 size sweep), sweep params (start size, max, M — defaults 768/20000/3 pre-filled), live readout (phase, current size binary+wire, last-good, sends/acks, last outcome+code), **Stop button** wired to `runner.cancel()` (visible while running). Summary view stays selectable/transcribable. `flutter run` over USB keeps the phone awake (no wakelock dep).
  - [x] `GarminSpikeBridge` reused unchanged; `initialize()` keeps its 10 s timeout guard; no new pubspec deps.
  - [x] Updated `companion/test/widget_test.dart`: asserts the new title + mode-toggle segments + Stop absent at rest; still pumps without platform channels. **(widget test green.)**

- [x] Task 3: Watch side — accept and report larger chunks without crashing (companion + watch) (AC: 1)
  - [x] Confirmed the watch receive path survives multi-KB payloads with no fixed-size assumption: `arrayToByteArray` → `new [arr.size()]b`, `isPlausibleBase64` full scan, `base64ToByteArray`/`StreamDecoder.decodeChunk` bounds-checked + dynamic alloc, broad-catch receive guard intact (records evidence, never crashes). No buffer/loop caps a larger chunk.
  - [x] Added the **max-decoded-size witness**: `ProcessResult.bytesLen` (set to `bytes.size()` on success), `PaceTurnerApp._maxDecoded` (bounded counter, reset with the rest), `GateV2.maxDecodedLine` shown on the view, and `md:` field in `GateV2.evidenceString`. Bounded — no growing log (AR25).
  - [x] Two-press reset + generation-tagged acks from Story 1.4 kept; `_maxDecoded` resets with the generation bump.
  - [x] Extended `watch/source-test/GateV2Test.mc`: a large (8160 B / 32×250) well-formed base64 fixture round-trips through `processMessage` with `bytesLen` witnessed (`largeChunk` built byte-exact so `convertEncodedString` never sees malformed input); `maxDecodedLine` + `evidenceString` (new signature) pure-tested; bytesLen asserted on the existing String round-trip. All three targets build Strict `-l 3` clean (normal, `-r`, `-t`).
  - [x] Ran the suite in the exact CI image (`ghcr.io/matco/connectiq-tester:latest`, SDK 8.4.0, `fenix847mm`): **21/21 PASS** (incl. `gateV2MaxDecodedLineTest`, `gateV2LargeChunkWitnessTest` — the 8160 B chunk round-trips, no 8.4.0 decode surprise). Protocol baseline green.

- [x] Task 4: Hardware sweep, record V3, wire the calibrated size forward (AC: 1, 2) — **human-in-the-loop (Nerya held the phone, 2026-06-13)**
  - [x] Prerequisites met: Samsung SM-S938B / Android 16, GCM paired to Fenix 8 47 mm (fw 22.35, API 6.0.2); watch sideloaded via MTP (`gio copy`, unplug); companion via `flutter run`; watch app foregrounded; **wireless**.
  - [x] Ran the size sweep (base64 transport). **last-good 12 096 B binary / 16 128 B wire; first-fail 12 288 B binary / 16 384 B wire; rejection class α (phone serializer cap), code `[FAILURE_MESSAGE_TOO_LARGE]`** (first-fail wire = exactly the 16 384 B SDK cap). β BLE cap is **above** α: watch received+acked a 12 288 B chunk (witness `rcv:12288B`, R/V/A 29/29/29). (c) not observed.
  - [x] **Safe working chunk size = 11 584 B binary / 15 448 B wire** (last-good − 512 B margin: BLE variance + envelope-overhead headroom) ≈ **~1 158 words/chunk** at ~10 B/word — Epic 4's 200–500-word chunker has large headroom.
  - [x] Updated `docs/gates.md`: V3 row flipped to **passed**; §V3 expanded with procedure, the two-run watchdog history, measured table, codes verbatim, watch witness, verdict matrix (observed row bold), and the two Epic-4 constraints (transport ≤11 584 B; decode incrementally).
  - [x] Course-correction recorded: the **watch decode-watchdog** is the tighter real constraint (first sweep crashed the watch on synchronous full-chunk decode — uncatchable `Watchdog Tripped`, AR15 vindicated; simulator can't see it). Watch changed to **lighten-receive** (ack-on-receipt, no in-callback decode) to measure the transport ceiling; Epic 4 must decode incrementally (CIQ has no threads → timer-slice; community-confirmed). Not a premise-rework flag — V2 passed; V3 is calibration and AC1's safe working size is recorded.
  - [x] Updated sprint-status: `1-5-gate-v3-chunk-size-calibration-hardware` → review (code-review flips it to done).

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

claude-opus-4-8[1m] (Opus 4.8)

### Implementation Plan

One harness, two modes (no parallel `gate_v3/`). Extended `GateV2Runner` with
`runSweep()` + `cancel()` beside the untouched fixed-N `run()`; added the V3
evidence types (`SweepSendOutcome`, `RejectionClass`, `SweepStep`,
`GateV3SweepProgress`, `GateV3SweepSummary`). Sweep = geometric-coarse →
bisect, M sends/size, re-test once to separate a reproducible size ceiling from
the mode-a silent hang. Screen gained a mode toggle, sweep params, live readout,
and a Stop button wired to `cancel()`. Watch gained a max-decoded-size witness.
TDD against the existing `FakeBridge` (extended with size-keyed scripting).

### Debug Log References

- Pre-existing uncommitted work in the tree was **Story 1.4's code-review pass**
  (13 patches + 2 deferrals, status→done), never committed. Verified green
  (companion 69/69, analyze clean) and committed as `b252047` before starting
  1.5, so the 1.5 diff is clean. Story `baseline_commit` advanced e25aa33 →
  b252047 to match (the eventual 1.5 review diffs against the true start point).
- `unintended_html_in_doc_comment` on a `List<int>` in a test doc comment — wrapped in backticks.
- `unnecessary_brace_in_string_interps` on `${safeMarginBytes}` — removed braces.

### Completion Notes List

- **Tasks 1–2 complete & verified:** `flutter analyze` clean; `flutter test`
  **77/77** (19 prior runner + 9 new sweep + widget + protocol). Sweep tests
  cover: clean β ceiling (bisected), α phone-cap, transient-(c)-noise-continues,
  reproduced-(c), reproduced-SUCCESS-without-ack→β, cancel-mid-sweep, exact
  size generation + SPEC §5 validity, geometric schedule, single-shot guard.
- **Task 3 complete & verified:** watch witness added; all three targets build
  Strict `-l 3` clean (normal, `-r`, `-t`) on host SDK 9.1.0; **CI image (SDK
  8.4.0, `fenix847mm`) 21/21 PASS** — the 8160 B large-chunk fixture round-trips
  with no 8.4.0 decode surprise.
- **Task 4 (hardware) complete (Nerya, 2026-06-13, wireless, real Fenix 8 ↔ SM-S938B/Android 16):**
  - **last-good 12 096 B binary / 16 128 B wire; first-fail 12 288 B / 16 384 B; class α**
    (`[FAILURE_MESSAGE_TOO_LARGE]`, wire = exactly the 16 384 B SDK 2.0.3 cap). Bisected.
  - **Safe working chunk size 11 584 B binary / 15 448 B wire** (margin 512 B) ≈ **~1 158 words**.
  - Watch witness `rcv:12288B`, R/V/A 29/29/29 — watch received+acked a 12 288 B chunk the phone's
    serializer rejected ⇒ **β (BLE) > α (phone)**; α is the operative transport ceiling.
- **Course-correction (the load-bearing finding) — watch decode watchdog (AR15 vindicated):** the
  FIRST sweep attempt **crashed the watch app** — `Watchdog Tripped Error — Code Executed Too Long`
  in `StreamDecoder.decodeChunk`/`isValidUtf8` (device `CIQ_LOG.YML`). Synchronous full-chunk decode
  in the BLE receive callback exceeds the firmware watchdog (per-callback instruction budget,
  device-varying, **absent in the simulator** → CI's 8 KB decode passed). The kill is **uncatchable**.
  Researched the CIQ community (Garmin forums): only fix is to **slice work across timer ticks** (no
  threads). Changed the watch to **lighten-receive** — O(1) structural validate + bounded-prefix
  integrity touch + received-size witness + ack, NO full decode in the callback — so the sweep finds
  the true *transport* ceiling and the watchdog is recorded as an Epic-4 constraint. `processMessage`
  (full decode) stays the host/CI integrity proof. **Two Epic-4 constraints:** transport ≤11 584 B
  binary; `ChunkedWordSource` must decode incrementally, never a whole chunk in the BLE callback.
- **Verification:** companion `flutter test` **77/77**, `flutter analyze` clean; watch Strict `-l 3`
  clean ×3 targets; **CI image (SDK 8.4.0, `fenix847mm`) 24/24** (3 new `receiveLight` tests).
- Both Story-1.4 deferred items resolved and pruned (struck through) in `deferred-work.md`.
- Scope held: no Epic 4 modules, no parallel `gate_v3/`, no SPEC change, no Run B re-sweep, no
  release hardening. Disposable spike files only.

### Hardware run checklist (Task 4 — Nerya)

Same prerequisites as Story 1.4 Task 3:
1. Android phone with **Garmin Connect Mobile installed and paired to the Fenix 8**; phone unlocked/awake, app foregrounded the whole run.
2. Sideload the **normal** watch build (crash symbols): `watch/bin/PaceTurner.prg` via MTP per `docs/setup.md` (USB Mode → MTP, `gio copy`, unplug). Foreground the GateV2 app.
3. Companion via `flutter run` over USB (keeps the phone awake; no wakelock).
4. In the harness: select **V3: size sweep**, leave defaults (start 768, max 20000, M 3), **Start run**. **WIRELESS only** (simulator/tethered misreports — AR15).
5. Watch the live readout: phase, current size (binary/wire), last-good, last outcome+code. The **Stop** button cancels cleanly if a send wedges.
6. When it converges (or stops at the cap), the summary panel shows the gates.md-ready transcript. Read the **watch** display for `max:<n>B` (the decoded-size witness) and note it.
7. Probe (c) deliberately: any timeout the sweep reports has already been re-tested once; if you see repeated silent timeouts at a size below a clean larger size, that's (c) noise, not the ceiling.

Then transcribe the summary + watch witness into `docs/gates.md` §V3 (fill the _TBD_ table + class + margin + words/chunk), bold the verdict-matrix row, fill the §V3 Result line, and flip sprint-status `1-5 → review`.

### File List

- `companion/lib/gate_v2/gate_v2_runner.dart` — sweep mode (`runSweep`) + `cancel()` + classified outcomes + V3 evidence types; bisect gated to non-destructive code rejections (`bisected`/`watchdogSuspect`/`rejectionOutcome`); `cancelled` on `GateV2Summary`
- `companion/lib/gate_v2/gate_v2_screen.dart` — V2/V3 mode toggle, sweep params, live readout, Stop button; `debugPrint`s the live steps + final transcript to the device log (machine-readable retrieval)
- `companion/test/gate_v2/gate_v2_runner_test.dart` — `FakeBridge.bySize` + size-keyed scripting; V3 sweep test group (bisect-vs-cliff, watchdogSuspect, α/β/c, cancel, exact size gen, single-shot)
- `companion/test/widget_test.dart` — updated for the new title + mode toggle + Stop-absent-at-rest
- `watch/source/GateV2View.mc` — **`receiveLight`** (lighten-receive: O(1) structural validate + `validateChunkEnvelopeLight` + `base64BinaryLen` + `headDecodes` bounded-prefix integrity); `ProcessResult.bytesLen`; witness renamed `maxReceivedLine`/`rcv:`; `evidenceString` `rcv:` field; witness drawn on the view. `processMessage` (full decode) retained for host/CI integrity proof
- `watch/source/PaceTurnerApp.mc` — `onPhoneMessage` uses `receiveLight`; `_maxReceived` witness counter (tracked, reset, exposed as `maxReceived()`)
- `watch/source-test/GateV2Test.mc` — `largeChunk`/`largeEnvelope` fixtures; `processMessage` large-chunk integrity test; **`receiveLight` test group** (large-chunk accept, size accounting, structural + head-integrity rejections); `maxReceivedLine` + `rcv:` `evidenceString` tests
- `docs/gates.md` — §V3 **passed**: procedure, two-run watchdog history, measured table (α cap), watch witness, verdict matrix (observed row bold), two Epic-4 constraints; V3 status row
- `_bmad-output/implementation-artifacts/deferred-work.md` — the two Story-1.4 items marked RESOLVED
- `_bmad-output/implementation-artifacts/1-5-gate-v3-chunk-size-calibration-hardware.md` — this story (tasks, Dev Agent Record)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — `1-5 → review`

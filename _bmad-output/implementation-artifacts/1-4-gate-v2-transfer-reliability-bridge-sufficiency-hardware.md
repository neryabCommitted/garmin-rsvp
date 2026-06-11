---
baseline_commit: 7f274d88758af0986024c610e1501a7cfd7575ba
---

# Story 1.4: Gate V2 — transfer reliability & bridge sufficiency (hardware)

Status: review

## Story

As a developer,
I want to prove reliable repeated phone→watch sends on real hardware and decide whether the community bridge suffices,
So that the delivery epic's protocol design (FR20) is validated and OQ2 is resolved before it hardens.

## Acceptance Criteria

1. **Given** a spike using the managed Communications API over `watch_connectivity_garmin`
   **When** the phone sends many chunks in sequence to the Fenix 8
   **Then** the documented "first-send-works-then-fails" Android bug is either not observed or is defeated by the timeout → SDK re-init → resend defense
   **And** a measured success rate is recorded.

2. **Given** the spike results
   **When** bridge sufficiency is assessed
   **Then** OQ2 is resolved with a decision (keep `watch_connectivity_garmin` vs build a custom MethodChannel bridge) recorded in `docs/decisions/`.

3. **Given** the run
   **When** it completes
   **Then** `docs/gates.md` records V2 status, method, success rate, and the bridge decision.

> Success definition for AC1: a send counts as **success only when the watch's ack arrives back on the phone** within the timeout — end-to-end, not the SDK's `SUCCESS` callback. Research shows `SUCCESS` can be reported alongside failure and the listener can silently never fire (see Dev Notes → The bug, precisely). The "measured success rate" is ack-confirmed first-try rate + retry-recovered rate + defense-activation count.

## Tasks / Subtasks

- [x] Task 1: Phone-side spike — send harness in the companion (AC: 1)
  - [x] Add `watch_connectivity_garmin: ^0.1.13` to `companion/pubspec.yaml`. No other new deps. (Plugin pins Garmin Android SDK 2.0.3 internally — see Dev Notes → Bridge reality before designing payloads.)
  - [x] `companion/lib/gate_v2/gate_v2_runner.dart` — pure-logic spike engine, **no Flutter imports** (architecture: pure logic constructible without UI). Owns: chunk plan (N sequential `chunkData` envelopes, offset-addressed `off += n`, fixed fingerprint), one-in-flight serialization (the plugin does NOT queue — concurrent sends run on parallel threads), per-send timeout wrapper (the Dart future can hang FOREVER on the known bug — every send goes through `.timeout()`, 10 s), retry-same-chunk on timeout/`PlatformException` (idempotent per FR20), and the V2 defense: after K=3 consecutive failures, request bridge re-init then resend. Abstract the bridge behind a minimal interface (e.g. `abstract class SpikeBridge { Future<void> send(Map<String, Object?> msg); Future<void> reinit(); Stream<Map<String, dynamic>> get messages; }`) so the runner is testable with a fake.
  - [x] Stats accounting in the runner: per-chunk outcome (first-try ack / retried-then-acked / failed-after-defense), timeout count, `PlatformException` codes seen verbatim (they look like `"[FAILURE_DURING_TRANSFER]"`), re-init activations and whether each recovered, wall-clock per send. Expose a results summary object — this becomes the gates.md evidence.
  - [x] `companion/lib/gate_v2/gate_v2_screen.dart` + wire `main.dart` to it (replace the Flutter demo counter app) — live counters (sent/acked/retries/defense activations/last error), payload-encoding toggle (Run A: base64 String, Run B: `List<int>` — see Dev Notes → Payload encoding), N selector (default 200), start button, and a final summary view that can be transcribed. Keep the phone screen on during a run (`flutter run` keeps the device awake via USB debug; no wakelock dep needed).
  - [x] Build payloads with the existing codec — `encodeChunk` from `companion/lib/protocol/stream_codec.dart` (~100 filler `WordRecord`s ≈ 900 B binary; stay ≤1 KB conservative — AR29 says calibration is V3/Story 1.5, NOT here) and `chunkDataEnvelope` from `envelope_codec.dart`, then transcode `p` for transport per the run's encoding. Do not inline protocol strings — `protocol_keys.dart` constants only.
  - [x] Tests in `companion/test/gate_v2/gate_v2_runner_test.dart` (mirrors `lib/` path): fake bridge driving the runner through — all-success run; silent-hang (future never completes) → timeout → retry → ack; K consecutive timeouts → reinit called exactly once → resend succeeds; `PlatformException` → retry; stats summary correct in each. `flutter analyze` clean under the strict options; existing protocol conformance tests stay green.
- [x] Task 2: Watch-side spike — receive, validate, ack (AC: 1)
  - [x] Add `<iq:uses-permission id="Communications"/>` to `watch/manifest.xml`. Do NOT touch `minApiLevel` (stays 5.2.0 — decision 0001; everything used here is ≤1.4.0: `registerForPhoneAppMessages` 1.4.0, `transmit` 1.0.0). The `Fit` permission and V1 session code are retired with the V1 spike (subtask below).
  - [x] Replace the V1 spike as the scaffold's resident spike (per Story 1.3 Dev Notes — git preserves): delete `GateV1View.mc`, `GateV1Delegate.mc`, `source-test/GateV1Test.mc`; strip session lifecycle/evidence-log/backlight code from `PaceTurnerApp.mc`. New `watch/source/GateV2View.mc` + `GateV2Delegate.mc`; `getInitialView()` returns them.
  - [x] Receive path: `Communications.registerForPhoneAppMessages(method(:onPhoneMessage))` registered at app/view start. Per message: `Protocol.validateEnvelope()` (existing, `watch/source/Protocol.mc`) → transcode `p` back to `ByteArray` per its runtime type (String → base64-decode via `StringUtil.convertEncodedString`; Array → manual byte loop) → `StreamDecoder.decodeChunk(payload, n)` (existing) → count valid/invalid. **Wrap Storage writes and decode work in try/catch — the deferred-work.md V1 robustness list applies here: this spike's receive callback must not crash the run it is recording** (guard `Storage.setValue`, catch broadly in the system callback, bound any in-memory log).
  - [x] Ack path: on each validated chunk, `Communications.transmit(ackDict, null, listener)` where `ackDict` is a **Dictionary** (the plugin's `messageStream` does `Map.from(e)` — a bare value from the watch throws in its stream mapper). Spike-local ack shape (named consts in the spike file, e.g. `{"ack" => off, "ok" => true}`) — this is NOT protocol; **do not add an ack type to SPEC.md** (spec changes are out of scope; the five types are fixed in v1).
  - [x] `GateV2View` renders live: received / valid / acked counts, last error code, current payload-encoding seen (String/Array). Reuse the V1 view's structural pattern (1 s `Timer.Timer` + `WatchUi.requestUpdate()`, Ink `#EAE6DF` on Void `#000000`, small lit-pixel area).
  - [x] Extract pure helpers (e.g. array→ByteArray transcode, counter formatting) into a `(:test)`-covered module in `watch/source-test/GateV2Test.mc` (Story 1.2/1.3 pattern). **Never feed malformed input to `StringUtil.convertEncodedString` in tests** — it raises an uncatchable system error on SDK 8.4.0 (the CI image); test the base64 path with well-formed fixtures only.
  - [x] Verify all three local targets green at Strict `-l 3` (normal, `-r`, `-t`), then run the suite in the exact CI image (`ghcr.io/matco/connectiq-tester:latest`, SDK 8.4.0, `fenix847mm`) before pushing. The 7 protocol tests must stay green (GateV1's 3 tests go away with its files).
- [x] Task 3: Hardware run — many sequential sends, both encodings (AC: 1) — **human-in-the-loop**
  - [x] Prerequisites checklist for Nerya: Android phone with **Garmin Connect Mobile installed and paired to the Fenix 8** (the SDK proxies everything through GCM — nothing works without it); watch app sideloaded per `docs/setup.md` (USB Mode → MTP, `gio copy`, unplug); companion on the phone via `flutter run` (debug build is fine — ProGuard keeps only matter for release, see Dev Notes); watch app open in the foreground for the whole run; phone unlocked/awake.
  - [x] **WIRELESS mode on real hardware only** — do not assess reliability in the simulator/tethered: the plugin's pinned SDK 2.0.3 has a known tethered/ADB bug (`SUCCESS` immediately followed by `FAILURE_UNKNOWN`, fixed upstream in 2.2.0) that would pollute the measurement. The simulator misreports this whole area (AR15 spirit).
  - [x] Run A: N=200 sequential chunkData sends, payload as base64 String. Run B: N=200, payload as `List<int>`. Record per run: ack-confirmed first-try rate, retry-recovered count, timeout count, exception codes verbatim, defense activations and whether re-init + resend recovered, total wall-clock (gives effective throughput — research baseline expects <1 KB/s, 1–2 s round trips).
  - [x] Specifically probe the first-send bug signature: if a send's future hangs (no callback, no error) — that IS the documented bug; record at which send index it appears and whether the timeout → re-init → resend defense deterministically recovers. If the plugin's `initialize()` re-call does NOT recover (it never calls SDK `shutdown()` — the forum-documented workaround is shutdown+initialize, which the plugin cannot do), that is decisive OQ2 evidence — record it, stop the run, and proceed to Task 4 with the "insufficient" verdict path.
  - [x] Free bonus evidence (record, not gate-blocking): watch→phone ack reliability over the run (Epic 4 position-sync channel), and any `FAILURE_MESSAGE_TOO_LARGE`/`BLE_REQUEST_TOO_LARGE (-102)` sighting at ~1 KB (V3 input, Story 1.5 owns the sweep).
- [x] Task 4: Resolve OQ2 and record the verdict (AC: 2, 3)
  - [x] Write `docs/decisions/0002-oq2-companion-bridge.md` in the 0001 format (Status/Date/Context/Decision/Consequences). Decide between the three options using the pinned criteria (Dev Notes → OQ2 decision framework): **keep stock plugin** / **fork it and bump the one gradle line to SDK 2.4.0** (gains native byte-array payloads + the tethered fix) / **custom MethodChannel bridge** over `com.garmin.connectiq:ciq-companion-app-sdk:2.4.0@aar`. Either answer is acceptable; it shifts effort, not requirements (OQ2 verbatim).
  - [x] Update `docs/gates.md`: V2 table row + expand §V2 — status, method (plugin version, SDK pin, encoding runs, N, defense design), measured success rates per run, bug observed/not + defense outcome, the bridge decision with a pointer to the ADR, and the Epic 4 implication (TransferEngine inherits the validated defense pattern in ONE place — architecture §Process Patterns; ProtocolClient/ciq_bridge build on the decided transport).
  - [x] Record the verdict against the matrix (Dev Notes → Outcome → verdict matrix). If transfers are unrecoverable even at SDK level, raise the premise-rework flag for Epic 4 explicitly in gates.md.
  - [x] Update sprint-status: `1-4-gate-v2-transfer-reliability-bridge-sufficiency-hardware` → review (code-review flips it to done).

## Dev Notes

### Scope discipline (prevent creep)

This story is **a disposable hardware spike + a measured verdict + one ADR**. Explicitly NOT here:
- No `companion/lib/data/ciq_bridge.dart`, no `transfer_engine.dart`, no `foreground_session.dart` — those are Epic 4 modules; this gate decides what transport they sit on. Spike code lives in `companion/lib/gate_v2/` and is disposable.
- No `watch/source/sync/ProtocolClient.mc`, no `ChunkedWordSource.mc`, no `StorageKeys.mc` — Epic 4. The watch spike validates+counts; it does not store chapters.
- No SPEC.md changes — no ack message type, no transport-encoding section. The spike's ack is spike-local. If the run produces protocol-relevant findings (e.g. transport can't carry binary), they go in the ADR/gates.md and the SPEC question is taken up by Epic 4 with correct-course if needed.
- No chunk-size sweep — that's V3 (Story 1.5), which reuses this harness. Keep payloads ≤1 KB.
- No foreground service, no wakelock plugin, no release-build hardening (ProGuard keeps) — note them forward, don't build them.
- One pubspec dep + one manifest permission are the only config changes. Strict-clean and CI-green is the bar, not gold-plating (Story 1.3 precedent).

### Bridge reality (web research 2026-06-11 — read before writing any send code)

- `watch_connectivity_garmin` latest is **0.1.13 (2026-06-08)**, actively published (rexios.dev) but the maintainer has stated he no longer has a Garmin app to test with. Android internals: **pins `com.garmin.connectiq:ciq-companion-app-sdk:2.0.3@aar` (Aug 2023)**; current upstream is 2.4.0 (2026-03-25). The changelog's "ConnectIQ 1.7.0" line refers to the iOS xcframework, not Android.
- **SDK 2.0.3 cannot serialize byte arrays.** `MonkeyType.fromJava` handles only Number/String/Char/Boolean/List/Map/null; a `Uint8List` (arrives native-side as `byte[]`) throws in the serializer → `FAILURE_INVALID_FORMAT`. Byte arrays (`MonkeyByteArray`) only exist in SDK 2.4.0. Hence the two-encoding experiment (below) and the fork option in OQ2.
- **Send semantics (verified from plugin source):** each Dart `sendMessage` spawns a thread, calls `ConnectIQ.sendMessage` for every connected device, and blocks on a `CountDownLatch` until the per-device listener fires. Non-`SUCCESS` → the future errors with a `PlatformException` whose code is the status-list string (e.g. `"[FAILURE_DURING_TRANSFER]"`). **If the listener never fires, the future hangs forever** — no plugin-side timeout exists. No queueing, no retry: the runner must serialize and timeout-wrap everything itself.
- `initialize(GarminInitializationOptions(applicationId: ..., urlScheme: ...))` — `applicationId` is the watch app's id from `watch/manifest.xml`: `dd7ace3fb3f44551bce0cd350896426f`. `urlScheme` is required but iOS-only; pass a placeholder. `connectType` defaults to wireless (correct). The plugin exposes `initialize()` but **never calls SDK `shutdown()`** (only on engine detach) — whether re-`initialize()` actually recovers a wedged session is exactly what Task 3 measures.
- `messageStream` applies `Map<String, dynamic>.from(e)` to every inbound event — watch acks MUST be Dictionaries. `isReachable` does a blocking `getApplicationInfo` round-trip per connected device — fine as a pre-run check, don't poll it mid-run.
- **Release builds strip Garmin classes** without `-keep class com.garmin.** { *; }` (plugin issue #19, not shipped in the plugin). The spike runs debug so this doesn't bite now — record it as an Epic 4/5 landmine in the ADR's consequences.
- Hard cap discovered in SDK bytecode (2.0.3→2.4.0): serialized payload >16384 bytes → `FAILURE_MESSAGE_TOO_LARGE` phone-side, before BLE. The watch-side ceiling (`BLE_REQUEST_TOO_LARGE` -102) may be lower and is V3's question.

### The bug, precisely (three documented failure modes — know which one you hit)

| Mode | Where | Signature | Status |
|---|---|---|---|
| (a) Silent no-callback after first transfer | **WIRELESS, real device** — the AC1 target | First send works; subsequent sends: listener never fires, no exception, nothing arrives. Through the plugin: the Dart future hangs | Garmin bug report "Acknowledged"; no verified fix in any SDK |
| (b) `SUCCESS` then `FAILURE_UNKNOWN` for the same send | Tethered/ADB (simulator) only | Both callbacks fire | Real in 2.0.3 (the plugin's pin), fixed upstream in 2.2.0 — why Task 3 forbids simulator measurement |
| (c) Sporadic `FAILURE_DURING_TRANSFER` | Wireless | Internal `IQDevice cannot be cast to java.lang.Long` ClassCastException; sends sometimes succeed despite the logged error | Long-standing; mitigations: retry, ProGuard keeps |

Defense (synthesis of forum guidance + architecture line): serialize sends (one in flight), 10 s timeout per send, treat timeout/(c)-codes as retryable with the same idempotent chunk, after 3 consecutive failures re-init the bridge and resend, and **trust only the watch's ack** as success. Epic 4's `TransferEngine` inherits whatever this spike proves, in one place — not scattered per call site (architecture §Process Patterns).

### Payload encoding (the OQ2 sub-question the spike must answer empirically)

The protocol's `chunkData.p` is binary (SPEC §5), but the stock bridge can't carry bytes (SDK 2.0.3, above). The spike runs both workable transports and measures them:
- **Run A — base64 String:** ~33% size inflation; watch decodes via `StringUtil.convertEncodedString` (`REPRESENTATION_STRING_BASE64` → ByteArray). Landmine (Story 1.2 lesson): that function raises an **uncatchable system error on malformed input on SDK 8.4.0** — safe on-device for self-generated well-formed payloads, but CI tests must never feed it garbage.
- **Run B — `List<int>`:** survives the trip as a Monkey C `Array` of `Number`s; watch transcodes to `ByteArray` with a bounds-checked loop. Heavier SDK serialization per element; the run measures whether that matters at ~900 B.
Either transport is a wire-level wrapper around an unchanged SPEC §5 payload — `StreamDecoder.decodeChunk` consumes the reconstructed `ByteArray` unchanged on the watch, proving end-to-end integrity. The third path — native bytes — requires forking the plugin (one gradle line: 2.0.3 → 2.4.0) or a custom bridge; the ADR weighs measured A/B overhead against that fork.

### OQ2 decision framework (pin in the ADR)

Criteria: (1) measured reliability with the defense (mode-(a) recoverable through plugin re-init or not — the decisive one); (2) payload carriage (A/B overhead acceptable vs fork-for-bytes); (3) failure signaling sufficiency (timeout-wrapped futures workable for Epic 4's TransferEngine); (4) maintenance posture (maintainer without Garmin hardware, SDK pin 3 releases behind, no ProGuard keeps shipped). Options: **keep stock** / **fork + bump to SDK 2.4.0** (cheapest middle path — plugin Kotlin compiles against the same API) / **custom MethodChannel bridge** (`com.garmin.connectiq:ciq-companion-app-sdk:2.4.0@aar` from mavenCentral; core calls `getInstance → initialize → registerForAppEvents → sendMessage → shutdown`; requires GCM installed regardless). OQ2 verbatim: "Either answer is acceptable; it shifts effort, not requirements."

### Outcome → verdict matrix (pin this in gates.md)

| Observed | Verdict | Consequence |
|---|---|---|
| High first-try ack rate, bug not observed (or rare + retry-recovered), defense unneeded or works | **V2 passed** — keep bridge (fork only if bytes-over-the-wire wins on measured overhead) | Epic 4 hardens on `watch_connectivity_garmin`; TransferEngine embeds timeout+retry anyway (FR20 designs for failure) |
| Bug observed; timeout → re-init → resend recovers deterministically | **V2 passed-with-defense** | Defense is mandatory in TransferEngine, validated here; bridge keep/fork per criteria |
| Bug observed; plugin re-init does NOT recover (needs SDK `shutdown()` the plugin can't reach) | **V2 bridge-insufficient** — OQ2 = custom MethodChannel (or fork adding shutdown) | ADR records it; correct-course adds the bridge-build to Epic 4's first story; V2 reliability re-verified on the new bridge before transfer hardens |
| Sends unrecoverable even with full SDK-level re-init (BLE/GCM fundamentally broken on this pairing) | **Premise-rework flag** — raise explicitly in gates.md | Epic 4 must NOT harden; delivery premise needs rework (R2 worst case) |

### Run protocol (the dev agent cannot hold the phone)

Task 3 is a hardware run executed by Nerya (phone + watch on the table). The dev agent's job: deliver a sideloadable Strict-clean watch build and a runnable companion with the harness UI, the prerequisites checklist, and the observation checklist (per-run summary numbers, bug signature index, defense outcomes) — then transcribe results into `docs/gates.md`, the ADR, and this story's Dev Agent Record. Don't simulate or guess hardware outcomes; mode (b) makes simulator numbers actively misleading.

### Previous story intelligence (Stories 1.2/1.3 Dev Agent Records)

- **CI ceiling is real:** the tester image is SDK 8.4.0 / `fenix847mm` / API 5.2.0 cap. `registerForPhoneAppMessages` (1.4.0) and `transmit` (1.0.0) compile under it; verify in the exact image anyway — 1.2 found an SDK-8.4.0-only uncatchable-error landmine (`StringUtil.convertEncodedString`) that local builds never showed, and it is **directly on this story's Run-A path**.
- All three watch build targets at Strict `-l 3`; needing the level lowered is a defect (Enforcement Guideline #5). `monkey.jungle` already links `source-test/`; new files need no jungle edit.
- Watch suite baseline after this story: 7 protocol tests + new GateV2 helper tests (GateV1's 3 leave with its files). Don't touch `Protocol.mc`/`StreamDecoder.mc` — consume them.
- Strict-mode patterns from 1.3 that recur here: constructor-inject the app reference into view/delegate (no `Application.getApp()` casting); persist evidence as a compact String, not nested arrays (Storage value-type polys differ between SDK 8.4.0/9.1.0).
- The V1 robustness deferral list (`deferred-work.md`, 2026-06-11) was written for Epic 3 — but items 3 (unguarded `Storage.setValue` in a system callback), 5 (type-narrowed catches in handlers), and 6 (unbounded log growth) apply verbatim to this spike's receive callback: a crash mid-run destroys an hour of hardware evidence. Guard them; skip the rest (disposable spike).
- `envelope_codec.dart`'s `chunkData` check is `Uint8List`-exact (deferred-work item, 2026-06-10) — irrelevant to this spike (phone *builds* envelopes, doesn't decode chunk-bearing ones; acks are spike-local dicts). It stays deferred to Epic 4's ciq_bridge wiring.
- Sideload procedure verified end-to-end (`docs/setup.md`): USB Mode → MTP, `gio copy` to `GARMIN/Apps/`, unplug to install. Sideload the **normal** build (debug symbols for crash triage).

### Project Structure Notes

- New: `companion/lib/gate_v2/gate_v2_runner.dart`, `companion/lib/gate_v2/gate_v2_screen.dart`, `companion/test/gate_v2/gate_v2_runner_test.dart`, `watch/source/GateV2View.mc`, `watch/source/GateV2Delegate.mc`, `watch/source-test/GateV2Test.mc`, `docs/decisions/0002-oq2-companion-bridge.md`.
- Modified: `companion/pubspec.yaml` (one dep), `companion/lib/main.dart` (spike screen), `watch/manifest.xml` (Communications permission in, Fit out), `watch/source/PaceTurnerApp.mc` (V1 spike stripped, V2 initial view), `docs/gates.md`.
- Deleted: `watch/source/GateV1View.mc`, `watch/source/GateV1Delegate.mc`, `watch/source-test/GateV1Test.mc` (git preserves; V2 spike is the scaffold's resident spike now).
- These spike files are deliberately NOT the architecture tree's `sync/`/`services/transfer/`/`data/` modules — those are Epic 4 deliverables informed by this gate (gate outcome swaps a transport, not the architecture).
- Conventions: Dart `snake_case.dart`, tests mirror `lib/` paths; Monkey C `PascalCase.mc`, private `_camelCase`, module consts `UPPER_SNAKE`; protocol constants only via `protocol_keys.dart`/`Protocol.mc`, never inline (architecture §Communication Patterns); Monkey C logging budget — state transitions and errors only, never per-message prints in the hot path (~10 KB device log).

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.4] — story + ACs verbatim; AR28 (V2 blocks transfer-epic hardening, resolves OQ2), AR29 (V3 owns chunk-size), AR31 (gates.md single status page)
- [Source: _bmad-output/planning-artifacts/prds/prd.md#§5.D FR20, §7 R2, §8 OQ2] — idempotent offset-addressed protocol designed assuming this failure; R2 HIGH; OQ2 "either answer acceptable"
- [Source: _bmad-output/planning-artifacts/architecture.md#Process Patterns] — V2 defense (timeout → SDK re-init → resend) lives in ONE place; offset-addressed idempotent re-request; named error states, never silent retry loops
- [Source: _bmad-output/planning-artifacts/architecture.md#Project Structure] — Epic 4 module map this spike must NOT build early (`transfer_engine.dart`, `ciq_bridge.dart` swap seam, `ProtocolClient.mc`); ≤2 outstanding transfers flow-control target
- [Source: _bmad-output/planning-artifacts/architecture.md#Enforcement Guidelines] — managed Communications API only, `Raw.sendMessage()` forbidden; Strict/-l 3 discipline
- [Source: protocol/SPEC.md §3–§8] — envelope/required-key matrix, chunkData semantics, word-record layout, error codes; §1.1 platform note on ByteArray transport
- [Source: docs/gates.md#V2] — procedure row to expand; V1 section as the format precedent
- [Source: docs/decisions/0001-watch-min-api-level.md] — ADR format (Status/Date/Context/Decision/Consequences); minApiLevel 5.2.0 stands
- [Source: docs/setup.md] — build at Strict, CI-image test command, MTP sideload
- [Source: _bmad-output/implementation-artifacts/deferred-work.md] — V1 robustness list (items 3/5/6 bind this spike's callback); envelope `Uint8List`-exact edge (stays deferred)
- [Source: _bmad-output/implementation-artifacts/1-3-gate-v1-hands-off-screen-on-feasibility-hardware.md#Dev Agent Record] — spike-replacement license, Strict patterns, evidence-as-String, CI-image discipline
- Research (2026-06-11, agent-verified incl. bytecode disassembly of SDK 2.0.3/2.2.0/2.4.0 aars and the plugin's Kotlin/Dart source): pub.dev/packages/watch_connectivity_garmin (0.1.13, SDK pin 2.0.3); github.com/Rexios80/watch_connectivity issues #19/#8 (ProGuard strips); forums.garmin.com bug reports — "no transfer after first attempt" (Acknowledged, the AC1 bug), "SUCCESS and FAILURE_UNKNOWN" (tethered, fixed in SDK 2.2.0), "internal exception during sendMessage" (ClassCastException); developer.garmin.com Toybox.Communications api-docs (`registerForPhoneAppMessages` 1.4.0, `transmit` 1.0.0, error enums incl. `BLE_REQUEST_TOO_LARGE` -102); maven 16384-byte serialized cap (bytecode); github.com/garmin/connectiq-android-sdk (2.4.0, 2026-03-25, adds MonkeyByteArray)

## Dev Agent Record

### Agent Model Used

claude-fable-5 (Fable 5)

### Implementation Plan

- Runner success definition implemented exactly per AC1: an attempt succeeds only when the watch's `{ack, ok}` Dictionary arrives on `messageStream` within the 10 s timeout; the plugin future completing (SDK `SUCCESS`) is explicitly ignored (it is documented to lie). Verified by the `successNoAck` test case.
- Defense per chunk: attempts 1–3 fail → one `reinit()` → one final resend. Post-defense failure aborts the run — that outcome is decisive OQ2 evidence (verdict-matrix row 3), so pushing on would only pollute the measurement.
- `PlatformException` never reaches the runner (no Flutter imports allowed): `GarminSpikeBridge` in `gate_v2_screen.dart` translates it to `SpikeSendException(code)`, code preserved verbatim for stats.
- Watch-side ordering deviates from the task's arrow order by necessity: `Protocol.validateEnvelope` (unchanged, per story) only accepts a `ByteArray` payload for chunkData, so the spike transcodes `p` → ByteArray FIRST, then validates, then `StreamDecoder.decodeChunk`. Same validators, unmodified; transcode-first is the only satisfiable order.
- Run B transcode emits a plain growable `List<int>` — never `Uint8List`, which the pinned SDK 2.0.3 serializer rejects (`FAILURE_INVALID_FORMAT`). Pinned by test.
- Watch evidence persisted only in guarded `onStop` (compact String) — a mid-run `Storage.setValue` would add latency inside the receive callback and pollute the phone's round-trip timing.

### Debug Log References

- `flutter analyze`: No issues found. `flutter test`: 60/60 pass (10 new runner tests; protocol conformance green).
- `flutter build apk --debug`: success — Gradle resolves the plugin's pinned `ciq-companion-app-sdk:2.0.3` aar; Task 3's `flutter run` is not blocked.
- monkeyc Strict `-l 3`, fenix847mm, SDK 9.1.0: normal / `-r` / `-t` all clean. Two initial Strict findings fixed: untyped Dictionary read needs `as Lang.Object?` (Protocol.mc pattern); invariant generics require bare `as Array` casts at `arrayToByteArray` call sites.
- CI image `ghcr.io/matco/connectiq-tester:latest` (SDK 8.4.0, fenix847mm): 15/15 pass — 8 new GateV2 tests + 7 baseline (GateV1's 3 retired with its files). Invocation note: the image takes positional args (`docker run --rm -v $PWD/watch:/work -w /work ghcr.io/matco/connectiq-tester:latest fenix847mm`).

### Completion Notes List

- Task 1 ✅: `watch_connectivity_garmin 0.1.13` added (only new dep); plugin API surface verified against pub-cache source — `sendMessage(Map<String, dynamic>)`, broadcast `messageStream` with `Map.from`, `initialize(GarminInitializationOptions)`, `connectType` defaults wireless. Runner is pure Dart behind `SpikeBridge`; harness screen has encoding toggle (Run A/B), N selector (default 200), live counters, selectable end-of-run transcript.
- Task 2 ✅: V1 spike fully retired (files deleted, app stripped; git preserves). Manifest: `Fit` out, `Communications` in; minApiLevel untouched at 5.2.0. Receive callback broad-catch guarded, bounded counters only, ack as Dictionary via `Communications.transmit` with listener counting acked/ackErrors.
- Task 3 ✅ (executed by Nerya, 2026-06-11; wireless, real Fenix 8 47 mm ↔ Samsung SM-S938B / Android 16, GCM paired; watch sideloaded via MTP, normal build):
  - **Run A (base64 String, N=200): 200/200 first-try acks.** 0 timeouts, 0 exceptions, 0 re-inits. 178 490 ms total → ~892 ms/chunk, ~1.0 KB/s payload. Watch final: R:200 V:200 A:200.
  - **Run B (List<int>, N=200): 200/200 first-try acks.** 0 timeouts, 0 exceptions, 0 re-inits. 293 074 ms total → ~1465 ms/chunk, ~0.6 KB/s payload — element-wise serialization costs ~64% more wall-clock than base64's 33% inflation. Watch live counters zeroed by a mid-run START press (~chunk 72): display `R:128 V:128 A:129` covers the post-reset window (`A` leads `V` by one in-flight ack callback straddling the reset); phone-side ack accounting spans the full run and is the authoritative AC1 measure.
  - First-send bug (mode a) NOT observed in 400 consecutive wireless sends; defense never activated (re-init arm hardware-unproven — noted in ADR). No TOO_LARGE/-102 at ~1 KB. Watch→phone ack channel lossless both runs.
  - Run artifact: one aborted Run B attempt was an Android 16 app-freeze of the backgrounded debug companion (Dart timers fully stopped — even the 10 s timeouts can't fire), then the system killed the process ("Lost connection to device"). Not a transfer failure; recorded in gates.md/ADR as direct evidence for Epic 4's foreground-service requirement.
- Task 4 ✅: OQ2 resolved = **keep stock `watch_connectivity_garmin`, base64-String transport** — `docs/decisions/0002-oq2-companion-bridge.md` (0001 format; criteria-by-criteria; fork/custom-bridge as documented escape hatches). `docs/gates.md` V2 row + §V2 expanded (method, both runs' measurements, verdict matrix with observed row bold, Epic 4 implication). Verdict matrix row 1: **V2 passed**; premise-rework flag not raised. Sprint-status → review.

### File List

- companion/pubspec.yaml (modified — one dep: watch_connectivity_garmin ^0.1.13)
- companion/pubspec.lock (modified — resolution)
- companion/lib/gate_v2/gate_v2_runner.dart (new)
- companion/lib/gate_v2/gate_v2_screen.dart (new)
- companion/lib/main.dart (modified — boots GateV2Screen, demo app gone)
- companion/test/gate_v2/gate_v2_runner_test.dart (new)
- companion/test/widget_test.dart (modified — smoke test for the harness screen)
- watch/manifest.xml (modified — Communications in, Fit out)
- watch/source/PaceTurnerApp.mc (modified — V1 session spike stripped; V2 receive/ack/counters)
- watch/source/GateV2View.mc (new — GateV2 module helpers + view)
- watch/source/GateV2Delegate.mc (new)
- watch/source-test/GateV2Test.mc (new)
- watch/source/GateV1View.mc (deleted)
- watch/source/GateV1Delegate.mc (deleted)
- watch/source-test/GateV1Test.mc (deleted)
- docs/decisions/0002-oq2-companion-bridge.md (new — OQ2 ADR)
- docs/gates.md (modified — V2 row + §V2 evidence)

### Change Log

- 2026-06-11: Tasks 1–2 implemented TDD (companion 60/60, watch CI-image 15/15, analyze + Strict `-l 3` clean on all targets). Hardware run (Task 3) handed to Nerya.
- 2026-06-11: Task 3 hardware runs completed by Nerya (Run A 200/200 @ ~892 ms/chunk; Run B 200/200 @ ~1465 ms/chunk; bug not observed). Task 4: ADR 0002 (keep stock bridge, base64 transport), gates.md V2 **passed**, story → review.

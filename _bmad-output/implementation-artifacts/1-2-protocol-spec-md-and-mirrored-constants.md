---
baseline_commit: f8a807fcd635e9478be0f05fb6d254cb72cab15e
---

# Story 1.2: Protocol SPEC.md and mirrored constants

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer (and a future third-party implementer),
I want the phone↔watch protocol written down as the single source of truth with mirrored constants on both sides,
so that the transfer and gate-test work has a stable contract to build against (FR28).

## Acceptance Criteria

**AC1 — SPEC.md is the complete contract.**
**Given** `protocol/SPEC.md`
**When** I read it
**Then** it fully specifies the `{t, v, fp, off, n, p}` envelope, the five message types (`manifest`, `chunkRequest`, `chunkData`, `position`, `error`), the little-endian binary word-record layout (~9 B/word), the flag-bit positions (sentenceEnd, paragraphStart, chapterStart, reserved continuation + direction), fingerprint semantics, the versioning rule, and error semantics.

**AC2 — Mirrored constants, no inline literals.**
**Given** the spec
**When** I inspect `watch/source/Protocol.mc` and `companion/lib/protocol/protocol_keys.dart`
**Then** every message-type and field key is defined once per side as a named constant mirroring the spec
**And** no inline protocol string literals exist at call sites.

**AC3 — Round-trip conformance against worked examples.**
**Given** the spec's worked byte-level examples
**When** round-trip encode/decode tests run on both sides
**Then** each side reproduces the spec's example bytes exactly.

**AC4 — Unknown version is rejected, never guessed.**
**Given** an unknown protocol-version value
**When** either side decodes it
**Then** it is rejected and reported, never guessed.

## Tasks / Subtasks

- [x] **Task 1 — Author `protocol/SPEC.md` (AC1)**
  - [x] Replace the Story-1.1 placeholder at `protocol/SPEC.md` with the full contract. Use numbered sections (e.g. §1 Overview, §2 Versioning, §3 Envelope, §4 Message Types, §5 Binary Word-Record Layout, §6 Flag Bits, §7 Fingerprint, §8 Error Semantics, §9 Glossary) — implementation comments on both sides will cite these section numbers, so keep numbering stable.
  - [x] **Envelope (§3):** CIQ `Dictionary` with short string keys, exactly `{t, v, fp, off, n, p}` — `t`: message type (camelCase string), `v`: protocol version (integer), `fp`: content fingerprint, `off`: absolute word index (0-based integer), `n`: count, `p`: payload. Document which fields are required/null per message type. No other top-level fields — new fields require a spec edit + version bump.
  - [x] **Message types (§4):** exactly five — `manifest` (book meta, chapter index → absolute word index mapping, cumulative durations, fingerprint), `chunkRequest` (fp, off, n), `chunkData` (fp, off, n, binary payload), `position` (fp, off, timestamp epoch-seconds, source), `error` (code + context). Define each type's payload shape precisely. Define `position.source` values (e.g. `watch` / `phone`) and `error` codes as named values.
  - [x] **Binary word-record layout (§5):** little-endian, tightly concatenated records, ~9 B/word average. Suggested layout (finalize in spec; this is the starting point): `u8 wordLen` (UTF-8 byte length 1–255) · `u8 flags` · `u8 orpPivot` (0-based **byte** index into the UTF-8 word) · `u16le bonusMs` (WPM-invariant additive dwell bonus, ms) · `wordLen` bytes UTF-8 word. A `chunkData` payload of `n` records starts at absolute word index `off`.
  - [x] **Flag bits (§6):** assign bit positions for `sentenceEnd`, `paragraphStart`, `chapterStart`; reserve `continuation` (FR7 long-word split escape hatch) and direction bits (NFR7 RTL); remaining bits reserved-must-be-zero.
  - [x] **Fingerprint semantics (§7):** per-conversion content fingerprint; carried on every `chunkRequest`/`chunkData`/`position`; the watch treats it as an **opaque equality token** — compares, never parses. Define its concrete wire form now (see Dev Notes → fingerprint type trap). Computation algorithm is phone-side and lands in Story 2.2 — the spec defines form + semantics, and may mark the algorithm section as "defined by the reference companion" as long as the wire form is fixed.
  - [x] **Versioning rule (§2):** explicit `v` on every message starting at `1`; receiver rejects unknown `v` — reject + report, never guess (AC4). State the compatibility policy (same major = compatible, or v-exact-match for MVP — decide and write it down).
  - [x] **Error semantics (§8):** error message type + the rule that every failure surfaces as a named state, never a silent retry (per architecture); define decode-failure behavior (bounds-check-and-degrade, NFR8).
  - [x] **Glossary (§9):** absolute word index, content fingerprint, word stream, chapter-transition card (closes a named architecture gap).
  - [x] State the platform note: `p` as `ByteArray` over `Communications.transmit` requires CIQ API ≥6.0.0; protocol consumers must target API 6.0+ for transport (codec itself has no such floor).
  - [x] **Worked examples in `protocol/examples/`:** at least (a) a word-record sequence with exact hex bytes covering an ASCII word, a multi-byte UTF-8 word (e.g. Hebrew — proves the pivot is a *byte* index), a sentence-end flag, and a non-zero bonus; (b) one full envelope per message type as annotated JSON-ish text with the `chunkData` payload hex. These exact bytes are what both sides' tests pin against (AC3).

- [x] **Task 2 — Watch mirror: `Protocol.mc` constants + decode (AC2, AC4)**
  - [x] Create `watch/source/Protocol.mc`: a `Protocol` module of `UPPER_SNAKE` consts — `PROTOCOL_VERSION`, envelope keys (`KEY_TYPE = "t"` …), message-type strings (`MSG_MANIFEST = "manifest"` …), flag bit masks (`FLAG_SENTENCE_END` …), error codes. One definition per value; everything cites its SPEC.md section in a comment.
  - [x] Create `watch/source/source_data/StreamDecoder.mc`: pure word-record decode over `ByteArray` (no `Toybox.WatchUi`, no `Toybox.Communications` imports — host-testable). Bounds-check every read; truncated/malformed input returns a typed failure (null/error result), never throws past the boundary (NFR8). Comment each field read with its SPEC.md section.
  - [x] Add envelope validation in `Protocol.mc` (or a small `Envelope` helper there): given a received `Dictionary`, verify `v == PROTOCOL_VERSION` and `t` is a known type; unknown version → explicit rejection result that callers must surface (AC4). No transmit/receive wiring — that is Epic 4.
  - [x] Verify the watch build stays green at Strict (level 3) and at the CI image's API ceiling (see Dev Notes → CI constraints).

- [x] **Task 3 — Companion mirror: `protocol_keys.dart` + codecs (AC2, AC4)**
  - [x] Create `companion/lib/protocol/protocol_keys.dart`: the same constant set as `Protocol.mc` (class-scoped `static const`, `lowerCamelCase` or `kPascalCase`), each citing its SPEC.md section.
  - [x] Create `companion/lib/protocol/stream_codec.dart`: word-record **encode and decode** using `dart:typed_data` (`ByteData`, `Endian.little`) + `dart:convert` (`utf8`). Pure Dart — no Flutter imports (isolate-runnable, trivially testable).
  - [x] Create `companion/lib/protocol/envelope_codec.dart`: build/validate envelope maps for the five message types; decoding an unknown `v` throws/returns a **typed** protocol-version error (AC4); no silent fallback. Pure Dart.
  - [x] No new pub dependencies — `dart:typed_data` + `dart:convert` cover everything. `flutter analyze` stays clean under the strict `analysis_options.yaml`.

- [x] **Task 4 — Conformance tests pinned to the spec's example bytes (AC3, AC4)** *(write these red-first against the examples from Task 1)*
  - [x] `companion/test/protocol/stream_codec_test.dart`: encode the example word sequence → assert the **exact** hex bytes from `protocol/examples/`; decode those bytes → assert every field (word, pivot, bonus, flags). Round-trip equality. Truncated-input and reserved-bits cases degrade per spec.
  - [x] `companion/test/protocol/envelope_codec_test.dart`: build each message type → matches the spec example; decode with unknown `v` → typed rejection (AC4); missing required field → typed error.
  - [x] `watch/source-test/ProtocolTest.mc`: `(:test)` functions — decode the same example bytes (hard-coded `ByteArray` literal mirroring the spec hex) → assert every field; re-encode via a test-side helper (or assert field-exact equality) so the watch demonstrably reproduces the example; envelope with unknown `v` → rejected (AC4); constants spot-check (e.g. `Protocol.MSG_CHUNK_DATA` equals `"chunkData"`) so constant drift fails the build, not a code review.
  - [x] Run locally: `cd companion && flutter analyze && flutter test` green; watch unit-test build green via the Story-1.1 path (local `monkeyc -t` and/or the CI tester image — see `docs/setup.md`).

- [x] **Task 5 — Finalize (AC1–4)**
  - [x] Grep both codebases for inline protocol literals outside `Protocol.mc`/`protocol_keys.dart` (e.g. `grep -rn '"chunkData"\|"manifest"\|"chunkRequest"' watch/source companion/lib` — only the two constant files may hit). Test files may reference literals deliberately (drift detection).
  - [x] Confirm README's existing `protocol/SPEC.md` link still resolves; push and confirm both CI workflows green.

### Review Findings

- [x] [Review][Patch] (resolved Decision: implement now) Watch envelope validation implements only SPEC §3 steps 1–2 — implement step 3 on the watch (required-field matrix, field types, unknown-key rejection, §7 fp shape) so `ERR_MALFORMED_ENVELOPE`/`FINGERPRINT_LENGTH` go live and both sides reject the same wire bytes [watch/source/Protocol.mc:73-89]
- [x] [Review][Patch] (resolved Decision: encoder enforces) SPEC §5 orpPivot-on-UTF-8-boundary MUST — enforce in the Dart encoder (reject mid-sequence pivots); SPEC §5 explicitly states decoders do NOT validate this [protocol/SPEC.md:227; companion/lib/protocol/stream_codec.dart:78-83]
- [x] [Review][Patch] (resolved Decision: reject) Non-null values in unused envelope fields — SPEC states a non-null value in a "—" field is `malformedEnvelope`; enforce in Dart `decodeEnvelope` and watch `validateEnvelope` [protocol/SPEC.md:110-115; companion/lib/protocol/envelope_codec.dart:213-238]
- [x] [Review][Patch] Watch invalid-UTF-8 handling is dead code — `StringUtil.convertEncodedString` returns null on failure (doesn't throw), the `as String` cast silences it, and a null-word record escapes the "never throws past this boundary" boundary; the one §5 case the watch suite doesn't test [watch/source/source_data/StreamDecoder.mc:63-73]
- [x] [Review][Patch] `encodeChunk` misses `flags > 0xFF` — `0x107` passes the reserved-mask guard and `setUint8` silently truncates to `0x07` on the wire [companion/lib/protocol/stream_codec.dart:92,103]
- [x] [Review][Patch] `utf8.encode` silently replaces unpaired UTF-16 surrogates with U+FFFD — encode mutates the word, round-trip inequality with no error; reject non-well-formed strings [companion/lib/protocol/stream_codec.dart:70]
- [x] [Review][Patch] `decodeEnvelope` accepts `off < 0` and `n < 1` despite §4.2 "n MUST be ≥ 1"; spec is also ambiguous on which error code `n = 0` maps to (malformedEnvelope vs rangeUnavailable vs decodeFailure) — add envelope-layer range checks and pin the code in SPEC §8 [companion/lib/protocol/envelope_codec.dart:215-226]
- [x] [Review][Patch] Payload fields get presence checks only — `{'ts': 'noon', 'src': 42}` decodes as a valid `position`, and an empty `ch` array passes despite §4.1 "at least one entry"; check the kinds the spec tables declare [companion/lib/protocol/envelope_codec.dart:294-323]
- [x] [Review][Patch] Envelope builders perform no input validation (fp shape, off/n ranges, n-vs-payload record count) — asymmetric with `encodeChunk`'s ArgumentError contract [companion/lib/protocol/envelope_codec.dart:72-160]
- [x] [Review][Patch] `encodeChunk(const [])` silently produces a zero-record payload no conformant decoder can accept — throw, matching the decode-side `n ≥ 1` floor [companion/lib/protocol/stream_codec.dart:67-110]
- [x] [Review][Patch] "Round-trips every spec example envelope" test asserts only `type` and `version` — dropping `fingerprint`/`offset`/`count`/`payload` in decode would still pass [companion/test/protocol/envelope_codec_test.dart:325-362]
- [x] [Review][Patch] Reserved-bit tests on both sides use only `0x08` — bits 5–7 (0xE0) never exercised; a mask typo of `0x18` would pass every test [companion/test/protocol/stream_codec_test.dart:164-170; watch/source-test/ProtocolTest.mc:195-198]
- [x] [Review][Patch] Drift-detection tests omit the two numeric constants — neither side asserts `RECORD_HEADER_BYTES == 5` or `FINGERPRINT_LENGTH == 8` [watch/source-test/ProtocolTest.mc; companion/test/protocol/envelope_codec_test.dart]
- [x] [Review][Patch] SPEC §1.1 calls every envelope "a flat dictionary of primitive values" but manifest/position/error payloads are nested dictionaries; §3 says "exactly these six keys" two paragraphs before mandating unused keys be omitted — wording traps for a third-party implementer [protocol/SPEC.md:46-49,85-87,113-115]
- [x] [Review][Patch] Spec leaves `off`/`tw`/`tb`/`cb` integer widths unbounded while Monkey C `Number` is signed 32-bit (`tb` can legally exceed 2^31−1); watch also rejects a `Long` 1 as versionMismatch where Dart accepts any int width — bound envelope integers in §1.2 [protocol/SPEC.md §1.2; watch/source/Protocol.mc:74-77]
- [x] [Review][Patch] Story Task 1 is `[x]` while 10 of its 11 subtasks are `[ ]` — content demonstrably exists; tick the boxes [_bmad-output/implementation-artifacts/1-2-protocol-spec-md-and-mirrored-constants.md:42-53]
- [x] [Review][Patch] Dev Agent Record test split is wrong — claims "14 stream-codec, 21 envelope-codec"; actual 17/18 (total 36 coincidentally right) [_bmad-output/implementation-artifacts/1-2-protocol-spec-md-and-mirrored-constants.md:172]
- [x] [Review][Defer] `chunkData` payload check is `Uint8List`-exact — rejects byte-valued `List<int>`, the shape platform channels commonly deliver [companion/lib/protocol/envelope_codec.dart:280-286] — deferred, Epic 4 bridge concern (decide when wiring `ciq_bridge.dart`)

## Dev Notes

### Scope discipline (prevent creep)
This story is **spec + mirrored constants + codecs + conformance tests only**. Explicitly NOT here:
- No `Communications.transmit` / `registerForPhoneAppMessages` wiring, no `watch_connectivity_garmin` — gate stories 1.4/1.5 and Epic 4 (`ProtocolClient.mc`, `ciq_bridge.dart`).
- No fingerprint **computation**, no pacing/ORP computation — Story 2.2 (`fingerprint.dart`, `pacing.dart`, `orp.dart`). This story fixes only the wire form + semantics.
- No `ChunkedWordSource`, no Storage buckets — Story 4.1.
- No new pub/Toybox dependencies on either side.

### The spec is the deliverable; code serves it
FR28 makes `protocol/SPEC.md` a third-party-implementable public contract. Write it so someone who has never seen this repo could build a compatible companion. Every later protocol change starts in SPEC.md, in the same PR as the code (architecture Enforcement Guideline #4). Epic 5 (Story 5.2) only *polishes* it — the substance lands now.

### Architecture decisions that bind this story (architecture.md)
- **Envelope:** exactly `{t, v, fp, off, n, p}` — CIQ `Dictionary` + binary `ByteArray` payload. No ad-hoc fields ever; additions go through spec + version bump. [§API & Communication Patterns]
- **Message types:** `manifest`, `chunkRequest`, `chunkData`, `position`, `error` — camelCase strings. [§Naming Patterns]
- **Units table (absolute):** position = 0-based absolute word index, the only coordinate; sync timestamps = Unix epoch **seconds**, integer; durations/dwell = **milliseconds**, integer; fingerprint = opaque to the watch (equality only); ORP pivot = **byte index into the UTF-8 word**, precomputed by the phone — the watch never recomputes pivots. [§Format Patterns]
- **Binary layout authority:** SPEC.md is the single source of truth — byte order (little-endian), record layout, flag-bit assignments. Both implementations cite spec section numbers at encode/decode sites (greppable drift detection). [§Format Patterns]
- **Mirrored constants:** keys/types/version defined once per side — `Protocol` module (Monkey C), `ProtocolKeys` (Dart). Never inline a protocol string at a call site. [§Naming Patterns, AR8]
- **Word-record content (AR9):** UTF-8 word + ORP pivot byte index + dwell **bonus** metadata + flags (`sentenceEnd`, `paragraphStart`, `chapterStart`, reserved `continuation` + direction bits); ~9 B/word; debuggable JSONL master stays phone-side (Epic 2, not here).
- **Timing model (AR10):** the stream stores the per-word WPM-invariant additive bonus in ms; the watch applies `60000/wpm + bonusMs`. The record field is the bonus, never the total duration.
- **Versioning (AR7):** explicit `v` from message one; unknown → reject + report, never guess.
- **Error posture (AR24/NFR8):** decode failures bounds-check-and-degrade; no silent `catch {}`; failures surface as typed results the caller must handle.

### Fingerprint type trap (decide in SPEC.md, get it right once)
Monkey C `Number` is a **signed 32-bit** integer; an unsigned 32-bit hash can overflow it, and `Long` boxes to 64-bit. Pick a wire form that dodges this — sane options: (a) fingerprint as a fixed-length lowercase hex **string** (e.g. 8 chars = 32 bits) — string equality is cheap, no sign trap, debuggable in logs; or (b) signed 32-bit integer with the spec stating it is an opaque signed value. Recommendation: hex string. Whatever you choose, the spec states the watch compares for equality only. Timestamps in epoch seconds fit signed 32-bit until 2038 — fine for `Number`, but note it in the spec.

### Suggested word-record layout (starting point — finalize in SPEC.md §5)
| offset | size | field | notes |
|---|---|---|---|
| 0 | u8 | wordLen | UTF-8 byte length, 1–255 |
| 1 | u8 | flags | bit assignments per §6 |
| 2 | u8 | orpPivot | 0-based byte index, `< wordLen` |
| 3 | u16le | bonusMs | 0–65535 ms, WPM-invariant additive bonus |
| 5 | wordLen | word | UTF-8 bytes |

5 fixed + ~4–5 avg word bytes ≈ the addendum's ~9 B/word for English. A u16 bonus has ample headroom (Nano-derived bonuses cap well under 1 s). If you change this layout, change it in the spec; the tests pin whatever the spec says.

### Monkey C API map (verify exact signatures via `find-docs` before coding — medium confidence from research, not load-bearing until checked)
- `ByteArray.decodeNumber(format, {:offset, :endianness})` / `encodeNumber(value, format, {:offset, :endianness})` with `Lang.NUMBER_FORMAT_UINT8 / UINT16 / SINT32 …` and `Lang.ENDIAN_LITTLE` — present well below API 5.2.0, safe for the CI image.
- UTF-8 bytes ↔ String: `StringUtil.utf8ArrayToString(...)` / `StringUtil.convertEncodedString(...)` with byte-array representation options; `String.toUtf8Array()` exists (confirmed via current api-docs) for the reverse.
- `ByteArray` literals in tests: `[0x05, 0x01, ...]b`; `slice()` available for sub-ranges.
- Transmittable types over `Communications` include `ByteArray` **since API 6.0.0** plus Number/Float/Long/Double/String/Boolean/Char/Array/Dictionary nested arbitrarily [research: technical-connect-iq-phone-watch-communication, High confidence]. Codec code in this story must NOT require 6.0 — only the (future) transport does. State this in the spec; do not raise `minApiLevel` (see decision 0001).

### Previous story intelligence (Story 1.1 — read its Dev Agent Record)
- **CI ceiling:** the public tester image (`ghcr.io/matco/connectiq-tester:latest`) is hardcoded to **SDK 8.4.0**, device `fenix847mm`, which caps at **API 5.2.0**; manifest `minApiLevel` is deliberately 5.2.0 (`docs/decisions/0001-watch-min-api-level.md`). Anything you write this story must compile and run there — stick to old, stable Toybox APIs (the ByteArray/StringUtil ops above qualify).
- **Local build path (Ubuntu 24.04):** SDK 9.1.0 via Docker-downloaded SDK Manager; CLI `monkeyc` with local Temurin JDK 17; Strict `-l 3`; dev key at `~/.Garmin/developer_key.der`. Full commands in `docs/setup.md`. Validate the watch test build against the exact CI image (`tester.sh fenix847mm`) before pushing — Story 1.1 proved local-SDK green ≠ CI green.
- **Strict is non-negotiable:** all three build targets (normal, `-r` release, `-t` unit-test) passed at Strict in 1.1; a build needing the level lowered is a defect (Enforcement Guideline #5).
- **`monkey.jungle` already links `source-test/`** (`base.sourcePath = source;source-test`); jungle source paths scan recursively, so the new `source/source_data/` subdir needs no jungle edit — verify with a clean build anyway.
- **Real-watch sideload works** (commit f8a807f: USB Mode → MTP, `gio` copy per `docs/setup.md`) — not needed for this story (host-side tests suffice), available if you want to eyeball anything on hardware.
- **Companion test layout:** `companion/test/` currently holds only the scaffold `widget_test.dart`; this story adds `test/protocol/` mirroring `lib/protocol/` per the structure pattern.

### Cross-side mirror discipline (the silent killer this story exists to prevent)
The two constant files cannot import each other — the spec is their only sync mechanism. Make drift mechanically detectable:
1. Tests on **both** sides assert constant literal values (`MSG_CHUNK_DATA == "chunkData"`), not just constant-to-constant equality.
2. Both sides' round-trip tests pin the **same** example bytes from `protocol/examples/` — if one side drifts, its test fails against the shared fixture.
3. Every encode/decode site comments its SPEC.md section number — greppable.

### Testing standards
- Watch: `(:test)` functions in `watch/source-test/` (pattern: `SmokeTest.mc`), `logger.debug` for context, return `Boolean`; excluded from release builds; run headless by `action-connectiq-tester` in CI.
- Companion: `flutter_test` under `companion/test/` mirroring `lib/` paths; pure-Dart tests (no widget pumping needed for codecs).
- Red → green → refactor: write the conformance tests from the spec's example bytes *before* implementing the codecs; the examples are the fixture.
- Both CI workflows (`watch-ci.yml`, `companion-ci.yml`) must be green on push — a red run is a story defect.

### Project Structure Notes
- New files land exactly per architecture.md §Complete Project Directory Structure: `watch/source/Protocol.mc`, `watch/source/source_data/StreamDecoder.mc`, `watch/source-test/ProtocolTest.mc`, `companion/lib/protocol/{protocol_keys,envelope_codec,stream_codec}.dart`, `companion/test/protocol/*_test.dart`, `protocol/SPEC.md` + `protocol/examples/`.
- Do NOT create `sync/ProtocolClient.mc`, `source_data/ChunkedWordSource.mc`, `source_data/StorageKeys.mc`, or `companion/lib/data/ciq_bridge.dart` — they belong to Epic 4 stories.
- Monkey C: `PascalCase.mc`, one public class/module per file, module consts `UPPER_SNAKE`, private fields `_camelCase`. Dart: `snake_case.dart`, class-scoped constants.
- The architecture tree's `paceturner/` root = this repo's root (established in Story 1.1).

### References
- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.2: Protocol SPEC.md and mirrored constants]
- [Source: _bmad-output/planning-artifacts/epics.md#Additional Requirements] — AR6 (SPEC.md), AR7 (envelope + types + version), AR8 (mirrored constants), AR9 (word-stream format), AR10 (timing model)
- [Source: _bmad-output/planning-artifacts/architecture.md#API & Communication Patterns (Protocol)] — envelope, versioning, message types, error standard, protocol/ directory rule
- [Source: _bmad-output/planning-artifacts/architecture.md#Format Patterns] — units table, binary layout authority, envelope immutability
- [Source: _bmad-output/planning-artifacts/architecture.md#Naming Patterns] — protocol naming, cross-language conventions
- [Source: _bmad-output/planning-artifacts/architecture.md#Architectural Boundaries] — protocol boundary: both sides implement SPEC.md, never each other; conformance via round-trip tests against worked examples
- [Source: _bmad-output/planning-artifacts/architecture.md#Gap Analysis Results] — SPEC.md is implementation story #2, prerequisite to V2/V3 harnesses; glossary closes a named gap
- [Source: _bmad-output/planning-artifacts/prds/prd-garmin_RSVP-2026-06-06/addendum.md] — ~9 B/word packing, bake-the-bonus timing model, fingerprint à la Nano `sourceFingerprint`, RTL/NFR7 direction-bit reservation
- [Source: _bmad-output/planning-artifacts/research/technical-connect-iq-phone-watch-communication-research-2026-06-06.md] — TransmitType set incl. ByteArray since API 6.0.0 (High); -102 size ceiling context
- [Source: _bmad-output/implementation-artifacts/1-1-monorepo-dual-scaffolds-dev-key-green-ci.md#Dev Agent Record] — CI image SDK 8.4.0 / fenix847mm / API 5.2.0 cap; local build path; jungle test linkage
- [Source: docs/decisions/0001-watch-min-api-level.md] — minApiLevel 5.2.0 stands; revisit only when a 6.0-only API is first needed
- [Source: docs/setup.md] — exact local build/test/sideload commands

## Dev Agent Record

### Agent Model Used

claude-fable-5 (Amelia / dev)

### Debug Log References

- Watch red phase: `monkeyc -t -l 3` failed with `Undefined symbol ':Protocol'` / `':StreamDecoder'` before implementation — tests authored first against the spec fixture.
- Watch green: all three local targets (normal, `-r`, `-t`) `BUILD SUCCESSFUL` at Strict `-l 3` on SDK 9.1.0.
- Watch tests executed in the **exact CI image** (`ghcr.io/matco/connectiq-tester:latest`, SDK 8.4.0, `fenix847mm`): `PASSED (passed=6, failed=0, errors=0)` — proves the code holds at the API 5.2.0 ceiling, not just on the local SDK.
- Companion red phase: `flutter test test/protocol/` failed loading both test files before the lib files existed.
- Companion green: `flutter analyze` → "No issues found!"; `flutter test` → "All tests passed!" (pre-review suite: 36 tests — 17 stream-codec, 18 envelope-codec, 1 scaffold widget test; the original 14/21 split in this entry was a recording error caught in review).
- **Code-review fix pass (2026-06-10):** all 17 patch findings applied (3 from resolved decisions: watch §3 step-3 validation, encoder-enforced orpPivot UTF-8 boundary, reject non-null unused fields). Post-fix verification: watch 7/7 `PASSED` in the exact CI image; all three local targets `BUILD SUCCESSFUL` at Strict; companion analyze clean, 50/50 tests (21 stream-codec, 28 envelope-codec, 1 scaffold).
- **CI-image landmine found during the fix pass:** on SDK 8.4.0, `StringUtil.convertEncodedString` on malformed UTF-8 dies with an UNCATCHABLE system error ("Failed invoking <symbol>") — try/catch cannot contain it. `StreamDecoder` now validates UTF-8 structurally (RFC 3629 scan, incl. overlongs/surrogates) before any conversion; conversion only ever sees well-formed bytes.
- Literal-drift grep over `watch/source` + `companion/lib`: only `Protocol.mc` and `protocol_keys.dart` define protocol strings (single remaining grep hit is a Flutter scaffold comment in `main.dart`, not a protocol literal).
- Worked-example bytes were computed programmatically (Python struct/UTF-8) before being written into `protocol/examples/`, then independently reproduced by both sides' codecs.

### Completion Notes List

- **AC1:** `protocol/SPEC.md` rewritten as the full third-party-implementable contract with stable numbered sections §1–§9: envelope `{t, v, fp, off, n, p}` with a per-type required/unused matrix; the five message types with exact payload shapes (`manifest` p = `{ti, tw, tb, ch[{o, ti, cb}]}`, `position` p = `{ts, src}`, `error` p = `{c, m}`); little-endian §5 record layout (u8 wordLen · u8 flags · u8 orpPivot · u16le bonusMs · UTF-8 word, 5+wordLen ≈ 9 B/word); §6 flag bits (sentenceEnd 0x01, paragraphStart 0x02, chapterStart 0x04, reserved continuation 0x08 + rtl 0x10, reserved-must-be-zero); §7 fingerprint; §2 versioning; §8 error codes; §9 glossary incl. chapter-transition card. CIQ ≥6.0 ByteArray-transport platform note stated in §1.1 (codec itself has no floor; `minApiLevel` 5.2.0 untouched per decision 0001).
- **Fingerprint type trap resolved as recommended:** wire form is a string of exactly 8 lowercase hex chars (`[0-9a-f]{8}`) — no signed-32-bit overflow risk, cheap equality, log-friendly; watch compares only. 2038 note recorded in §4.4.
- **Versioning policy decided:** v-exact-match for MVP (`v == 1`), reject + report (`versionMismatch`), never guess. Error *codes* are extensible values (unknown code → treat as `internal`); envelope *fields* are not (unknown key → malformed).
- **Reserved-bits posture decided:** receivers treat any set reserved flag bit as a malformed record — version gating guarantees same-version senders write zeros, so a set bit signals corruption.
- **AC2:** `Protocol.mc` (UPPER_SNAKE module consts) and `protocol_keys.dart` (`abstract final class ProtocolKeys`, static const) mirror every key/type/flag/code once per side, each citing its SPEC § in a comment; no inline protocol literals at any call site (greps clean; test files pin literals deliberately for drift detection).
- **AC3:** both sides pin the same 32-byte fixture from `protocol/examples/word-records.md` ("Pace" ¶+chapter start / "turns" / Hebrew "שלום" sentence-end + 350 ms bonus — proves byte-index pivots). Dart `encodeChunk` reproduces the exact fixture bytes; Dart and Monkey C decoders assert every field; the watch re-encodes via a test-side helper back to the exact bytes; envelope builders match `protocol/examples/envelopes.md` field-for-field.
- **AC4:** unknown `v` → typed rejection on both sides: `Protocol.validateEnvelope` returns `ERR_VERSION_MISMATCH` (callers must surface it); Dart `decodeEnvelope` throws `EnvelopeException(code: versionMismatch)`. Missing `v` rejected identically (SPEC §3 check order). Both pinned by tests.
- **Error posture (AR24/NFR8):** watch `StreamDecoder.decodeChunk` bounds-checks every read and returns null (typed failure → `ERR_DECODE_FAILURE`) on truncation, wordLen 0, pivot ≥ wordLen, reserved bits, invalid UTF-8, leftover bytes, n<1 — never throws past the boundary; Dart mirror throws typed `StreamDecodeException` for the same cases. Exact-consumption rule (§4.3) enforced on both sides.
- **Scope held:** no transport wiring, no fingerprint computation, no ChunkedWordSource/Storage, zero new pub/Toybox dependencies. Dart codecs are pure (`dart:typed_data` + `dart:convert`; no Flutter imports); watch decoder imports no WatchUi/Communications.
- **Note for Story 2.2:** SPEC §7 fixes only the fingerprint wire form; the computation algorithm is explicitly delegated to the reference companion.

### File List

- `protocol/SPEC.md` (rewritten — full contract)
- `protocol/examples/word-records.md` (new — normative 32-byte record fixture)
- `protocol/examples/envelopes.md` (new — normative envelope-per-type fixture)
- `protocol/examples/.gitkeep` (deleted — directory now has content)
- `watch/source/Protocol.mc` (new — mirrored constants + envelope validation)
- `watch/source/source_data/StreamDecoder.mc` (new — pure §5 decoder)
- `watch/source-test/ProtocolTest.mc` (new — conformance tests)
- `companion/lib/protocol/protocol_keys.dart` (new — mirrored constants)
- `companion/lib/protocol/stream_codec.dart` (new — §5 encode/decode)
- `companion/lib/protocol/envelope_codec.dart` (new — §3/§4 build/validate)
- `companion/test/protocol/stream_codec_test.dart` (new — conformance tests)
- `companion/test/protocol/envelope_codec_test.dart` (new — conformance tests)
- `_bmad-output/implementation-artifacts/1-2-protocol-spec-md-and-mirrored-constants.md` (story tracking)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (status tracking)
- `_bmad-output/implementation-artifacts/deferred-work.md` (new — review-deferred items)

## Change Log

- 2026-06-10: Story 1.2 implemented — SPEC.md authored (envelope, 5 message types, binary record layout, flags, fingerprint-as-hex-string, v-exact-match versioning, error semantics, glossary, worked examples); constants mirrored in `Protocol.mc`/`protocol_keys.dart`; codecs + conformance tests green on both sides (watch: 6/6 in the CI tester image at Strict; companion: analyze clean, 36/36). Status → review.
- 2026-06-10: Adversarial code review (Blind Hunter / Edge Case Hunter / Acceptance Auditor) — 18 findings: 3 decisions resolved (watch implements SPEC §3 step 3; orpPivot UTF-8 boundary enforced at encode, decoders explicitly don't check; non-null unused envelope fields = `malformedEnvelope`), 17 patches applied (SPEC clarified: §1.1 envelope description, §1.2 signed-32-bit integer bound, §3 unused-field/range rules, §4.2/§8 error-code split, §5 sender-side pivot rule; watch: full step-3 envelope validation incl. §4 payload structure + structural UTF-8 validation replacing an uncatchable `convertEncodedString` crash; Dart: flags-u8/surrogate/empty-list/pivot-boundary encode checks, envelope range/unused/payload-kind checks, builder validation incl. n-vs-payload record count; tests hardened on both sides), 1 deferred to Epic 4 (`Uint8List`-exact payload check → `deferred-work.md`). Verified: watch 7/7 in CI image, three Strict targets green; companion analyze clean, 50/50. Status → done.

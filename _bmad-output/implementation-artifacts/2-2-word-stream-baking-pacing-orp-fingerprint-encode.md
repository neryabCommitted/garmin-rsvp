---
baseline_commit: 9697a7f7750654cd3abd834bbd3726859b14266d
---

# Story 2.2: Word-stream baking (pacing, ORP, fingerprint, encode)

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer,
I want flagged tokens baked into the compact binary word stream with per-word timing and pivot metadata, plus a manifest and a content fingerprint,
so that the watch can play a book without computing any linguistics (FR17, NFR7).

This is the **final pure-Dart stage** of the Epic 2 import pipeline (`sanitize → tokenize → pace → ORP → fingerprint → encode`, AR20). Story 2.1 produced the flagged `Token` list; this story turns `List<Token>` (grouped into chapters) into the **on-disk word-stream artifacts**: the SPEC §5 binary stream, a §4.1 manifest, a §7 fingerprint, and a JSONL debug master. It does **not** read files, run isolates, persist to drift/disk, or touch the UI — that orchestration is Story 2.3 (`import_service`, `stream_store`), which will call this story's pure `bake()` inside an isolate.

## Acceptance Criteria

1. **AC1 — Pacing (WPM-invariant bonus).** Given flagged tokens, when pacing runs, then each word gets a **WPM-invariant additive `bonusMs`** (never an absolute duration) computed from the length / complexity / punctuation tiers in the addendum. The contract `displayMs = 60000/wpm + bonusMs` (SPEC §5.1) must hold and `bonusMs` must depend **only** on the word, not on WPM. [Source: epics.md#Story-2.2; addendum §2 line 21; SPEC §5.1; rsvpnano-teardown — `ReadingLoop::pacingBonusMsForWord`]
2. **AC2 — ORP pivot (UTF-8 byte index).** Given each word, when ORP runs, then the pivot is selected by the length→ordinal table (counting word-characters only, punctuation skipped) and stored as a **0-based UTF-8 byte index** into the word that points at the **first byte of a UTF-8 sequence** and is `< wordLen`. [Source: epics.md#Story-2.2; addendum §2 line 24; SPEC §5; rsvpnano-teardown — `orpOrdinalForLength`/`findFocusLetterIndex`]
3. **AC3 — Binary stream + JSONL master + fingerprint.** Given a converted book, when baking completes, then it produces (a) the SPEC §5 binary stream (~9 B/word, little-endian, flag bits per `protocol/SPEC.md` §6) via the existing `encodeChunk`, (b) a JSONL debug master (one line per word), **and** (c) an §7 content fingerprint (exactly 8 lowercase hex chars). [Source: epics.md#Story-2.2; addendum §2 line 19, §3 line 31; SPEC §7]
4. **AC4 — Round-trips exactly.** Given the encoder output, when decoded by `decodeChunk` (the Dart mirror of the watch-side `StreamDecoder.mc`), then it round-trips to the identical records, cross-checked against the Story 1.2 SPEC fixtures. [Source: epics.md#Story-2.2; protocol/examples/word-records.md; companion/lib/protocol/stream_codec.dart]
5. **AC5 — Manifest.** Given a baked book, when the manifest is produced, then it carries the chapter index (`ch[]` with absolute word offsets `o`, titles `ti`), cumulative `bonusMs` durations (`cb` per chapter + book-total `tb`), total word count `tw`, and the fingerprint — exactly the SPEC §4.1 shape, with `ch[0].o == 0` and `ch[0].cb == 0`. [Source: epics.md#Story-2.2; SPEC §4.1]
6. **AC6 — Pure Dart in an isolate.** Given the modules, when tests run, then they are pure Dart (no `package:flutter/*` imports), no global mutable state, no async I/O — runs unchanged in a Dart isolate (called via `compute` in Story 2.3). [Source: architecture.md AR19, "services/import/ is pure Dart"; mirrors Story 2.1 AC5]

## Tasks / Subtasks

- [x] **Task 1 — `pacing.dart`: WPM-invariant bonus** (AC: #1, #6)
  - [x] Write failing tests first in `companion/test/services/import/pacing_test.dart` (red).
  - [x] Implement `int bonusMsForWord(Token token, {Token? next})` returning a WPM-invariant additive bonus in ms (see Dev Notes → "Pacing model"). Port RSVP Nano's `pacingBonusMsForWord` percentages from the addendum; apply each tier to a **fixed reference-ms base** (not `60000/wpm`) so the result is WPM-independent.
  - [x] Length tier: `6%/char` for chars >6, `9%` >10, `12%` >14, capped at `170%` of the length reference base.
  - [x] Complexity tier: syllable-groups up to `+50%`, mixed-alphanumeric `+22%`, ALL-CAPS `+14%`, compound-joiner (hyphen) `+14%`, capped at `85%` of the complexity reference base.
  - [x] Punctuation tier (from the token's trailing punctuation + the baked `sentenceEnd` flag, **not** re-detected): comma `45%`, dash `60%`, semicolon/colon `80%`, ellipsis `110%`, trailing period `135%` (suppressed when not a sentence end — abbreviation), `sentenceEnd` flag `150%`. Use `Token.sentenceEnd` as the authority for the sentence pause; do not re-run abbreviation detection.
  - [x] **Lock the WPM-invariance contract with a test** mirroring Nano's `test_word_pacing_bonus_at_is_invariant_to_wpm`: the bonus is identical regardless of any WPM, and `60000/wpm + bonus` is the only timing expression. Assert `0 ≤ bonus ≤ 65535` (u16, SPEC §5).
  - [x] Green, then refactor. Keep the tier percentages and reference bases in named consts (no magic numbers).

- [x] **Task 2 — `orp.dart`: length→pivot byte index** (AC: #2, #6)
  - [x] Write failing tests first in `companion/test/services/import/orp_test.dart` (red).
  - [x] Implement `int orpPivot(String word)` returning the 0-based **UTF-8 byte index** of the pivot character.
  - [x] Ordinal table (count **word-characters** only — `\p{L}\p{N}`, skip punctuation): length ≤1 → 0th, ≤5 → 1st, ≤9 → 2nd, ≤13 → 3rd, else 4th.
  - [x] Map the chosen word-character ordinal to the byte offset of that character's first UTF-8 byte within `utf8.encode(word)` (the **full** stored word, including any leading/trailing punctuation). Leading quotes/brackets must not shift the pivot off a letter.
  - [x] Invariant the test must prove: the returned index is `< utf8.encode(word).length`, points at the first byte of a UTF-8 sequence (`byte & 0xC0 != 0x80`), and lands on a letter/digit. Cover ASCII, multi-byte (Hebrew/accented), leading-punctuation, and trailing-punctuation words.
  - [x] Green, then refactor.

- [x] **Task 3 — `fingerprint.dart`: §7 conversion fingerprint** (AC: #3, #6)
  - [x] Write failing tests first in `companion/test/services/import/fingerprint_test.dart` (red).
  - [x] Implement `String fingerprint(Uint8List streamBytes, {required int salt})` → exactly 8 lowercase hex chars (`[0-9a-f]{8}`, `ProtocolKeys.fingerprintLength`). FNV-1a 32-bit over stream bytes + 8 LE salt bytes.
  - [x] Tests: same bytes + same salt → identical fp (deterministic for fixtures); same bytes + **different salt** → different fp with high probability (SPEC §7: re-bake of identical source yields a new fingerprint); output always matches `^[0-9a-f]{8}$` including leading-zero padding.
  - [x] Green, then refactor.

- [x] **Task 4 — `word_stream_baker.dart`: orchestrate the bake** (AC: #3, #4, #5, #6)
  - [x] Write failing tests first in `companion/test/services/import/word_stream_baker_test.dart` (red).
  - [x] Define the input/output value types (see Dev Notes → "Baker API & models") — immutable, `==`/`hashCode`/`toString` in the `WordRecord`/`Token` style.
  - [x] Implement `BakedBook bake({required String title, required List<BakeChapter> chapters, required int salt})`:
    - [x] Flatten chapters → `List<WordRecord>`: for each token, set `flags` from `Token.paragraphStart`/`sentenceEnd` mapped to `ProtocolKeys.flagParagraphStart`/`flagSentenceEnd` (AR8 — never inline `0x01`/`0x02`), set `flagChapterStart` on the **first token of each chapter**, compute `orpPivot` (Task 2) and `bonusMs` (Task 1, passing the next token for look-ahead). Reserved bits stay 0.
    - [x] Encode the whole stream with the **existing** `encodeChunk(records)` (SPEC §5 concatenation == the on-disk stream). Do NOT write a second encoder.
    - [x] Build the manifest (Task: AC5): `tw` = total words, `tb` = Σ`bonusMs`, `ch[]` with `o` (absolute first-word index), `ti` (chapter title), `cb` (cumulative `bonusMs` before `o`); `ch[0].o == 0`, `ch[0].cb == 0`.
    - [x] Compute the fingerprint (Task 3) over the encoded stream bytes + `salt`; stamp it onto the manifest.
    - [x] Emit the JSONL debug master (one line per word; see Dev Notes → "JSONL master").
  - [x] **Round-trip test (AC4):** `decodeChunk(baked.streamBytes, baked.manifest.totalWords)` returns records equal to the baker's records. Do **not** re-pin the `word-records.md` hex — `stream_codec_test.dart:20` already pins it; rely on `encodeChunk` being conformant and round-trip the baker's own output.
  - [x] Green, then refactor.

- [x] **Task 5 — Bounds-check-and-degrade & edge cases** (AC: all; NFR8)
  - [x] Empty book / chapter with zero tokens: define and test the typed outcome (e.g. `ArgumentError`/typed failure — `encodeChunk` throws `ArgumentError` on an empty record list; do not let a chapterless or wordless book reach it unguarded).
  - [x] Single-word book; single-word chapters; a word that is one multi-byte grapheme; very long word (>14 chars, length cap) — assert `bonusMs` stays within u16 and `orpPivot` stays valid.
  - [x] Confirm every `WordRecord` the baker emits passes `encodeChunk`'s validators (wordLen 1–255, pivot first-byte & `< wordLen`, bonus u16, reserved bits 0) — these are baking bugs if they throw, per the codec's `ArgumentError` contract.

- [x] **Task 6 — Verify & keep CI green** (AC: all)
  - [x] `cd companion && flutter test` — all pass (136 baseline + 47 new = 183; no regression).
  - [x] `flutter analyze` — clean (strict-casts / strict-inference / strict-raw-types).
  - [x] Grep-confirm: no `import 'package:flutter` under `lib/services/import/`.

### Review Findings

_Code review 2026-06-14 (Amelia, bmad-code-review): 3 adversarial layers (Blind Hunter, Edge Case Hunter, Acceptance Auditor). All 6 ACs satisfied; AR8/AR19/AR20 honoured; no BLOCKER/HIGH. 1 patch, 4 deferred, 9 dismissed as noise._

- [x] [Review][Patch] Complexity 85% cap never exercised by a test; misleading "complexity capped at 64%" comment [companion/test/services/import/pacing_test.dart:60] — DONE: replaced the loose `<=510` assertion with an exact cap-engaging case (`AREA-51-XYZ` → 206 ms; uncapped would be 236, so the exact value proves `_complexityCapPct` engages) and corrected the `mother-in-law` comment (64% is below the 85% cap, not "capped"). flutter test 183 pass, analyze clean.
- [x] [Review][Defer] Pacing tuning fidelity — complexity tier counts ASCII hyphen only while punctuation tier honours em/en dash; `y` always counted as a vowel inflates syllable groups [companion/lib/services/import/pacing.dart:63,117] — deferred to Gate V4 recalibration (addendum flags Nano percentages for Fenix 8 retune).
- [x] [Review][Defer] `!`/`?` have no punctuation-tier branch; masked today because the tokenizer always flags them `sentenceEnd` (→150%) [companion/lib/services/import/pacing.dart:141] — deferred; add an explicit branch if `bonusMsForWord` is ever driven from a non-tokenizer source.
- [x] [Review][Defer] ORP word-char-free token degrades to byte 0 rather than a typed failure [companion/lib/services/import/orp.dart:62] — deferred to Story 2.4: decide whether the extractor may emit punctuation-only tokens, then guard or accept explicitly. (Not reachable from the 2.1 tokenizer; for a standalone-punctuation token byte 0 is in fact the correct pivot.)
- [x] [Review][Defer] Fingerprint test hardening — no assertion that large salts differing only in high bytes (or negative salts) yield different fingerprints [companion/test/services/import/fingerprint_test.dart] — deferred; add high-bit / negative-salt sensitivity tests. (Salt fold is correct on the 64-bit mobile VM; no web target exists.)

## Dev Notes

### What this story is / isn't
- **Is:** pure-Dart baking — pacing bonus, ORP byte pivot, fingerprint, the bake orchestrator that assembles `WordRecord`s, encodes via the existing codec, and produces the manifest + JSONL master.
- **Isn't:** file I/O / flat-file `stream_store` writing (Story 2.3 + `data/stream_store.dart`), isolate orchestration / `import_service` (2.3), EPUB/HTML extraction & chapter discovery (2.4 `epub_extractor.dart`), cover extraction (2.4), the binary record codec itself (already exists — `stream_codec.dart`), envelope/manifest wire serialization (Epic 4 `envelope_codec.dart`), tokenization/sanitation (2.1, done). Do not pull those forward.

### Reuse — do NOT reinvent
- **`encodeChunk` / `decodeChunk` already exist** — `companion/lib/protocol/stream_codec.dart:88,167`. The on-disk word stream **is** the SPEC §5 concatenation of all records, i.e. exactly what `encodeChunk(allRecords)` produces. Use it; do not write a second encoder. It already validates wordLen, the UTF-8-boundary pivot rule (`:124`), bonus u16, and reserved-bit cleanliness — and throws `ArgumentError` for baking bugs (a record the wire cannot carry). `decodeChunk` is the Dart mirror of the watch `StreamDecoder.mc`; use it for the AC4 round-trip.
- **`WordRecord`** (`stream_codec.dart:12`) is the baking output type — `{word, flags, orpPivot, bonusMs}`. Emit it; mirror its immutable `==`/`hashCode`/`toString` style for any new value type (`BakeChapter`, `BookManifest`, `ChapterEntry`, `BakedBook`).
- **`Token`** (`tokenizer.dart:17`) is the input — `{text, paragraphStart, sentenceEnd}`. The exported `abbreviations` const lives in `tokenizer.dart:86`; you should **not** need abbreviation detection here (sentence-end is already baked into `Token.sentenceEnd`).
- **Flag constants** — map booleans to bits via `ProtocolKeys.flagSentenceEnd` / `flagParagraphStart` / `flagChapterStart` (`protocol_keys.dart:54-56`). **Never inline `0x01`/`0x02`/`0x04`** (AR8). Reserved bits (`flagContinuation`/`flagRtl` and 5–7) stay 0 — `encodeChunk` rejects a non-zero reserved bit.
- **Constants** — `ProtocolKeys.fingerprintLength` (8), `ProtocolKeys.recordHeaderBytes` (5). Use them; don't inline.

### Pacing model (Task 1) — port RSVP Nano [Source: addendum §2 line 21; rsvpnano-teardown §"Per-word duration" lines 92, 274-275; SPEC §5.1]
- **The bonus must be WPM-invariant.** Nano computes `durationForWord = 60000/wpm + pacingBonusMsForWord(word)`, where the bonus depends only on the word. The addendum percentages are **relative to fixed reference-ms bases** (Nano's three pacing delays default 200 ms each: `pacingLongWordDelayMs_`, `pacingComplexWordDelayMs_`, `pacingPunctuationDelayMs_`), **not** relative to `60000/wpm` — that is what keeps the bonus WPM-independent. Choosing the bases against `60000/wpm` would make the bonus WPM-dependent and **violate AC1** — do not do this.
- **Decision point (resolve in Task 1, record in Completion Notes):** pick the reference-ms bases. **Recommended:** the Nano defaults (`200 ms` per tier) so the ported percentages reproduce Nano's tuned feel. The addendum flags these percentages "were tuned for Nano's hardware; expect recalibration on Fenix 8" — keep all percentages and bases in **named consts in one place** so Gate V4 / future tuning is a one-file change, not a hunt. For fidelity on the syllable-group heuristic and exact accumulation/cap order (not fully pinned by the addendum), consult the actual source: `github.com/ionutdecebal/rsvpnano` → `src/reader/ReadingLoop.cpp` `pacingBonusMsForWord` / `wordEndsSentenceAt`, and its host tests `test/test_pacing/test_main.cpp` (the `test_*_bonus` / `test_comma_pause` family).
- **Tiers** (sum the three, each capped independently, then add):
  - *Length* (per word-char count): `6%`/char beyond 6, `9%` beyond 10, `12%` beyond 14; cap `170%`.
  - *Complexity*: syllable-groups → up to `+50%`; mixed alphanumeric `+22%`; ALL-CAPS `+14%`; compound-joiner (contains `-`) `+14%`; cap `85%`.
  - *Punctuation*: from trailing punctuation + the `sentenceEnd` flag — comma `45%`, dash `60%`, semicolon/colon `80%`, ellipsis (`...`/`…`) `110%`, trailing period `135%` (suppressed when the token is **not** a sentence end, i.e. abbreviation/decimal), `sentenceEnd` flag → `150%`. Prefer the flag-driven 150% sentence pause over the raw-period 135% when `Token.sentenceEnd` is set.
- **Look-ahead:** Nano's bonus considers the *next* word's leading case (`pacingBonusMsForWord(word, nextWordLowercase, …)`). Pass `next` so this is portable; if you don't end up needing it, drop the param and note why.
- **Result fits u16.** With 200 ms bases the max is ≈ `1.7·200 + 0.85·200 + 1.5·200 ≈ 810 ms` ≪ 65535. Still clamp/validate to `[0, 65535]` (SPEC §5; `encodeChunk` enforces it).

### ORP model (Task 2) [Source: addendum §2 line 24; rsvpnano-teardown lines 108-110; SPEC §5]
- Count **word-characters** (`\p{L}\p{N}`) only, skipping punctuation, to get the length used for the ordinal table — so leading quotes/brackets don't shift the pivot (Nano `findFocusLetterIndex` skips punctuation when counting).
- Ordinal table (`orpOrdinalForLength`): ≤1 → 0, ≤5 → 1, ≤9 → 2, ≤13 → 3, else 4. The ordinal is always `< wordCharCount`, so the pivot always lands on a real letter/digit.
- The stored `orpPivot` is a **byte** index into `utf8.encode(word)` — the byte offset of the first UTF-8 byte of the ordinal-th word-character. SPEC §5 example #2 (`שלום`, pivot 2 = first byte of the 2nd char, not char index 2) is the canonical proof this is a byte index. The `encodeChunk` validator (`:124`) will reject a continuation-byte pivot — your byte offset must be a rune boundary (it is, if you encode up to the chosen rune and take its length).

### Fingerprint (Task 3) [Source: SPEC §7; addendum §3 line 31]
- **Wire form:** exactly 8 lowercase hex chars (32 bits). **Semantics:** opaque equality token; SPEC §7 leaves the algorithm to the reference companion provided distinct conversions get distinct values with high probability, **and re-baking identical source yields a new fingerprint.**
- **Decision point (recommended):** a small pure-Dart 32-bit hash (e.g. **FNV-1a 32-bit**, ~6 lines, no dependency, isolate-safe) over `streamBytes` **plus a per-bake `salt`**. The salt is what makes a re-bake of identical text produce a fresh fp (SPEC §7) while keeping tests deterministic (pass a fixed salt). The **caller (Story 2.3 `import_service`) supplies the salt** (e.g. a timestamp/counter) — this module stays pure and deterministic. Emit `value.toRadixString(16).padLeft(8, '0')`. Avoid pulling `crypto` (sha) just for this; reject anything with a Flutter/platform dep (AR19).

### Baker API & models (Task 4)
Recommended shape (finalize names in the `WordRecord`/`Token` idiom; immutable, `==`/`hashCode`/`toString`):
- Input: `BakeChapter { String title; List<Token> tokens; }` and `bake({required String title, required List<BakeChapter> chapters, required int salt}) → BakedBook`. (For 2.3 `.txt/.md` this is a single chapter; 2.4 supplies many. The baker does **not** discover chapters — it receives them.)
- Output: `BakedBook { Uint8List streamBytes; BookManifest manifest; List<String> debugJsonl; }` (the fingerprint lives on the manifest).
- `BookManifest { String title; int totalWords; int totalBonusMs; String fingerprint; List<ChapterEntry> chapters; }` — the SPEC §4.1 data, as a pure model (Epic 4 maps it to the wire dict via `envelope_codec`; do not serialize the envelope here).
- `ChapterEntry { int offset; String title; int cumulativeBonusMs; }` ↔ §4.1 `o`/`ti`/`cb`.
- **Scope/structure note:** `architecture.md:412-420` lists `pacing.dart`, `orp.dart`, `fingerprint.dart` explicitly but not a baker file; introducing `word_stream_baker.dart` as the pure orchestrator is a deliberate, additive variance — `import_service.dart` (2.3, the impure/isolate orchestrator) will call `bake()`. Keeping orchestration here (pure) preserves AR19 host-testability and keeps `import_service` thin.

### JSONL master (Task 4) [Source: addendum §2 line 19 — "Keep a debuggable master (JSONL …)"]
- Line-delimited JSON, human-debuggable, parallel to the binary. Recommended: line 0 = the manifest (`title`, `tw`, `tb`, `fp`, `chapters`); lines 1..n = one word each, e.g. `{"i":<absIdx>,"w":<word>,"flags":<int>,"orp":<bytePivot>,"bonusMs":<int>,"ch":<chapterIdx>}`. Use `dart:convert` `jsonEncode`. Exact schema is your call — it must be valid line-delimited JSON and carry enough to reconstruct/inspect each record. This is a debug artifact, **not** a wire format; the watch never sees it.

### Round-trip / fixtures (AC4)
- `companion/test/protocol/stream_codec_test.dart:20` **already pins** the normative `protocol/examples/word-records.md` 32-byte fixture for both encode and decode; `watch/.../StreamDecoder.mc` (Monkey C) pins the same fixture independently — that is the cross-side guarantee. **Do not duplicate the hex.** This story's AC4 test bakes real tokens → `encodeChunk` → `decodeChunk` → asserts equal records, relying on the already-conformant codec.

### Testing standards [Source: architecture.md#Testing; existing test/protocol/, test/services/import/]
- Framework: `flutter_test` + `test` (pure-Dart modules need no widget tree). Pattern exemplars: `test/protocol/stream_codec_test.dart`, `test/services/import/tokenizer_test.dart`, the data-driven `test/services/import/corpus_test.dart` + `test/fixtures/text/pipeline_cases.json` (consider extending the corpus with expected pacing/ORP outputs for a few golden words).
- TDD per the team principle: red → green → refactor, one task at a time, in order.
- NFR8 — bounds-check-and-degrade: empty/whitespace-only/single-word/truncated input must yield a typed result or typed exception, never an unhandled crash (Task 5).

### Architecture compliance / guardrails
- **AR19:** `services/import/` is pure Dart — no `package:flutter/*`, no global mutable state, no async I/O; must run unchanged in a Dart isolate (invoked via `compute` in 2.3). Allowed imports: `dart:typed_data`, `dart:convert`, and the project's `protocol/` codec + keys. [architecture.md AR19]
- **AR8:** no inline protocol magic — `ProtocolKeys.*` for all flag bits, header sizes, fingerprint length.
- **AR20:** this completes the import pipeline `sanitize → tokenize → pace → ORP → fingerprint → encode`.
- **Layering:** `ui/ → services/ → data/`. This story adds only under `services/import/`; touch nothing in `ui/`, `gate_v2/`, `data/`, or `protocol/` (the codec is reused, not modified).
- Keep `flutter analyze` clean under strict-casts / strict-inference / strict-raw-types (`companion/analysis_options.yaml`).

### Previous-story intelligence (2.1) [Source: 2-1-text-sanitation-tokenization.md]
- 2.1 shipped `text_sanitizer.dart` + `tokenizer.dart`, added `unorm_dart: 0.3.2`, all pure Dart, 136/136 tests, analyze clean. The `Token` contract is stable: `{text, paragraphStart, sentenceEnd}`, trailing punctuation kept on the token, `sentenceEnd` is abbreviation-aware **and** the **last token of the text is forced `sentenceEnd=true`** (terminal-boundary guarantee — the bake-time equivalent of Nano's `… || atEnd()`). Consequence for this story: the final word's `bonusMs` will carry the 150% sentence pause — that is intended (FR8 coast / FR10 rewind have a real terminal boundary to land on). Per-chapter: the first token of each chapter gets `flagChapterStart` here (2.1 does **not** set chapter flags).
- Deferred from 2.1: the ASCII-fold table is Latin-1-only (`deferred-work.md`) — not this story's concern, but leftover non-folded glyphs are still valid UTF-8 and bake fine (the ORP byte-index logic is encoding-agnostic).

### References
- [Source: epics.md#Epic-2 / Story 2.2, lines 402–429]
- [Source: protocol/SPEC.md §5 (record layout), §5.1 (timing model), §6 (flag bits), §4.1 (manifest), §7 (fingerprint)]
- [Source: protocol/examples/word-records.md — normative byte fixture (already pinned in stream_codec_test.dart)]
- [Source: companion/lib/protocol/stream_codec.dart:12-47 WordRecord; :88 encodeChunk; :167 decodeChunk; :124 UTF-8-boundary pivot check]
- [Source: companion/lib/protocol/protocol_keys.dart:54-60 flag bits, header size, fingerprint length]
- [Source: companion/lib/services/import/tokenizer.dart:17 Token; :86 abbreviations]
- [Source: _bmad-output/.../prds/.../addendum.md §2 lines 19-26 (word-stream format, pacing percentages, ORP table), §3 line 31 (fingerprint)]
- [Source: research/technical-rsvpnano-reader-teardown-research-2026-06-06.md — pacing (lines 92, 274-275), ORP geometry (108-110), WPM-invariant-bonus contract (219); upstream repo github.com/ionutdecebal/rsvpnano `src/reader/ReadingLoop.cpp`]
- [Source: architecture.md AR8/AR19/AR20; lines 412-420 (import file layout); :265 host-testability; :275-277 timing/fingerprint/ORP data dictionary]
- [Source: 2-1-text-sanitation-tokenization.md — Token contract, terminal-boundary guarantee, pure-Dart discipline]

### Project Structure Notes
- Adds `companion/lib/services/import/{pacing,orp,fingerprint,word_stream_baker}.dart` + mirrored tests under `companion/test/services/import/`. Aligns with `ui/ → services/ → data/`; no conflict with `protocol/` (reused) or `2.1`'s sanitizer/tokenizer.
- `word_stream_baker.dart` is an additive pure-orchestrator file not enumerated in `architecture.md:412-420` (which lists the leaf stages); rationale above under "Baker API & models".

## Dev Agent Record

### Agent Model Used

Amelia (bmad-dev-story) on Claude Opus 4.8 (`claude-opus-4-8[1m]`).

### Debug Log References

- One test miss self-corrected: `orp_test.dart` initially expected `orpPivot('however,') == 1`; `however` has 7 word-chars → ordinal 2 (≤9 bucket) → byte 2. Test fixed; impl unchanged.
- Full suite green: `flutter test` → 183 pass (136 baseline + 47 new). `flutter analyze` → no issues.

### Completion Notes List

Decision points resolved (recorded per Dev Notes):
- **Pacing reference bases (Task 1):** Nano defaults — **200 ms per tier** (length / complexity / punctuation), so a tier of `p`% adds `p·2` ms. All tier percentages + bases are named consts at the top of `pacing.dart`, so Gate V4 recalibration is a one-file edit. Max possible bonus ≈ 340 (len cap) + 170 (cplx cap) + 300 (sentence) = 810 ms ≪ 65535; still clamped to u16.
- **Pacing tier model:** length = marginal rates 6%/9%/12% for word-char ranges (6,10]/(10,14]/(14,∞), cap 170%; complexity = syllable-groups (vowel-run count, 25%/extra group, cap 50%) + mixed-alnum 22% + ALL-CAPS 14% + hyphen-compound 14%, cap 85%; punctuation = single dominant trailing mark, with the `Token.sentenceEnd` flag driving the 150% sentence pause that dominates the 135% raw period (and a non-sentence-end period suppressed as an abbreviation/decimal). Uses `Token.sentenceEnd` as the authority — no re-detection.
- **Look-ahead `next` param:** retained on `bonusMsForWord(token, {Token? next})` for API portability with Nano's next-word-case heuristic and wired through the baker, but the ported per-word tiers are self-contained, so it is currently unused (test asserts it does not change the result). Kept so a future retune can use it without a signature change.
- **Fingerprint algorithm (Task 3):** **FNV-1a 32-bit** over the encoded stream bytes, then 8 little-endian bytes of the per-bake `salt` folded in — dependency-free, isolate-safe, deterministic for a fixed salt. The caller (Story 2.3) supplies the salt so a re-bake of identical text yields a fresh §7 fingerprint while this module stays pure. Output is `value.toRadixString(16).padLeft(8,'0')` → always exactly 8 lowercase hex chars.
- **Baker (Task 4):** `word_stream_baker.dart` is an additive **pure orchestrator** (not in `architecture.md:412-420`, which lists leaf stages) — rationale in Dev Notes. It flattens chapters → `WordRecord`s (flags via `ProtocolKeys.*`, never inline; `flagChapterStart` on each chapter's first word; reserved bits 0), encodes via the **existing** `encodeChunk` (no second encoder), builds the §4.1 manifest (`tw`/`tb`/`ch[]` with `o`/`ti`/`cb`, `ch[0].o==0`, `ch[0].cb==0`), stamps the §7 fingerprint, and emits the JSONL master (line 0 = manifest using SPEC keys; lines 1..n = one word each).
- **NFR8 degrade (Task 5):** `bake()` throws typed `ArgumentError` for no chapters or any zero-token chapter (an empty chapter cannot satisfy §4.1's strictly-increasing offsets — the 2.4 extractor must filter empties). Wire-invalid records (e.g. a >255-byte word) surface as `encodeChunk`'s own `ArgumentError` — a typed baking failure, never a silent mangle.
- **AC4 round-trip:** the baker test bakes real tokens → `encodeChunk` → `decodeChunk` and asserts equal records; it does NOT re-pin the `word-records.md` hex (already pinned in `stream_codec_test.dart:20`).
- **AR19/AR8 compliance:** all four new files are pure Dart — only `dart:typed_data`, `dart:convert`, and the project `protocol/` codec+keys; grep confirms no `package:flutter/*` under `lib/services/import/`; no global mutable state; no async I/O.

### File List

- `companion/lib/services/import/pacing.dart` (new)
- `companion/lib/services/import/orp.dart` (new)
- `companion/lib/services/import/fingerprint.dart` (new)
- `companion/lib/services/import/word_stream_baker.dart` (new)
- `companion/test/services/import/pacing_test.dart` (new)
- `companion/test/services/import/orp_test.dart` (new)
- `companion/test/services/import/fingerprint_test.dart` (new)
- `companion/test/services/import/word_stream_baker_test.dart` (new)

## Change Log

- 2026-06-14 — Story drafted (create-story): pure-Dart word-stream baking — pacing bonus, ORP byte pivot, fingerprint, baker orchestrator producing the SPEC §5 binary stream (via existing `encodeChunk`), §4.1 manifest, §7 fingerprint, and JSONL debug master. 6 ACs, 6 tasks. Status → ready-for-dev.
- 2026-06-14 — Story implemented (dev-story): all 6 tasks complete, TDD red→green→refactor. Added `pacing.dart` (WPM-invariant additive bonus, named-const tiers), `orp.dart` (length→ordinal UTF-8 byte pivot), `fingerprint.dart` (salted FNV-1a 32-bit §7 fp), `word_stream_baker.dart` (pure orchestrator → stream + §4.1 manifest + fp + JSONL master) + 47 tests. `flutter test` 183 pass, `flutter analyze` clean, AR19 purity grep clean. Status → review.

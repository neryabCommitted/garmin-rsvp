---
baseline_commit: 88bb862dda0a35d9a28ee136adab39e9b50a041e
---

# Story 2.1: Text sanitation & tokenization

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer,
I want raw book text sanitized and tokenized into words carrying sentence/paragraph flags,
so that downstream stream baking (Story 2.2) has clean, correctly-segmented input — the FR8/FR10 correctness foundation.

This is the **first stage** of the Epic 2 import pipeline (`sanitize → tokenize → pace → ORP → fingerprint`, AR20). It produces a flagged token list. It does **not** compute pacing, ORP pivots, or the binary encoding — those are Story 2.2.

## Acceptance Criteria

1. **AC1 — Sanitation.** Given raw text containing soft hyphens, zero-width characters, and NBSPs, when the sanitizer runs, then output is NFC-normalized, soft-hyphens (U+00AD) and zero-width characters stripped, and NBSP (U+00A0) → regular space (U+0020). [Source: epics.md#Story-2.1; architecture.md AR20]
2. **AC2 — Optional ASCII-fold.** Given the sanitizer with ASCII-fold enabled (off by default), when it runs, then glyphs missing from the watch font (curly quotes, em/en dashes, ellipsis char, accented letters) are folded to ASCII equivalents; with the flag off, those glyphs pass through unchanged. [Source: epics.md#Story-2.1; addendum — "optionally ASCII-fold glyphs missing from the watch font"]
3. **AC3 — Tokenization.** Given sanitized text, when the tokenizer runs (Unicode `\p{L}\p{N}`, `unicode: true`), then it emits a word list where each word carries `paragraphStart` and `sentenceEnd` flags, with trailing punctuation kept **on** the token. [Source: epics.md#Story-2.1; research#tokenizer]
4. **AC4 — Abbreviation-aware sentence-end.** Given abbreviations and initialisms ("Dr.", "U.S.", "e.g."), when sentence-end flagging runs, then those periods do **not** set `sentenceEnd`, verified against a fixture set. [Source: epics.md#Story-2.1; rsvpnano-teardown#sentence-detection]
5. **AC5 — Pure Dart in an isolate.** Given the modules, when tests run, then they are pure Dart (no `package:flutter/*` imports), have no global mutable state and no async I/O, so they run unchanged in a Dart isolate. [Source: architecture.md AR19, "services/import/ is pure Dart"]

## Tasks / Subtasks

- [x] **Task 1 — Scaffold the pure-Dart import package** (AC: #5)
  - [x] Create `companion/lib/services/import/` (new directory — does not exist yet).
  - [x] Add the NFC dependency to `companion/pubspec.yaml` (see Dev Notes → "NFC decision point"). Pin the version; run `flutter pub get`.
  - [x] Verify no `package:flutter/*` import appears in any file under `services/import/`.

- [x] **Task 2 — `text_sanitizer.dart`** (AC: #1, #2, #5)
  - [x] Write failing tests first in `companion/test/services/import/text_sanitizer_test.dart` (red).
  - [x] Implement `sanitize(String raw, {bool asciiFold = false}) → String`.
  - [x] Order: **NFC-normalize first**, then strip/replace (normalization can change which codepoints are present).
  - [x] Strip soft hyphen `U+00AD`.
  - [x] Strip zero-width set: `U+200B` ZWSP, `U+200C` ZWNJ, `U+200D` ZWJ, `U+2060` word-joiner, `U+FEFF` ZWNBSP/BOM.
  - [x] Replace NBSP `U+00A0` and narrow NBSP `U+202F` → regular space `U+0020`.
  - [x] `asciiFold` (default **false**): fold curly quotes (`U+2018/2019→'`, `U+201C/201D→"`), em/en dash (`U+2014/2013→-`), ellipsis (`U+2026→...`), and common accented letters → base. Keep the fold table small and tested; document each mapping.
  - [x] Green, then refactor.

- [x] **Task 3 — `tokenizer.dart`** (AC: #3, #4, #5)
  - [x] Write failing tests first in `companion/test/services/import/tokenizer_test.dart` (red).
  - [x] Define the token type: `Token { final String text; final bool paragraphStart; final bool sentenceEnd; }` — immutable, with `==`/`hashCode`/`toString` (mirror the style of `WordRecord` in `stream_codec.dart`). Keep it linguistics-only — do **not** add orpPivot/bonusMs/binary flags here (that is Story 2.2).
  - [x] Implement `tokenize(String sanitized) → List<Token>`.
  - [x] Paragraph segmentation: treat one-or-more blank lines (`\n` runs producing an empty line, i.e. `\n\s*\n`) as a paragraph boundary. The first token of the text and the first token after each boundary get `paragraphStart = true`.
  - [x] Word splitting: split on whitespace `RegExp(r'\s+')`; keep tokens that contain a letter or digit via `RegExp(r'\p{L}\p{N}', unicode: true)` (note: this is `[\p{L}\p{N}]` semantics — a token is kept if it matches *any* letter/digit). Preserve trailing punctuation on the token (`"hello."` stays one token).
  - [x] Sentence-end flagging (abbreviation-aware): see Dev Notes → "Sentence-end algorithm". Set `sentenceEnd = true` on the last word of each sentence.
  - [x] Green, then refactor.

- [x] **Task 4 — Abbreviation fixture corpus** (AC: #4)
  - [x] Create `companion/test/fixtures/text/` (new directory).
  - [x] Add fixture inputs + expected token/flag output covering the cases listed in Dev Notes → "Fixture corpus". Drive AC4 tests from these.

- [x] **Task 5 — Verify & keep CI green** (AC: all)
  - [x] `cd companion && flutter test` — all pass (127/127; no regression from Epic 1 baseline).
  - [x] `flutter analyze` — clean (strict-casts / strict-inference / strict-raw-types are on).
  - [x] Grep-confirm: no `import 'package:flutter` under `lib/services/import/`.

### Review Findings

_Code review 2026-06-14 (Blind Hunter + Edge Case Hunter + Acceptance Auditor). AC verdict: all 5 ACs satisfied; findings below are correctness gaps beyond the literal spec._

- [x] [Review][Patch] Guarantee a terminal sentence boundary — `tokenizer.dart` `_endsSentence`/`_isSuppressed` can leave the **last token of the text** with `sentenceEnd=false` via three paths: (a) no terminal punctuation (test `tokenizer_test.dart:897-900` enshrines this as expected), (b) ends with an abbreviation/initialism (`U.S.`, `Co.`, `etc.` at end-of-text), (c) ends with a single capital initial (`I.`, `A.`). FR8 two-stage pause coasts to the next `sentenceEnd` and FR10 rewind lands on `sentenceEnd`; a document/chapter with no terminal flag breaks both on-device. **Resolved → Option 1 (Nerya, 2026-06-14):** force the last token of the text to `sentenceEnd=true`. This is the data-baked equivalent of rsvpnano's `currentWordEndsSentence() \|\| atEnd()` (`App.cpp:1883-1894`); their detector hits the same false-negatives but the consumer OR's with `atEnd()` at read time — our bake-once design (FR17) has no read-time fallback, so the guard moves into the baked flag. Update `tokenizer_test.dart:897-900` accordingly. [edge+auditor]
- [x] [Review][Patch] `_dottedInitialism` over-matches single letter+period — suppresses legitimate lowercase single-letter sentence ends (`"...option a."`, `"...labeled b."`). Regex `^(\p{L}\.)+\p{L}?\.?$` matches a lone `a.`; intent was multi-segment initialisms. Tighten to require ≥2 letter-dot groups. [tokenizer.dart:378-379] [blind+edge]
- [x] [Review][Patch] Sanitizer does not normalize bare `\r`/`\r\r` line endings — `_paragraphBreak = \n\s*\n` misses CR-only/CR-pair blank lines (classic-Mac / some EPUB extraction), dropping `paragraphStart`. Normalize CR/CRLF→LF in `sanitize()`. [text_sanitizer.dart sanitize] [edge]
- [x] [Review][Patch] Fixture `_doc` falsely claims inputs use `\u` escapes — inputs are raw invisible codepoints (soft-hyphen/ZWNJ/NBSP). Tests are valid, but invisibles are non-reviewable and silently editable. Fix the doc string (or escape the inputs). [pipeline_cases.json:503] [blind]
- [x] [Review][Defer] ASCII-fold table is Latin-1 only — `œ`/`ß`/`ā`/`æ`/Latin-Extended-A pass through even with `asciiFold:true` (the exact "missing watch-font glyphs" AC2 targets). Spec sanctioned a "small table"; deferred — revisit when a real EPUB corpus reveals which glyphs actually occur. [text_sanitizer.dart:_foldMap] [edge+auditor]

_Dismissed as noise (3): closer-strip inspects only the single trailing char (contrived `end."a` constructs, not real prose); redundant `e.g`/`i.e` abbreviation-const entries (harmless belt-and-suspenders vs the dotted regex); no asserting pure-Dart guard test (AC5 satisfied via `flutter analyze` + grep)._

## Dev Notes

### What this story is / isn't
- **Is:** pure-Dart linguistics — sanitize raw text, split into words, flag paragraph starts and (abbreviation-aware) sentence ends.
- **Isn't:** pacing/bonus-ms (2.2 `pacing.dart`), ORP pivot (2.2 `orp.dart`), binary encoding/`WordRecord` (2.2 `stream_codec.dart` already exists), EPUB/HTML extraction (2.4), fingerprint (2.2). Do not pull those forward.

### Exact file locations [Source: architecture.md#Project-Structure, lines 412–452]
- Source: `companion/lib/services/import/text_sanitizer.dart`, `companion/lib/services/import/tokenizer.dart` (create `services/import/` — only `lib/{main.dart, protocol/, gate_v2/}` exist today).
- Tests: `companion/test/services/import/text_sanitizer_test.dart`, `companion/test/services/import/tokenizer_test.dart` (mirror `lib/` layout — see existing `test/protocol/stream_codec_test.dart`).
- Fixtures: `companion/test/fixtures/text/` (new).
- Naming: `snake_case.dart` files, `PascalCase` classes, `camelCase` members.

### Reuse — do NOT reinvent
- **Flag constants already exist** in `companion/lib/protocol/protocol_keys.dart:45-50`: `flagSentenceEnd = 0x01`, `flagParagraphStart = 0x02`, `flagChapterStart = 0x04`, `flagContinuation = 0x08` (reserved), `flagRtl = 0x10` (reserved), `flagsReservedMask = 0xF8`. Story 2.2 maps `Token.paragraphStart → ProtocolKeys.flagParagraphStart` and `Token.sentenceEnd → ProtocolKeys.flagSentenceEnd` when it builds `WordRecord`s. **This story does not touch the binary flags byte** — keep `Token` as bool fields and leave the bit-mapping to 2.2. If you do reference flag bits anywhere, use `ProtocolKeys.*`, never inline `0x01`/`0x02` (AR8).
- `chapterStart` is **not** set by the tokenizer — it's a downstream manifest/chapter concern. Do not set it here.
- `WordRecord` (`companion/lib/protocol/stream_codec.dart:12`) is the **2.2 baking output**; it carries `orpPivot`/`bonusMs` you don't compute. Don't emit it from 2.1.
- Style reference for an immutable value type with `==`/`hashCode`/`toString`: `WordRecord` in `stream_codec.dart:11-47`.

### NFC decision point (resolve in Task 1)
Dart's core `String` has **no built-in Unicode normalization** (there is no `String.normalize()`). You must add a package.
- **Recommended:** `unorm_dart` — pure-Dart port of `unorm.js`, provides NFC/NFD/NFKC/NFKD, no Flutter/platform deps → isolate-safe. Verify the current version on pub.dev and pin it.
- Acceptable alternative if it already pulls its weight elsewhere, but heavier: `intl`.
- **Reject:** ML/CJK tokenizers (`dart_wordpiece`, `tiny_segmenter_dart`, sentencepiece ports) — wrong tool for Latin prose RSVP [Source: epub-parsing-research#tokenizer]. Avoid "convenience" normalizers that silently transform beyond NFC.
- Whichever you pick, add a one-line rationale in the Completion Notes and confirm it has no Flutter dependency.

### Sentence-end algorithm (AC4) [Source: rsvpnano-teardown#sentence-detection — `wordEndsSentenceAt()` honoring abbreviations & dotted initialisms]
For each token, decide `sentenceEnd`:
1. Strip trailing closing quotes/brackets for inspection only (`" ' ” ’ ) ]`), keep them on the stored token text. (`hello."` → terminal punct is `.`.)
2. If the (stripped) token ends with `!` or `?` → `sentenceEnd = true`.
3. If it ends with `.`:
   - **Suppress** (not a sentence end) when the token is a known abbreviation (case-insensitive match against the curated list), OR a dotted initialism (matches `^(\p{L}\.)+\p{L}?\.?$` like `U.S.`, `e.g.`, `i.e.`, `Ph.D.`), OR a single capital initial (`^\p{Lu}\.$` like `J.`), OR a decimal where the dot is internal (`3.14` — only a *trailing* dot can end a sentence).
   - Otherwise → `sentenceEnd = true`.
4. Ellipsis (`...` or folded from `…`) mid-text → not a sentence end; treat a trailing `...` like a single terminal `.` for the suppression check (i.e., only ends a sentence if not an abbreviation context).
- Curated abbreviation list (seed; extend via fixtures): titles `Mr Mrs Ms Dr Prof Rev Sr Jr St`, common `etc vs e.g i.e cf al`, months `Jan Feb Mar Apr Jun Jul Aug Sep Sept Oct Nov Dec`, units/orgs `Inc Ltd Co Corp No`. Keep the list in one named const so fixtures can extend it.
- **Why it matters:** the watch's two-stage pause (FR8) coasts to the next `sentenceEnd`, and sentence-rewind (FR10) lands on `sentenceEnd` boundaries. A false sentence end from "Dr." silently breaks both on-device. These flags are baked once on the phone and consumed verbatim by the watch (FR17) — the watch never recomputes linguistics.

### Fixture corpus (Task 4) — cases the fixtures MUST cover [Source: addendum R6; epub-parsing-research]
- Soft-hyphen inside a word → single clean token after sanitation.
- Zero-width char mid-word (`word‌boundary` → `wordboundary`).
- NBSP runs → clean word split, no phantom empty tokens.
- Precomposed vs decomposed accents (`é` = `U+00E9` vs `e`+`U+0301`) → identical after NFC.
- Abbreviation no-split: `"Dr. Smith went to the U.S. yesterday."` → `sentenceEnd` only on `yesterday.`
- Initialisms / `e.g.` / `i.e.` mid-sentence → no split.
- Decimals: `"The value is 3.14 today."` → no split at `3.14`.
- Ellipsis: `"Wait... what?"` vs `"Wait... what"` (trailing).
- Closing quote/paren after terminal punct: `"He left.")` and `He smiled (happily).` → sentence ends at the right token.
- Paragraph boundaries: blank-line-separated paragraphs → `paragraphStart` on the first token of each.
- ASCII-fold on vs off: curly quotes / em-dash / accented pass through when off, fold when on.

### Testing standards [Source: architecture.md#Testing; existing test/protocol/]
- Framework: `flutter_test` + `test` (already in `dev_dependencies`). Pure-Dart modules need no widget tree.
- Pattern exemplar: `companion/test/protocol/stream_codec_test.dart`, `companion/test/protocol/envelope_codec_test.dart`.
- TDD per the team principle: red → green → refactor, one task at a time, in order.
- NFR8 — bounds-check-and-degrade: malformed/empty/whitespace-only/truncated input must yield a typed result or typed exception, never an unhandled crash. Add tests for empty string, whitespace-only, single word, no-terminal-punctuation tail.

### Architecture compliance / guardrails
- **AR19:** `services/import/` is pure Dart — no `package:flutter/*`, no global mutable state, no async I/O. Must run unchanged in a Dart isolate (it will be invoked via `compute`/isolate during import in Story 2.3). [architecture.md#"services/import/ is pure Dart … runs in isolates and tests trivially"]
- **AR8:** no inline protocol magic — use `ProtocolKeys.*` if you reference flag bits at all.
- **Layering:** `ui/ → services/ → data/`. This story adds only `services/import/`; touch nothing in `ui/`, `protocol/`, or `gate_v2/`.
- Keep `flutter analyze` clean under strict-casts / strict-inference / strict-raw-types (`companion/analysis_options.yaml`).
- ORP is a **UTF-8 byte** index (SPEC §5) — not your concern here, but it's why upstream sanitation matters: leftover soft-hyphens/zero-widths shift byte offsets and silently corrupt 2.2's ORP pivots. Strip them completely.

### References
- [Source: epics.md#Epic-2 / Story 2.1, lines 373–400]
- [Source: architecture.md#AR20 import pipeline, lines 114–115]
- [Source: architecture.md#Project-Structure & enforcement, lines 412–452 ("services/import/ is pure Dart")]
- [Source: companion/lib/protocol/protocol_keys.dart:45-50 — flag constants]
- [Source: companion/lib/protocol/stream_codec.dart:11-47 — WordRecord value-type style; :115-136 ORP/byte validation]
- [Source: protocol/SPEC.md §5 word-record layout, §6 flag bits]
- [Source: prds/prd-garmin_RSVP-2026-06-06/prd.md — FR8 (two-stage pause), FR10 (sentence rewind), FR17 (phone does the heavy lifting)]
- [Source: research/technical-epub-parsing-flutter-dart-research-2026-06-06.md — sanitation codepoints, `\p{L}\p{N}` tokenizer, package guidance]
- [Source: research/technical-rsvpnano-reader-teardown-research-2026-06-06.md — abbreviation-aware sentence detection]

### Project Structure Notes
- Adds the first `companion/lib/services/` subtree; aligns with the architecture's `ui/ → services/ → data/` layering. No conflicts with existing `protocol/` or `gate_v2/` code.
- New test-fixture root `companion/test/fixtures/text/` — none exists yet; create it.

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Amelia / dev-story)

### Debug Log References

- `flutter analyze` → "No issues found!" (strict-casts / strict-inference / strict-raw-types on).
- `flutter test` → 127/127 pass (50 new: 15 sanitizer + 19 tokenizer + 16 corpus; no regression).
- Pure-Dart guard: `grep -rnE "^\s*import .*package:flutter" lib/services/import/` → no matches.

### Completion Notes List

- **NFC package decision (Task 1):** chose `unorm_dart: 0.3.2` (pinned). Pure-Dart port of `unorm.js`, **zero dependencies, no Flutter/platform code** (verified via pub.dev API) → isolate-safe per AR19. Dart core `String` has no `normalize()`, so a package was required; `intl` was the heavier alternative, ML/CJK tokenizers rejected per research.
- **AC1 sanitation:** `sanitize()` NFC-normalizes first, then strips soft-hyphen + the zero-width set and maps NBSP/narrow-NBSP → space. Order matters — normalization can introduce/alter codepoints before stripping.
- **AC2 ASCII-fold:** off by default; folds curly quotes/em-en dash/ellipsis/common Latin-1 accents via a small documented `_foldMap` (ellipsis is one-to-many, expanded before the per-rune pass). With the flag off, all those glyphs pass through verbatim.
- **AC3 tokenization:** `tokenize()` splits paragraphs on `\n\s*\n`, words on `\s+`, keeps a token only if it matches `[\p{L}\p{N}]` (unicode), preserves trailing punctuation, and flags `paragraphStart` on the first kept token of each paragraph.
- **AC4 sentence-end:** abbreviation-aware per the Dev Notes algorithm — strips trailing closers for inspection, `!`/`?` always terminate, `.`/`…`/trailing `...` terminate **unless** the token is a dotted initialism (`U.S.`, `e.g.`), a single capital initial (`J.`), or in the curated `abbreviations` const. Internal decimal dots (`3.14`) never reach the terminal check (token does not end in a dot).
  - Note: the SPEC initialism regex `^(\p{L}\.)+\p{L}?\.?$` matches single-letter segments only, so multi-letter forms like `Ph.D.` are intentionally covered via the extensible `abbreviations` const rather than the regex.
  - Interpretation recorded for the ambiguous ellipsis rule: a **trailing** `...`/`…` is treated as a terminal period (ends a sentence unless an abbreviation context); embedded ellipsis (`a...b`) naturally does not, since the token does not end in a dot. The two `Wait...` fixtures differ only on the unpunctuated tail, consistent with this.
- **AC5 pure Dart:** both modules import only `package:unorm_dart` (sanitizer) / nothing (tokenizer); no Flutter imports, no global mutable state, no async I/O — verified by analyze + grep. `abbreviations` is a top-level `const` (immutable), not mutable state.
- **AC4 corpus (Task 4):** `test/fixtures/text/pipeline_cases.json` is the data-driven source of truth (15 cases), run end-to-end through `sanitize → tokenize` by `corpus_test.dart`. Extend the corpus to grow coverage without touching code.
- **Scope discipline:** no pacing/ORP/binary encoding/`WordRecord` (Story 2.2), no chapter flag, no inline protocol magic — `Token` stays bool-flagged and 2.2 maps to `ProtocolKeys.flag*`.

### File List

- `companion/pubspec.yaml` (modified — added `unorm_dart: 0.3.2`)
- `companion/lib/services/import/text_sanitizer.dart` (new)
- `companion/lib/services/import/tokenizer.dart` (new)
- `companion/test/services/import/text_sanitizer_test.dart` (new)
- `companion/test/services/import/tokenizer_test.dart` (new)
- `companion/test/services/import/corpus_test.dart` (new)
- `companion/test/fixtures/text/pipeline_cases.json` (new)

## Change Log

- 2026-06-14 — Implemented Story 2.1 (Tasks 1–5): pure-Dart `text_sanitizer.dart` + `tokenizer.dart` under `companion/lib/services/import/`, abbreviation-aware sentence-end, JSON fixture corpus. Added `unorm_dart: 0.3.2`. All ACs satisfied; `flutter test` 127/127, `flutter analyze` clean. Status → review.
- 2026-06-14 — Code review (Blind Hunter + Edge Case Hunter + Acceptance Auditor); all 5 ACs verified satisfied. Resolved 1 decision + applied 4 patches: (P4/decision, Option 1) terminal-boundary guarantee — `tokenize()` now forces the last token of the text to `sentenceEnd=true` (bake-time equivalent of rsvpnano's `... || atEnd()`; consumer `atEnd()` OR forwarded to Epic 3); (P1) tightened `_dottedInitialism` to `^\p{L}\.(\p{L}\.?)+$` so a single letter+period (`a.`) is no longer suppressed; (P2) `sanitize()` normalizes CR/CRLF→LF so CR-delimited paragraphs are detected; (P3) corrected the fixture `_doc` (raw codepoints, not `\u` escapes). 1 finding deferred (ASCII-fold table is Latin-1-only → deferred-work.md), 3 dismissed as noise. Added 9 tests (4 sanitizer line-ending, 1 single-lowercase-letter lock-in, 2 terminal-boundary, mid-text non-terminal) + 3 fixture cases. `flutter test` 136/136, `flutter analyze` clean. Status → done.

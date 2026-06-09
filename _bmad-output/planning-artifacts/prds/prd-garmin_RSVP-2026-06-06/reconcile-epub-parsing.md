# Reconciliation: EPUB-Parsing Technical Research → PRD + Addendum

**Input:** `_bmad-output/planning-artifacts/research/technical-epub-parsing-flutter-dart-research-2026-06-06.md`
**Targets:** `prd.md`, `addendum.md` (same PRD folder)
**Date:** 2026-06-06

## Method

Read all three in full. Mapped each substantive INPUT claim (package landscape, pipeline, format, timing/ORP, isolates, storage, import, risks) to PRD or addendum coverage. This is a technical research report; most implementation detail correctly lives in the addendum or belongs downstream in architecture. Only items that change requirements, risks, or scope — or that are hard constraints/numbers a document got wrong or omitted — are flagged below. Everything else is recorded as "correctly carried" or "correctly deferred."

## What the documents already carry well

The addendum is a faithful distillation of this report. It carries: epub_pro v5.6.0 + DIY `html` text extraction with epubx fallback (addendum §1); the nested-chapter bug rationale; hand-rolled Unicode tokenization (`\p{L}\p{N}`, `unicode:true`); SQLite-for-metadata / flat-file-for-stream split with isolate parsing returning a path; binary-packed ~9 B/word format and ~0.9 MB / 100k-word figure vs 2.5–4 MB JSONL; the WPM-invariant "bake the bonus not the duration" inversion of RSVP Nano; the pacing percentages (length 6/9/12% with cap 170%, complexity cap 85%, punctuation comma 45% … sentence-end 150%, period 135% w/ abbreviation suppression); the ORP length→ordinal table; chapter chunking 200–500 words, never split a word, sentence/paragraph boundaries, absolute word index header; Readium-as-escape-hatch; recalibration risk for Nano's percentages. PRD carries the user-facing requirements (FR1/2/3/6, FR16/17, FR21, NFR5/7) and risks (R3 chunk ceiling). No action needed on any of these.

## Gaps worth flagging

### GAP 1 — Text-extraction quality hazards are entirely absent (affects FR25 / stream correctness) — MEDIUM
The INPUT's "Text-extraction edge cases & gotchas" section (footnotes/endnotes `<a epub:type="noteref">` and aside note bodies, tables, images-alt, ruby `<rt>`, and the warning that naive `html` `.text` over-includes all of these — Confidence High) appears in neither document. The addendum's parsing row only mentions the nested-chapter bug. These directly determine whether the produced word stream is clean prose or contains "stray words mid-sentence." This is the substance behind FR25 ("never a silently broken book") and the quality of FR16's output. At minimum the DOM pre-filter requirement (drop `script/style/figure/table/rt` and noterefs before extracting `.text`) should be a named architecture constraint, not left to rediscovery.

### GAP 2 — Unicode sanitation requirements not captured (affects stream format / Garmin glyph constraints) — MEDIUM
INPUT specifies concrete pre-tokenization normalization beyond NFC: strip soft hyphen (U+00AD), convert NBSP (U+00A0) to space, drop zero-width chars — "otherwise words gain phantom characters and break ORP indexing." It also notes Garmin fonts may lack glyphs for smart quotes / em-dash / ellipsis, with optional ASCII folding (RSVP Nano's ASCII mode). The addendum's format section mentions neither NFC nor ASCII folding (the brief's RSVP-Nano teardown row doesn't carry it). Since ORP is a precomputed per-word byte index (addendum §2) and the watch uses a custom bitmap font (§4), phantom characters and missing glyphs are correctness bugs against FR1 (stable ORP anchor). Should be a named stream-generation requirement.

### GAP 3 — Long-word handling: research leans the opposite way from the PRD's assumption — LOW/MEDIUM
PRD FR6 `[ASSUMPTION]`: "Scale font down for the outlier word and extend its dwell, rather than splitting words." The INPUT presents this as a genuinely open UX decision and notes "For a watch with a narrow display, splitting words longer than the ORP-display width *may be necessary*; chunk at syllable/hyphenation points and mark continuation flags" (Sprint Reader does intelligent hyphenation). The INPUT also flags it as an open question pending "Fenix 8 text metrics." The PRD has effectively closed an assumption the research keeps open and which may force a *format* change (continuation flags in the per-word stream) if scaling proves insufficient on the 454×454 round display. The assumption is fine as a default, but the format should reserve a continuation flag now, and the open question should be registered.

### GAP 4 — Minor numeric omissions in the pacing model — LOW
Two pacing details from INPUT are absent from the addendum's otherwise-complete percentage list: compound-joiner bonus (hyphen/slash +14% each) and the complexity sub-percentages (syllable groups beyond 2 → +%/group up to +50%; mixed letter+digit +22%; ALL-CAPS +14%). The addendum keeps the category names and the +85% complexity cap, so this is implementation detail that legitimately lives downstream — flagged only for completeness, no action required unless the architecture doc claims to be the authoritative port spec.

## Items correctly deferred (no action)

- Full package comparison table (epub_decoder, epub3, epub_plus, shu_epub-unavailable) — downstream/library-selection detail; the chosen pair + fallback is carried.
- JSONL byte-budget arithmetic, dictionary-dedup tradeoff — downstream.
- OpenSpritz vs Sprint Reader timing comparison — reference material; the chosen model (Nano) is carried.
- isolate API specifics (`Isolate.run` vs `compute`) — architecture-level.
- `.txt`/`.md` ingestion mechanics (`markdown` / `strip_markdown`) — PRD FR21 carries the requirement; mechanism is downstream.
- `file_picker` + `receive_sharing_intent` package names and manifest/Info.plist declarations — FR21 carries import-via-picker-and-share-sheet; package choice is downstream.

## Risk-register check

INPUT "Risks and Open Questions": epub_pro bus-factor (mitigated by DIY + epubx — carried implicitly via §1 fallback), EPUB-in-the-wild variability, BLE/CIQ throughput (= PRD R3 / addendum §3), timing-model subjectivity (= addendum §2 recalibration note), Spritz ORP table provenance (folk-standard), long-word handling (see GAP 3). The two not registered anywhere: **EPUB-in-the-wild variability** (obfuscated/malformed/exotic-encoding/heavy-footnote books needing per-book tuning, untested at scale) — this is the risk behind GAP 1 and arguably belongs as a low/medium risk against FR25; and **long-word handling** (GAP 3). Others are adequately covered.

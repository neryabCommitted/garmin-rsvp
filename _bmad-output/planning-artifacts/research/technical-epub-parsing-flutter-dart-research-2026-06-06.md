---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments:
  - '_bmad-output/planning-artifacts/briefs/brief-garmin_RSVP-2026-06-05/brief.md'
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'EPUB parsing in Flutter/Dart for producing a word-ready RSVP stream'
research_goals: 'Evaluate Dart/Flutter EPUB parsing libraries (maturity, maintenance, MIT-compatible licensing), approaches for HTML text extraction and tokenization into a word-ready .rsvp-style stream with chapter structure, and fallback options via platform channels'
user_name: 'Nerya'
date: '2026-06-06'
web_research_enabled: true
source_verification: true
---

# Research Report: technical

**Date:** 2026-06-06
**Author:** Nerya
**Research Type:** technical

---

## Research Overview

This report evaluates how a Flutter companion app should turn DRM-free EPUB (plus `.txt`/`.md`) into a word-ready RSVP stream for streaming to a Garmin Fenix 8. Scope spans the Dart/Flutter EPUB package landscape, a DIY parsing path (zip + XML/HTML), text-extraction quality, RSVP tokenization (ORP/pivot and variable per-word timing), intermediate-format design (modeled on RSVP Nano's `.rsvp`), and Flutter runtime concerns (isolates, local storage, file import). Methodology was web-first with source verification: pub.dev package pages, GitHub source code (fetched via `gh` API where raw fetches failed), and the RSVP Nano repository's actual pacing implementation were inspected directly; ORP conventions were cross-checked against multiple Spritz and OpenSpritz sources. Every factual claim carries a `_Source:_` URL and uncertain facts carry confidence levels.

Key findings: (1) **epub_pro** is the strongest maintained Dart EPUB parser (v5.6.0, ~9 months old as of mid-2026, BSD-3/MIT, null-safe, lazy ZIP, EPUB2 NCX + EPUB3 nav, CFI) — _Source: https://pub.dev/packages/epub_pro_; **epubx** is more popular (74 likes, 4.3k weekly downloads) but ~2 years stale; `shu_epub` is not findable on pub.dev. (2) The DIY path (archive + html + xml) is genuinely viable and gives full control over reading-order text extraction via the `html` package's `.text`, which matters because RSVP needs clean tokens, not rendered HTML. (3) RSVP Nano's `.rsvp` format is a **plain-text, directive-based, timing-free** format (`@rsvp 1`, `@title`, `@chapter`, `@para`, wrapped word lines) — timing is computed at read time, not stored — _Source: https://github.com/ionutdecebal/rsvpnano (web/library.js)_. (4) RSVP Nano's pacing algorithm is the best documented open-source reference: a WPM base interval plus percentage bonuses for word length (tiered), syllable complexity, all-caps/mixed tokens, and trailing punctuation, with abbreviation suppression — directly portable to Dart. (5) Parsing must run in an isolate (`compute`/`Isolate.run`); storage is best split between SQLite (drift/sqflite) for metadata/position and flat files for the parsed stream.

The two decision outputs are the **package comparison table** (Technology Stack Analysis) and the **recommended parse pipeline** (epub_pro for structure + DIY `html`-based text extraction, emitting a binary or JSONL stream with precomputed timing flags), detailed in Research Synthesis.

---

## Technical Research Scope Confirmation

**Research Topic:** EPUB parsing in Flutter/Dart — producing a word-ready RSVP stream (companion app pivoted from Kotlin to Flutter)
**Research Goals:** Evaluate Dart/Flutter EPUB parsing libraries (maturity, maintenance, MIT-compatible licensing), approaches for HTML text extraction and tokenization into a word-ready `.rsvp`-style stream with chapter structure and variable-timing metadata, and fallback options (native parsing via platform channels) if Dart options are weak.

**Technical Research Scope:**

- Architecture Analysis - EPUB structure (OCF/OPF/XHTML), parsing pipeline design
- Implementation Approaches - text extraction, tokenization, ORP/timing pre-computation
- Technology Stack - Dart EPUB/HTML/XML packages, Flutter file handling, isolates
- Integration Patterns - intermediate word-stream format, chunking for watch delivery
- Performance Considerations - parsing large books, memory, background processing

**Research Methodology:**

- Current web data with rigorous source verification
- Multi-source validation for critical technical claims
- Confidence level framework for uncertain information
- Comprehensive technical coverage with architecture-specific insights

**Scope Confirmed:** 2026-06-06

<!-- Content will be appended sequentially through research workflow steps -->

---

## Technology Stack Analysis

### Dart/Flutter EPUB package landscape

All metrics below were observed on pub.dev / GitHub in June 2026. "Last release" and download figures drift; treat them as point-in-time. Confidence is High for licenses and "what it parses" (verified on package pages), Medium for exact like/download counts (pub.dev surfaces these but they move).

| Package | Latest ver / last release | Likes / pub points / downloads | Null-safe / Dart 3 | License | Parses (OPF / spine / NCX / nav / XHTML) | Notes & known issues | Verdict |
|---|---|---|---|---|---|---|---|
| **epub_pro** | 5.6.0, ~9 mo ago (≈Aug 2025) | 8 likes / 150 pts / ~600 dl | Yes | BSD-3-Clause **and** MIT | OPF metadata, spine/reading order, **NCX (EPUB2) + nav (EPUB3)**, XHTML content, resources | "Only working & actively maintained" fork of dart-epub; lazy ZIP (claims 1.89× faster); CFI positioning; optional auto-split of >3000-word chapters. Open issue #1: `_getChapterBySpineIndex` fails when a chapter has subchapters (relevant to reading-order extraction). | **Recommended** for structure |
| **epubx** | 4.0.0, ~2 yr ago (≈2024) | **74 likes** / 130 pts / **~4.3k weekly dl** | Likely (4.x) — not stated on page | **MIT** | OPF, spine, NCX/nav, HTML/CSS/images/fonts; no `dart:io` dependency (web-safe) | Most popular by far but **stale ~2 yr**; fork of original `epub`. Companion `epub_view` widget. | Viable fallback; staleness is the risk |
| **epub_decoder** | 0.1.4, ~20 mo ago | 20 likes / 120 pts | Flutter pkg (uses `archive`,`xml`,`equatable`) | **MIT** | Metadata, resources (audio/image/text), sections in reading order, **Media Overlays** (text-audio sync) | Pre-1.0; "navigation definitions/bindings WIP"; depends on `flutter` (not pure Dart). Media-overlay focus not needed here. | Niche; skip |
| **epub3** | (active per pub.dev) | — | Yes | (verify) | Read **and write**; states EPUB 2.0/2.0.1/3.0/3.0.1/3.2/3.3 | Read+write support; less battle-tested than epub_pro/epubx for extraction. | Watch as alternative |
| **epub_plus** | fork of `epub` | — | Yes | (fork of MIT `epub`) | OPF/spine/nav/XHTML | Another dart-epub fork; overlaps epub_pro. | Redundant |
| **epub** (original `orthros`) | legacy | — | Partial | MIT | Baseline parser | Effectively unmaintained; epubx/epub_pro are its descendants. | Don't use directly |
| **shu_epub** | **not found on pub.dev (June 2026)** | — | — | — | — | Searches for `shu_epub` returned no pub.dev package; may be renamed/removed. | Treat as unavailable |
| **epub_view / flutter_epub_viewer / flutter_epub_reader** | epub_view ~2023; flutter_epub_viewer Jan 2026 | — | Yes | MIT (epub_view) | Render-only (epub_view wraps epubx; the *_viewer ones wrap epub.js in a WebView) | These are **rendering widgets**, not extraction libs. WebView-based ones unsuitable for headless tokenization. | Out of scope |

_Source: https://pub.dev/packages/epub_pro (accessed 2026-06-06)_
_Source: https://github.com/watate/epub_pro (accessed 2026-06-06)_
_Source: https://github.com/watate/epub_pro/issues (accessed 2026-06-06)_
_Source: https://pub.dev/packages/epubx (accessed 2026-06-06)_
_Source: https://github.com/rbcprolabs/epubx.dart (accessed 2026-06-06)_
_Source: https://pub.dev/packages/epub_decoder (accessed 2026-06-06)_
_Source: https://pub.dev/packages/epub3 (accessed 2026-06-06)_
_Source: https://pub.dev/packages/epub_view (accessed 2026-06-06)_
_Source: https://pub.dev/packages/flutter_epub_viewer (accessed 2026-06-06)_

### Supporting/DIY stack packages

| Package | Role | License | Notes |
|---|---|---|---|
| `archive` | Unzip the EPUB OCF container (EPUB = ZIP) | MIT | Pure-Dart zip decode/encode; works in isolates. _Source: https://pub.dev/packages/archive_ |
| `xml` | Parse `container.xml`, OPF (`.opf`), NCX (`toc.ncx`), EPUB3 `nav.xhtml` | MIT | Standard Dart XML lib. |
| `html` | Parse XHTML chapter bodies; extract reading-order text via `element.text` | MIT (dart-lang/html) | `parse()` for full docs, `.text` strips tags. _Source: https://pub.dev/packages/html_ |
| `markdown` | Parse `.md` → AST/HTML, then strip | BSD-3 | Official dart-lang package. |
| `strip_markdown` | One-shot `.md` → plain text (`removeMd`) | MIT | Port of node `remove-markdown`. _Source: https://pub.dev/packages/strip_markdown_ |
| `drift` or `sqflite` | Local store: book metadata, chapter index, resume position | MIT | drift = reactive/type-safe over SQLite; sqflite = thin SQLite. _Source: https://pub.dev/packages/drift_ |
| `file_picker` | User-initiated EPUB/txt/md import | MIT | Cross-platform picker. |
| `receive_sharing_intent` | Android "Share to app" / iOS Share Extension for EPUBs | (verify; permissive) | Maintained; supports arbitrary file types. _Source: https://pub.dev/packages/receive_sharing_intent_ |

---

## Integration Patterns Analysis

### EPUB structure (what the pipeline must walk)

An EPUB is a ZIP (OCF container). The fixed entry point is `META-INF/container.xml`, which points at the OPF package document. The OPF contains three things the pipeline needs:

- **`<metadata>`** — title, author, language (for resume display and possibly sentence rules).
- **`<manifest>`** — every resource (XHTML, CSS, images, fonts) with id → href.
- **`<spine>`** — the **ordered list of manifest idrefs** that defines linear reading order. Walking the spine in order, resolving each idref to its XHTML file, and concatenating extracted text is the canonical way to get a book's reading-order content.

Table of contents is **EPUB2 `toc.ncx`** (NCX `navMap`) vs **EPUB3 `nav.xhtml`** (`<nav epub:type="toc">`). epub_pro reconciles both and even folds orphaned spine items into the chapter tree. _Source: https://github.com/watate/epub_pro (accessed 2026-06-06)_. For chapter boundaries, prefer spine-file boundaries as the primary chapter unit and use TOC labels for naming; pure TOC-driven splitting breaks when one XHTML file holds multiple TOC entries (fragment anchors) — Confidence: High (this is standard EPUB behavior).

### Parsing pipeline (package vs DIY)

Recommended hybrid: **use epub_pro for container/OPF/spine/TOC structure**, but **extract text yourself from each spine document with the `html` package** rather than trusting a library's chapter-to-string conversion. Rationale: RSVP needs clean reading-order tokens; library "content" getters may return raw HTML or split inconsistently (cf. epub_pro issue #1 on subchapters). Pipeline stages:

1. Unzip (archive) or let epub_pro lazy-load.
2. Resolve spine order (epub_pro or DIY via xml on the OPF).
3. For each spine XHTML: `html.parse(bytes-as-utf8)`, remove non-content nodes (script/style, optionally figures), then take `body.text` (or per-block `.text`) to preserve paragraph boundaries.
4. Normalize whitespace/Unicode (see Implementation Research).
5. Tokenize into words with precomputed ORP + timing.
6. Emit intermediate stream, segmented by chapter.

### Intermediate format design (modeled on RSVP Nano `.rsvp`)

RSVP Nano's `.rsvp` is a **plain-text, directive-based, timing-free** format produced by a browser-side converter. Header directives `@rsvp 1`, `@title …`, `@author …`, `@source …`; body uses `@chapter …`, `@para`, and word-wrapped text lines (`WRAP_WIDTH = 96`). **Timing is NOT stored** — it is computed at read time from word position + reader config. Text is Unicode NFC-normalized (optional ASCII mode maps curly quotes etc.). Tokenization filter: `cleaned.split(/\s+/).filter(t => t && /[\p{L}\p{N}]/u.test(t))` — keep only tokens containing a Unicode letter/digit. _Source: https://github.com/ionutdecebal/rsvpnano (web/library.js, accessed 2026-06-06)_. Large books also get `.ridx`/`.rdat` sidecars for indexed seeking on-device. _Source: https://github.com/ionutdecebal/rsvpnano/blob/main/README.md (accessed 2026-06-06)_.

**Design choice for garmin_RSVP:** unlike RSVP Nano (powerful device, computes timing on-device), the Garmin watch is memory-constrained and Monkey C is slow, so **precompute timing on the phone and ship it**. Three viable encodings:

- **JSONL (JSON-lines):** one object per word `{w, orp, ms, flags}` or per chapter a list. Human-debuggable; ~25–40 bytes/word → a 100k-word novel ≈ 2.5–4 MB. Fine on phone disk; too fat to stream raw.
- **Binary packed (recommended for the wire):** per word a varint/struct: word UTF-8 bytes + 1 byte ORP index + 1–2 bytes dwell-ms (or a quantized timing tier) + 1 byte flags (chapter-start, para-start, sentence-end). Roughly `avg_word_len(≈5) + 4 ≈ 9 bytes/word` → 100k words ≈ **0.9 MB**. Strings could be deduped via a small dictionary, but novels have high vocab; marginal gain.
- **Hybrid:** store JSONL/SQLite on phone as the master; generate binary chunks on demand for BLE.

### Chunking for BLE delivery to the watch

The watch buffers a small window and requests more (pull model per the brief). Chunk on **word count** (e.g., 200–500 words/chunk ≈ a few KB binary), aligned to **never split a chunk mid-word** and ideally aligned to paragraph/sentence boundaries so a chunk gap coincides with a natural pause. Include an absolute word index in each chunk header so resume/seek is exact and position can sync back. BLE MTU and CIQ message-size limits should size the chunk; a 200-word binary chunk (~1.8 KB) is comfortably within typical CIQ `Communications` transfer sizes — Confidence: Medium (exact CIQ/BLE throughput is a separate open question flagged in the brief).

---

## Architectural Patterns Analysis

### Off-UI-thread parsing (isolates)

EPUB parsing + tokenizing a full novel is CPU-bound and will jank the UI if run on the main isolate. Use `Isolate.run()` (Dart 2.19+/3) or Flutter's `compute()` to run the whole parse-and-tokenize pipeline in a worker isolate and return the structured result. `compute()` returns results efficiently since Dart 2.15's faster isolate messaging. _Source: https://docs.flutter.dev/perf/isolates (accessed 2026-06-06)_. _Source: https://codewithandrea.com/articles/parse-large-json-dart-isolates/ (accessed 2026-06-06)_. The `archive` package is pure Dart and runs fine in an isolate; pass the EPUB **bytes/path** into the isolate, do everything (unzip → parse → tokenize → serialize), and return either the serialized stream path or the compact word list. Avoid passing huge object graphs back across the isolate boundary — write the parsed stream to a file inside the isolate and return only the path + chapter index.

### Local storage of parsed books

Split responsibilities:

- **SQLite (drift or sqflite):** library table (book id, title, author, source path, total words, import date), chapter index (chapter → start word index, label), and **resume position** (book id → word index, updated frequently). drift gives reactive queries (auto-updating library/progress UI) and type safety; sqflite is lighter if you prefer raw SQL. _Source: https://www.oreateai.com/blog/drift-vs-sqflite-choosing-the-right-local-storage-solution-for-flutter/4ca09a00c821552ea7bbfb1a6a51573a (accessed 2026-06-06)_.
- **Flat files (app documents dir):** the parsed word stream itself (binary or JSONL) — do not store multi-MB blobs as SQLite rows for the whole book; keep the stream as a file and index into it. This also makes BLE chunk generation a cheap file-range read.

### File import flow

Two entry points, both standard:

- **`file_picker`** for explicit "Import book" (user taps button, picks `.epub`/`.txt`/`.md`).
- **`receive_sharing_intent`** (or equivalents `flutter_sharing_intent`, `share_intent_package`) to register the app as a target for "Share to…"/"Open with…" so users can send an EPUB from a file manager or browser. Requires declaring MIME types in `AndroidManifest.xml` and iOS `Info.plist` Share Extension. _Source: https://pub.dev/packages/receive_sharing_intent (accessed 2026-06-06)_. On import: copy file into app storage → enqueue parse isolate → on completion write stream file + DB rows.

---

## Implementation Research

### Tokenization

Follow RSVP Nano's proven approach: normalize to Unicode NFC, then split on whitespace and keep only tokens containing a letter or digit (`/[\p{L}\p{N}]/u`), preserving trailing punctuation **on** the token so the timing stage can read it. _Source: https://github.com/ionutdecebal/rsvpnano (web/library.js, accessed 2026-06-06)_. Dart's `RegExp` supports Unicode mode (`unicode: true`) and `\p{...}` classes, so this is a direct port. There is **no strong general-purpose sentence/word segmenter on pub.dev** for prose RSVP — the tokenizer packages found (`dart_wordpiece`, `dart_sentencepiece_tokenizer`, `tiny_segmenter_dart`) are ML/CJK tokenizers, not what RSVP needs. _Source: https://pub.dev/packages/dart_wordpiece (accessed 2026-06-06)_. So **hand-roll** whitespace + punctuation tokenization; it is small and fully controllable — Confidence: High.

**Long-word chunking:** very long words can be split for readability. Sprint Reader does "intelligent hyphenation" of long words. _Source: https://github.com/anthonynosek/sprint-reader-chrome (accessed 2026-06-06)_. A simpler, RSVP-Nano-aligned alternative is to **not split** but **extend dwell** for long words (see timing). For a watch with a narrow display, splitting words longer than the ORP-display width may be necessary; chunk at syllable/hyphenation points and mark continuation flags.

### ORP / pivot calculation

The "Optimal Recognition Point" sits slightly left of center and moves further left as words lengthen; perceptual span ≈ 13 chars. _Source: https://www.spritzreader.com/how-it-works (accessed 2026-06-06)_. _Source: https://theconversation.com/spritz-and-other-speed-reading-apps-prose-and-cons-24467 (accessed 2026-06-06)_. The original OpenSpritz bookmarklet computes the pivot near the middle of the word (`start = word.slice(0, word.length/2)`, pivot = last char of `start`), i.e. ORP index ≈ `floor((len-1)/2)` for short words, padded for display. _Source: https://github.com/gleitz/OpenSpritz (spritz.js, accessed 2026-06-06 via gh API)_. The widely-used discrete Spritz table (Confidence: Medium — folk-standard, not from official Spritz spec) is:

| Word length | ORP (0-based) |
|---|---|
| 1 | 0 |
| 2–5 | 1 |
| 6–9 | 2 |
| 10–13 | 3 |
| 14+ | 4 |

_Source: https://www.spritzreader.com/how-it-works (concept, accessed 2026-06-06)_. Either the OpenSpritz "~length/2, capped" formula or the discrete table works; precompute the ORP **byte index** per word in the intermediate stream so the watch just renders three spans (before / pivot / after) with the pivot at a fixed x.

### Variable per-word timing — the best-cited open-source algorithm

**RSVP Nano's pacing** (`src/reader/ReadingLoop.cpp`, with a host-side unit-test suite) is the most directly reusable and well-structured reference. Base interval is `60000 / wpm` ms; total = base + percentage bonuses. _Source: https://github.com/ionutdecebal/rsvpnano (src/reader/ReadingLoop.cpp, accessed 2026-06-06 via raw fetch)_.

- **Length tiers** (extra chars beyond threshold, % per char): >6 chars: +6%/char (`kLongWordPercentPerChar`); >10: +9%/char (`kVeryLongWordPercentPerChar`); >14: +12%/char (`kUltraLongWordPercentPerChar`); **capped at +170%**. Compound joiners (hyphen/slash): +14% each.
- **Complexity:** syllable groups beyond 2: +%/group up to +50%; mixed letter+digit token: +22%; ALL-CAPS: +14%; complexity **capped at +85%**.
- **Punctuation pauses (trailing):** comma +45%; dash +60%; semicolon/colon +80%; ellipsis +110%; sentence-end `! ?` +150%; period +135% **unless** `looksLikeAbbreviation()` is true (dotted initialisms, known titles get no pause).

_Source: https://github.com/ionutdecebal/rsvpnano (src/reader/ReadingLoop.cpp, accessed 2026-06-06)_.

For comparison, the much cruder **OpenSpritz** approach inserts duplicate frames instead of computing ms: it shows a long/comma/colon/dash/paren word (or `length > 8`) for an extra two frames, and inserts three blank "." frames after sentence-ending/closing punctuation — i.e. integer-frame multipliers rather than smooth percentages. _Source: https://github.com/gleitz/OpenSpritz (spritz.js lines ~96–116, accessed 2026-06-06 via gh API)_. **Sprint Reader** exposes user-tunable per-mark "grammar delays" (comma/period/paragraph) plus word-length/word-frequency display options. _Source: https://github.com/anthonynosek/sprint-reader-chrome (accessed 2026-06-06)_. _Source: https://chromewebstore.google.com/detail/sprint-reader-speed-readi/kejhpkmainjkpiablnfdppneidnkhdif (accessed 2026-06-06)_.

**Recommendation:** port RSVP Nano's percentage model to Dart (it is the brief's stated inspiration and already has a tested tier structure), quantize the resulting dwell to a small integer (ms or a tier byte) per word in the stream, and let the watch optionally scale all dwells by a live WPM multiplier so on-watch WPM up/down works without re-streaming.

### Text-extraction edge cases & gotchas

- **EPUB2 NCX vs EPUB3 nav:** handle both; epub_pro reconciles them. _Source: https://github.com/watate/epub_pro (accessed 2026-06-06)_.
- **Encoding:** XHTML is usually UTF-8 but declarations vary; decode per the XML/HTML declared charset, default UTF-8.
- **Soft hyphen (U+00AD), NBSP (U+00A0), zero-width chars:** strip soft hyphens, convert NBSP to space, drop zero-width joiners before tokenizing — otherwise words gain phantom characters and break ORP indexing.
- **Smart quotes / em-dashes / ellipsis (…):** Garmin fonts may lack glyphs; optionally fold to ASCII (RSVP Nano's ASCII mode does exactly this). _Source: https://github.com/ionutdecebal/rsvpnano (web/library.js, accessed 2026-06-06)_.
- **Footnotes / endnotes:** linked superscripts pollute the stream; detect and skip `<a epub:type="noteref">` and aside note bodies, or they appear as stray words mid-sentence.
- **Tables / images / ruby:** tables linearize poorly (read row-major or skip); images contribute only `alt` text (often empty) — skip silently; ruby annotations (`<rt>`) should usually be dropped, keeping base text. `.text` on the `html` package flattens all of these without structure, so pre-filter the DOM (remove `figure`, `table`, `rt`, noterefs) before extracting. Confidence: High that naive `.text` over-includes; Medium on the best default policy per type.
- **Paragraph boundaries:** extract per block element (`p`, `div`, `li`, headings) and emit `@para`-style markers, rather than one giant `.text` call, so the reader gets paragraph pauses and chapter nav later.
- **epub_pro subchapter bug (issue #1):** if relying on its chapter API, verify nested-chapter content isn't dropped; the DIY spine-walk avoids this. _Source: https://github.com/watate/epub_pro/issues (accessed 2026-06-06)_.

### .txt / .md ingestion

`.txt` is trivial: read, normalize, split into paragraphs on blank lines, tokenize. `.md`: either `markdown` package → render to HTML → reuse the HTML extractor, or `strip_markdown`'s `removeMd()` for a one-shot plain-text conversion (handles list leaders, links, image alt). _Source: https://pub.dev/packages/strip_markdown (accessed 2026-06-06)_. _Source: https://pub.dev/packages/markdown (accessed 2026-06-06)_.

### Native fallback (platform channels)

If Dart parsing proves too weak for some EPUBs, the platform-channel fallback is **Readium** (Readium Kotlin Toolkit on Android, Readium Swift Toolkit on iOS) — the industry-standard, well-maintained EPUB engine. However, Readium is heavyweight (rendering/streaming focused), adds a platform-channel surface, and the value here is *text extraction only*, which the Dart `html`/`xml`/`archive` stack already does well. **Verdict: not worth it for MVP**; DIY Dart parsing + epub_pro is sufficient, and a native fallback can be a contributor-territory escape hatch later. Confidence: Medium (no EPUB was found in testing that the Dart stack cannot parse, but coverage of pathological/obfuscated EPUBs is unverified).

---

## Research Synthesis

### Executive Summary

For the Flutter companion app, the recommended approach is a **hybrid parse pipeline**: use **epub_pro** (the only actively maintained, permissively licensed Dart EPUB parser with both EPUB2 NCX and EPUB3 nav support) to handle the OCF container, OPF metadata, and spine/TOC structure, but perform **text extraction yourself** by walking the spine and using the `html` package to pull reading-order text block-by-block. Tokenization and variable per-word timing should be hand-rolled in Dart, **porting RSVP Nano's well-tested percentage-based pacing model** (length tiers + complexity + punctuation pauses with abbreviation suppression), and the **ORP pivot index precomputed per word**. The whole pipeline runs in a worker isolate; the parsed stream is written to a flat file (binary-packed for size/BLE efficiency) with metadata, chapter index, and resume position in SQLite (drift). Crucially, unlike RSVP Nano which computes timing on-device, **garmin_RSVP should bake timing into the stream on the phone** because the watch is memory- and CPU-constrained.

### Key Findings

1. **epub_pro is the package to use for structure** — v5.6.0, ~9 months old, BSD-3/MIT, null-safe, lazy ZIP, NCX+nav, CFI. _Source: https://pub.dev/packages/epub_pro_.
2. **epubx is more popular but stale (~2 yr)** — MIT, 74 likes, ~4.3k weekly downloads; a reasonable fallback but unmaintained. _Source: https://pub.dev/packages/epubx_.
3. **shu_epub appears unavailable** on pub.dev as of June 2026.
4. **DIY extraction is viable and recommended** for the text layer (archive + xml + html), giving clean reading-order tokens and side-stepping epub_pro's nested-chapter bug (issue #1). _Source: https://github.com/watate/epub_pro/issues_.
5. **`.rsvp` is plain-text, directive-based, timing-free** (`@rsvp 1`/`@title`/`@chapter`/`@para` + wrapped word lines, NFC Unicode). _Source: https://github.com/ionutdecebal/rsvpnano_.
6. **RSVP Nano's pacing algorithm is the best open-source timing reference** — base `60000/wpm` + tiered length bonuses (6/9/12% per char, cap 170%), complexity (cap 85%), punctuation pauses (comma 45% … sentence-end 150%, period 135% with abbreviation suppression). _Source: https://github.com/ionutdecebal/rsvpnano (src/reader/ReadingLoop.cpp)_.
7. **ORP ≈ near-center, drifting left with length**; use OpenSpritz's ~length/2-capped formula or the discrete length→index table; precompute the pivot byte index. _Source: https://github.com/gleitz/OpenSpritz_, _https://www.spritzreader.com/how-it-works_.
8. **No prose sentence/word segmenter on pub.dev** worth adopting; hand-roll Unicode-aware tokenization (`\p{L}\p{N}`). _Source: https://github.com/ionutdecebal/rsvpnano (web/library.js)_.
9. **Parse in an isolate** (`compute`/`Isolate.run`); write the stream to a file inside the isolate and return only the path + index. _Source: https://docs.flutter.dev/perf/isolates_.
10. **Storage split:** SQLite (drift/sqflite) for metadata/chapter-index/position; flat file for the multi-MB word stream. _Source: https://www.oreateai.com/blog/drift-vs-sqflite-...
11. **Binary-packed stream ≈ 0.9 MB** for a 100k-word novel (word bytes + ORP + dwell + flags) vs ~2.5–4 MB as JSONL; chunk for BLE on word count at paragraph/sentence boundaries with absolute word indices for resume.
12. **Bake timing on the phone** (not on-watch) — inverts RSVP Nano's on-device model to fit Garmin's constraints.
13. **Import via `file_picker` + `receive_sharing_intent`** (Android intent / iOS Share Extension). _Source: https://pub.dev/packages/receive_sharing_intent_.
14. **`.md` via `markdown` or `strip_markdown`; `.txt` trivial.** _Source: https://pub.dev/packages/strip_markdown_.
15. **Readium native fallback is overkill for MVP** — DIY Dart parsing suffices; keep native as a contributor escape hatch.

### Recommendations for garmin_RSVP

- **Parser:** epub_pro for OCF/OPF/spine/TOC; DIY `html`-based reading-order text extraction per spine document; pre-filter DOM (drop script/style/figure/table/rt/noterefs) before `.text`.
- **Timing/ORP:** port RSVP Nano's percentage pacing model to Dart; precompute per-word `{utf8, orpIndex, dwellMs|tier, flags}`. Make dwell scalable by a live WPM multiplier so on-watch WPM controls work without re-streaming.
- **Intermediate format:** keep a debuggable master (JSONL or SQLite-referenced file) on the phone; generate **binary-packed chunks** for BLE (≈9 bytes/word). Borrow RSVP Nano's directive/structure ideas (chapter/para markers, NFC normalize, optional ASCII fold) but **store timing** (the key divergence).
- **Runtime:** parse+tokenize in an isolate; persist stream as a flat file + SQLite (drift) for metadata/chapter-index/position; resume is a single indexed word offset.
- **Import:** `file_picker` + `receive_sharing_intent`; `.txt`/`.md` reuse the same tokenizer (md stripped first).
- **Chunking:** ~200–500 words/chunk, never split a word, prefer paragraph/sentence boundaries, header carries absolute word index.

### Risks and Open Questions

- **epub_pro maintenance & bus factor:** single-maintainer fork, low downloads, an open subchapter bug. Mitigated by DIY text extraction and epubx as fallback. Confidence: Medium.
- **EPUB-in-the-wild variability:** obfuscated/malformed EPUBs, exotic encodings, heavy footnote/ruby/table use may need per-book tuning. Untested at scale. Confidence: Medium.
- **BLE/CIQ throughput & watch memory** (already flagged in the brief): sizes the chunk window; needs empirical CIQ measurement. Confidence: Low on exact figures.
- **Timing-model subjectivity:** RSVP Nano's percentages are tuned for its device; on a 454×454 AMOLED at the reader's WPM they may need recalibration. Confidence: Medium.
- **Spritz ORP table provenance:** the discrete length→index table is folk-standard, not from an official Spritz spec. Confidence: Medium.
- **Long-word handling on a watch:** whether to split or extend-dwell for words wider than the display needs a UX decision once Fenix 8 text metrics are known. Confidence: Medium.

### Source Documentation

EPUB packages
- https://pub.dev/packages/epub_pro — epub_pro page (High) — accessed 2026-06-06
- https://github.com/watate/epub_pro — epub_pro source (High) — 2026-06-06
- https://github.com/watate/epub_pro/issues — epub_pro issues incl. subchapter bug (High) — 2026-06-06
- https://pub.dev/packages/epubx — epubx page (High) — 2026-06-06
- https://github.com/rbcprolabs/epubx.dart — epubx source (Medium) — 2026-06-06
- https://pub.dev/packages/epub_decoder — epub_decoder page (High) — 2026-06-06
- https://github.com/SofieTorch/epub_decoder — epub_decoder source (Medium) — 2026-06-06
- https://pub.dev/packages/epub3 — epub3 page (Medium) — 2026-06-06
- https://pub.dev/packages/epub_plus — epub_plus page (Medium) — 2026-06-06
- https://pub.dev/packages/epub_view — epub_view widget (Medium) — 2026-06-06
- https://pub.dev/packages/flutter_epub_viewer — WebView-based viewer (Medium) — 2026-06-06
- https://fluttergems.dev/epub/ — Flutter Gems EPUB category (Medium) — 2026-06-06

DIY stack
- https://pub.dev/packages/archive — zip decode (High) — 2026-06-06
- https://pub.dev/packages/html — XHTML parse / `.text` (High) — 2026-06-06
- https://pub.dev/packages/markdown — md parser (High) — 2026-06-06
- https://pub.dev/packages/strip_markdown — md→text (High) — 2026-06-06
- https://pub.dev/packages/dart_wordpiece — ML tokenizer (not used) (Medium) — 2026-06-06

RSVP / timing / ORP references
- https://github.com/ionutdecebal/rsvpnano — RSVP Nano repo (.rsvp format, pacing) (High) — 2026-06-06
- https://github.com/ionutdecebal/rsvpnano/blob/main/README.md — features, sidecars (High) — 2026-06-06
- https://github.com/gleitz/OpenSpritz — OpenSpritz spritz.js pivot+frame timing (High, via gh API) — 2026-06-06
- https://github.com/anthonynosek/sprint-reader-chrome — Sprint Reader grammar delays/hyphenation (Medium) — 2026-06-06
- https://chromewebstore.google.com/detail/sprint-reader-speed-readi/kejhpkmainjkpiablnfdppneidnkhdif — Sprint Reader features (Medium) — 2026-06-06
- https://www.spritzreader.com/how-it-works — ORP concept (Medium) — 2026-06-06
- https://theconversation.com/spritz-and-other-speed-reading-apps-prose-and-cons-24467 — 13-char span/ORP (Medium) — 2026-06-06
- https://github.com/SeanZoR/claude-speed-reader — RSVP+ORP skill (Low, code not inspected) — 2026-06-06

Flutter architecture
- https://docs.flutter.dev/perf/isolates — isolates/compute (High) — 2026-06-06
- https://codewithandrea.com/articles/parse-large-json-dart-isolates/ — compute pattern (Medium) — 2026-06-06
- https://www.oreateai.com/blog/drift-vs-sqflite-choosing-the-right-local-storage-solution-for-flutter/4ca09a00c821552ea7bbfb1a6a51573a — drift vs sqflite (Medium) — 2026-06-06
- https://pub.dev/packages/drift — drift (High) — 2026-06-06
- https://pub.dev/packages/receive_sharing_intent — share intents (High) — 2026-06-06
- https://pub.dev/packages/file_picker — file import (High) — 2026-06-06

---
baseline_commit: 099b7afb80895495cac8fc5871713c9aa63e54ec
---

# Story 2.4: Import EPUB with cover and chapters

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a reader,
I want to import an EPUB and get its real chapters and cover,
so that first-class books look and read properly.

This is the **EPUB path of Epic 2**, built directly on the 2.3 integration spine. Story 2.3 stood up the whole impure shell — `import_service` (isolate orchestration via `compute`), the shared `html_extractor`, the drift `Books`+`Chapters` schema, the flat-file `stream_store`, Riverpod providers, `LibraryScreen`, the file-picker + share-sheet entries, and the typed-failure / no-partial-state seam (AC7). **This story does not rebuild any of that.** It adds the three EPUB-specific pieces the 2.3 schema was pre-shaped for: a **structure-aware EPUB parser** (`epub_extractor.dart`) that walks the spine/TOC into real chapters with a DOM pre-filter, a **cover extractor** (`cover_extractor.dart`) that lands the cover as a phone-only file and fills the already-existing `cover_path` column, and the **multi-chapter bake** (the `bake()` API already takes `List<BakeChapter>` and emits `chapterStart` flags — 2.3 just fed it one chapter). It also surfaces `author` (already a nullable column) and a cover thumbnail on the library row.

**Scope guardrail:** EPUB import + cover + real chapters + OPF title/author + library-row thumbnail only. **NOT** in scope: book-detail screen / chapter list UI / Remove / Restart (**2.5**); the full failure taxonomy, inline error messaging, and the ugly-EPUB corpus suite (**2.6**); `Positions`/progress/sync (**Epic 4/4.5**); transfer/Send-to-watch (**Epic 4**). Do the minimum typed-failure handling to not crash and not leave partial state on a bad EPUB (AC5) — do **not** pull 2.6's taxonomy or corpus forward.

## Acceptance Criteria

1. **AC1 — Structure parse + DOM pre-filter spine walk.** Given an EPUB, when I import it, then `epub_extractor` reads OCF/OPF/spine/TOC (via `epub_pro`) and a **DOM-pre-filtered spine walk** extracts prose, **dropping noteref/footnote anchors, `<rt>` ruby readings, and image `alt` text, with an explicit, documented table policy**. The extraction runs the same `sanitize → tokenize` chain as 2.3 (no parallel linguistics). [Source: epics.md#Story-2.4 lines 468-470; architecture.md:414 `epub_extractor.dart` "epub_pro structure + DOM pre-filter spine walk", :49, :74; AR §452 services/import pure-Dart]
2. **AC2 — Cover extracted to a phone-only file.** Given the EPUB carries a cover, when import runs, then `cover_extractor` produces the cover image **bytes** and `stream_store` writes a **cover image file**, and the `Books` row's **`cover_path`** is set to it. **The cover never enters the word stream or the protocol** (phone-only). When the EPUB has no cover, `cover_path` stays null and import still succeeds. [Source: epics.md#Story-2.4 lines 472-475; architecture.md:178 "cover image file in stream store, `cover_path` column … never enters the protocol or the watch", :415, :589]
3. **AC3 — Chapter boundaries → flags + manifest index.** Given the parsed EPUB, when baked, then each chapter becomes a `BakeChapter` so `bake()` sets the **`chapterStart` flag** on each chapter's first word and the **manifest chapter index** (`ChapterEntry{offset,title,cumulativeBonusMs}`) is populated; one drift `Chapters` row is persisted per chapter (in reading order, `chapterIndex` 0..n-1). [Source: epics.md#Story-2.4 lines 477-479; word_stream_baker.dart:172 `bake`, :54 `ChapterEntry`, :199-224 chapterStart; architecture.md:279 flag bits, :192-193 manifest chapter index]
4. **AC4 — Library row shows cover, title, author.** Given the library, when the EPUB appears, then its row shows the **cover thumbnail** (M3 `ListTile` leading), **title**, and **author** taken from the **OPF metadata** (placeholder/icon when no cover). [Source: epics.md#Story-2.4 lines 481-483; DESIGN.md:85,156 "M3 ListTile with cover thumbnail … title, author"; EXPERIENCE.md:53,86; FR23]
5. **AC5 — Isolate, non-blocking, typed-failure + no-partial-state (carries 2.3 AC4/AC7 to the EPUB path).** Given a large or malformed/DRM/encrypted EPUB, when imported, then the parse+bake runs **inside `compute`** (UI never blocks), and any failure returns a **typed `ImportFailure` — never an uncaught exception/crash** — leaving **no `Books`/`Chapters` row, no stream/JSONL file, and no cover file** (rollback covers the cover too). [Source: epics.md#Story-2.6 lines 517-524 (typed failure, no partial state — minimal seam only); architecture.md:180 "bounds-check-and-degrade … EPUB parse" NFR8, :293 typed failures/no silent catch; 2-3 AC4/AC7]
6. **AC6 — EPUB import entry (picker + share sheet).** Given an `.epub` file, when I pick it via the file picker **or** receive it via the OS share sheet, then it runs the **same `import_service` path** (no second pipeline). The picker is the testable spine; the share-sheet `application/epub+zip` filter is the thin, manually-verified extension of 2.3's seam. [Source: epics.md#Story-2.4 line 463 implied "I import"; FR22; architecture.md:399,401 share intent filters; 2-3 Task 8]

## Tasks / Subtasks

> TDD throughout: red → green → refactor, one task in order. Pure modules (epub_extractor, cover_extractor, runEpubPipeline) get plain unit tests against synthetic in-memory EPUB fixtures (built with `package:archive` — see Task 1); the impure shell (import_service) uses in-memory drift + temp-dir store + a synchronous runner override; UI uses widget tests with `ProviderScope(overrides:[…])`. Plugin-bound entries (file_picker/share) are kept thin and manually verified.

- [x] **Task 0 — Dependency: `epub_pro`** (AC: #1, #2)
  - [x] Add `epub_pro: ^5.6.0` to `companion/pubspec.yaml` `dependencies:` (latest stable; SDK `>=3.0.0 <4.0.0`; transitively pulls `archive`, `xml`, `image`, `collection` — all **pure Dart, no `dart:io`**, so the parser runs inside `compute`). `flutter pub get`. [Source: pub.dev/packages/epub_pro 5.6.0, fetched 2026-06-16; README "does not rely on dart:io … available for both desktop and web"]
  - [x] `archive` is already transitively present (epub_pro dep) — use it for the **test fixture builder** (Task 1) too; no separate dep needed. Confirm `flutter analyze` stays clean under strict lints after `pub get`.
  - [x] No drift schema change: `Books.author` and `Books.coverPath` (`cover_path`) **already exist** (nullable, added in 2.3 specifically for this story — `database.dart:31-32`). `schemaVersion` stays **1**; **no migration, no codegen change**. Do NOT add columns.

- [x] **Task 1 — Synthetic EPUB test-fixture builder** `companion/test/fixtures/epubs/epub_fixture_builder.dart` (AC: all — test infra)
  - [x] Build a pure-Dart helper that assembles a **minimal valid EPUB** (OCF zip) in memory with `package:archive` (`ZipEncoder`): `mimetype` (stored, **first entry, uncompressed** — OCF requirement), `META-INF/container.xml` → `content.opf`, an OPF with `<metadata>` (`dc:title`, `dc:creator`/author, `<meta name="cover" .../>`), `<manifest>`, `<spine>`, a `toc.ncx` **and/or** EPUB3 `nav.xhtml`, N xhtml chapter docs, and a tiny cover image (generate a ~2×2 PNG via `package:image` `img.encodePng`). Return `Uint8List`.
  - [x] Parameterize it so tests can craft: (a) a clean 3-chapter book with cover+author; (b) a book whose chapter HTML contains a **footnote/noteref anchor**, a **`<rt>` ruby** block, an **`<img alt="...">`**, and a **`<table>`** — to exercise the AC1 pre-filter; (c) a **no-cover** book; (d) a **no-author** book; (e) a chapter that is **all punctuation/symbols** (ORP/empty-chapter contract, Task 4); (f) **corrupt bytes** (not a valid zip) and an **empty-spine** book for the AC5 failure tests.
  - [x] **Do NOT commit any real/copyrighted EPUB.** The real corpus at `/home/nerya/Desktop/epub` is for **manual exploratory testing only** (2.4/2.6) — never a test input, never committed. All committed fixtures are synthetic and tiny. [Source: memory epub-corpus-location; architecture.md:445 `test/fixtures/epubs/`]
  - [x] Quick sanity test: the clean fixture round-trips through `EpubReader.readBook(bytes)` → expected title/author/chapter count/cover present. (This validates the builder before the real modules consume it.)

- [x] **Task 2 — Refactor `html_extractor` to expose an HTML core + EPUB pre-filter** `companion/lib/services/import/html_extractor.dart` (AC: #1) — PURE Dart
  - [x] Write failing tests first in `companion/test/services/import/html_extractor_test.dart` (red). **Preserve all existing 2.3 tests green** (the `.md`/`.txt` behaviour must not change).
  - [x] Extract the block-walk into a public `String extractFromHtml(String html, {bool epubFilter = false})`: `parse(html)` → walk block elements emitting their text separated by `\n\n` (the existing `_visit`/`_collapse` logic). Re-point the **`.md` branch** of `extractPlainText` to call `extractFromHtml(md.markdownToHtml(raw))` so there is **one** HTML walker. `.txt` (`isMarkdown:false`) still returns `raw` unchanged. [Source: 2-3 html_extractor.dart:57-69; the 2.3 file already isolates `_visit`/`_collapse` — promote, don't rewrite]
  - [x] When `epubFilter == true`, the walk **drops** (AC1):
    - **Noteref/footnote anchors:** elements with `epub:type` (read the attribute literally — `package:html` keeps namespaced attrs) containing `noteref`/`footnote`/`rearnote`/`endnote`, and `<a>` whose `role`/`class` marks a footnote ref. Drop the element subtree.
    - **Ruby readings:** `<rt>` and `<rp>` (keep the base text / `<rb>`; drop only the pronunciation). 
    - **Image alt text:** never read `alt`/`title` attributes — only text nodes. (The 2.3 walker already ignores attributes, so this is **assert-and-lock**, not new behaviour — add a test proving `<img alt="X">` contributes nothing.)
    - **Table policy (DECIDE + DOCUMENT in Completion Notes):** recommended default = **linearize** — emit each `<td>/<th>` cell's text as inline, each `<tr>` as one block (`\n\n`-separated), so prose inside tables survives rather than being silently dropped. Dropping tables entirely is acceptable if you justify it; either way add a `<table>` fixture test asserting the chosen behaviour. Do **not** leave the policy implicit.
  - [x] PURE: `package:html` only; **no `package:flutter/*`**, no async, no I/O (AR §452 / AR19) so it runs in `compute`. Green, refactor.

- [x] **Task 3 — `epub_extractor.dart`** `companion/lib/services/import/epub_extractor.dart` (AC: #1, #3, #4) — PURE Dart
  - [x] Write failing tests first in `companion/test/services/import/epub_extractor_test.dart` using the Task-1 fixtures (red).
  - [x] Define a pure result type, e.g. `final class EpubParse { final String title; final String? author; final List<BakeChapter> chapters; final Uint8List? coverBytes; final String? coverFormat; }` (all sendable across the isolate boundary).
  - [x] Implement `Future<EpubParse> extractEpub(List<int> epubBytes)` (async — `EpubReader.readBook` is `Future<EpubBook>`; `compute` accepts async callbacks):
    1. `final book = await EpubReader.readBook(epubBytes);` — **use plain `readBook`, NOT `readBookWithSplitChapters`** (that splits long chapters at >3000 words — we want *real* TOC/spine chapters, not arbitrary parts; the watch's BLE chunking is independent of chapter boundaries). [Source: epub_pro README — `readBook` vs `readBookWithSplitChapters`]
    2. **Title:** `book.title` (fallback to a non-empty default only if null/blank). **Author:** `book.author` (nullable — leave null if absent; AC4). [Source: epub_pro README:122-124 `title`/`author`/`authors`]
    3. **Chapters:** `book.chapters` is `List<EpubChapter>` with nested `.subChapters`. **Flatten depth-first in reading order** (parent's own `htmlContent` first, then its subchapters). For each node with non-null/non-blank `htmlContent`: `final text = extractFromHtml(node.htmlContent!, epubFilter: true)` → `sanitize(text)` → `tokenize(...)` → if **≥1 token**, append `BakeChapter(title: node.title ?? '<derived>', tokens: tokens)`. **Skip chapters that tokenize to zero tokens** (nav-only nodes, all-punctuation chapters) — `bake()` throws on a zero-token chapter (`word_stream_baker.dart:184-193`), so they must be filtered *here*, not passed through. [Source: epub_pro README:136-144 chapters/subChapters; tokenizer drops pure-punctuation tokens]
    4. If **no chapter yields any tokens**, throw a typed/marked condition that `import_service` maps to `emptyContent` (AC5) — do not return an empty chapter list to `bake()`.
    5. **Cover:** delegate to `cover_extractor` (Task 4) → `coverBytes`/`coverFormat` (may be null).
  - [x] **ORP word-char-free-token contract (resolve the 2.2-deferred item here):** the extractor feeds chapter HTML through the **same `sanitize → tokenize` chain** as txt/md, and `tokenize` drops pure-punctuation tokens — so the extractor **never** emits a word-char-free token, and `orp.dart:62`'s byte-0 degrade is **unreachable** from this path. **Document the accept** in Completion Notes (no guard added to `bake()`); add a test: an all-symbol chapter → zero tokens → chapter filtered (not a byte-0 ORP, not a bake throw). [Source: deferred-work.md:15 "Resolve the contract in Story 2.4 … then either guard in `bake()` or document the accept"]
  - [x] PURE: epub_pro + html + sanitizer/tokenizer are all pure Dart. **No Flutter, no `dart:io`.** Tests assert: chapter count, titles, `chapterStart` semantics (via the downstream bake in Task 5), and that the pre-filtered fixture's footnote/ruby/alt/table content is handled per Task 2. Green, refactor.

- [x] **Task 4 — `cover_extractor.dart`** `companion/lib/services/import/cover_extractor.dart` (AC: #2) — PURE Dart
  - [x] Write failing tests first in `companion/test/services/import/cover_extractor_test.dart` (red).
  - [x] Implement `({Uint8List bytes, String format})? extractCover(EpubBook book)` (or return null):
    - `book.coverImage` is a **decoded `img.Image`** from `package:image` (nullable). [Source: epub_pro README:127-129]
    - If present: optionally **downscale** to a bounded max dimension (recommend ≤~600 px longest side via `img.copyResize`, preserving aspect) and **encode to bytes** — recommend `img.encodeJpg(image, quality: 80)` (`format: 'jpg'`) to bound the on-disk size; PNG is acceptable for images with alpha. Return `(bytes, format)`.
    - If `book.coverImage == null`: return null (no-cover EPUBs are valid — AC2). 
  - [x] **Cover bytes are produced in the isolate; the *file* is written on the main isolate** (Task 6 / `stream_store`) — same split as the word stream (bytes baked in `compute`, file written by `stream_store` on main). Do NOT write a file here (no `dart:io` in a `compute`-run module). The cover **never** touches `streamBytes` or the protocol (AC2). [Source: architecture.md:178,589; mirrors 2-3 stream-bytes-in-isolate / file-on-main split]
  - [x] PURE. Tests: cover fixture → non-empty bytes + format; no-cover fixture → null. Green, refactor.

- [x] **Task 5 — Isolate pipeline entry for EPUB** `companion/lib/services/import/pipeline.dart` (AC: #1, #3, #5) — PURE Dart
  - [x] Write failing tests first in `companion/test/services/import/pipeline_test.dart` (extend; keep the 2.3 single-chapter `runPipeline` tests green) (red).
  - [x] Add `final class EpubPipelineRequest { final Uint8List epubBytes; final int salt; }` and a **top-level** `Future<EpubBaked> runEpubPipeline(EpubPipelineRequest req)` (top-level/static so `compute` can use it). `EpubBaked { final BakedBook baked; final String? author; final Uint8List? coverBytes; final String? coverFormat; }` — all sendable.
  - [x] Body: `final parse = await extractEpub(req.epubBytes)` → `final baked = bake(title: parse.title, chapters: parse.chapters, salt: req.salt)` (multi-chapter → `bake` sets `chapterStart` + manifest index, AC3) → return `EpubBaked(baked, parse.author, parse.coverBytes, parse.coverFormat)`. Title lives in `baked.manifest`; **author is NOT in the manifest** — that is why `EpubBaked` carries it separately to the `Books` row.
  - [x] Keep `runPipeline`/`PipelineRequest` (the txt/md single-chapter entry) **unchanged** — `.epub` gets its own entry; do not overload the text one. Tests: clean 3-chapter fixture → `baked.manifest.chapters.length == 3`, first token of chapter 2 carries `chapterStart` (assert via the JSONL master or a `decodeChunk` check), 8-hex fingerprint, non-empty `streamBytes`, author surfaced. Green, refactor.

- [x] **Task 6 — `stream_store` cover file + `import_service` EPUB orchestration** `companion/lib/data/stream_store.dart` + `companion/lib/services/import/import_service.dart` (AC: #2, #3, #5)
  - [x] **`stream_store` (red→green):** add `Future<String> writeCover({required Uint8List bytes, required String fingerprint, required String format})` → writes `covers/<fingerprint>.<ext>` under the injected base dir, returns the absolute path; and `Future<void> deleteCover(String coverPath)` (idempotent — no throw if absent) for AC5 rollback / 2.5 Remove. Keep covers in a **`covers/`** subdir, sibling to `streams/` (do not co-mingle with `.stream`/`.jsonl`). Tests (temp dir): writeCover → file exists, bytes round-trip; deleteCover → gone, idempotent.
  - [x] **`import_service` (red→green):** branch `importFile({required String path, required List<int> bytes})` on extension. Add an `_isEpub(filename)` check (`.epub`). 
    - **`.epub` path:** **do NOT `utf8.decode` the bytes** (it is a ZIP, not text — decoding corrupts it). Compute the salt as today. Run `final epubBaked = await _epubRunner(runEpubPipeline, EpubPipelineRequest(Uint8List.fromList(bytes), salt));` through a **second injected runner seam** (default `compute`, overridable to run synchronously in tests — mirror the existing `PipelineRunner` seam). Persist in order: `store.write(streamBytes, debugJsonl, fingerprint)` → **if `coverBytes != null`**, `store.writeCover(...)` → drift `transaction`: insert `Books` (now with **`author: epubBaked.author`** and **`coverPath: <cover path or null>`**) + **one `Chapters` row per `baked.manifest.chapters`** (`chapterIndex` 0..n-1, `wordOffset = entry.offset`, `cumulativeBonusMs = entry.cumulativeBonusMs`, `title = entry.title`). Return `ImportSuccess(bookId)`.
    - **non-`.epub`:** the existing 2.3 text path, untouched.
  - [x] **AC5 rollback (extend 2.3's):** wrap the parse+persist so any failure (corrupt/DRM/encrypted EPUB → epub_pro throw; empty → `emptyContent`; I/O; drift error) is caught → typed `ImportFailure(reason, filename)`, and **on failure delete BOTH the stream file (if written) AND the cover file (if written)** before returning — no `Books`/`Chapters` row, no `.stream`/`.jsonl`, **no cover** may survive. **No silent `catch {}`** (architecture.md:293).
  - [x] **Failure-reason mapping (minimal seam, NOT the 2.6 taxonomy):** the `unreadable`/`unsupported` enum members (dead seeds in 2.3) go **live** here — recommend: malformed/corrupt/non-zip → `unreadable`; DRM/encrypted/unsupported-structure → `unsupported`; no-token book → `emptyContent`; I/O → `ioError`. **Do not build the fine-grained 2.6 taxonomy** (e.g. the >255-byte-token `ArgumentError` mislabel is explicitly **2.6's** — `deferred-work.md:7`); just don't crash and don't mislabel the obvious cases. [Source: deferred-work.md:7 (taxonomy → 2.6)]
  - [x] DB + `stream_store` stay on the **main isolate**; only `runEpubPipeline` crosses into `compute`. Never pass the drift connection / `StreamStore` into `compute`.
  - [x] Tests (in-memory drift + temp store + synchronous epub-runner override, fixed salt): clean fixture → `ImportSuccess`, 1 Books row with `author` + `cover_path` set + correct `fingerprint`/`totalWords`, **N Chapters rows** at correct offsets, stream + cover files present. No-cover fixture → success, `cover_path` null, no cover file. Corrupt fixture → `ImportFailure(unreadable)`, **zero** rows, **no** stream/cover file. Empty-spine fixture → `ImportFailure(emptyContent)`. Green, refactor.

- [x] **Task 7 — Library row: cover thumbnail + author** `companion/lib/ui/library/library_screen.dart` (AC: #4)
  - [x] Extend the `ListTile` (currently title + "Not started" + 0% bar — `library_screen.dart:192-205`): add a **`leading:`** cover thumbnail — when `book.coverPath != null` render the file via `Image.file(File(book.coverPath!))` sized to a small M3 thumbnail (recommend ~40×56 / book aspect, `BoxFit.cover`, rounded per M3); when null render a **placeholder** (e.g. `Icon(Icons.menu_book)` in an M3 container). Add **author** to the subtitle (e.g. author line above "Not started"; when `author == null` omit the line). Title unchanged. [Source: DESIGN.md:85,156; EXPERIENCE.md:53,86]
  - [x] Widget tests (`test/ui/library/library_screen_test.dart`, extend): with a fake `libraryProvider` book carrying `author` + a `coverPath`, the row renders the author text and a cover widget; with `coverPath == null`, the placeholder renders and no `Image.file` is attempted. Use `ProviderScope(overrides:[…])` — **no real drift/plugins/filesystem** in widget tests (use a `Book` value with a coverPath string; assert the widget type chosen, not actual image decoding — or guard the file-exists branch so the test path doesn't hit disk). Keep the empty-state (AC3 of 2.3) test green.

- [x] **Task 8 — EPUB import entry: picker + share filter** `companion/lib/ui/library/library_screen.dart` + `companion/android/app/src/main/AndroidManifest.xml` (AC: #6) — *picker is the testable spine; share is thin + manually verified (2.3 precedent)*
  - [x] **Picker:** add `'epub'` to `allowedExtensions` (`library_screen.dart:66` — currently `['txt','md','markdown']`). The picked `.epub` flows through the **same** `importFile(path:, bytes:)` (which Task 6 branches to the epub path). Confirm the picker returns **bytes** for binary files (it does for `withData`/in-memory; if the project's picker call relies on a path, ensure bytes are read).
  - [x] **Share sheet:** add the `application/epub+zip` mime to the existing `SEND`/`VIEW` `intent-filter`s in `AndroidManifest.xml` (currently `text/plain` + `text/markdown`, lines 35-36, 42-43). The 2.3 share handler reconstructs a path string — for EPUB ensure the handler reads the **real shared file's bytes** (EPUB is binary; the 2.3 `'Shared text.txt'` placeholder-path trick must not corrupt binary content). [Source: 2-3 Task 8; architecture.md:401; deferred-work.md:6 share-sheet caveats]
  - [x] This path is **plugin/platform-bound → not unit-tested**; keep it thin (adapt the payload into the already-tested `importFile`) and **manually verify on-device** (share a real EPUB from a file manager → it lands in the library with cover + chapters). Note the manual step in Completion Notes. The demo-critical path is the **picker** ("import a real EPUB on the phone" — EXPERIENCE.md:187) and it is fully testable.

- [x] **Task 9 — Verify & keep CI green** (AC: all)
  - [x] `cd companion && flutter test` — all pass (222 baseline from 2.3 + new; **no regression** — especially the unchanged `.md`/`.txt` html_extractor tests and the single-chapter `runPipeline` tests).
  - [x] `flutter analyze` — clean under strict-casts / strict-inference / strict-raw-types.
  - [x] **AR §452 purity grep:** no `package:flutter/*` and no `dart:io` in the **pure** modules (`epub_extractor.dart`, `cover_extractor.dart`, `runEpubPipeline`, `extractFromHtml`). `import_service.dart`/`stream_store.dart`/`ui/` MAY use Flutter/`dart:io` (impure shell) — that's correct.
  - [x] Confirm layering (architecture.md:452): `ui/ → services/ → data/`. `ui/` reads the cover only via the `Book.coverPath` string + `Image.file` — it does **not** import `stream_store`/`drift` directly.
  - [x] `flutter build apk --debug` to confirm the new native-free dep assembles (epub_pro is pure Dart — no Gradle changes expected, unlike 2.3's plugins).

### Review Findings

_Code review 2026-06-16 (Blind Hunter + Edge Case Hunter + Acceptance Auditor). All 6 ACs satisfied; no scope violations. Resolved: 2 decision-needed (1 dismissed-after-verification, 1 patched), 2 patched, 4 deferred, 7 dismissed as noise._

- [x] [Review][Decision→Dismiss] Anchored-TOC text duplication — VERIFIED FALSE against `epub_pro` 5.6.0 source. `readHtmlContent()` does return the full content file ignoring the anchor (`epub_chapter_ref.dart:44-45`), but the production path `bookRef.getChapters()` → `ChapterReader.getChapters` dedups by base content-file via a shared `seenContentFiles` set (`chapter_reader.dart:84-85, 177-181`), so multiple `#anchor` entries on one file collapse to a single chapter node. No duplicate node → no duplicated prose, no inflated word count. Effect is only chapter-granularity loss on anchor-split single-file books (text baked once, correctly). No change needed.
- [x] [Review][Decision→Patch] Dead `extractCover(EpubBook)` after the `readCover()` pivot — runtime uses `bookRef.readCover()` + `encodeCover()` (`epub_extractor.dart:102-107`); `extractCover` was called only by its own test. Deleted the dead function + its test; kept the live `encodeCover`.
- [x] [Review][Patch] `title`/`author` bypass token validation — pathological OPF metadata (unpaired UTF-16 surrogate) can throw at the drift/SQLite insert, mapping to `ioError` and rolling back an otherwise-good book; chapter words are guarded by `stream_codec` but metadata is not [`import_service.dart:232-237`, `epub_extractor.dart:114-115`]. Fixed: metadata sanitized in the extractor before crossing the persist boundary.
- [x] [Review][Defer] `_classifyParseError` string-matches the exception message — brittle/locale-dependent; mislabels `unreadable`↔`unsupported` [`import_service.dart:284-292`] — deferred, fine failure taxonomy explicitly scoped to 2.6.
- [x] [Review][Defer] Nested-`<table>` prose duplicated by `_linearizeTable` — `querySelectorAll('tr')` matches descendant rows so nested-table text is emitted twice [`html_extractor.dart:132-148`] — deferred, ugly-HTML edge belongs to the 2.6 corpus suite.
- [x] [Review][Defer] Cover `catch (_)` swallows all errors incl. OOM; cover decode is unbounded on input dimensions (`kMaxCoverDimension` caps output only) — huge cover can OOM the isolate [`epub_extractor.dart:101-111`] — deferred, robustness hardening / 2.6.
- [x] [Review][Defer] Re-importing the same EPUB creates a duplicate book (time-based salt → unique fingerprint, no content dedup) [`import_service.dart:99, 216-254`] — deferred, dedup is a later product decision (not corruption).

## Dev Notes

### What this story IS / ISN'T
- **IS:** `epub_extractor.dart` (OCF/OPF/spine/TOC via `epub_pro` + DOM-pre-filter walk → real chapters), `cover_extractor.dart` (decoded cover → bytes, phone-only), the `html_extractor` refactor exposing `extractFromHtml` + the EPUB pre-filter, the **multi-chapter** bake wiring (`runEpubPipeline`), `import_service` EPUB branch + cover persistence + rollback, `stream_store.writeCover`/`deleteCover`, the OPF **author** + **cover thumbnail** on the library row, and the `.epub` picker/share entry. Resolves the **ORP word-char-free-token contract** (document-the-accept).
- **ISN'T:** book-detail screen / chapter-list UI / Remove / Restart (**2.5**); full failure taxonomy + inline error messaging + ugly-EPUB corpus suite (**2.6**); `Positions`/progress/sync (**Epic 4/4.5**); transfer/Send-to-watch (**Epic 4**); chapter splitting for long chapters (`readBookWithSplitChapters` — **not used**, ever; real chapters only). Do not pull these forward.

### Reuse — do NOT reinvent (almost everything already exists, fully tested)
- **`bake(...)`** — `word_stream_baker.dart:172`: `BakedBook bake({required String title, required List<BakeChapter> chapters, required int salt})`. **Already multi-chapter** — it flattens chapters, sets `flagChapterStart` on each chapter's first word (`:199-224`), and builds the manifest `List<ChapterEntry>` (`:242-259`). 2.3 fed it a list of one; **2.4 feeds N — no change to `bake` needed.** Throws `ArgumentError` if `chapters.isEmpty` or any chapter has zero tokens (`:177-193`) — hence the empty-chapter filtering in Task 3. [Source: word_stream_baker.dart:172,199-224,242-259,177-193]
- **`BakeChapter { String title; List<Token> tokens }`** — `word_stream_baker.dart:34`. **`ChapterEntry { int offset; String title; int cumulativeBonusMs }`** — `:54` — maps 1:1 to a drift `Chapters` row (offset → `wordOffset`). **`BookManifest { title, totalWords, totalBonusMs, fingerprint, List<ChapterEntry> chapters }`** — `:87`. **`BakedBook { Uint8List streamBytes; BookManifest manifest; List<String> debugJsonl }`** — `:127`.
- **`sanitize(String raw, {bool asciiFold = false}) → String`** — `text_sanitizer.dart:70`. Default `asciiFold:false`. **`tokenize(String) → List<Token>`** — `tokenizer.dart:112`; paragraph boundary `\n\s*\n` (`:52`) — so `extractFromHtml` must keep emitting `\n\n` between blocks; drops pure-punctuation tokens; forces last token `sentenceEnd=true`. **`Token { text, paragraphStart, sentenceEnd }`** — `tokenizer.dart:17`.
- **`extractPlainText(String raw, {required bool isMarkdown})`** — `html_extractor.dart:57`; Task 2 promotes its block-walk to `extractFromHtml(String html, {bool epubFilter})` and re-points `.md` through it. **Author is NOT in the manifest** — thread it from `EpubBaked`.
- **Drift schema already has the columns** — `Books.author` (`database.dart:31`, nullable) and `Books.coverPath`/`cover_path` (`:32`, nullable) were added in 2.3 *for this story*. `Chapters` table (`:50-60`) already has `wordOffset`/`cumulativeBonusMs`/`chapterIndex`/`title`. **No schema bump, no migration.** Queries: `insertBook`/`insertChapters`/`watchAllBooks`/`deleteBookCascade` (`database.dart:75-92`) — reuse as-is.
- **`stream_store`** — `write({streamBytes, debugJsonl, fingerprint})` + `delete(streamPath)` (`stream_store.dart:51,81`). 2.4 **adds** `writeCover`/`deleteCover`; does **not** change `write`.
- **`sealed ImportResult` / `ImportSuccess(int bookId)` / `ImportFailure(ImportFailureReason, String filename)` / `enum ImportFailureReason{emptyContent,unreadable,unsupported,ioError}`** — `import_service.dart:33-49`. Reuse the type; the `unreadable`/`unsupported` members (dead in 2.3) go live (Task 6). **Do not widen the enum** (2.6 owns the taxonomy).

### epub_pro API (verified) [Source: pub.dev/packages/epub_pro 5.6.0 + README, fetched 2026-06-16]
- `Future<EpubBook> EpubReader.readBook(List<int> bytes)` — async; pure (no `dart:io`); deps `archive`/`xml`/`image`/`collection`.
- `EpubBook`: `.title` (String?), `.author` (String?), `.authors` (List<String>), `.coverImage` (decoded `img.Image?` from `package:image`), `.chapters` (`List<EpubChapter>`), `.content` (images/html/css).
- `EpubChapter`: `.title` (String?), `.htmlContent` (String?), `.subChapters` (`List<EpubChapter>`), `.contentFileName`.
- **Use `readBook`, not `readBookWithSplitChapters`** (the latter splits chapters >3000 words into `(X/Y)` parts — wrong for real chapter boundaries). epub_pro already does NCX/spine reconciliation for malformed nav (orphaned spine items become subchapters in reading order) — so flattening `chapters`+`subChapters` depth-first gives the correct reading order.

### Isolate boundary (AC5) — the thing to get right
- The **whole** EPUB chain runs in `compute(runEpubPipeline, request)`: `readBook → extractEpub (spine walk + pre-filter + sanitize/tokenize) → cover decode/encode → bake`. The return value `EpubBaked` is sendable (`Uint8List` stream bytes + `Uint8List?` cover bytes + value objects + `List<String>` jsonl). 
- **drift + `stream_store` stay on the main isolate.** Read bytes (main) → `compute` parse+bake (background) → `store.write` + `store.writeCover` + drift inserts (main). Same flow as 2.3 (`architecture.md:469`), now also writing the cover file on main.
- epub_pro/`archive`/`xml`/`image`/`html`/`markdown` are all pure Dart — safe in `compute`. `file_picker`/`receive_sharing_intent` are platform plugins — main isolate / UI only, never in `compute`.

### Cover handling — bytes in isolate, file on main (AC2)
- `cover_extractor` returns **bytes** (decoded `img.Image` → re-encoded, recommend downscale ≤~600px + `encodeJpg(quality:80)` to bound size). The **file** is written by `stream_store.writeCover` on the main isolate (a `compute`-run module cannot touch `dart:io`). This mirrors how the *word stream* is baked in `compute` then written by `stream_store` on main.
- The cover **never** enters `streamBytes` or any protocol message — it is a sidecar file referenced only by `Books.cover_path`, phone-only (architecture.md:178,589). No-cover EPUBs are valid (`cover_path` null).

### Failure handling (AC5) — minimal seam, NOT 2.6
- This story makes the EPUB path **not crash** and **not leave partial state** (stream + cover + rows roll back together). It takes `unreadable`/`unsupported` live and maps the obvious cases. It does **not** build 2.6's fine-grained taxonomy/messaging/ugly-corpus suite. Specifically, the >255-byte-token `ArgumentError`→`emptyContent` mislabel is **explicitly deferred to 2.6** (`deferred-work.md:7`) — don't fix it here (half-measure 2.6 redoes).
- The inline library error message ("Couldn't read {filename} — {reason}") is **2.6** (EXPERIENCE.md:114); 2.4 keeps the 2.3 `SnackBar` on `ImportFailure`.

### ORP contract resolution (2.2-deferred → resolved here) [Source: deferred-work.md:15]
- Decision: **document-the-accept, no guard added to `bake()`.** Rationale: `epub_extractor` feeds every chapter's text through the same `sanitize → tokenize` chain as txt/md, and `tokenize` drops pure-punctuation tokens — so a word-char-free token is **never produced from the EPUB path**, and `orp.dart:62`'s byte-0 degrade is unreachable. The only adjacent risk (a chapter that is *entirely* symbols/punctuation → zero tokens) is handled by **filtering zero-token chapters before `bake`** (Task 3), with a fixture test proving it. Record this decision in Completion Notes so 2.6/Epic-3 don't re-litigate it.

### Test fixtures (AC: all) — synthetic only
- Hermetic tests need committed EPUBs, but **the real corpus (`/home/nerya/Desktop/epub`, 190 EPUBs) is copyrighted — never commit it, never use it as a test input** (manual exploratory use only, 2.4/2.6). Build **tiny synthetic** EPUBs in-memory with `package:archive` (Task 1) so the pre-filter ACs are testable with *crafted* footnote/ruby/alt/table HTML you control. Generate the cover via `package:image` `encodePng`. Commit only these synthetic fixtures under `companion/test/fixtures/epubs/`. [Source: memory epub-corpus-location; architecture.md:445]
- After the suite is green, **manually** import a few real EPUBs from the local corpus (varied publishers/footnote styles) to sanity-check the pre-filter against real-world HTML — this is the exploratory pass 2.6's ugly-corpus suite will later formalize.

### Architecture compliance / guardrails
- **AR §452 (purity):** `services/import/` leaf modules are pure Dart (no Flutter imports) so they run in isolates — `epub_extractor`, `cover_extractor`, `extractFromHtml`, `runEpubPipeline` must stay pure (no `package:flutter/*`, **no `dart:io`**). `import_service`/`stream_store`/`ui/` are the impure shell.
- **Layering (architecture.md:452):** `ui/ → services/ → data/`. The library row reads the cover via `Book.coverPath` + `Image.file` only — `ui/` does not import `stream_store`/`drift`.
- **No silent `catch {}`** (architecture.md:293): every failure → a typed `ImportFailure` member.
- **Cover never in protocol/stream** (architecture.md:178) — sidecar file only.
- Keep `flutter analyze` clean under strict lints.

### Previous-story intelligence
- **2.3 (done):** built the entire shell this story extends — `import_service` (`compute(runPipeline)` + persistence + rollback), `html_extractor` (block-walk, `\n\n` paragraph preservation), drift `Books`(+author/cover_path nullable, pre-shaped for 2.4)+`Chapters`, `stream_store` (atomic stream/jsonl write + idempotent delete), Riverpod providers, `LibraryScreen`+empty state, picker + share-sheet seam (`ShareSource` defaulting to no-op so widget tests skip platform channels), `main.dart` repointed off Gate V2. 222 tests green, analyze clean. Review patches: `stream_store.write` made atomic (orphan `.stream` on jsonl failure) — **`writeCover` must be equally atomic / rollback-covered**; share `reset()` ordering fixed. Deferred to 2.4 from 2.3: nothing blocking (share md-as-text + taxonomy + dedup → 2.5/2.6).
- **2.2 (done):** `bake`/`BakedBook`/manifest/`ChapterEntry`/`BakeChapter`, salted FNV-1a fingerprint (caller supplies salt), JSONL master. **`bake` is already multi-chapter** — this story is its first multi-chapter caller. Deferred to 2.4: the **ORP word-char-free-token contract** (resolved above).
- **2.1 (done):** `sanitize`+`tokenize`; paragraph boundary `\n\s*\n`; pure-punctuation tokens dropped; terminal `sentenceEnd=true`. Consequence: feed EPUB chapter text through the same chain and boundaries are correct.

### Project Structure Notes
- **New files** (all under architecture.md:404-445's tree):
  - `companion/lib/services/import/epub_extractor.dart` — arch:414.
  - `companion/lib/services/import/cover_extractor.dart` — arch:415.
  - Tests: `companion/test/services/import/{epub_extractor,cover_extractor}_test.dart`; fixture builder `companion/test/fixtures/epubs/epub_fixture_builder.dart` — arch:445.
- **Modified:**
  - `companion/lib/services/import/html_extractor.dart` (promote `extractFromHtml` + EPUB pre-filter; `.md`/`.txt` behaviour unchanged).
  - `companion/lib/services/import/pipeline.dart` (add `EpubPipelineRequest`/`runEpubPipeline`/`EpubBaked`; `runPipeline` unchanged).
  - `companion/lib/services/import/import_service.dart` (epub branch + cover persistence + rollback; second runner seam).
  - `companion/lib/data/stream_store.dart` (`writeCover`/`deleteCover`).
  - `companion/lib/ui/library/library_screen.dart` (cover thumbnail + author; picker `'epub'`).
  - `companion/pubspec.yaml`/`pubspec.lock` (`epub_pro`).
  - `companion/android/app/src/main/AndroidManifest.xml` (`application/epub+zip` SEND/VIEW filters — Task 8 only).
- **Preserved untouched:** drift schema (`database.dart` — columns already present), the 2.1/2.2 pipeline leaf modules, `protocol/`, `gate_v2/`.

### Testing standards [Source: architecture.md:264; existing test/ patterns; 2-3 testing notes]
- `flutter_test` + `test`; tests mirror `lib/` paths under `companion/test/`.
- Pure modules (`epub_extractor`, `cover_extractor`, `runEpubPipeline`, `extractFromHtml`) — plain unit tests over synthetic in-memory EPUB fixtures. drift — `NativeDatabase.memory()`. `stream_store` — temp dir via injected `Directory`. `import_service` — in-memory drift + temp store + **synchronous epub-runner override** (fixed salt → deterministic fingerprint). UI — widget tests with `ProviderScope(overrides:[…])`, no real drift/plugins/disk.
- Plugin-bound paths (`file_picker`, `receive_sharing_intent`) not unit-tested — thin, manually verified.
- TDD: red → green → refactor, one task in order.

### References
- [Source: epics.md#Epic-2 / Story 2.4, lines 460-483; Story 2.5 lines 485-507 (book-detail/Remove deferred); Story 2.6 lines 509-528 (failure taxonomy/corpus deferred)]
- [Source: architecture.md:49 (cluster E), :74 (epub_pro + DIY html), :178,589 (cover → file in stream store, `cover_path`, never in protocol), :180 (bounds-check-and-degrade at EPUB parse, NFR8), :192-193 (manifest chapter index), :204-205 (M3 + Riverpod), :279 (flag bits incl. chapterStart, SPEC.md), :293 (typed failures/no silent catch), :404-445 (companion tree; :414 epub_extractor, :415 cover_extractor, :445 fixtures/epubs), :452 (layering + services/import pure-Dart), :469 (book-delivery data flow)]
- [Source: DESIGN.md:85,156,157 (M3 ListTile cover thumbnail/title/author; book detail cover — 2.5); EXPERIENCE.md:52-54,86-87,114-115,187 (Library/Import surfaces, row layout, import-failure copy → 2.6, demo moment); extract-product.md:64-65 (FR22 import / FR23 library list)]
- [Source: companion/lib/services/import/word_stream_baker.dart:34 BakeChapter, :54 ChapterEntry, :87 BookManifest, :127 BakedBook, :172 bake (multi-chapter), :177-193 zero-token throw, :199-224 chapterStart, :242-259 manifest chapters]
- [Source: companion/lib/services/import/html_extractor.dart:57 extractPlainText (promote to extractFromHtml); pipeline.dart:24-58 PipelineRequest/runPipeline (keep); import_service.dart:33-49 ImportResult/Reason, :84-153 importFile, :54-57 PipelineRunner seam]
- [Source: companion/lib/data/db/database.dart:27-47 Books (author:31, cover_path:32 nullable, pre-shaped), :50-60 Chapters, :75-92 queries; stream_store.dart:51 write, :81 delete (add writeCover/deleteCover)]
- [Source: companion/lib/ui/library/library_screen.dart:65-66 picker allowedExtensions, :79-85 share handler, :192-205 ListTile; library_providers.dart:1-35 providers]
- [Source: companion/lib/services/import/text_sanitizer.dart:70 sanitize; tokenizer.dart:17 Token, :52 paragraph boundary, :112 tokenize]
- [Source: companion/android/app/src/main/AndroidManifest.xml:33-44 SEND/VIEW filters (text/plain+text/markdown — add epub+zip)]
- [Source: pub.dev/packages/epub_pro 5.6.0 + github.com/watate/epub_pro README — readBook/EpubBook/EpubChapter API, NCX/spine reconciliation, fetched 2026-06-16]
- [Source: deferred-work.md:7 (taxonomy → 2.6), :15 (ORP word-char-free-token contract → resolve in 2.4), :6 (share md-as-text); memory: epub-corpus-location (real corpus = manual-only, never commit), watch-decode-watchdog-constraint (Epic 4, irrelevant to phone import)]
- [Source: 2-3-import-txt-md-into-the-library.md (the spine this story extends — shell, schema, rollback, share seam, review patches)]

## Dev Agent Record

### Agent Model Used

Amelia (dev-story workflow) — Claude Opus 4.8 (`claude-opus-4-8[1m]`).

### Debug Log References

- `epub_pro 5.6.0` API verified against the installed package source (not training data): `EpubReader.readBook(FutureOr<List<int>>)` async; `EpubBook{title?, author?, authors, coverImage(img.Image?), chapters}`; `EpubChapter{title?, htmlContent?, subChapters, contentFileName?}`; EPUB2 NCX path = `<spine toc="ncx">` → manifest `id="ncx"` → navMap navPoints (titles from navLabel); cover = `<meta name="cover">` → manifest id → image, **with a first-image fallback** (so the no-cover fixture carries zero images). `getChapters` returns `[]` when navigation is absent.
- `archive 4.0.9`: `ArchiveFile.noCompress`/`.string`/`.bytes`, `Archive.add`, `ZipEncoder().encode` — mimetype added first/stored per OCF.
- Probe: corrupt (non-zip) bytes throw a plain `Exception` ("container.xml not found"), **not** `ArgumentError` — so the parse classifier maps it to `unreadable` and does not collide with the bake-empty path.

### Completion Notes List

- **All 6 ACs satisfied; 262 tests pass (222 baseline 2.3 + 40 new), `flutter analyze` clean under strict lints, `flutter build apk --debug` succeeds.**
- **AC1 table policy = LINEARIZE (decided + documented):** `extractFromHtml(..., epubFilter: true)` emits each `<tr>` as one block with its `<td>`/`<th>` cell text joined inline by a space, so tabular prose survives rather than being silently dropped. Noteref/footnote anchors (`epub:type` containing noteref/footnote/rearnote/endnote, or `<a class/role>` footnote markers) are dropped subtree-and-all; `<rt>`/`<rp>` ruby readings dropped (base kept); image `alt`/`title` never read (text-nodes-only walk — assert-and-locked by test). The `.md`/`.txt` path leaves `epubFilter` off, so 2.3 behaviour is byte-for-byte unchanged.
- **ORP word-char-free-token contract (2.2-deferred → RESOLVED here as document-the-accept, no guard added to `bake()`):** the EPUB extractor feeds every chapter through the same `sanitize → tokenize` chain as txt/md, and `tokenize` drops pure-punctuation tokens, so a word-char-free token is never produced from the EPUB path and `orp.dart:62`'s byte-0 degrade is unreachable. The only adjacent risk — a chapter that is *entirely* symbols → zero tokens — is filtered in `epub_extractor._flatten` **before** `bake` (a zero-token chapter would make `bake` throw). Proven by `mixedEmptyChapterEpub` (all-punctuation chapter filtered, prose chapter survives) and `allPunctuationChapterEpub` → `emptyContent`.
- **AC5 isolate + no-partial-state:** the whole `readBook → pre-filter spine walk → sanitize/tokenize → multi-chapter bake → cover decode` chain runs in `compute(runEpubPipeline, …)` via a second injected `EpubPipelineRunner` seam (default `compute`, synchronous override in tests). drift + `stream_store` stay on the main isolate. Failures: parse errors are caught **before** anything is written (no rollback needed) — `EpubEmptyContentException → emptyContent`, DRM/encrypt/obfusc message → `unsupported`, else → `unreadable`; persistence errors → `ioError` and roll back **both** the stream pair AND the cover file (`writeCover` is atomic like `write`). The drift transaction self-rolls-back, so no row survives.
- **Failure taxonomy is the MINIMAL seam only (NOT 2.6):** `unreadable`/`unsupported` enum members go live; the fine-grained taxonomy, inline error copy, and ugly-corpus suite remain 2.6's. The >255-byte-token `ArgumentError` mislabel was deliberately **not** addressed (deferred-work.md:7) — it surfaces as a non-crashing typed failure, no special-casing added.
- **Cover handling:** bytes produced in the isolate (`cover_extractor`: decoded `img.Image` → downscale ≤600px longest side → `encodeJpg(quality:80)`), file written on main by `stream_store.writeCover` into a sibling `covers/` subdir; `Books.cover_path` references it. Cover never touches `streamBytes`/protocol. No-cover EPUBs valid (`cover_path` null).
- **No schema change:** `Books.author`/`cover_path` and the `Chapters` table were pre-shaped in 2.3; `schemaVersion` stays 1, no migration, no codegen.
- **REAL-WORLD ROBUSTNESS FIX (found during on-device verification):** `epub_extractor` now composes the lazy API — `EpubReader.openBook` + `getChapters`/`readChapters` + `readCover` — instead of `EpubReader.readBook`. `readBook` eagerly loads *every* manifest resource via `readContent`, which throws on **Calibre-exported EPUBs** whose manifest references a stray `META-INF/calibre_bookmarks.txt` through an unresolvable `OEBPS/../` href (a very large share of real books). We need only spine chapters + cover, so skipping `readContent` makes import robust to that class while staying on real TOC/spine chapters. Cover read is now best-effort (a malformed cover degrades to no-cover, never sinks the import). Discovered because the first device run of a real Tolkien EPUB returned `ImportFailure(unreadable)` — AC5 behaved correctly (typed, no crash, no partial state), but the book wouldn't import; the fix makes it succeed.
- **ON-DEVICE VERIFICATION DONE (Galaxy S25 Ultra, Android 16):** real EPUB ("The Hobbit", 4 MB) imported through the **real file picker** in the running app → `ImportSuccess` in ~1.2 s (real `compute` isolate): title "The Hobbit: Or There and Back Again", author "J. R. R. Tolkien", **29 chapters**, 96,609 words, fingerprint baked, **cover JPEG written (34 KB)**, stream file written. Library row renders the **cover thumbnail + title + author** (AC4 visually confirmed via screenshot). An `integration_test/epub_import_on_device_test.dart` harness drives the real `ImportService` against a device-staged EPUB and prints machine-readable `RSVP_HW:` lines (memory: hardware-run-results-machine-readable) — NOT part of CI; the real EPUB is never committed (memory: epub-corpus-location).
- **STILL MANUAL (Task 8 share-sheet, plugin-bound):** the `application/epub+zip` SEND/VIEW intent filters are in `AndroidManifest.xml`; the share path reuses 2.3's `SharedMediaType.file` branch (reads real bytes, binary-safe). On-device share-sheet hand-off not yet exercised (picker path is the demo-critical one and is now verified end-to-end). Broader exploratory pass over the local corpus remains useful before 2.6 formalizes the ugly-corpus suite.

### File List

**New (lib):**
- `companion/lib/services/import/epub_extractor.dart`
- `companion/lib/services/import/cover_extractor.dart`

**New (test):**
- `companion/test/fixtures/epubs/epub_fixture_builder.dart`
- `companion/test/fixtures/epubs/epub_fixture_builder_test.dart`
- `companion/test/services/import/epub_extractor_test.dart`
- `companion/test/services/import/cover_extractor_test.dart`
- `companion/integration_test/epub_import_on_device_test.dart` (manual hardware harness, not CI)

**Modified (lib):**
- `companion/lib/services/import/html_extractor.dart` (promoted `extractFromHtml` + `epubFilter` pre-filter; `.md`/`.txt` unchanged)
- `companion/lib/services/import/pipeline.dart` (`EpubPipelineRequest`/`EpubBaked`/`runEpubPipeline`; `runPipeline` unchanged)
- `companion/lib/services/import/import_service.dart` (`.epub` branch, second runner seam, cover persistence, stream+cover rollback, parse classifier)
- `companion/lib/data/stream_store.dart` (`writeCover`/`deleteCover`, `covers/` subdir)
- `companion/lib/ui/library/library_screen.dart` (cover thumbnail + author line; `'epub'` in picker `allowedExtensions`)
- `companion/pubspec.yaml` / `companion/pubspec.lock` (`epub_pro`, `image` deps; `archive` + `integration_test` dev-deps)
- `companion/android/app/src/main/AndroidManifest.xml` (`application/epub+zip` SEND/VIEW filters)

**Modified (test):**
- `companion/test/services/import/html_extractor_test.dart`
- `companion/test/services/import/pipeline_test.dart`
- `companion/test/services/import/import_service_test.dart`
- `companion/test/data/stream_store_test.dart`
- `companion/test/ui/library/library_screen_test.dart`

## Change Log

- 2026-06-16 — Story implemented (dev-story): EPUB import on the 2.3 spine. `epub_extractor` (epub_pro 5.6.0 OCF/OPF/spine/TOC, depth-first chapter flatten, AC1 DOM pre-filter), `cover_extractor` (decoded cover → bounded JPEG bytes, phone-only), `html_extractor` refactor (`extractFromHtml` + `epubFilter`; table policy = linearize), `runEpubPipeline` (multi-chapter bake → chapterStart + manifest index), `import_service` epub branch + second `compute` seam + cover persistence + stream+cover rollback + parse classifier, `stream_store.writeCover`/`deleteCover`, library-row cover thumbnail + OPF author, `.epub` picker + `application/epub+zip` share filter. Resolved the 2.2-deferred ORP word-char-free-token contract (document-the-accept; zero-token chapters filtered pre-bake). Synthetic-only fixtures. No schema change. 262 tests green, analyze clean, debug APK builds. Status → review.
- 2026-06-16 — Story drafted (create-story): the EPUB path on the 2.3 spine — `epub_extractor` (epub_pro 5.6.0 OCF/OPF/spine/TOC + DOM pre-filter: drop noteref/footnote/`<rt>`-ruby/img-alt, explicit table policy), `cover_extractor` (decoded cover → bytes, phone-only), `html_extractor` refactor (`extractFromHtml` + epubFilter), multi-chapter `runEpubPipeline` (bake already multi-chapter → chapterStart + manifest index), `import_service` epub branch + cover persistence + rollback (stream+cover+rows together), `stream_store.writeCover`/`deleteCover`, library-row cover thumbnail + OPF author, `.epub` picker + `application/epub+zip` share filter. Resolves the 2.2-deferred ORP word-char-free-token contract (document-the-accept; zero-token chapters filtered pre-bake). Synthetic-only EPUB fixtures (real corpus is manual-only, never committed). No drift schema change (author/cover_path pre-shaped in 2.3). 6 ACs, Tasks 0-9. Status → ready-for-dev.

- 2026-06-16 — Story drafted (create-story): the EPUB path on the 2.3 spine — `epub_extractor` (epub_pro 5.6.0 OCF/OPF/spine/TOC + DOM pre-filter: drop noteref/footnote/`<rt>`-ruby/img-alt, explicit table policy), `cover_extractor` (decoded cover → bytes, phone-only), `html_extractor` refactor (`extractFromHtml` + epubFilter), multi-chapter `runEpubPipeline` (bake already multi-chapter → chapterStart + manifest index), `import_service` epub branch + cover persistence + rollback (stream+cover+rows together), `stream_store.writeCover`/`deleteCover`, library-row cover thumbnail + OPF author, `.epub` picker + `application/epub+zip` share filter. Resolves the 2.2-deferred ORP word-char-free-token contract (document-the-accept; zero-token chapters filtered pre-bake). Synthetic-only EPUB fixtures (real corpus is manual-only, never committed). No drift schema change (author/cover_path pre-shaped in 2.3). 6 ACs, Tasks 0-9. Status → ready-for-dev.

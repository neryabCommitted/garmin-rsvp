---
baseline_commit: 4212cae0eb7eb26742ffd882b42747f5111b20d5
---

# Story 2.3: Import .txt/.md into the library

Status: review

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a reader,
I want to import a .txt or .md file and see it appear in my library,
so that the simplest book path works end-to-end before EPUB complexity.

This is the **first integration + UI story of Epic 2** and of the companion app. Stories 2.1 (sanitize/tokenize) and 2.2 (pace/ORP/fingerprint/bake) shipped the **pure-Dart pipeline** as host-testable leaf modules. This story builds the **impure shell** that turns them into a working feature: read a file, run the pipeline in an isolate, persist the artifacts (flat-file stream + drift rows), and render the library list. It is the spine the whole app hangs from — it stands up Riverpod, drift, the stream store, the first real screen, and repoints `main.dart` away from the Gate V2 spike harness.

**Scope guardrail:** this is the `.txt`/`.md` path only (single chapter, no cover, no author). EPUB structure/cover/chapters is **2.4**, book-detail/remove is **2.5**, and the full hardened failure taxonomy + ugly-corpus suite is **2.6**. Do the minimum typed-failure handling needed to not leave partial state (below); do not pull 2.6 forward.

## Acceptance Criteria

1. **AC1 — Import runs the pipeline in an isolate and persists.** Given a `.txt` or `.md` file, when I import it via the file picker (or the OS share sheet — see AC6), then `import_service` runs the 2.1→2.2 pipeline (`extract → sanitize → tokenize → bake`) **inside a `compute` isolate** and persists a **flat-file word stream** + a **drift `Books` row** (and its `Chapters` row(s)). For `.md`, the path is **markdown → HTML → the shared plain-text extractor**; `.txt` feeds the extractor's text directly. [Source: epics.md#Story-2.3 lines 439-441; architecture.md:469 data-flow; AR19/AR20]
2. **AC2 — Imported book appears in the library.** Given the import completes, when I view the library, then the book appears as an **M3 `ListTile`** with a **filename-derived title**, a **last-read placeholder** subtitle, and a **thin progress bar at 0%**. The list is driven by a **reactive drift stream** (FR16-ready). [Source: epics.md#Story-2.3 lines 443-445; architecture.md:202-204,233 Riverpod+drift streams; FR23]
3. **AC3 — Empty-library state.** Given an empty library, when I open the app, then I see **"Add a DRM-free EPUB to begin."** with an import action. [Source: epics.md#Story-2.3 lines 447-449]
4. **AC4 — UI never blocks; large-file target.** Given the import runs, when parsing a large file, then the UI **does not block** (the bake runs in the `compute` isolate, never on the UI thread) **and** a typical **100k-word file completes in ≤30 s (NFR5)**. [Source: epics.md#Story-2.3 lines 451-454; NFR5]
5. **AC5 — Only the tables needed here exist.** Given the drift schema, when this story lands, then **only the `Books` and `Chapters` tables** needed here are created — **no `Positions` or other unused tables** (those land in 4.5). [Source: epics.md#Story-2.3 lines 456-458; implementation-readiness-report:183 "Books/Chapters in 2.3, Positions in 4.5"]
6. **AC6 — Share-sheet entry (see Decision in Dev Notes).** Given a `.txt`/`.md` shared to the app via the OS share sheet, when the app receives it, then it runs the **same `import_service` path** as the picker. *Scope-fork: AC1's wording is "picker **or** share sheet." The default plan delivers the picker as the spine and wires the share sheet as the final, self-contained task (Task 8). If share-sheet plumbing balloons it may be split to a follow-up — see Dev Notes → "Decision: share-sheet scope" and confirm with Nerya before deferring.* [Source: epics.md#Story-2.3 line 440; architecture.md:399,401 `receive_sharing_intent` + intent filters; FR22]
7. **AC7 — No partial state on failure (minimal 2.6 seam).** Given an import fails (unreadable/empty/non-text file), when it returns, then `import_service` returns a **typed failure result — never an uncaught exception** — and **leaves behind no `Books`/`Chapters` row and no stream/JSONL file** (rollback). The full failure taxonomy + inline UI messaging + ugly-corpus suite is **2.6**; this story establishes the typed-result shape and the no-partial-state guarantee. [Source: epics.md#Story-2.6 lines 517-524; architecture.md:293 typed failure results, no silent catch; NFR8]

## Tasks / Subtasks

> TDD throughout: red → green → refactor, one task in order. Pure-logic tasks (1, 2) get unit tests first; the drift/store/service tasks (3, 4, 5) use in-memory drift + temp dirs; UI (6) uses widget tests; the plugin-bound tasks (7, 8) isolate the plugin behind a seam so logic stays testable.

- [x] **Task 0 — Dependencies & build setup** (AC: all)
  - [x] Add to `companion/pubspec.yaml` `dependencies:` — `flutter_riverpod: ^3.3.1` (arch-pinned, architecture.md:202), `drift: ^2.34.0`, `drift_flutter: ^0.3.1-wip`, `path_provider: ^2.1.5`, `file_picker:` (latest stable), `markdown:` (latest), `html:` (latest). Add `receive_sharing_intent:` only when starting Task 8.
  - [x] Add to `dev_dependencies:` — `drift_dev: ^2.34.0`, `build_runner: ^2.15.0`. [Source: drift.simonbinder.eu/setup, fetched 2026-06-14]
  - [x] `flutter pub get`; run `dart run build_runner build --delete-conflicting-outputs` after Task 3 defines the schema (generates `database.g.dart`).
  - [x] **Decision point — drift_flutter `-wip` caveat:** `drift_flutter ^0.3.1-wip` is a pre-release. If you prefer a stable pin, use the classic native setup instead (`drift` + `sqlite3_flutter_libs` + `path_provider`, `LazyDatabase`/`NativeDatabase.createInBackground`). Either is acceptable; record which you chose in Completion Notes. Recommended: `drift_flutter` for less boilerplate. [Source: drift docs — "Complete AppDatabase Setup" vs "Setup Native SQLite Database"]
  - [x] Confirm `flutter analyze` stays clean under the strict lints (`analysis_options.yaml`) after codegen — `.g.dart` is generated; do not hand-edit it.

- [x] **Task 1 — Shared plain-text extractor** `companion/lib/services/import/html_extractor.dart` (AC: #1) — PURE Dart
  - [x] Write failing tests first in `companion/test/services/import/html_extractor_test.dart` (red).
  - [x] Implement `String extractPlainText(String raw, {required bool isMarkdown})`:
    - `.txt` (`isMarkdown == false`): return `raw` unchanged (the file's own blank lines already encode paragraphs).
    - `.md` (`isMarkdown == true`): render to HTML with `package:markdown` (`md.markdownToHtml`), then parse with `package:html` (`parse(...)`) and walk block-level elements emitting their text **separated by a blank line (`\n\n`)** so the tokenizer's paragraph boundary (`\n\s*\n`, `tokenizer.dart:52`) fires at real paragraph breaks.
  - [x] **Why blank-line separation is load-bearing:** `tokenize()` derives `paragraphStart` **only** from `\n\s*\n`. If markdown blocks are joined without a blank line, every `paragraphStart` flag is silently lost → wrong FR pacing/rewind boundaries baked permanently into the stream (the watch never recomputes — `tokenizer.dart:7-9`). Cover this with an explicit test: a 2-paragraph markdown doc → the first token of the second paragraph has `paragraphStart == true` after the full `extract→sanitize→tokenize` chain.
  - [x] Drop non-prose nodes minimally for this story (script/style); a **richer DOM pre-filter (noteref/footnote/ruby/alt-text, table policy) is 2.4's `epub_extractor`** — do NOT build it here. This extractor is the **shared core 2.4 will reuse** for EPUB spine HTML (additive-file rationale mirrors `word_stream_baker.dart`; note it in Project Structure Notes).
  - [x] PURE: `package:markdown` and `package:html` are pure Dart — allowed. **No `package:flutter/*`**, no async I/O, no global state (AR19) so it runs inside `compute`. Green, refactor.

- [x] **Task 2 — Isolate pipeline entry** (top-level function for `compute`) (AC: #1, #4) — PURE Dart
  - [x] In `import_service.dart` (or a sibling), define a **top-level** function `BakedBook runPipeline(PipelineRequest req)` taking an immutable, sendable request `{String rawText, bool isMarkdown, String title, int salt}` and returning a `BakedBook`. It must be top-level (or `static`) so `compute` can use it.
  - [x] Body: `extractPlainText(rawText, isMarkdown:…)` → `sanitize(...)` (`text_sanitizer.dart:70`) → `tokenize(...)` (`tokenizer.dart`, `List<Token> tokenize(String)`) → wrap as a **single** `BakeChapter(title: title, tokens: tokens)` → `bake(title: title, chapters: [chapter], salt: salt)` (`word_stream_baker.dart:172`).
  - [x] **Empty/whitespace-only input:** `tokenize` may return `[]`; `bake` throws `ArgumentError` on a zero-token chapter (`word_stream_baker.dart:184-193`). Catch this boundary in `import_service` (Task 4) and map to a typed failure (AC7) — do not let it crash. Add a test asserting an empty `.txt` yields zero tokens → typed failure (not an unhandled throw).
  - [x] Test `runPipeline` directly (it's pure): `.txt` and `.md` inputs → assert word count, `paragraphStart` on paragraph 2, a non-empty `streamBytes`, and an 8-hex fingerprint. Red → green → refactor.

- [x] **Task 3 — drift schema** `companion/lib/data/db/database.dart` (AC: #5) + `database.g.dart` (generated)
  - [x] Write failing tests first in `companion/test/data/db/database_test.dart` using `NativeDatabase.memory()` (red).
  - [x] Define **exactly two tables** — `Books` and `Chapters` (AC5 — **no `Positions`**). drift naming: Dart classes `PascalCase` plural, SQL columns `snake_case` (architecture.md:254).
    - `Books`: `id` (`integer().autoIncrement()`), `title` (`text()`), `author` (`text().nullable()` — null for txt/md; 2.4 fills from OPF), `coverPath` (`text().named('cover_path').nullable()` — null here; 2.4 sets it), `streamPath` (`text().named('stream_path')` — flat-file path), `fingerprint` (`text()`), `totalWords` (`integer().named('total_words')`), `totalBonusMs` (`integer().named('total_bonus_ms')`), `createdAtEpochS` (`integer().named('created_at_epoch_s')`), `lastReadEpochS` (`integer().named('last_read_epoch_s').nullable()` — the AC2 last-read placeholder; stays null until Epic 4).
    - `Chapters`: `id` (autoIncrement), `bookId` (`integer().named('book_id').references(Books, #id)`), `chapterIndex` (`integer().named('chapter_index')`), `title` (`text()`), `wordOffset` (`integer().named('word_offset')` — absolute first-word index, mirrors `ChapterEntry.offset`), `cumulativeBonusMs` (`integer().named('cumulative_bonus_ms')`).
  - [x] **Do NOT store progress/position on `Books`.** Progress is the `Positions` table (Epic 4 / 4.5); the AC2 "0% progress bar" is a **UI placeholder** (`value: 0.0`), not a column (architecture.md:461; readiness:183). Adding a position column now would violate AC5.
  - [x] `@DriftDatabase(tables: [Books, Chapters])`, `schemaVersion => 1`, `driftDatabase(name: 'paceturner')` connection (or `LazyDatabase`+`NativeDatabase` per Task 0 choice). Expose a constructor that accepts an injected `QueryExecutor` so tests pass `NativeDatabase.memory()`. [Source: drift docs "Complete AppDatabase Setup"]
  - [x] Add the queries this story needs: `watchAllBooks()` → `Stream<List<Book>>` (ordered by `createdAtEpochS desc`, FR16-ready reactive), `insertBook(...)` / `insertChapters(...)`, and a `deleteBookCascade(id)` helper kept minimal (full Remove UX is 2.5; here it backs AC7 rollback). Test the stream emits on insert. Green, refactor.

- [x] **Task 4 — Flat-file stream store** `companion/lib/data/stream_store.dart` (AC: #1, #7)
  - [x] Write failing tests first in `companion/test/data/stream_store_test.dart` against a temp dir (red).
  - [x] Implement a store that writes the word stream + JSONL master as flat files under the app support dir (`getApplicationSupportDirectory()` via `path_provider`), in a `streams/` subdir. Recommended naming: `<fingerprint>.stream` (binary) + `<fingerprint>.jsonl` (debug master). [Source: architecture.md:177 "Flat files … paths referenced from drift", :433 `stream_store`]
  - [x] API: `Future<StoredStream> write({required Uint8List streamBytes, required List<String> debugJsonl, required String fingerprint})` returning the absolute `streamPath`; and `Future<void> delete(String streamPath)` (deletes the `.stream` and sibling `.jsonl`; idempotent — no throw if absent) for AC7 rollback / 2.5 Remove.
  - [x] Make the base directory **injectable** (constructor takes an optional `Directory`) so tests use a temp dir without `path_provider`'s platform channel. Test: write → file exists, bytes round-trip equal; delete → both files gone.

- [x] **Task 5 — `import_service.dart` orchestrator** `companion/lib/services/import/import_service.dart` (AC: #1, #4, #7)
  - [x] Write failing tests first in `companion/test/services/import/import_service_test.dart` (in-memory drift + temp-dir store) (red).
  - [x] **This is the impure shell** — Flutter/async allowed here (AR19 purity binds only the leaf pipeline modules, which is why `bake` runs in `compute`). Constructor-injected deps (architecture.md:285 — no globals/singletons): `AppDatabase db`, `StreamStore store`, and a `compute`-runner seam (default `compute`, overridable in tests so they can call `runPipeline` synchronously without spawning an isolate).
  - [x] `Future<ImportResult> importFile({required String path, required List<int> bytes})` (or accept the picked file's bytes + name):
    1. Derive `title` from the filename (strip directory + extension). Detect `isMarkdown` from the `.md`/`.markdown` extension; treat everything else as text.
    2. Decode bytes → String (`utf8.decode(..., allowMalformed: true)` so a bad-encoding file degrades rather than throws — NFR8).
    3. Compute `salt` here (caller-supplies-salt contract, `word_stream_baker.dart:165-166`): e.g. `DateTime.now().millisecondsSinceEpoch & 0x7fffffff`.
    4. `final baked = await _runner(runPipeline, PipelineRequest(rawText, isMarkdown, title, salt));` — **bake runs off the UI thread (AC4).**
    5. Persist **stream first, then drift in a transaction**: `store.write(...)` → `db.transaction(() { insert Books row from baked.manifest; insert one Chapters row per baked.manifest.chapters (here exactly 1); })`. Return `ImportSuccess(bookId)`.
  - [x] **AC7 rollback:** wrap steps 4–5 so any failure (empty→`ArgumentError` from `bake`, decode issue, I/O error, drift error) is caught and mapped to a **typed `ImportFailure(reason, filename)`** — and if the stream file was already written but the drift insert failed, `store.delete(...)` it. No `ImportFailure` path may leave a `Books`/`Chapters` row or a stream/JSONL file. **No silent `catch {}`** (architecture.md:293).
  - [x] Define the typed result: `sealed class ImportResult` → `ImportSuccess(int bookId)` / `ImportFailure(ImportFailureReason reason, String filename)`. Keep `ImportFailureReason` a small enum (`emptyContent`, `unreadable`, `unsupported`, `ioError`) — **2.6 extends it**; do not over-build the taxonomy now.
  - [x] DB access stays on the **main isolate** — only `runPipeline` crosses into `compute`. Add a Dev-Notes-level comment: never pass the drift connection or `StreamStore` into `compute` (not sendable / platform-bound).
  - [x] Tests: a small `.txt` fixture → `ImportSuccess`, 1 Books row with correct `fingerprint`/`totalWords`/`streamPath`, 1 Chapters row at offset 0, stream file present. A `.md` fixture → paragraph structure preserved (token-level assertion via the baked JSONL or a `runPipeline` check). An **empty** file → `ImportFailure(emptyContent)`, **zero** Books rows, **no** stream file (AC7). Green, refactor.

- [x] **Task 6 — Library UI** `companion/lib/ui/library/` + providers + app shell (AC: #2, #3)
  - [x] Providers (`companion/lib/ui/library/library_providers.dart` or `lib/providers.dart`): `databaseProvider` (singleton `AppDatabase`), `streamStoreProvider`, `importServiceProvider` (composes the two), and `libraryProvider` = `StreamProvider` over `db.watchAllBooks()`. Names end in `Provider` (architecture.md:285).
  - [x] `app.dart` (new): `MaterialApp` with **Material 3 + dynamic color** (`useMaterial3: true`, `ColorScheme` from dynamic color with system light/dark — architecture.md:204), `home: LibraryScreen`. `main.dart`: wrap in `ProviderScope`. **Repoint `home` away from `GateV2Screen`** — but **keep `gate_v2/` files and their tests intact** (Story 1.4/1.5 harness, still referenced by `test/gate_v2/`); just stop booting into it. (Optional: a debug-only route to the gate harness; not required.)
  - [x] `library_screen.dart`:
    - **Empty state (AC3):** when the list is empty, center the text **"Add a DRM-free EPUB to begin."** + an import affordance (FAB or button).
    - **Populated (AC2):** `ListView` of M3 `ListTile`s — `title` = book title, `subtitle` = last-read placeholder (e.g. "Not started" / "—"; `lastReadEpochS` is null), trailing/below a **thin `LinearProgressIndicator(value: 0.0)`**. No cover here (2.4).
    - Import action → `file_picker` (`FileType.custom, allowedExtensions: ['txt','md']`) → read bytes → `importService.importFile(...)`. Show a progress indicator while the future runs (UI stays responsive — AC4); on `ImportFailure` show a `SnackBar` (full inline error UX is 2.6).
  - [x] Widget tests (`test/ui/library/library_screen_test.dart`): empty state renders the exact AC3 string + import affordance; with a fake `libraryProvider` overriding to a list of one book, a `ListTile` with the title and a 0.0-value progress bar renders. Use `ProviderScope(overrides: [...])` to inject fakes — do **not** hit real drift/plugins in widget tests. Green, refactor.

- [x] **Task 7 — NFR5 / non-blocking evidence** (AC: #4)
  - [x] Add a correctness-at-scale test: synthesize a ~100k-word input → `runPipeline` (pure) → assert it completes and `manifest.totalWords ≈ 100k` and the stream is well-formed. This proves throughput/correctness without a flaky wall-clock gate.
  - [x] **Do NOT assert a hard 30 s wall-clock in CI** (CI hardware varies → flaky). Treat ≤30 s as a documented on-device target; note in Completion Notes that AC4's non-block is structurally guaranteed by running `bake` in `compute`, and the 30 s figure is validated manually on a real device. (If you want a guard, a generous soft bound like ≤120 s purely to catch pathological regressions is acceptable — comment it as such.)

- [x] **Task 8 — Share-sheet entry (receive_sharing_intent)** (AC: #6) — *see Decision in Dev Notes; confirm scope with Nerya if it balloons*
  - [x] Add `receive_sharing_intent:` (latest) to pubspec.
  - [x] Android native: add `.txt`/`.md` (`text/plain`, and `text/markdown`/`*.md` via mime/extension) `SEND`/`VIEW` `intent-filter`s to `companion/android/app/src/main/AndroidManifest.xml` (currently only `MAIN`/`LAUNCHER` — verified). [Source: architecture.md:401 "share-sheet intent filters"]
  - [x] Wire the initial + streamed shared-file events to call the **same** `importService.importFile(...)` path (no second pipeline). Handle both cold-start (`getInitialMedia`) and warm (`getMediaStream`) deliveries; dispose the subscription.
  - [x] This path is **plugin/platform-bound and not unit-testable** — keep the handler thin (it only adapts the plugin payload into the already-tested `importFile`), and verify manually via a real share. Note the manual-verification step in Completion Notes.

- [x] **Task 9 — Verify & keep CI green** (AC: all)
  - [x] `cd companion && flutter test` — all pass (183 baseline from 2.2 + new; no regression).
  - [x] `flutter analyze` — clean under strict-casts / strict-inference / strict-raw-types. (Generated `*.g.dart` is exempt from hand-edits but must analyze clean.)
  - [x] Grep-confirm AR19 purity preserved on the leaf modules: no new `package:flutter/*` under the **pure** files (`html_extractor.dart`, and `runPipeline`'s pure chain). `import_service.dart` itself MAY import Flutter/async (it's the shell) — that's correct.
  - [x] Confirm layering (architecture.md:452): `ui/ → services/ → data/`. `ui/` must not import `drift`/`stream_store` directly — it goes through providers/`import_service`.

## Dev Notes

### What this story IS / ISN'T
- **IS:** the impure integration shell — `import_service` (isolate orchestration + persistence), `html_extractor` (shared md/EPUB plain-text core), drift `Books`+`Chapters` schema, flat-file `stream_store`, Riverpod providers, the first real screen (`LibraryScreen` + empty state), repointing `main.dart`, file-picker entry, and (Task 8) the share-sheet entry. Minimal typed-failure + no-partial-state seam.
- **ISN'T:** EPUB parsing / cover / real chapters / OPF author (**2.4** `epub_extractor.dart` + `cover_extractor.dart`); book-detail screen + Remove UX + Restart (**2.5**); the full failure taxonomy, inline error messaging, and ugly-EPUB corpus suite (**2.6**); `Positions`/progress/sync (**Epic 4 / 4.5**); transfer/Send-to-watch (**Epic 4**). Do not pull these forward.

### Reuse — do NOT reinvent (the pipeline already exists, fully tested)
- **`bake(...)`** — `word_stream_baker.dart:172`: `BakedBook bake({required String title, required List<BakeChapter> chapters, required int salt})`. Returns `BakedBook { Uint8List streamBytes; BookManifest manifest; List<String> debugJsonl; }`. The **manifest** (`BookManifest { title, totalWords, totalBonusMs, fingerprint, List<ChapterEntry> chapters }`, `:87`) is exactly what the drift `Books` + `Chapters` rows are populated from — `ChapterEntry { offset, title, cumulativeBonusMs }` (`:54`) maps 1:1 to a `Chapters` row. **Do not recompute any of this.**
- **`sanitize(String raw, {bool asciiFold = false}) → String`** — `text_sanitizer.dart:70`. Default `asciiFold:false` (leftover non-folded glyphs are valid UTF-8 and bake fine — 2.1 note).
- **`tokenize(String sanitized) → List<Token>`** — `tokenizer.dart`. Paragraph boundary is `\n\s*\n` (`:52`); this is why the md extractor must emit blank lines between blocks. `Token { text, paragraphStart, sentenceEnd }` (`:17`). The **last token of the text is forced `sentenceEnd=true`** (2.1 terminal-boundary guarantee).
- **`BakeChapter { String title; List<Token> tokens }`** — `word_stream_baker.dart:34`. txt/md = a **single** `BakeChapter`. Each chapter must have ≥1 token (`bake` throws otherwise — that's your empty-file failure path).
- **`encodeChunk`/`decodeChunk`, `WordRecord`, `ProtocolKeys.*`** — already used inside `bake`; you do not touch them here.
- **Salt contract:** `bake`'s `salt` makes a re-bake of identical text yield a fresh SPEC §7 fingerprint; **the caller (this story) supplies it** (`word_stream_baker.dart:165-166`, 2.2 Completion Notes). Use a timestamp/counter — keep it deterministic in tests (pass a fixed salt).

### Isolate boundary (AC1, AC4) — the one thing that's easy to get wrong
- **`compute(runPipeline, request)`** runs the **pure** `extract→sanitize→tokenize→bake` chain on a background isolate. `BakedBook` is sendable (it's `Uint8List` + immutable value objects with primitive/`List<String>` fields), so `compute` can return it across the isolate boundary.
- **drift and `StreamStore` stay on the main isolate.** Do NOT pass the database connection or the store into `compute` — drift connections are not sendable and `path_provider` is platform-bound. The flow is: read bytes (main) → `compute` bake (background) → write store + insert drift rows (main). This is exactly `architecture.md:469`'s data-flow up to the drift rows.
- `package:markdown` and `package:html` are **pure Dart** — safe inside `compute`. `file_picker`/`receive_sharing_intent` are platform plugins — they run on the main isolate, in the UI layer, never inside `compute`.

### Decision: share-sheet scope (AC6 / Task 8)
- AC1 reads "via the file picker **or** the OS share sheet." The architecture provisions `receive_sharing_intent` + Android intent filters (architecture.md:399,401), and FR22 names the share sheet — so it is **in scope** and the default plan delivers it (Task 8).
- **But** the share-sheet path is platform-plumbing-heavy (native intent filters + cold/warm delivery lifecycle) and not unit-testable. The picker path is the testable spine and satisfies the end-to-end goal on its own. **Recommendation:** build Tasks 0–7 first (picker spine, fully green), then Task 8. If Task 8 plumbing proves heavy/flaky, it is a clean candidate to split to a 2.3b follow-up — **confirm with Nerya before deferring** rather than dropping silently. Either way, Task 8 must reuse `importFile` — never a second pipeline.

### drift setup specifics [Source: drift.simonbinder.eu/setup, fetched 2026-06-14]
- Deps: `drift: ^2.34.0`, `drift_flutter: ^0.3.1-wip`, `path_provider: ^2.1.5`; dev `drift_dev: ^2.34.0`, `build_runner: ^2.15.0`. Codegen: `dart run build_runner build --delete-conflicting-outputs` → `database.g.dart` (committed; `part 'database.g.dart';`).
- App connection (drift_flutter): `driftDatabase(name: 'paceturner', native: DriftNativeOptions(databaseDirectory: getApplicationSupportDirectory))`. **Stable alternative** if you avoid the `-wip` pre-release: `drift` + `sqlite3_flutter_libs` + `LazyDatabase(() async { … NativeDatabase.createInBackground(File(p.join(dir.path,'db.sqlite'))) })`.
- **Testing drift:** construct `AppDatabase(NativeDatabase.memory())` — inject the executor via the constructor. In-memory needs `sqlite3` on the host; CI ubuntu images ship it. Keep table tests free of `path_provider`.
- Naming (architecture.md:254): Dart table classes `PascalCase` plural (`Books`, `Chapters`); columns `snake_case` via `.named('…')`; FK `book_id`.

### Persistence model & boundaries
- **drift owns metadata** (Books/Chapters); **`stream_store` owns the bulk bytes** (the binary stream + JSONL master as flat files); each has a single owning module (architecture.md:453,177). Never put multi-MB blobs in SQLite.
- `Books.streamPath` is the bridge: drift row → flat file. Recommended file id = the fingerprint (`<fp>.stream`/`<fp>.jsonl`).
- **No `Positions` table, no progress column** — progress/sync is Epic 4/4.5 (AC5). The 0% bar and the last-read subtitle are **UI placeholders** until then.

### UX / Material 3 [Source: architecture.md:204 — "Material 3 with dynamic color, system light/dark, M3 defaults"; EXPERIENCE.md surfaces = Library/Import]
- M3 defaults throughout; dynamic color + system light/dark. Library + Import are the two surfaces this story touches; Book detail/Transfer/Settings are later stories.
- The empty-state copy is **verbatim**: `Add a DRM-free EPUB to begin.` (AC3). (It says "EPUB" even though this story imports txt/md — that's the product's canonical empty-state line; do not reword.)

### NFR5 / non-blocking (AC4)
- The non-block is **structural**: `bake` runs in `compute`, so the 100k-word parse never touches the UI thread. Prove correctness-at-scale with a synthetic ~100k-word `runPipeline` test; treat the **≤30 s** figure as an on-device manual target, not a CI wall-clock assertion (CI hardware variance → flaky). See Task 7.

### Architecture compliance / guardrails
- **AR19:** purity binds the **leaf pipeline modules** (`text_sanitizer`, `tokenizer`, `pacing`, `orp`, `fingerprint`, `word_stream_baker`, and the new `html_extractor` + `runPipeline`) — no `package:flutter/*`, no global mutable state, no async I/O, so they run unchanged in `compute`. `import_service.dart`, `stream_store.dart`, providers, and `ui/` are the **impure shell** and MAY use Flutter/async — that's by design.
- **Layering (architecture.md:452):** `ui/ → services/ → data/`. `ui/` never imports `drift`/`stream_store`/`ciq_bridge` directly — only via providers/`import_service`.
- **AR8:** no inline protocol magic — but you won't touch protocol bytes here; `bake` already handles flags via `ProtocolKeys.*`.
- **No silent `catch {}`** (architecture.md:293): every failure → a typed `ImportFailure` member (AC7).
- Keep `flutter analyze` clean under strict lints (`analysis_options.yaml`).

### Previous-story intelligence
- **2.2 (done):** shipped `bake`/`BakedBook`/`BookManifest`/`ChapterEntry`/`BakeChapter`, salted FNV-1a fingerprint (caller supplies salt), JSONL master (line 0 = manifest, lines 1..n = words). 183 tests, analyze clean, AR19 purity grep clean. **This story consumes `bake` verbatim** and supplies the salt + the file/persistence/UI shell it explicitly deferred to 2.3 (`word_stream_baker.dart:10-13`, 2.2 Dev Notes "Isn't").
- **2.1 (done):** `sanitize` + `tokenize`; paragraph boundary `\n\s*\n`; last-token `sentenceEnd=true`. Consequence here: feed the extractor's output to `sanitize`→`tokenize` and the boundaries are already correct — your only job is to make sure `.md` extraction **preserves blank lines** so paragraphs survive (Task 1).
- **Deferred-work relevant to 2.3** (`deferred-work.md`):
  - ASCII-fold table is Latin-1-only — not this story's concern (default `asciiFold:false`); the corpus-driven fold extension is later (Nerya is sourcing a real corpus before 2.4/2.6).
  - ORP word-char-free-token contract is to be resolved in **2.4**, not here.
  - The watch decode-watchdog constraint is an **Epic 4 / Story 4.1** binding — irrelevant to phone-side import.

### Project Structure Notes
- New files (all under the arch's prescribed tree, architecture.md:404-445):
  - `companion/lib/services/import/import_service.dart` (impure orchestrator — arch:413) + `html_extractor.dart` (**additive shared extractor** — arch lists `epub_extractor.dart` for 2.4's DOM walk; the pure plain-text core is introduced here for reuse, same additive-variance pattern as `word_stream_baker.dart`; note it).
  - `companion/lib/data/db/database.dart` (+ generated `database.g.dart`) — arch:431.
  - `companion/lib/data/stream_store.dart` — arch:433.
  - `companion/lib/ui/library/library_screen.dart` + `library_providers.dart`; `companion/lib/app.dart` — arch:435-436,405.
  - Mirrored tests under `companion/test/{services/import,data/db,data,ui/library}/`.
- Modified: `companion/pubspec.yaml` (deps), `companion/lib/main.dart` (ProviderScope + repoint home), `companion/android/app/src/main/AndroidManifest.xml` (Task 8 intent filters only).
- Preserved untouched: `gate_v2/` + `test/gate_v2/` (spike harness, still referenced), `protocol/` (reused, not modified), the 2.1/2.2 pipeline leaf modules.

### Testing standards [Source: architecture.md:264 test placement; existing test/ patterns]
- Framework: `flutter_test` + `test`. Tests mirror `lib/` paths under `companion/test/`.
- Pure modules (`html_extractor`, `runPipeline`) — plain unit tests, no widget tree. drift — `NativeDatabase.memory()`. `stream_store` — temp dir via injected `Directory`. `import_service` — in-memory drift + temp store + a synchronous `compute`-runner override. UI — widget tests with `ProviderScope(overrides:[…])`, no real drift/plugins.
- Plugin-bound paths (`file_picker`, `receive_sharing_intent`) are not unit-tested — kept thin and manually verified; their logic lives in the already-tested `importFile`.
- TDD: red → green → refactor, one task in order (team principle).

### References
- [Source: epics.md#Epic-2 / Story 2.3, lines 431-458; Story 2.4 lines 460-483 (what's deferred); Story 2.6 lines 509-528 (failure taxonomy deferred)]
- [Source: architecture.md:172-181 (Data Architecture — drift, flat files), :199-205 (Frontend — Riverpod/M3), :254 (drift naming), :285 (provider/DI naming), :293 (typed failures, no silent catch), :404-445 (companion directory structure), :452-453 (layering + data boundaries), :461,469 (FR-to-structure, book-delivery data-flow)]
- [Source: implementation-readiness-report-2026-06-09.md:183 (Books/Chapters in 2.3, Positions in 4.5); :142 (NFR5→2.3)]
- [Source: companion/lib/services/import/word_stream_baker.dart:34 BakeChapter, :54 ChapterEntry, :87 BookManifest, :127 BakedBook, :172 bake, :165-166 caller-supplies-salt]
- [Source: companion/lib/services/import/text_sanitizer.dart:70 sanitize; tokenizer.dart:17 Token, :52 paragraph boundary]
- [Source: companion/lib/main.dart (current boots GateV2Screen — to repoint); companion/android/app/src/main/AndroidManifest.xml (MAIN/LAUNCHER only — to add filters in Task 8)]
- [Source: drift.simonbinder.eu/setup — dep versions + driftDatabase/LazyDatabase setup, fetched 2026-06-14 via ctx7]
- [Source: 2-2-…md (bake API, salt contract, JSONL), 2-1-…md (Token contract, paragraph boundary), deferred-work.md (ASCII-fold / ORP / watchdog — none block 2.3)]

## Dev Agent Record

### Agent Model Used

Amelia (dev-story workflow) — claude-opus-4-8[1m].

### Debug Log References

- `flutter test` — 221 pass (183 baseline + 38 new), 0 fail.
- `flutter analyze` — 0 issues (strict-casts / strict-inference / strict-raw-types).
- `flutter build apk --debug` — ✓ `app-debug.apk` (after Task-8 Gradle fixes below).
- `dart run build_runner build` — generated `lib/data/db/database.g.dart`.

### Completion Notes List

- **Task 0 — drift connection decision:** chose the **stable native setup**
  (`drift` + `sqlite3_flutter_libs` + `path_provider` + `LazyDatabase` /
  `NativeDatabase.createInBackground`) over the recommended `drift_flutter
  ^0.3.1-wip`, because the `-wip` pre-release does not resolve against the
  current pub constraints. Tests inject `NativeDatabase.memory()` via the
  `AppDatabase(QueryExecutor)` constructor. Resolved versions: drift 2.34.0,
  flutter_riverpod 3.3.2, file_picker 8.3.7, markdown 7.3.1, html 0.15.6,
  receive_sharing_intent 1.8.1.
- **Pure pipeline split:** `runPipeline` + `PipelineRequest` live in a pure
  sibling `pipeline.dart` (no Flutter import) so the AR19 purity grep stays
  clean; `import_service.dart` is the impure shell and imports
  `package:flutter/foundation.dart` (`compute`) by design.
- **AC1/AC4 isolate boundary:** only `runPipeline` crosses into `compute`; the
  drift connection and `StreamStore` stay on the main isolate. The `compute`
  runner is a constructor-injected seam (tests run it synchronously with a fixed
  salt → deterministic fingerprints).
- **AC4/NFR5:** non-block is structural (bake runs in `compute`). The 100k-word
  `scale_test` proves correctness-at-scale (totalWords == 100k, stream
  round-trips via `decodeChunk`); the ≤30 s figure is a documented on-device
  target, **not** a CI wall-clock gate (only a generous ≤120 s pathological
  guard). On-device timing still to be confirmed on the Fenix companion build.
- **AC5:** drift has exactly `Books` + `Chapters` (asserted by a table-name
  test); no `Positions`/progress column. The 0% bar + "Not started" subtitle are
  UI placeholders.
- **AC7:** `sealed ImportResult` (`ImportSuccess`/`ImportFailure` +
  `ImportFailureReason` enum). Rollback verified: empty/whitespace → typed
  `emptyContent` with zero rows and no stream file; a forced drift failure after
  the stream write deletes the orphan (`store.delete`). No silent `catch {}`.
- **Task 6 layering:** widgets reach drift/import **only** via providers + the
  `Book` model type; `library_screen.dart` imports neither `package:drift` nor
  `stream_store`. The DI providers (`library_providers.dart`) compose `data/` by
  design (story-sanctioned). `main.dart` repointed off `GateV2Screen`;
  `gate_v2/` + `test/gate_v2/` preserved and still green. M3 theming via seeded
  `ColorScheme` + system light/dark (`themeMode.system`) — no extra
  `dynamic_color` dep (not provisioned in Task 0).
- **Task 8 — share-sheet (delivered per Nerya's call):** `receive_sharing_intent`
  behind a `ShareSource` seam whose provider **defaults to a no-op**, so widget
  tests never touch platform channels; only `main.dart` injects
  `PluginShareSource`. Android `SEND`/`VIEW` intent filters scoped to
  `text/plain` + `text/markdown`; `launchMode` → `singleTask` (plugin
  requirement). The handler is thin and routes both warm (`getMediaStream`) and
  cold (`getInitialMedia`) deliveries through the same `importFile`. This path is
  platform-bound → **manual on-device verification still pending** (sharing a
  .txt/.md from another app should land it in the library).
- **Task 8 — build fixes** (required to make the APK assemble with the new native
  plugins; researched, KasemJaffer/receive_sharing_intent#326,#344):
  - `android/build.gradle.kts`: subprojects `afterEvaluate` forces plugin modules
    to Java 17 (fixes "Inconsistent JVM-target" Java 11 vs Kotlin 17) and bumps
    plugin `compileSdk` to 36; guarded with `state.executed` so the
    already-evaluated `:app` (already 17/17) is skipped.
  - `android/app/build.gradle.kts`: `compileSdk = 36` (file_picker's transitive
    `flutter_plugin_android_lifecycle` requires ≥36).
  - Informational warning remains: receive_sharing_intent applies KGP (future
    Flutter built-in-Kotlin migration) — does not block the current build.

### File List

**New — lib:**
- `companion/lib/services/import/html_extractor.dart`
- `companion/lib/services/import/pipeline.dart`
- `companion/lib/data/db/database.dart`
- `companion/lib/data/db/database.g.dart` (generated)
- `companion/lib/data/stream_store.dart`
- `companion/lib/services/import/import_service.dart`
- `companion/lib/ui/library/library_providers.dart`
- `companion/lib/ui/library/library_screen.dart`
- `companion/lib/ui/library/share_receiver.dart`
- `companion/lib/app.dart`

**New — test:**
- `companion/test/services/import/html_extractor_test.dart`
- `companion/test/services/import/pipeline_test.dart`
- `companion/test/data/db/database_test.dart`
- `companion/test/data/stream_store_test.dart`
- `companion/test/services/import/import_service_test.dart`
- `companion/test/services/import/scale_test.dart`
- `companion/test/ui/library/library_screen_test.dart`

**Modified:**
- `companion/pubspec.yaml`, `companion/pubspec.lock` (deps)
- `companion/lib/main.dart` (ProviderScope + repoint home + inject share source)
- `companion/test/widget_test.dart` (repurposed: gate-v2 boot → library boot)
- `companion/android/app/src/main/AndroidManifest.xml` (share intent filters, singleTask)
- `companion/android/build.gradle.kts` (plugin JVM target + compileSdk alignment)
- `companion/android/app/build.gradle.kts` (compileSdk 36)

## Change Log

- 2026-06-14 — Story implemented (dev-story): all Tasks 0-9 complete. Picker spine
  (Tasks 0-7) + share-sheet (Task 8, delivered per Nerya's scope call) + verify
  (Task 9). 38 new tests (html_extractor 11, pipeline 5, drift 7, stream_store 7,
  import_service 7, library widgets 4 incl. boot, scale 1) → 221 total green;
  analyze clean; debug APK builds. drift stable-native setup (drift_flutter -wip
  unresolvable); Android Gradle JVM-target + compileSdk fixes for the new native
  plugins. Status → review. Share-sheet runtime behaviour pending manual
  on-device verification.
- 2026-06-14 — Story drafted (create-story): the first Epic-2 integration+UI story — `import_service` (isolate orchestration via `compute(runPipeline)`), shared `html_extractor` (md→HTML→text, blank-line paragraph preservation), drift `Books`+`Chapters` schema (no `Positions` — AC5), flat-file `stream_store`, Riverpod providers, `LibraryScreen` + empty state, `main.dart` repoint off the Gate V2 spike, file-picker entry, share-sheet entry (Task 8, scope-fork noted), and a minimal typed-failure / no-partial-state seam (AC7). 7 ACs, Tasks 0-9. drift setup grounded against current docs (drift 2.34 / drift_flutter 0.3.1-wip). Status → ready-for-dev.

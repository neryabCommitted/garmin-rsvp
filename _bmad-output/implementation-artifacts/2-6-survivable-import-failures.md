---
baseline_commit: 0ffeadd05d97025517f6ec6fb734c8839ad7e4b7
---

# Story 2.6: Survivable import failures

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a reader,
I want a clear message when a file can't be read,
so that a bad book never crashes the app or half-appears (FR26, R6).

## Acceptance Criteria

**AC1 — Typed failure, never a crash**
**Given** a malformed, DRM-protected, or unsupported file
**When** import fails
**Then** `import_service` returns a typed `ImportFailure` result, never an exception that crashes the app.

**AC2 — Inline message + no partial state**
**Given** a failed import
**When** I look at the library
**Then** I see an **inline** message **"Couldn't read {filename} — {reason}"** (EXPERIENCE.md:114 — canonical copy)
**And** no partial book row, stream file (`.stream`/`.jsonl`), or cover file is left behind.

**AC3 — Ugly-EPUB corpus survives**
**Given** the ugly-EPUB fixture corpus (footnote-riddled, obfuscated, creatively encoded, DRM, nested-table, oversized-token, bad-metadata)
**When** the importer test suite runs
**Then** each fixture either imports cleanly or fails with a typed, message-bearing `ImportFailure` — **never a crash and never mid-sentence pollution** in the baked stream.

---

## Scope clarification — what this story does and does NOT do

This story is the **failure-taxonomy + survivability** capstone of Epic 2. The happy-path import pipeline (txt/md in 2.3, EPUB in 2.4) and the library/detail UI (2.5) already exist and **must keep working**. 2.6 hardens the *failure* edges that prior stories deliberately deferred to here.

**IN scope (this story owns these):**
1. A **robust typed failure taxonomy** that classifies by *structure/type*, not by fragile substring-matching of locale/version-dependent exception text.
2. Splitting the txt/md `ArgumentError` arm so a non-empty file with an oversized/unencodable token is **not** mislabeled "empty."
3. The **inline** library error message with the canonical copy (replacing the interim SnackBar).
4. An **ugly-EPUB fixture corpus** + tests proving every fixture imports cleanly or typed-fails — never crashes, never pollutes the stream.
5. Fixing the **nested-`<table>` double-emit** bug (it produces literal mid-sentence pollution, which AC3 forbids).
6. Hardening the **cover catch** (too-broad `catch (_)` + unbounded decode).

**OUT of scope (do NOT build here):**
- **Re-import dedup.** Per `deferred-work.md` (2026-06-21, Nerya): dedup is keyed on raw-file-content identity, needs a schema add (content hash) + a uniqueness check, and is explicitly **NOT a 2.6 freebie**. It gets its own Story 2.7. Do not touch the salt or add a hash here.
- **Transfer / send-to-watch** failures (Epic 4).
- **Share-sheet UX hardening** (queue-vs-reject decision, markdown-as-text mis-typing) — deferred to the on-device share pass, not 2.6.
- **Pacing/ASCII-fold fidelity** tuning (Gate V4 recalibration).

---

## Tasks / Subtasks

- [x] **Task 1 — Introduce a typed failure-classification seam in the pure pipeline (AC1, AC3)**
  - [x] 1.1 In `companion/lib/services/import/` define a small typed exception hierarchy that the pure pipeline throws, mirroring the existing `EpubEmptyContentException` (`epub_extractor.dart:50`). Add (at minimum): a `TextEmptyContentException` (zero tokens from txt/md) and an `UnencodableContentException` (a token the SPEC §5 wire cannot carry — >255 UTF-8 bytes or unpaired surrogate). Keep them pure-Dart (no `package:flutter`), so they cross the `compute` boundary.
  - [x] 1.2 In `pipeline.dart#runPipeline`: after `tokenize`, if `tokens.isEmpty` throw `TextEmptyContentException` **before** calling `bake` (so the cause is typed, not an opaque `ArgumentError` from `bake`). Wrap the `bake(...)` call so an `encodeChunk` `ArgumentError` whose cause is an oversized/surrogate word is rethrown as `UnencodableContentException` (inspect `encodeChunk` throw sites at `stream_codec.dart:100-112` — the ">255 bytes" / "unpaired surrogates" arms). Do **not** swallow `bake`'s zero-chapter `ArgumentError` — that is a programming bug, let it surface as `ioError`.
  - [x] 1.3 Extend `ImportFailureReason` only if needed. Current enum: `emptyContent, unreadable, unsupported, ioError`. The four are sufficient — map `UnencodableContentException` → `unsupported` ("contains text we can't encode"), zero-token → `emptyContent`. Do **not** over-build the enum (the seed comment in `import_service.dart:34` says keep it small).

- [x] **Task 2 — Replace brittle EPUB parse-error classification with structural detection (AC1, AC3)**
  - [x] 2.1 Rewrite `import_service.dart#_classifyParseError` (lines ~284-292). It currently substring-matches the lowercased exception message (`encrypt`/`drm`/`obfusc`) — locale- and `epub_pro`-version-dependent and explicitly flagged brittle (deferred-work 2.4, line 50). Replace with **structural detection**: before/independent of relying on `epub_pro`'s error text, inspect the OCF zip with `package:archive` for **`META-INF/encryption.xml`** (the OCF-standard location for encryption/DRM metadata). Presence → `unsupported` (DRM/encrypted). This is deterministic and locale-independent.
  - [x] 2.2 For everything else `epub_pro` throws (not-a-zip, missing/invalid OPF, malformed structure) → `unreadable`. Keep the `EpubEmptyContentException` → `emptyContent` arm as-is (`import_service.dart` `_importEpub` catch).
  - [x] 2.3 The encryption-detection probe must itself never throw: if `package:archive` can't even open the bytes as a zip, that's `unreadable` (not a crash). Do this probe in the **pure** layer (it's pure-Dart) — fold it into the EPUB pipeline/extractor so the classification crosses the isolate boundary as a typed result, OR run it in the shell on the raw bytes before dispatch. Prefer the pure layer (`extractEpub`/`runEpubPipeline`) to keep `import_service` thin (architecture.md:469).

- [x] **Task 3 — Fix nested-`<table>` double-emit (mid-sentence pollution — AC3)**
  - [x] 3.1 In `html_extractor.dart` `_linearizeTable` (~lines 132-148): `table.querySelectorAll('tr')` matches **descendant** rows, so a `<table>` nested inside a `<td>` has its text emitted once via the outer cell's `_blockText` and again when the loop reaches the inner `<tr>`s → prose baked **twice** (deferred-work 2.4, line 51). Scope row selection to **direct** rows of the current table (e.g. only `<tr>` whose nearest ancestor `<table>` is this table — walk `tbody`/`thead`/`tr` children, not `querySelectorAll`). Verify against a nested-table fixture (Task 5) that each cell's text appears exactly once in the baked stream.

- [x] **Task 4 — Harden the cover extraction (AC1 robustness)**
  - [x] 4.1 In `epub_extractor.dart` cover block (~lines 96-111) the `catch (_)` is intended to degrade a bad cover to no-cover (AC2 valid state) but also swallows programming/OOM errors; and `encodeCover` decodes the full image before resize, so a pathologically large cover can OOM the `compute` isolate (deferred-work 2.4, line 52). Keep the degrade-to-no-cover behavior, but: (a) guard the decode so an absurdly large source image is rejected (size/dimension ceiling) rather than decoded whole, and (b) confirm a no-cover degrade never leaves a partial cover file (it can't today — cover is written in the shell only when `coverBytes != null` — assert this with a fixture in Task 5). Keep this conservative; do not rewrite `cover_extractor.dart` wholesale.

- [x] **Task 5 — Build the ugly-EPUB fixture corpus + harden the existing fixtures (AC3)**
  - [x] 5.1 Extend `test/fixtures/epubs/epub_fixture_builder.dart` with new synthetic-only scenario helpers (NEVER use the real corpus at `/home/nerya/Desktop/epub` as a test input — memory: epub-corpus-location). The builder already assembles in-memory OCF zips with `package:archive`. Add helpers for the ugly cases:
    - **DRM/encrypted**: a structurally valid OCF that also contains `META-INF/encryption.xml` → must classify `unsupported`. (Add a `withEncryption` flag or a dedicated builder.)
    - **Nested-table**: a chapter whose `<td>` contains another `<table>` → proves Task 3 (each cell once, no duplication).
    - **Footnote/ruby/alt-heavy** beyond the existing `preFilterEpub` (already covers a basic case) — a denser pre-filter torture chapter.
    - **Oversized-token**: a chapter containing a single >255-UTF-8-byte token (long URL / base64 blob / ~86-char CJK run) → must classify `unsupported`, not `emptyContent` (this is the txt/md case too — Task 1.2).
    - **Bad-metadata**: an OPF title/author carrying an unpaired UTF-16 surrogate → must still import (already handled by `stripUnpairedSurrogates` in `epub_extractor.dart`; add a regression fixture so it stays handled).
    - **Truncated/zero-byte zip** and **valid-zip-but-not-EPUB** (no OPF) → `unreadable`.
  - [x] 5.2 In `test/services/import/import_service_test.dart`, add a `group('2.6 — survivable failures')` that runs each ugly fixture and asserts: result is the **expected typed `ImportFailure` reason** OR `ImportSuccess`; **zero** orphaned rows/stream/cover files on every failure (reuse the existing `streamFileCount()`/`coverFileCount()` helpers); and for the success cases, **no mid-sentence pollution** (decode the baked stream / inspect the JSONL master and assert the expected words appear, duplicated prose does not).
  - [x] 5.3 Add the txt/md oversized-token test: a `.txt` whose content is one >255-byte token → `ImportFailure(unsupported)`, **not** `emptyContent`, no partial state. (This is the specific 2.3-deferred mislabel, deferred-work line 7.)

- [x] **Task 6 — Inline library error message (AC2)**
  - [x] 6.1 In `library_screen.dart#_runImport`, replace the interim SnackBar (lines ~118-126) with an **inline** message on the library surface. Canonical copy (EXPERIENCE.md:114): **`Couldn't read "{filename}" — {reason}`**. Note the apostrophe and em-dash; match it exactly. The current `_failureMessage` copy ("Couldn't import … — it is empty") is interim — rewrite to the canonical form.
  - [x] 6.2 Reason text per `ImportFailureReason`: `emptyContent` → "it's empty"; `unreadable` → "the file is damaged or not a valid EPUB"; `unsupported` → "it's protected (DRM) or uses content we can't read"; `ioError` → "it couldn't be saved". Keep copy clear, actionable, non-blaming (UX voice, extract-product.md:190). Confirm final wording is a small, reviewable set — do not invent new reasons.
  - [x] 6.3 "Inline" means visible **on the library screen**, not a transient toast: render the message in the library body (e.g. a dismissible banner/`MaterialBanner` above the list, or inline text in the empty state when the library is empty) so a failed import that leaves an empty library still shows why. Decide the single placement; keep it M3-idiomatic. The book must **never half-appear** — the list is driven by `libraryProvider` (a drift stream), and AC2's no-partial-state guarantee (already enforced by the service rollback) is what makes this true; the UI just reports.
  - [x] 6.4 Hold the failure message in screen state (e.g. a `String? _lastImportError` set in `_runImport`), cleared on the next successful import or on dismiss.

- [x] **Task 7 — Widget tests for the inline message (AC2)**
  - [x] 7.1 In `test/ui/library/library_screen_test.dart`, add tests: a failing import (inject an `ImportService`/provider override that returns `ImportFailure(reason, 'bad.epub')`) renders the exact canonical string with the filename and the mapped reason; the message appears on the library surface (find by text) and is **not** a SnackBar; importing successfully afterward clears it; the failed book does not appear in the list.

- [x] **Task 8 — Verify (AC1·AC2·AC3)**
  - [x] 8.1 `cd companion && flutter analyze` → clean (strict `analysis_options.yaml`).
  - [x] 8.2 `cd companion && flutter test` → all green, including the new 2.6 groups.
  - [x] 8.3 No `catch {}` that silently swallows (architecture.md:293) — every catch maps to a named `ImportFailureReason` or rethrows a typed exception.

---

## Dev Notes

### The crux: classify by structure/type, not by message text

The single most important design decision in this story: **the failure taxonomy must not depend on substring-matching exception messages.** Three prior reviews flagged the current approach as brittle:
- `import_service.dart#_classifyParseError` matches `encrypt`/`drm`/`obfusc` in `error.toString().toLowerCase()` — locale- and `epub_pro`-version-dependent (deferred-work 2.4, line 50).
- The txt/md `on ArgumentError` arm maps **both** "zero tokens" (empty) **and** "oversized/unencodable token" (a clearly-non-empty file) to `emptyContent` — so a long-URL file reports "is empty" (deferred-work 2.3, line 7).

**Fix pattern (mirror what already works):** the EPUB path already throws a *typed* `EpubEmptyContentException` that the shell catches by type. Extend that pattern: the pure pipeline throws typed exceptions for each distinguishable failure cause, and `import_service` classifies by `catch (TypedException)`, not by reading message text. For DRM specifically, detect `META-INF/encryption.xml` structurally (it's the OCF standard) rather than guessing from `epub_pro`'s throw.

### What must keep working (read these — the system must be left end-to-end correct)

The story changes failure edges of files that prior stories built. Read the current state before editing:

- **`companion/lib/services/import/import_service.dart`** (the impure shell). Two paths: `_importText` (txt/md) and `_importEpub`. Both already return typed `ImportResult` and roll back partial state (`_rollback`, `_rollbackEpub`). **Preserve:** the AC7/AC5 rollback guarantee (stream + cover deleted on any persist failure), the isolate boundary (only `runPipeline`/`runEpubPipeline` cross `compute`; drift + `StreamStore` stay on the main isolate — architecture.md:469), and "never throws." You are *refining classification*, not changing the rollback or persistence shape.
- **`companion/lib/services/import/pipeline.dart`** — `runPipeline` (txt/md, single chapter) and `runEpubPipeline` (EPUB, async). Pure, sendable, top-level. Your typed exceptions live here / in the extractor.
- **`companion/lib/services/import/epub_extractor.dart`** — `extractEpub` composes `openBook` + `readChapters` + `readCover` (deliberately NOT `readBook`, which over-eagerly loads stray manifest resources and throws on real Calibre exports — see its doc comment; do not "simplify" back to `readBook`). Already throws `EpubEmptyContentException`, strips unpaired surrogates from metadata, and degrades a bad cover to no-cover. Tasks 2 & 4 touch this file.
- **`companion/lib/services/import/html_extractor.dart`** — the AC1 DOM pre-filter (drops noteref/ruby/alt; linearizes tables). Task 3 fixes `_linearizeTable`'s descendant-`tr` bug.
- **`companion/lib/protocol/stream_codec.dart`** — `encodeChunk` throws `ArgumentError` for wire-invalid records (word empty or >255 UTF-8 bytes at `:108-112`; unpaired surrogate at `:90-95`; bad orpPivot/bonusMs/flags). These are the "unencodable token" sources Task 1.2 must catch and reclassify. **Do not change the codec** — it's protocol-locked (SPEC §5); catch and reclassify upstream.
- **`companion/lib/services/import/word_stream_baker.dart`** — `bake` throws `ArgumentError` for zero chapters or a zero-token chapter (`:178`, `:186`). The zero-token-chapter case is a real-input failure for txt/md (whole-file empty); the zero-*chapters* case is a programming bug. Distinguish: txt/md should detect empty **before** `bake` (Task 1.2) so `bake`'s throw only ever means a bug → `ioError`.
- **`companion/lib/ui/library/library_screen.dart`** — `_runImport` already shows a SnackBar via `_failureMessage`. Task 6 replaces it with the inline message. **Preserve** the `_importing` guard, the share-sheet entry, and the picker.

### Canonical copy & UX (do not paraphrase)

- Inline message, on the library surface: **`Couldn't read "{filename}" — {reason}`** (EXPERIENCE.md:114). The book **never half-appears** — that line is the product's promise.
- Voice: clear, actionable, **non-blaming** on the phone (extract-product.md:190; extract-constraints.md:186 — "typed import/transfer failures, each with a user-facing message + actionable next step, FR26").
- The watch's "one-red" rule is watch-only; the phone may use the full M3 semantic palette incl. error roles (DESIGN.md:26,111).

### Error-handling standard (architecture.md:293, NFR8)

> every failure surfaces as a member of a named, enumerated state set … companion: typed import/transfer failure results with user-facing message + actionable next step (FR26). **No silent `catch {}` anywhere**; bounds-check-and-degrade per NFR8 (skip/refetch/report — never crash mid-read).

Every `catch` you add maps to a named `ImportFailureReason` or rethrows a typed exception. No bare swallow.

### Testing standards

- Dart tests in `companion/test/` mirroring `lib/` paths (architecture.md:264). Import-service tests → `test/services/import/import_service_test.dart`; widget tests → `test/ui/library/library_screen_test.dart`.
- **Fixtures are synthetic-only**, built in-memory by `test/fixtures/epubs/epub_fixture_builder.dart` (`package:archive`). The real corpus at `/home/nerya/Desktop/epub` is for **manual exploratory testing only** and is **never** a test input or committed (memory: epub-corpus-location; builder doc comment). If you want to sanity-check the taxonomy against real ugly books, do it manually and feed the *learnings* back into synthetic fixtures.
- Existing test scaffolding to reuse: `make()` injects synchronous `runner`/`epubRunner` + fixed `saltSource: () => 42` (no isolate, deterministic fingerprints); `streamFileCount()`/`coverFileCount()` assert no orphans; `_ThrowingInsertDb` injects a drift-insert failure for the `ioError`/rollback path.
- Pure pipeline classes stay UI-free / `compute`-runnable (AR19, architecture.md:265) — your new typed exceptions must not import `package:flutter`.

### Library / dependency notes

- `epub_pro` is pinned at **5.6.0** (already integrated in 2.4; sprint-status note). Don't bump it for this story. Treat its throw *types* as opaque — that's exactly why Task 2 classifies DRM structurally (encryption.xml) rather than via its message text. Verify epub_pro's actual behavior on an encrypted fixture during implementation; the structural probe is the contract regardless of its version.
- `package:archive` is currently declared **only under `dev_dependencies`** (`companion/pubspec.yaml:101` — "test-only", used by the fixture builder). The Task 2 encryption-detection probe opens the OCF zip; if you run it in production `lib/` code you **must promote `archive` to `dependencies`** (the `depend_on_referenced_packages` lint will otherwise fail `flutter analyze`). It resolves transitively via `epub_pro` already, so this is a declaration move, not a new transitive pull. **Alternative that avoids the dep move:** run the encryption probe inside `epub_extractor.dart`/`runEpubPipeline` where `epub_pro` (and thus `archive`) is legitimately in scope — still keep `archive` declared in `dependencies` for the direct import. Decide one; don't leave it dev-only with a `lib/` import.

### Previous story intelligence (2.5 → done, 2026-06-21)

- 2.5 code-review caught **`AsyncValue.when` loading-precedence masking an error as a spinner** in book detail — when wiring the inline error in Task 6, make sure a failure state isn't shadowed by the library's `loading`/`data` branches. The library uses `library.when(loading/error/data)`; the import-failure message is *separate* screen state, not the provider's error arm — keep them distinct so a transient stream reload doesn't clear the import error and vice-versa.
- 2.5 deferred two items NOT in 2.6 scope (family providers `.autoDispose`; `removeBook` UI error-surfacing — rides the Epic-4 error-UX pass). Don't fold them in.
- Pattern continuity from the epic: typed sealed results (`ImportResult`), DI-no-globals (`ImportService` constructor injection), drift reactive streams for the list, `Navigator.push` (no router), synchronous-runner test seam.

### Project structure notes

- All new production code stays under `companion/lib/services/import/` (pipeline/extractor/exceptions) and `companion/lib/ui/library/` (inline message). No new top-level modules.
- No schema change in this story (dedup — which would need a content-hash column — is explicitly Story 2.7). Confirm you touch neither `companion/lib/data/db/` migrations nor the `Books`/`Chapters` tables.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.6: Survivable import failures]
- [Source: _bmad-output/planning-artifacts/prds/prd-garmin_RSVP-2026-06-06/prd.md#FR26] — "Import failures are survivable. A malformed or unsupported file produces a clear, actionable error — never a crash, never a silently broken book."
- [Source: _bmad-output/planning-artifacts/prds/prd-garmin_RSVP-2026-06-06/prd.md#R6] — EPUB-in-the-wild variability; mitigated by extraction pre-filter, FR26 posture, and an ugly-EPUB fixture corpus.
- [Source: _bmad-output/planning-artifacts/ux-designs/ux-garmin_RSVP-2026-06-06/EXPERIENCE.md:114] — canonical inline copy "Couldn't read {filename} — {reason}". The book never half-appears.
- [Source: _bmad-output/planning-artifacts/architecture.md:293] — error-handling standard, no silent catch, FR26 typed results.
- [Source: _bmad-output/planning-artifacts/architecture.md:60,84,180] — NFR8 bounds-check-and-degrade at every ingest boundary (incl. EPUB parse).
- [Source: _bmad-output/planning-artifacts/architecture.md:264-265,469] — test placement, UI-free pipeline, isolate boundary.
- [Source: _bmad-output/implementation-artifacts/deferred-work.md] — items routed to 2.6: txt/md `ArgumentError` mislabel (2.3, line 7); `_classifyParseError` brittle (2.4, line 50); nested-table double-emit (2.4, line 51); cover catch + unbounded decode (2.4, line 52). And the OUT-of-scope dedup decision (2.5, line 59 → Story 2.7).
- [Source: companion/lib/services/import/import_service.dart] — `_importText`, `_importEpub`, `_classifyParseError`, `ImportFailureReason`, rollback.
- [Source: companion/lib/services/import/epub_extractor.dart] — `extractEpub`, `EpubEmptyContentException`, `stripUnpairedSurrogates`, cover degrade.
- [Source: companion/lib/services/import/html_extractor.dart#_linearizeTable] — descendant-`tr` double-emit.
- [Source: companion/lib/protocol/stream_codec.dart:90-112] — `encodeChunk` wire-validity throws (unencodable-token sources).
- [Source: companion/test/services/import/import_service_test.dart] — `make()`, `streamFileCount`/`coverFileCount`, `_ThrowingInsertDb`, existing `.epub` failure tests.
- [Source: companion/test/fixtures/epubs/epub_fixture_builder.dart] — `buildEpub`, scenario helpers, `corruptEpubBytes`, synthetic-only mandate.

## Dev Agent Record

### Agent Model Used

Amelia (dev-story) — claude-opus-4-8[1m]

### Debug Log References

- `flutter pub get` — promoted `archive` from dev_dependencies to dependencies (declaration-only move; resolves transitively via epub_pro already).
- `flutter analyze` → No issues found.
- `flutter test` → All 314 tests pass.

### Completion Notes List

**The crux (classify by structure/type, not message text) — done:**
- New pure-Dart typed exceptions in `import_exceptions.dart`: `TextEmptyContentException`, `UnencodableContentException`, `EpubEncryptedException`. The shell classifies by `on <Type>` — no substring-matching anywhere. `_classifyParseError` (the brittle `encrypt`/`drm`/`obfusc` matcher) is **deleted**.
- DRM is detected **structurally**: `epub_extractor` probes the OCF zip for `META-INF/encryption.xml` via `package:archive` before parsing. Deterministic and locale-independent. The probe never throws (bytes that aren't a zip → `false` → epub_pro rejects → `unreadable`).

**Taxonomy mapping (enum unchanged — `emptyContent/unreadable/unsupported/ioError`):**
- txt/md: zero tokens → `TextEmptyContentException` → `emptyContent`; a >255-byte / unpaired-surrogate token → `UnencodableContentException` → **`unsupported`** (fixes the 2.3-deferred "non-empty file mislabeled empty"). The empty check now fires **before** `bake`, so `bake`'s `ArgumentError` only ever means a wire-invalid word (reclassified) — never an opaque crash.
- EPUB: `EpubEmptyContentException` → `emptyContent`; `EpubEncryptedException` → `unsupported`; `UnencodableContentException` → `unsupported`; everything else epub_pro throws → `unreadable`.

**Nested-table double-emit (AC3) — fixed:** `_linearizeTable` now selects only the table's **direct** rows via `_directRows` (own `<tr>` + those in a direct `<thead>`/`<tbody>`/`<tfoot>`), not `querySelectorAll('tr')`. A nested table's prose is preserved exactly once (folded into its containing cell). Verified at both the html_extractor unit level and end-to-end (decoded baked stream asserts each cell once).

**Cover hardening (Task 4):** added `coverWithinBounds` + `kMaxCoverSourceDimension` (5000) — an oversized decoded cover is rejected → no-cover (AC2) before the resize/encode allocation. The cover catch narrowed from `catch (_)` to `on Exception catch (_)` so a real `Error` (OOM/programming bug) propagates instead of being silently swallowed. End-to-end test proves a corrupt cover degrades to no-cover with **zero** orphaned cover files.

**Inline message (AC2):** `library_screen` replaces the SnackBar with an M3 `MaterialBanner` in the library body (visible even on an empty library). Canonical copy exact: `Couldn't read "{filename}" — {reason}` (ASCII apostrophe + em-dash, per EXPERIENCE.md:114). Held in `_lastImportError` screen state — separate from `libraryProvider`'s `loading/error/data` arms (heeds the 2.5 `AsyncValue.when` precedence lesson) — cleared on next success or dismiss. Reason copy is non-blaming per Task 6.2.

**Note on bad-metadata fixture:** a *lone* UTF-16 surrogate cannot survive the UTF-8 zip round-trip (it's substituted before parse), so the lone-surrogate stripping stays covered by the existing `stripUnpairedSurrogates` unit tests. The new end-to-end `weirdMetadataEpub` fixture instead asserts valid-but-tricky metadata (emoji surrogate **pairs** + accents) is preserved through import.

**Out of scope (untouched, per story):** re-import dedup (→ Story 2.7; no schema/hash change), transfer failures, share-sheet UX, pacing tuning. No DB schema change.

### File List

**Production (`companion/lib/`):**
- `services/import/import_exceptions.dart` — NEW: typed pure-Dart failure exceptions.
- `services/import/pipeline.dart` — typed throws in `runPipeline`; bake `ArgumentError` → `UnencodableContentException` in both pipelines.
- `services/import/epub_extractor.dart` — structural `META-INF/encryption.xml` probe; cover source-dimension guard; narrowed cover catch.
- `services/import/cover_extractor.dart` — `coverWithinBounds` + `kMaxCoverSourceDimension`.
- `services/import/html_extractor.dart` — `_linearizeTable` direct-rows fix (`_directRows`).
- `services/import/import_service.dart` — typed-catch classification (txt + epub); deleted `_classifyParseError`.
- `ui/library/library_screen.dart` — inline `MaterialBanner` error; canonical copy; `_lastImportError` state.
- `pubspec.yaml` — `archive` promoted to dependencies.

**Tests (`companion/test/`):**
- `fixtures/epubs/epub_fixture_builder.dart` — `withEncryption`/`coverPngBytes` params + helpers: `drmEncryptedEpub`, `nestedTableEpub`, `denseFilterEpub`, `oversizedTokenEpub`, `weirdMetadataEpub`, `corruptCoverEpub`, `truncatedZipBytes`, `zipButNotEpubBytes`.
- `services/import/import_service_test.dart` — `group('2.6 — survivable failures')`; `bakedWords` helper.
- `services/import/pipeline_test.dart` — typed-failure boundary group (replaces old ArgumentError expectations).
- `services/import/epub_extractor_test.dart` — structural-taxonomy group.
- `services/import/html_extractor_test.dart` — nested-table + thead/tbody tests.
- `services/import/cover_extractor_test.dart` — `coverWithinBounds` group.
- `ui/library/library_screen_test.dart` — `group('2.6 — inline import-failure message')`.

### Change Log

- 2026-06-21 — Story 2.6 implemented (Tasks 1–8). Typed failure taxonomy (structure-based, not message-based), txt/md oversized-token reclassification, structural DRM detection, nested-table double-emit fix, cover-decode bound + narrowed catch, ugly-EPUB synthetic fixture corpus, inline `MaterialBanner` library error with canonical copy. No schema change. analyze clean; 314 tests pass.

### Review Findings

Code review 2026-06-21 (Blind Hunter + Edge Case Hunter + Acceptance Auditor). Auditor verdict: **PASS** — AC1/AC2/AC3 satisfied, crux (classify by structure not substring) met, no scope violations. `flutter analyze` clean; 314 tests pass (re-verified). 1 patch, 2 deferred, 8 dismissed as noise/false-positive/by-design.

- [x] [Review][Patch] DRM probe is exact-match — case/separator variants of `META-INF/encryption.xml` slip through to `unreadable` instead of `unsupported` [companion/lib/services/import/epub_extractor.dart:179] — FIXED: `_isEncrypted` normalizes (lowercase + `\`→`/`) before comparing; regression test `drmEncryptedEpubVariantName` added. 315 tests pass.
- [x] [Review][Defer] `bake`'s `ArgumentError`→`UnencodableContentException` reclassification is type-blind — a future non-`encodeChunk` `ArgumentError` would be masked as `unsupported` [companion/lib/services/import/pipeline.dart:78,136] — deferred, current invariant verified correct (empty-checks fire before bake)
- [x] [Review][Defer] Binary file renamed `.txt` (all-U+FFFD via `allowMalformed` decode) classifies as `emptyContent` not `unsupported` [companion/lib/services/import/import_service.dart:121] — deferred, reliable binary detection out of 2.6 scope

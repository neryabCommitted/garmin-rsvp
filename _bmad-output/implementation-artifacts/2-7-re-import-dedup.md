# Story 2.7 — Re-import dedup

**Status:** done
**Epic:** 2 — Phone Library & Book Conversion
**Created:** 2026-06-21 (post-Epic-2 retro; carved out of 2.6 per deferred-work.md line 59)

## Story

As a reader,
I want re-importing the *same* file to not silently create a duplicate book,
So that my library stays clean — while still letting me keep different editions of the same title.

**Origin:** Product decision made by Nerya (2026-06-21, deferred-work.md): dedup is keyed on **raw-file-content identity** (a hash of the source bytes), NOT on title/author (which would wrongly block legitimately-different editions). Today the fingerprint salt is `DateTime.now()`-derived, so the same file always yields a fresh fingerprint → a duplicate `Books` row + stream + cover.

## Acceptance Criteria

**AC1 — Same bytes → no duplicate.**
Importing a file whose raw bytes are byte-identical to an already-imported book does NOT create a second `Books` row, stream, or cover. It returns a distinct `ImportDuplicate` result carrying the existing book id, and writes no new stream/cover file (no partial state).

**AC2 — Different bytes → imports.**
A file with different bytes imports normally — *including a different edition of the same title/author*. Dedup is content-keyed, never metadata-keyed.

**AC3 — Content hash computed up front + persisted.**
A SHA-256 of the raw source bytes is computed **before** the time-derived stream salt and persisted on the `Books` row (`content_hash`). A **partial unique index** (`WHERE content_hash IS NOT NULL`) enforces it at the DB level as a race backstop.

**AC4 — Quiet-librarian message.**
On a duplicate, the library surfaces an informational message — "This book is already in your library." — not an error banner, never a crash, never silent.

**AC5 — Non-destructive migration.**
Schema migrates v1 → v2 adding `content_hash` (nullable; pre-2.7 rows stay null and coexist under the partial unique index). The migration never wipes books, chapters, or streams.

## Out of scope

- Backfilling `content_hash` for pre-2.7 rows (they remain null; a re-import of an old book imports once more, then dedups thereafter — acceptable pre-release).
- "Replace existing" / merge UX — duplicate is reported, not negotiated.

## Tasks

1. Add `crypto` to deps (pure-Dart, isolate-safe); `flutter pub get`.
2. `database.dart`: `content_hash` nullable column on `Books`; `schemaVersion` 1→2; `MigrationStrategy` (onCreate creates tables + partial unique index; onUpgrade adds column + index); `bookByContentHash` query. Regenerate `database.g.dart` via build_runner.
3. `import_service.dart`: compute `contentHash` from bytes up front; new `ImportDuplicate` result arm; pre-insert dedup check; persist `content_hash`; map a unique-constraint violation (race) to `ImportDuplicate`.
4. `library_screen.dart`: handle `ImportDuplicate` with a neutral notice banner (quiet-librarian copy).
5. Tests: dedup (same→duplicate, different→success, hash persisted, no orphan stream); migration v1→v2; UI duplicate notice.

## Dev Notes

- Hash on raw bytes (`List<int>`), the same bytes the picker/share path already hands `importFile` — computed in the impure shell before dispatch, not in the pure pipeline (the pipeline is salt-driven and must stay deterministic for tests).
- `ImportDuplicate` is NOT an `ImportFailure` — it's a third sealed arm, so the UI switch is forced to handle it and the quiet-librarian voice stays distinct from the failure voice.
- Partial unique index so multiple null hashes (pre-2.7 rows) coexist; SQLite treats NULLs as distinct anyway, but the partial predicate makes intent explicit.

## Dev Agent Record (2026-06-21)

**Implemented — all 5 ACs, 331 tests pass, `flutter analyze` clean.**

- **Schema (AC3/AC5):** `Books.contentHash` (`content_hash`, nullable TEXT) added; `schemaVersion` 1→2; `MigrationStrategy` (onCreate = createAll + partial unique index; onUpgrade = addColumn + index). Partial unique index `books_content_hash_unique ON books(content_hash) WHERE content_hash IS NOT NULL`. New query `bookByContentHash`. Codegen regenerated (`database.g.dart`).
- **Service (AC1/AC2/AC3):** `importFile` computes `sha256(bytes)` hex up front, pre-checks `bookByContentHash` → short-circuits to the new `ImportDuplicate(existingBookId, filename)` arm **before** baking/writing (no partial state). Hash threaded to both `_importText`/`_importEpub` and persisted. A lost race (unique-index rejection at insert) is re-resolved to `ImportDuplicate` via `_ioErrorOrDuplicate` rather than mislabeled `ioError` — no fragile `SqliteException` type-catch.
- **UI (AC4):** `ImportDuplicate` renders a neutral `_ImportNoticeBanner` (secondaryContainer role, info icon) with copy "This book is already in your library." — distinct from the error banner; a later success/duplicate clears it.
- **Deps:** `crypto: ^3.0.6` promoted to direct dependency (was transitive).
- **Tests added:** dedup group in `import_service_test.dart` (same-bytes→duplicate, content-keyed not filename, different-edition→both import, .epub re-import no second stream/cover, hash persisted); `test/data/db/migration_test.dart` (v1→v2 non-destructive, legacy rows survive null-hash, partial-index rejects dup non-null, NULLs coexist, onCreate path); duplicate-notice + clear tests in `library_screen_test.dart`.

**Deferred:** none new. Pre-2.7 rows keep a null `content_hash` (out-of-scope backfill, per the story) — they dedup once re-imported.

**Next:** code-review (the project's gate before `done`; fresh context / different LLM recommended).

### Review Findings (2026-06-21)

Code review: 3 adversarial layers (Blind Hunter / Edge Case Hunter / Acceptance Auditor). **PASS** — all 5 ACs fully met, all Dev-Notes constraints honored. 0 decision-needed, 0 patch, 4 deferred, 2 dismissed.

- [x] [Review][Defer] Multi-file batch share collapses results — an earlier file's duplicate notice/error is clobbered by a later file's result [companion/lib/ui/library/library_screen.dart:135-140, _handleShared:93-113] — deferred, pre-existing (the same `setState` overwrite already affected `_lastImportError` before 2.7); batch-result aggregation is outside the single-file dedup scope of this story.
- [x] [Review][Defer] Re-import of bytes whose Books row survives but whose stream/cover file was deleted out-of-band returns `ImportDuplicate` at a now-dangling row, with no repair path [companion/lib/services/import/import_service.dart:130-133] — deferred, requires out-of-band corruption; "replace existing"/repair UX explicitly out of scope (story line 35).
- [x] [Review][Defer] Migration test `degradeToV1` depends on `ALTER TABLE ... DROP COLUMN` (SQLite ≥ 3.35) [companion/test/data/db/migration_test.dart] — deferred, test-only portability debt; passes on the Ubuntu 24.04 / ubuntu-latest host (SQLite ≥ 3.45). Rebuild v1 via explicit DDL if an older SQLite ever enters CI.
- [x] [Review][Defer] SHA-256 is computed synchronously over the full byte buffer on the caller thread before dispatch [companion/lib/services/import/import_service.dart:127,142] — deferred, minor UI-jank risk for large EPUBs; the spec mandates shell-side computation, and moving it into a `compute()` isolate is a future optimization with its own tradeoffs.

**Dismissed (verified false positives):**
- `_ioErrorOrDuplicate` "mislabels a genuine I/O error as a duplicate" — false positive: `insertBook` runs inside `_db.transaction()` (import_service.dart:176,281), so on any throw the row auto-rolls-back and `_rollback` deletes only the stream file. A hash match at `_ioErrorOrDuplicate` can therefore only be a concurrent/prior committed import → the book genuinely *is* in the library → `ImportDuplicate` is correct.
- Index-creation "single point of failure" — speculative; `CREATE UNIQUE INDEX` failing silently while `addColumn` succeeds in the same `onUpgrade` is not a reachable path (drift throws on DDL failure).

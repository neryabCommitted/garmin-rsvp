---
baseline_commit: 375350adc12012c655b3198a8f8bc792548896b0
---

# Story 3.6: Local persistence & resume-never-lies

Status: review

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a reader,
I want my position saved relentlessly on the watch,
so that a crash or carousel-kill never loses my place (FR14, NFR4).

## Acceptance Criteria

**AC1 — All position writes route through `SyncManager.commitPosition(force)`.**
**Given** any position change
**When** it occurs
**Then** it routes through `SyncManager.commitPosition(force)` — **debounced ~15 s while playing**, `force: true` on **pause / exit / rewind / chunk-boundary / disconnect / `onStop`**
**And** no code writes position to `Storage` directly (the single owning module rule — `SyncManager` is the only writer of the position key).
> Epic-3 scope: chunk-boundary and disconnect are Epic-4 transitions (no BLE / no chunks here) — wire the *catchable* Epic-3 transitions now (pause, rewind, finish, exit/onStop/onHide, chapter-card freeze) and leave the two Epic-4 sites as documented reserved hooks.

**AC2 — Abrupt-kill resume lands on Paused, at-or-before the saved word.**
**Given** an abrupt kill (carousel navigation, no exit hook)
**When** I relaunch
**Then** the app opens on **Paused** at-or-before the last force-saved word — **never past it** (UX-DR13, NFR4 "never overshoot").

**AC3 — Per-book key + schema-version governance.**
**Given** `Storage`
**When** position is stored
**Then** it uses the **per-book key** via `StorageKeys` (`pos_<bookId>`), and a **schema-version key** governs the layout — a version mismatch **wipes the content cache (re-fetchable), never the position**.

**AC4 — Bounded, never crashes on malformed Storage.**
**Given** position reads/writes
**When** they happen
**Then** they are bounded and **never crash on malformed `Storage` reads** (bounds-check-and-degrade, NFR8/AR24): a missing/corrupt/out-of-range stored value degrades to "start at word 0" (read) or a swallowed-and-logged failure (write — e.g. `StorageFullException` on exit), never an uncaught exception.

## Tasks / Subtasks

- [x] **Task 1 — `StorageKeys` position key + schema-version key (AC1, AC3).** Extend the centralised key module; no inline key strings anywhere. (AC: 1, 3)
  - [x] In `watch/source/source_data/StorageKeys.mc` add: `function posKey(bookId as String) as String { return "pos_" + bookId; }` and `const SCHEMA_VERSION = "schemaVersion";` (the version *key* name, per architecture.md:258). Keep the existing `SETTINGS` const.
  - [x] Do **NOT** add `chunk_<…>` / `meta_<…>` keys here — those are Epic-4 (`ChunkedWordSource`) content-cache keys with no writer in Epic 3. Add the drift comment noting they land with Epic 4 (matches the file's existing "the full key set … lands with Story 3.6 / Epic 4" note — update it to "position lands here; chunk/meta land with Epic 4").

- [x] **Task 2 — `bookId()` on the source seam (AC3).** A per-book identity for the position key, fed by the canned source now and `ChunkedWordSource` from the live manifest in Epic 4 — exactly the `chapters()` pattern (Story 3.5). (AC: 3)
  - [x] `watch/source/engine/BookWordSource.mc`: add `function bookId() as String` returning `""` in the base (degrade-quietly default; a source with no identity gets a stable empty-id key rather than crashing).
  - [x] `watch/source/source_data/CannedWordSource.mc`: override `bookId()` to return the dev book's fingerprint **`"4bd588b9"`** — verbatim from the committed fixture `companion/test/fixtures/streams/dev_sample_book.manifest.json` (`fp`). Add the same "regenerate from the fixture" drift comment that `WORD_COUNT = 228` and `CHAPTER_OFFSETS` already carry. (The fingerprint is the book identity in this system — FR20 / content-hash dedup; `Protocol.FINGERPRINT_LENGTH = 8` lowercase hex.)

- [x] **Task 3 — `ReaderEngine.seekTo(index)` resume primitive (AC2).** A pure, Lang-only seek-and-pause so launch can land the engine on the restored word. (AC: 2)
  - [x] Add `function seekTo(index as Number) as Void` to `watch/source/engine/ReaderEngine.mc`: clamp `index` to `[0, wordCount - 1]` (**at-or-before the last word, never past** — empty book → no-op, stay `STATE_IDLE`), set `_index`, set `_state = STATE_PAUSED`, `_pausePending = false`, `_source.prefetchAround(_index)`, `_currentDuration = computeDuration()`. **Do NOT** `setTransition(...)` — seek is a restore, not a user transition (it must not trip a commit on its own). Keep the engine Lang-only (no System/WatchUi/Comms — 3.1 AC7).
  - [x] This is the general reposition primitive `rewind()` is not (`rewind` only lands on sentence starts). It lands `STATE_PAUSED` so the existing `onShow` STATE_IDLE auto-play guard keeps a restored engine Paused (AC2) with zero `onShow` change.
  - [x] Extend `ReaderEngineTest.mc`: `seekTo` clamps below 0 → 0 and above `count-1` → `count-1`; lands `STATE_PAUSED` from `IDLE`/`PLAYING`/`FINISHED`; empty book stays `IDLE` (no-op); emits **no** `TRANSITION_*` (i.e. `lastTransition()` unchanged across a `seekTo`); after `seekTo` a `play(now)` re-ramps from the new index (re-anchors the accumulator — no catch-up burst).

- [x] **Task 4 — `Sync` module: pure persistence policy + `SyncManager` adapter (AC1, AC3, AC4).** The single owner of the position key. (AC: 1, 3, 4)
  - [x] NEW directory + file `watch/source/sync/SyncManager.mc` declaring `module Sync { … }`. (`base.sourcePath = source;source-test` includes `source/` recursively — `sync/` ships automatically; verify the Strict-L3 build picks it up.) The module holds BOTH the pure free functions (host-testable, Lang-only logic, **no Storage/System calls**) AND the `SyncManager` class (the thin Storage/clock adapter) — mirrors how `Settings` keeps pure `applyDict`/`toDict` separate from the thin `loadFrom`/`save`.
  - [x] **Pure free functions** (called by tests directly, never touch Storage):
    - `const DEBOUNCE_MS = 15000;` (~15 s while playing — AR14/NFR4 "trail ≤ one persistence interval (~15 s playing)").
    - `const SCHEMA_VERSION_CURRENT = 1;` (the current layout version value written under `StorageKeys.SCHEMA_VERSION`).
    - `function shouldCommit(lastWriteMs as Number?, now as Number, force as Boolean) as Boolean` — `force` ⇒ true; never written (`lastWriteMs == null`) ⇒ true; wraparound (`now < lastWriteMs`) ⇒ true (resync, mirrors the engine's `onTick` wraparound guard); else `now - lastWriteMs >= DEBOUNCE_MS`.
    - `function encodePosition(index as Number, tsEpochSec as Number) as Dictionary` — `{ "pos" => index, "ts" => tsEpochSec }`. (`ts` is epoch **seconds**, the same unit Epic-4 LWW reconciles on — architecture.md:241 units table, H3 clock-skew. Storing it now is forward-compatible and free.)
    - `function decodeIndex(value as Object?, wordCount as Number) as Number?` — bounds-check-and-degrade: not a `Dictionary` ⇒ null; `pos` not a `Number` ⇒ null; `pos < 0` ⇒ null; `pos > wordCount - 1` ⇒ **clamp to `wordCount - 1`** (never past the end — AC2/AC4); `wordCount <= 0` ⇒ null; else the `pos`. (null ⇒ caller starts at word 0.)
  - [x] **`SyncManager` class** (imports `Toybox.Application.Storage`, `Toybox.System`, `Toybox.Time`, `Toybox.Lang`):
    - `initialize(bookId as String)` — store `bookId`, `_lastWriteMs = null`. Call `migrateIfNeeded()` here, **before** any position read, so a schema bump never runs over the position.
    - `function loadPosition(wordCount as Number) as Number?` — guarded `Storage.getValue(StorageKeys.posKey(_bookId))` inside try/catch (return null on throw), pass through `Sync.decodeIndex(value, wordCount)`. Returns the restore index or null.
    - `function commitPosition(index as Number, force as Boolean, nowMs as Number) as Void` — if `!Sync.shouldCommit(_lastWriteMs, nowMs, force)` return; else guarded `Storage.setValue(StorageKeys.posKey(_bookId), Sync.encodePosition(index, Time.now().value()))` inside try/catch (swallow + `System.println` on `StorageFullException`/any throw — a failed save must not crash a read session or app exit, AC4). On a successful write set `_lastWriteMs = nowMs`. (`Time.now().value()` = epoch seconds.)
    - `private function migrateIfNeeded() as Void` — guarded read of `StorageKeys.SCHEMA_VERSION`; if `null` ⇒ write `SCHEMA_VERSION_CURRENT` (fresh install, nothing to migrate); if `!= SCHEMA_VERSION_CURRENT` ⇒ wipe the **content cache** (Epic 3: there are no content-cache keys yet — this is a structured no-op; Epic 4 fills the wipe list with the `chunk_`/`meta_` keys) and then write `SCHEMA_VERSION_CURRENT`. **Never** delete a `pos_*` key here (position is the only sacred state — architecture.md:181, NFR4). All reads/writes guarded.
  - [x] NEW `watch/source-test/SyncManagerTest.mc` (`(:test)` host tests, conditional-assert style — NO `Test.assert*`): `shouldCommit` (force=true always; null lastWrite ⇒ true; inside the 15 s window ⇒ false; at/after the window ⇒ true; wraparound `now < last` ⇒ true); `encodePosition`/`decodeIndex` round-trip; `decodeIndex` degrade matrix (null, non-dict, missing `pos`, non-number `pos`, negative ⇒ null; `pos > count-1` ⇒ clamped to `count-1`; `count <= 0` ⇒ null). (Honors the architecture tree's named `SyncManagerTest.mc`; LWW/clock-skew cases are Epic-4 additions to this same file.)

- [x] **Task 5 — Wire persistence into `PlaybackView` (AC1, AC2).** The view owns the engine/source/timer; it also owns the `SyncManager` and routes every catchable transition through it. (AC: 1, 2)
  - [x] In `initialize()`, after constructing `_source` and `_engine`: `_sync = new Sync.SyncManager(_source.bookId());` then **restore**: `var restored = _sync.loadPosition(_source.wordCount()); if (restored != null) { _engine.seekTo(restored); }`. A restored engine is now `STATE_PAUSED` at the saved word; a fresh install leaves it `STATE_IDLE` at 0 (the existing first-launch auto-play demo still applies only to the IDLE case). Order matters: construct `_source` → `_engine` → restore (engine exists before seek).
  - [x] Add a single private helper `function commitPosition(force as Boolean) as Void { _sync.commitPosition(_engine.index(), force, System.getTimer()); }` and call it at every catchable transition:
    - **`onTimerTick`** — in the **playing/ramping** branch: `commitPosition(false)` (debounced ~15 s). In the **paused/finished** branch (the `else` that stops the timer): `commitPosition(true)` — this single fire covers coast-pause finalize, instant-pause settle, and `TRANSITION_FINISHED` (all land in this branch).
    - **`rewindOne()`** — after `_engine.rewind()`: `commitPosition(true)`. **Critical:** rewind-while-already-paused arms no pending tick, so `onTimerTick`'s paused branch never fires for it — without this explicit call a paused-rewind would not force-save (it would silently miss AC1's `force: true` on rewind).
    - **`maybeEnterChapterCard(...)`** — after `_engine.pauseAtCurrent()` (the chapter-start freeze): `commitPosition(true)`. The chapter boundary is a natural force-save point (the Epic-4 chunk-boundary analog) and the card may sit ~2 s.
    - **`onHide()`** — `commitPosition(true)` before/after `_timer.stop()` (becoming hidden is a catchable carousel/overlay transition).
  - [x] Do **not** add a commit inside `pauseOrResume()`/`resumeFromCard()`/`stepWpm()`: pause settles in `onTimerTick`'s paused branch (covered), resume is not a position change, and a WPM step does not move the index. Keep the call sites to the four above + `onStop` (Task 6) — over-calling is harmless (the debounce/force gate dedupes) but the enumerated set is the contract.

- [x] **Task 6 — App-lifecycle force-save on `onStop` (AC1).** The last catchable exit hook. (AC: 1)
  - [x] In `watch/source/PaceTurnerApp.mc`: store the constructed view — `getInitialView()` currently builds `new PlaybackView()` inline; assign it to a new `private var _playbackView as PlaybackView?` (init `null` in `initialize()`) before returning. (App→View strong ref is fine: the App is the GC root; the view does not reference the App — no cycle, AR15.)
  - [x] In `onStop(state)`: after the existing guarded GateV2 evidence write (leave the spike write intact — git-preserved reference), add `if (_playbackView != null) { _playbackView.commitOnStop(); }`. Add `function commitOnStop() as Void { commitPosition(true); }` to `PlaybackView` (thin public wrapper over the Task-5 helper).
  - [x] Note: the carousel-navigate-away kill does **NOT** reliably call `onStop` (that is the whole point of UX-DR13 / "no graceful-exit assumption"). `onStop` is a *best-effort* catchable save; the durability guarantee for the abrupt kill comes from the per-transition force-saves (Task 5) + the ~15 s debounce while playing (NFR4: "trail ≤ one persistence interval"). Do not regress the existing `onStop` GateV2 write or `onStart` phone-message registration.

- [ ] **Task 7 — Build, host tests, on-device check (AC1–AC4).** (AC: 1, 2, 3, 4)
  - [x] Strict L3 **release** build clean (warning-free) + **unit-test** build green. Run the matco/action-connectiq-tester host suite (see Testing) — all 73 prior tests still pass; new `SyncManagerTest` + extended `ReaderEngineTest` (`seekTo`) green.
  - [ ] On-device (Fenix 8 sideload) — verify **resume-never-lies**: (a) read a few words, pause, **force-quit via the carousel** (navigate away — NOT a graceful BACK exit), relaunch → app opens **Paused at-or-before** the last word seen, **never past it**; (b) read → pause → relaunch lands on the paused word (clean exit path); (c) rewind then relaunch lands at-or-before the rewound word; (d) read to the end (Finished) then relaunch → does not crash, lands sanely (Finished or last word, not past end); (e) playback/paused/context/chapter-card/finished flows from 3.2–3.5 unchanged. Record the result in the sprint note (machine-readable, per repo memory).
  - [ ] If feasible, eyeball the schema bump: temporarily set `SCHEMA_VERSION_CURRENT = 2` on a device that already has a saved position, relaunch → position MUST survive the bump (only the — currently empty — content cache is wiped). Revert to `1` (do **not** commit the bump).

## Dev Notes

### Scope boundary (read first)
This story makes **resume-never-lies hold on the watch alone** over the single canned dev book — local `Storage` persistence only. **In scope:** the `SyncManager.commitPosition(force)` discipline routed through every catchable Epic-3 transition, the per-book `pos_<bookId>` key, the schema-version stamp + mismatch-wipe routine (structurally complete, no content keys to wipe yet), the bounds-checked restore-to-Paused on launch, and the `seekTo` engine primitive. **Out of scope (Epic 4 / later):** the `position` BLE message + two-way LWW reconcile (Story 4.5 — `SyncManager` grows the protocol-client half then), chunk-boundary / disconnect force-save *triggers* (no BLE/chunks here — reserved hooks only), the `chunk_`/`meta_` content-cache keys and their wipe payload (Story 4.1), one-active-book / `BookChanged` selection of *which* book's position (Epic 4 — Epic 3 has exactly one book, the canned one), and the Finished "across N days" wall-clock stat (see "Out of scope: the Finished days tail" below). Do not wire transport or BLE here.

### Out of scope: the Finished "across N days" tail (deferred-work #118)
Story 3.5's review routed deferred-work #118 ("Finished stat single-line non-wrap → the '6h 41m **across N days**' tail") toward 3.6. **It is NOT in 3.6's acceptance criteria** — 3.6's ACs are position-persistence-only. The "across N days" tail needs **calendar-day tracking** (a persisted set/count of distinct days a book was read), which is a separate persisted artifact from the position key and an unspecified feature here. Leave `drawFinished` rendering the Epic-3 string `"Finished. 6h 41m."` (`StatusLayout.formatFinished(totalReadingMs(), null)`) unchanged. If Nerya wants day-tracking, it is a clean follow-up (see "Questions for Nerya"). Do **not** silently add it.

### The ownership model (the key decision)
`PlaybackView` already owns the engine / source / settings / timer and is the only place that detects transitions (it drives `onTimerTick` and the action API). So **`PlaybackView` owns the `SyncManager`** too, and routes `commitPosition` from the transition sites it already has. The App reaches the same `SyncManager` indirectly for `onStop` by holding the constructed view (`_playbackView`) and calling `commitOnStop()`. This keeps the "single owning module for the position key" rule (architecture.md:453) — `SyncManager` is the only `Storage` writer of `pos_*`; `PlaybackView` and the App only *call* `commitPosition`. Do **not** write `Storage.setValue("pos_…", …)` anywhere but inside `SyncManager` (AC1 anti-pattern: "persisting a chunk into the position key's namespace" / ad-hoc key strings — architecture.md:323).

### Why `commitPosition` lives at four view sites + onStop (not just one)
The engine exposes a sticky `lastTransition()` (Story 3.1, designed *for this story* — ReaderEngine.mc:24–31) but it is not self-clearing, so polling it for "did a NEW transition happen" is error-prone. Instead, drive `commitPosition` from the **view's** known transition moments, because the view already branches on them:
- `onTimerTick` paused/finished branch = coast-finalize + instant-pause + finish (all funnel here — the timer self-stops on pause). One `commitPosition(true)`.
- `onTimerTick` playing/ramping branch = the steady stream. `commitPosition(false)` → the `~15 s` debounce inside `SyncManager` does the throttling (NOT a per-word write — that would be the 700-WPM Storage-thrash analog of the logging anti-pattern, AR25/architecture.md:323).
- `rewindOne()` = the one transition that can happen **with no pending tick** (rewind-while-paused). Needs its own explicit `commitPosition(true)` or it silently misses AC1.
- `maybeEnterChapterCard` = the chapter freeze (Epic-4 chunk-boundary analog).
- `onStop` (App) = best-effort catchable exit.
This is the precise reading of AR14 / architecture.md:295: "any code path that changes position must route through `commitPosition(force)` — debounced (~15 s) while playing, `force: true` on pause/exit/rewind/chunk-boundary/disconnect/onStop."

### Why restore is `seekTo` + the existing onShow guard (zero onShow change)
`onShow` already guards auto-play on `STATE_IDLE` (PlaybackView.mc:147) — added in 3.4/3.5 with the explicit comment "Pre-aligns with Story 3.6 'resume lands Paused'." So restore just needs to leave the engine **`STATE_PAUSED`** (not IDLE) at the saved index before the first `onShow`. `seekTo(index)` does exactly that in `initialize()`. Then:
- **Restored book** → engine `PAUSED` at saved word → `onShow` does nothing (not IDLE, not playing, not carded) → lands Paused (AC2). Press START → `play()` re-ramps from there.
- **Fresh install** (no saved position) → engine `IDLE` at 0 → `onShow` auto-plays the demo as today (no saved position to overshoot — resume-never-lies is vacuous). Auto-play stays IDLE-only and unchanged.
Do **not** add a new "restore" branch to `onShow`; the IDLE guard already does the right thing. `seekTo` must NOT emit a transition (it is a restore, not a user action) or it would immediately re-commit on construction.

### Resume-never-lies math (AC2 / AC4)
"At-or-before the saved word, never past it." Two guards together deliver this:
1. **Write side** force-saves on every catchable transition, so the saved index is always a word the reader has *reached*, never ahead.
2. **Read side** `decodeIndex` clamps a too-large stored index DOWN to `wordCount - 1` (e.g. a book re-baked shorter, or a corrupt large value) and degrades a malformed/negative/missing value to `null` ⇒ start at word 0. Either way the restored index is `<=` a real word — never past the end, never a crash (AC4, NFR8/AR24).
The ~15 s debounce means an abrupt kill *while playing* can trail by up to one interval — that is NFR4's accepted bound ("trail ≤ one persistence interval; zero on any pause/exit/boundary"), not a violation. It is a *trail* (behind), never an *overshoot* (ahead).

### Schema-version discipline (AC3)
`StorageKeys.SCHEMA_VERSION = "schemaVersion"` (the key) + `Sync.SCHEMA_VERSION_CURRENT = 1` (the value). `migrateIfNeeded()` runs in `SyncManager.initialize()` **before** any position read. Mismatch ⇒ wipe the **content cache** (re-fetchable) and re-stamp; **never** touch `pos_*` (position is sacred — architecture.md:181 "mismatch wipes content cache (re-fetchable), never position records"). In Epic 3 there are no content-cache keys, so the wipe body is a documented no-op placeholder that Epic 4 fills with the `chunk_`/`meta_` deletions. Build the routine now so the layout is versioned from the first store build (architecture.md:181 "Storage layout carries a schema-version key").

### Files being modified — current behavior to preserve (READ THESE before editing)
- `watch/source/views/PlaybackView.mc` — owns engine/source/settings/timer + the drift-free loop. `onTimerTick` re-arms while playing/ramping else stops+recomputes jitter (your debounced vs force commit hooks attach to those two branches). `onShow` STATE_IDLE auto-play guard (line 147) is the resume hinge — **do not change it**, just seed the engine PAUSED in `initialize()`. Action API (`pauseOrResume`/`stepWpm`/`rewindOne`/`openContextView`) and the chapter-card lifecycle (`maybeEnterChapterCard`/`resumeFromCard`/`onCardTimeout`) must keep working — you only *add* commit calls, never reorder these. `rewindOne()` is the no-pending-tick case (line 217 comment) — it needs its own commit.
- `watch/source/engine/ReaderEngine.mc` — pure, Lang-only (3.1 AC7 — keep it that way). `seekTo` is additive; reuse the `clampWpm`-style clamp idiom and `_source.prefetchAround`. Do NOT change existing transitions/timing. Note `rewind()` already sets PAUSED+transition; `seekTo` is the general (non-sentence-aligned, no-transition) reposition.
- `watch/source/PaceTurnerApp.mc` — `onStart` registers phone messages + prints the GateV2 spike evidence; `onStop` writes guarded GateV2 evidence; `getInitialView` builds `PlaybackView` + `PlaybackDelegate`. Leave the spike paths intact (git-preserved) — only *store* the view and *add* the `commitOnStop()` call in `onStop`.
- `watch/source/source_data/StorageKeys.mc` — currently holds only `SETTINGS`. Add `posKey()` + `SCHEMA_VERSION`; keep the constant-discipline comment (AR8 — never inline a key string at a call site).
- `watch/source/engine/BookWordSource.mc` — typed seam; `bookId()` is additive with an empty-string default (same degrade-quietly posture as the `chapters()` empty-catalog default added in 3.5).
- `watch/source/source_data/CannedWordSource.mc` — decodes the stream + builds the catalog once at startup; add `bookId()` returning the fixture fingerprint beside the existing `WORD_COUNT`/`CHAPTER_OFFSETS` fixture-drift block.

### Architecture & pattern compliance
- **Pure/adapter split** (architecture.md:207, 451): pure decision logic (`shouldCommit`/`encodePosition`/`decodeIndex`) is Lang-only and host-tested; the `SyncManager` class is the thin `Storage`/`System`/`Time` adapter. Same shape as `Settings` (pure `applyDict`/`toDict` + thin `loadFrom`/`save`) and `PausedLayout` (pure) + `PlaybackView` (thin). The engine stays Lang-only.
- **Single owning module** (architecture.md:453, 471): `SyncManager` is the only writer/reader of `pos_*`. Position flow = `ReaderEngine` index change → `PlaybackView.commitPosition` → `SyncManager` → `Storage` (the Epic-3 half of architecture.md:471; the `position` message → `position_sync` half is Epic 4).
- **Bounds-check-and-degrade at every ingest** (NFR8/AR24, architecture.md:180,323): every `Storage` read/write in `SyncManager` is wrapped; no `catch (e) {}` empty swallow — log via `System.println` (a `Storage` failure is rare and worth a line; this is exit/restore, not the 700-WPM hot path).
- **Constants discipline** (AR8, architecture.md:258,321,323): all key strings via `StorageKeys`; never `"pos_" + …` or `"schemaVersion"` inline at a call site outside `StorageKeys`/`Sync`.

### Project Structure Notes
- **NEW directory** `watch/source/sync/` — included automatically by `base.sourcePath = source;source-test` (recursive); the architecture tree places `SyncManager.mc` there (architecture.md:366). Verify the L3 build compiles it (a brand-new source subdir).
- **No `manifest.xml` change**: `Storage` needs no CIQ permission (the manifest declares only `Communications`, for the Epic-4 sync radio — untouched here).
- Monkey C conventions (architecture.md:243–265): `PascalCase.mc`, one public class per file; module `UPPER_SNAKE` consts; `_camelCase` private fields; pure logic imports only `Toybox.Lang`; tests under `source-test/` with `(:test)`, conditional-assert style (no `Test.assert*`).
- `bookId` / `pos_<bookId>` is per-device local state; it never crosses the protocol (only the `position` *message* does, Epic 4) — consistent with the settings-are-local rule (AR16).

### Testing standards
- Host tests run under `matco/action-connectiq-tester` (SDK 8.4.0, fenix847mm) at **Strict level 3**, via Docker locally (`ghcr.io/matco/connectiq-tester`; `rm` any stale `app.prg` first — repo memory). **No `Test.assert*` API**: assert via conditionals + `logger.error(...)` + `return false`, one `(:test) function name(logger as Test.Logger) as Boolean` per case (see `ReaderEngineTest.mc`/`PausedLayoutTest.mc`).
- Pure-only host coverage: `SyncManagerTest` exercises the `Sync` free functions (debounce/encode/decode) — NOT the `SyncManager` class (its `Storage`/`Time` calls need a device context). `seekTo` is covered in `ReaderEngineTest`. The view's wiring + the real `Storage` round-trip are the **on-device** check (Task 7) — they need real `Application.Storage`.
- Current suite: **73** host tests passing (Story 3.5). Target after this story: 73 + new `SyncManagerTest` cases + new `seekTo` `ReaderEngineTest` cases, all green.

### Resolves / touches prior deferred work
- **deferred-work.md (Story 3.3 carry):** "no button-path rewind from FINISHED" was already resolved by decision in 3.5 (no FINISHED rewind, BACK exits, re-read phone-side, UX-DR14) — unchanged here.
- **deferred-work.md #118** ("Finished stat single-line non-wrap → '… across N days' tail") — **explicitly deferred again**: 3.6's ACs are position-only; day-tracking is unspecified and out of scope (see "Out of scope: the Finished days tail"). The deferred item stays open.
- This story **consumes** the engine's transition surface (`lastTransition()`, ReaderEngine.mc:24–31) and the `onShow` STATE_IDLE guard (PlaybackView.mc:147) that 3.1/3.4/3.5 built ahead of time *for* this story.

### References
- [Source: _bmad-output/planning-artifacts/epics.md#Story 3.6] — ACs (lines 672–695).
- [Source: _bmad-output/planning-artifacts/epics.md] — FR14 eager persistence (44, 201), NFR4 position durability (74), AR14 persistence discipline / commitPosition (105), UX-DR13 abrupt-kill resume (160), UX-DR8 paused readout context (153), epic-3 description "eager local persistence so resume-never-lies holds on the watch alone" (235, 532).
- [Source: architecture.md] — persistence discipline / `commitPosition(force)` (295), Storage keys `pos_<bookId>`/`schemaVersion`/`settings` in one `StorageKeys` module (258), schema-version wipes content cache never position (181), position is the only sacred state / migrations (181), NFR4 commitPosition + schema-version wipe rule (495), bounds-check-and-degrade at every ingest (180, 323), position flow path (471), single owning module / data boundaries (453, 471), four-class watch separation + pure/adapter seams (207, 451), SyncManager under `sync/` + `SyncManagerTest.mc` named (366, 388), units table / epoch-second timestamps for LWW (241, 522), H1 carousel 0–15 s loss bounded by force-on-every-transition (521), anti-patterns: ad-hoc key strings / chunk-in-position-namespace / empty catch (323).
- [Source: watch/source/engine/ReaderEngine.mc] — states/transitions + transition surface designed for this story (18–31, 218–235), `index()`/`state()`/`currentRecord()` (220–240), instant-pause path `finalizePause` (269–273), `play` ramp/no-op + accumulator re-anchor (79–96), `rewind` PAUSED+transition (134–151), `prefetchAround`/`computeDuration` idioms (146, 282–291), `clampWpm` clamp idiom to mirror for `seekTo` (326–330).
- [Source: watch/source/views/PlaybackView.mc] — `onShow` STATE_IDLE auto-play guard "pre-aligns with 3.6 resume lands Paused" (131–156), `onHide` stops timer (158–160), `onTimerTick` playing-vs-paused/finished branches (277–299), `rewindOne` no-pending-tick case (211–228), `maybeEnterChapterCard`/`pauseAtCurrent` freeze (309–335), `initialize` constructs engine/source/settings/timer (110–126), `drawFinished` Epic-3 string (540–551).
- [Source: watch/source/PaceTurnerApp.mc] — `getInitialView` constructs view+delegate (80–91), `onStop` guarded GateV2 write (68–78), `onStart` phone-message registration (52–66).
- [Source: watch/source/source_data/StorageKeys.mc] — `SETTINGS` key + constant discipline comment (the file to extend).
- [Source: watch/source/Settings.mc] — pure (`applyDict`/`toDict`) + thin adapter (`loadFrom`/`save`) split to mirror for `Sync`/`SyncManager` (16–164); `readNumber`/bounds helpers idiom for `decodeIndex` (138–163).
- [Source: watch/source/engine/BookWordSource.mc] — typed seam + degrade-quietly defaults; `chapters()` empty default is the pattern `bookId()` mirrors (27–46).
- [Source: watch/source/source_data/CannedWordSource.mc] — fixture-drift block (`WORD_COUNT=228`, `CHAPTER_OFFSETS`) to add `bookId()` beside (19–48).
- [Source: watch/source/Protocol.mc] — fingerprint wire form (8 lowercase hex, `FINGERPRINT_LENGTH`) (57–58, 152–168); position payload keys `ts`/`src` for Epic-4 LWW context (36–39).
- [Source: companion/test/fixtures/streams/dev_sample_book.manifest.json] — `fp` `4bd588b9` (the canned book id), tw=228.
- [Source: watch/monkey.jungle] — `base.sourcePath = source;source-test` (recursive; `sync/` auto-included; `(:test)` stripped from release).
- [Source: _bmad-output/implementation-artifacts/3-5-chapter-card-finished-screen-status-view-shells.md] — prior story patterns: seam-mirroring (`chapters()`), PlaybackView draw-mode/lifecycle structure, deviation-documentation discipline, on-device record format.
- [Source: _bmad-output/implementation-artifacts/deferred-work.md] — #118 Finished days tail (deferred again here).

## Dev Agent Record

### Agent Model Used

claude-fable-5 (Amelia / bmad-dev-story), 2026-07-02.

### Implementation Plan

Executed the story's task order exactly: keys → identity seam → engine primitive → Sync module → view wiring → App onStop → gates. TDD: wrote `SyncManagerTest.mc` + 5 `seekTo` `ReaderEngineTest` cases first and confirmed red (on-host Strict L3 unit-test compile fails on undefined `Sync`/`seekTo`), then implemented to green.

### Debug Log References

- Red check (pre-implementation): `monkeyc --unit-test -l 3` → `Undefined symbol ':Sync'` / `':decodeIndex'` across SyncManagerTest.mc (expected — tests written first).
- Green gate: `ghcr.io/matco/connectiq-tester` (desktop-linux context, `rm bin/app.prg` first) → `Ran 81 tests / PASSED (passed=81, failed=0, errors=0)`.
- Non-vacuous red check (mutation): seeded `decodeIndex` over-large → null (instead of clamp) + `seekTo` clamp to `count` (instead of `count-1`) → exactly `syncDecodeIndexDegradeMatrix` FAIL + `engineSeekToLandsPausedAndClamps` FAIL ("seekTo past end not clamped to last word"), 79/81. Reverted; re-run 81/81 green on the final tree.
- Release build (gate image, Strict L3 `-w -r`): BUILD SUCCESSFUL, warning-free, 43,404 B (was 41,996 B after 3.5). On-host SDK 9.1.0 Strict L3: unit-test + release both clean.

### Completion Notes List

- **Task 1** — `StorageKeys.posKey(bookId)` + `SCHEMA_VERSION` const added; module comment updated to "position lands here; chunk/meta land with Epic 4". No inline key strings anywhere (`grep 'pos_'` hits only StorageKeys.mc).
- **Task 2** — `BookWordSource.bookId()` base returns `""` (degrade-quietly, mirrors `chapters()`); `CannedWordSource.bookId()` returns `BOOK_FINGERPRINT = "4bd588b9"` verbatim from the committed fixture manifest (`fp` re-verified against `companion/test/fixtures/streams/dev_sample_book.manifest.json`), with the same regenerate-from-fixture drift comment as `WORD_COUNT`/`CHAPTER_OFFSETS`.
- **Task 3** — `ReaderEngine.seekTo(index)`: clamps to `[0, wordCount-1]`, lands `STATE_PAUSED`, clears `_pausePending`, `prefetchAround`, recomputes duration; **no** `setTransition` (restore, not a user transition); empty book no-op stays IDLE. Engine still imports only `Toybox.Lang` (3.1 AC7 intact). 5 new host tests: clamp both edges + duration recompute; from PLAYING and FINISHED; empty-book no-op; no-transition (fresh + across a sticky REWIND); play-after-seek re-ramps and re-anchors the accumulator (no catch-up burst).
- **Task 4** — NEW `watch/source/sync/SyncManager.mc`, `module Sync`: pure `DEBOUNCE_MS=15000` / `SCHEMA_VERSION_CURRENT=1` / `shouldCommit` (force ⇒ true; null lastWrite ⇒ true; wraparound `now < last` ⇒ true; else `>= DEBOUNCE_MS`) / `encodePosition` (`{"pos","ts"}`, ts epoch seconds for Epic-4 LWW) / `decodeIndex` (degrade matrix per AC4, over-large clamps to `count-1`); `SyncManager` class = thin guarded Storage/Time adapter, `migrateIfNeeded()` in `initialize()` before any position read, mismatch wipes content cache (structured no-op in Epic 3, comment marks the Epic-4 chunk_/meta_ spot) and **never** touches `pos_*`. `_lastWriteMs` advances only on successful write (failed debounced write retries next tick). The `sync/` dir is picked up by `base.sourcePath = source;source-test` — verified by both builds. 3 new host tests cover the pure half; the adapter's Storage round-trip is the on-device check (as with Settings).
- **Task 5** — `PlaybackView`: `_sync = new Sync.SyncManager(_source.bookId())` + restore via `loadPosition`/`seekTo` in `initialize()` (order source → engine → restore); private `commitPosition(force)` helper is the single routing point; wired at exactly the contract sites — `onTimerTick` playing branch (debounced false), `onTimerTick` paused/finished branch (force — covers coast finalize, instant settle, FINISHED), `rewindOne` after `_engine.rewind()` (force — the no-pending-tick case), `maybeEnterChapterCard` after `pauseAtCurrent()` (force), `onHide` before `_timer.stop()` (force). No commit in `pauseOrResume`/`resumeFromCard`/`stepWpm` (per story). `onShow` untouched — the existing STATE_IDLE guard delivers restore-lands-Paused (AC2) as designed.
- **Task 6** — `PaceTurnerApp`: `_playbackView` field (null in `initialize()`, assigned in `getInitialView`), `onStop` calls `commitOnStop()` after the intact GateV2 evidence write; `PlaybackView.commitOnStop()` = thin public wrapper. GateV2 spike paths and `onStart` phone-message registration untouched.
- **Task 7** — Host suite 81/81 green @ Strict L3 in the CI image (73 → 81: +5 seekTo, +3 Sync); release + unit-test builds clean/warning-free on both the gate image (8.4.0) and on-host SDK 9.1.0. Signed `watch/bin/PaceTurner.prg` (43,404 B) built for sideload. **PENDING human (on-device Fenix 8):** resume-never-lies checks (a) carousel force-quit mid-read → relaunch Paused at-or-before last word; (b) pause → relaunch on the paused word; (c) rewind → relaunch at-or-before; (d) read to Finished → relaunch sane; (e) 3.2–3.5 flows no-regression; plus the optional schema-bump eyeball (set `SCHEMA_VERSION_CURRENT=2` locally, position must survive; do not commit). Record results in the sprint note (machine-readable).
- **Scope guards honored:** no BLE/transport, no chunk/meta keys, no Finished "across N days" tail (deferred-work #118 stays open), no manifest/permission change, GateV2 spike preserved.

### File List

- `watch/source/source_data/StorageKeys.mc` — modified (posKey(), SCHEMA_VERSION, comment update)
- `watch/source/engine/BookWordSource.mc` — modified (bookId() base default + doc)
- `watch/source/source_data/CannedWordSource.mc` — modified (BOOK_FINGERPRINT + bookId() override)
- `watch/source/engine/ReaderEngine.mc` — modified (seekTo())
- `watch/source/sync/SyncManager.mc` — NEW (module Sync: pure policy + SyncManager adapter)
- `watch/source/views/PlaybackView.mc` — modified (_sync + restore in initialize, commitPosition helper + 5 wired sites, commitOnStop)
- `watch/source/PaceTurnerApp.mc` — modified (_playbackView field, onStop exit save)
- `watch/source-test/SyncManagerTest.mc` — NEW (3 host tests: debounce gate, round-trip, degrade matrix)
- `watch/source-test/ReaderEngineTest.mc` — modified (+5 seekTo tests)

## Change Log

- 2026-07-02 (Story 3.6, dev-story): Local persistence & resume-never-lies — Sync module (pure shouldCommit/encodePosition/decodeIndex + SyncManager Storage adapter, single pos_* owner), StorageKeys.posKey()+SCHEMA_VERSION, BookWordSource.bookId() seam (CannedWordSource → fixture fp 4bd588b9), ReaderEngine.seekTo() restore primitive (no transition, lands PAUSED), commitPosition routed at 4 PlaybackView sites + App.onStop, restore-to-Paused in PlaybackView.initialize. 81/81 host tests @ Strict L3 (73→81), release build clean 43,404 B. On-device carousel-kill resume check pending.

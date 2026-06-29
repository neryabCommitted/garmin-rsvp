---
baseline_commit: 355eecb4aeee3b21f43b12addc83e4b169feecf7
---

# Story 3.5: Chapter card, Finished screen & status-view shells

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a reader,
I want chapter breaks, an explicit ending, and worded system states,
so that the book has rhythm and never silently stops or hangs (FR5, FR6).

## Acceptance Criteria

**AC1 — Chapter card.**
**Given** a chapter boundary
**When** it is crossed during playback
**Then** a chapter card shows the chapter number + title on Void (title in the `chapter-title` role; progress beneath in Ink-Dim), the word stream freezes on the chapter's first word while the card shows, and resume behavior follows the `chapterResume` setting — **Auto** (card shows ~2 s, then flow resumes) or **Wait** (resumes on START). The card is the prefetch breath between chapters; the prefetch *trigger* is wired in Epic 4 (not here).

**AC2 — Finished screen.**
**Given** the last word's dwell ends (engine reaches `STATE_FINISHED` / `TRANSITION_FINISHED`)
**When** the book finishes
**Then** an explicit Finished screen replaces the frozen last word — an end sentence + the available stat (e.g. "Finished. 6h 41m.") in the `status-view` style — and BACK exits to the watch face. Never a silent stop on the last word. There is **no** rewind-back-into-text affordance: re-read is a phone-side decision (UX-DR14) — this is by design and resolves the deferred "no button-path rewind from FINISHED" item.

**AC3 — Status-view shells (render-only).**
**Given** the named states WaitingForPhone, Buffering, BookChanged, StorageFull
**When** rendered
**Then** each is one plain-text sentence in Ink-Dim, centered in the ~320 px safe square (Buffering may show a minimal indeterminate dot cycle), with no icons and no spinners otherwise. The shells are **render-only with no interactive controls** in this story; their triggers (and BookChanged's one-tap acknowledge) are wired in Epic 4.

**AC4 — No regression to playback.**
**Given** the existing playback / paused / context flows (Stories 3.2–3.4)
**When** chapter card and Finished modes are added
**Then** normal word streaming, the transient WPM readout, paused readout, context-on-pause push/pop, rewind, and the drift-free render loop all still behave exactly as before; the new modes only intercede at a chapter boundary and at end-of-book.

## Tasks / Subtasks

- [x] **Task 1 — `chapterResume` setting (AC1).** Add the Auto/Wait setting to `SettingsModel` (consumer is this story; the menu UI is Story 3.8). (AC: 1)
  - [x] Add `CHAPTER_RESUME_AUTO = 0`, `CHAPTER_RESUME_WAIT = 1`, `DEFAULT_CHAPTER_RESUME = CHAPTER_RESUME_AUTO`, `KEY_CHAPTER_RESUME = "chapterResume"` to `Settings.mc`.
  - [x] Add field `public var chapterResume as Number;`, default it in `initialize()`, round-validate it in `applyDict()` via the existing `readEnum(...)` helper, and serialize it in `toDict()`.
  - [x] Extend `SettingsTest` (in `ReaderEngineTest.mc` or wherever the Settings cases live) for the default + apply/serialize round-trip + out-of-range degrade, mirroring the existing `pauseMode`/`handedness` cases.

- [x] **Task 2 — `ChapterCatalog` pure module (AC1).** Host-testable chapter metadata + lookups; Lang-only. (AC: 1)
  - [x] NEW `watch/source/views/ChapterCatalog.mc`: a small value class built from parallel arrays of chapter **offsets** (absolute word index of each chapter's first word) and **titles**. Methods: `count()`, `numberForWord(wordIndex)` → 1-based chapter number (the highest chapter whose offset ≤ wordIndex; clamps to 1), `titleForWord(wordIndex)` → that chapter's title (or null), `offsetAt(chapterIndex)`, `titleAt(chapterIndex)`. Pure, bounds-checked, never crashes (NFR8/AR24).
  - [x] NEW `watch/source-test/ChapterCatalogTest.mc`: number/title lookups at offsets, between offsets, before the first / past the last, and the empty-catalog degrade. Use the same conditional-assert style (no `Test.assert*`).

- [x] **Task 3 — Chapter seam on the source (AC1).** Expose the catalog through the `BookWordSource` contract so the canned source feeds it now and `ChunkedWordSource` feeds it from the real manifest in Epic 4. (AC: 1)
  - [x] `BookWordSource.mc`: add `chapters() as ChapterCatalog` returning an empty catalog (0 chapters) in the base (degrade-quietly contract).
  - [x] `CannedWordSource.mc`: build a `ChapterCatalog` once (at startup, beside the stream decode) from the dev book's 3 chapters — offsets `[0, 81, 170]`, titles `["I. The Harbor at Dusk", "II. A Café and a Question", "III. What the Tide Returned"]` — sourced verbatim from `companion/test/fixtures/streams/dev_sample_book.manifest.json` (`ch[].o` / `ch[].ti`). Add the same "regenerate from the fixture" drift comment that `WORD_COUNT = 228` already carries; override `chapters()`.

- [x] **Task 4 — `ReaderEngine.pauseAtCurrent()` (AC1).** A minimal instant freeze at the current word for chapter-card entry. (AC: 1, 4)
  - [x] Add `pauseAtCurrent()` to `ReaderEngine.mc`: if `PLAYING` or `RAMP`, freeze on the current `_index` immediately (the existing instant-pause path — set `STATE_PAUSED`, clear `_pausePending`, `setTransition(TRANSITION_PAUSE)`), independent of `_pauseMode` (coast must NOT overshoot past the chapter's first word). No-op otherwise. Keep the engine Lang-only.
  - [x] Extend `ReaderEngineTest.mc`: `pauseAtCurrent()` from PLAYING freezes at the exact current index even in `PAUSE_COAST`; resuming via `play(now)` re-ramps and the accumulator is re-anchored (no catch-up burst); no-op from IDLE/PAUSED/FINISHED.

- [x] **Task 5 — `StatusLayout` pure module (AC2, AC3).** Host-testable status text + Finished stats; Lang-only. (AC: 2, 3)
  - [x] NEW `watch/source/views/StatusLayout.mc`: typed state constants (`STATE_WAITING_FOR_PHONE`, `STATE_BUFFERING`, `STATE_BOOK_CHANGED`, `STATE_STORAGE_FULL`); `statusSentence(stateId, title)` → the exact UX copy (see Dev Notes "Status copy"); `formatReadingTime(ms)` → "6h 41m" / "41m" / "0m"; `formatFinished(totalMs, daysOrNull)` → "Finished. 6h 41m." (Epic 3: `days == null`) or "Finished. 6h 41m across N days." (Epic 4/3.6 when day-tracking exists).
  - [x] NEW `watch/source-test/StatusLayoutTest.mc`: each status sentence (incl. BookChanged title interpolation), `formatReadingTime` across the minute/hour boundaries and zero, and `formatFinished` with and without days.

- [x] **Task 6 — `StatusView` render-only shell (AC3).** One parameterized view for the four system states. (AC: 3)
  - [x] NEW `watch/source/views/StatusView.mc` extends `WatchUi.View`: constructed with a `stateId` (+ optional `title`); `onUpdate` clears to Void and draws `StatusLayout.statusSentence(...)` in Ink-Dim, centered (`TEXT_JUSTIFY_CENTER | VCENTER`) at screen center, within the safe square. For `STATE_BUFFERING`, run a small `Timer` started in `onShow`/stopped in `onHide` that cycles a minimal dot count (e.g. `.` → `..` → `...`) and `requestUpdate`s. **No delegate, no controls** (render-only shell — triggers are Epic 4).
  - [x] No host test (pure logic is in `StatusLayout`); the shell's correctness is the on-device visual check (Task 9).

- [x] **Task 7 — Chapter-card mode in `PlaybackView` (AC1, AC4).** Intercept the stream at a chapter boundary. (AC: 1, 4)
  - [x] Add card state: `_chapterCard as Boolean`, `_cardedIndex as Number` (the index a card was last shown for — prevents re-triggering the same boundary on resume), `_cardChapterNum`/`_cardChapterTitle` snapshot, and a card deadline `_cardUntil` for Auto. Add `const CHAPTER_CARD_MS = 2000;` (UX "~2 s"; tune on device).
  - [x] In `onTimerTick`, **after** `_engine.onTick(now)`: if `_engine.isPlaying()` and the now-current word carries `Protocol.FLAG_CHAPTER_START` and `_engine.index() > 0` and `_engine.index() != _cardedIndex` → enter card mode: snapshot `numberForWord/titleForWord` from `_source.chapters()`, `_cardedIndex = _engine.index()`, `_engine.pauseAtCurrent()`, `_chapterCard = true`. Auto → `_cardUntil = now + CHAPTER_CARD_MS` and arm a one-shot timer (`armCardTimer`); Wait → stop the timer (START resumes). Then `requestUpdate`.
  - [x] Auto card timeout handler (`onCardTimeout`): clear `_chapterCard`, `resumeFromCard()`.
  - [x] `resumeFromCard()`: `_chapterCard = false`, `_engine.play(System.getTimer())` (PAUSED→ramp→playing, re-anchors the accumulator — the breath/ramp on chapter resume is intended), `armTimer()`, `requestUpdate`. Note `_cardedIndex` stays set so the just-resumed chapter-start word does not immediately re-card; it is naturally distinct from the next chapter's index.
  - [x] `onUpdate`: when `_chapterCard`, draw ONLY the card (private `drawChapterCard(dc, w, h)`: "Chapter N" + title centered via the chapter-title face, progress `PausedLayout.bookPercent(index, count)` beneath in Ink-Dim) and `return` before the word/guides/readouts. Title face: use the largest native face as the `chapter-title` proxy (bold/Atkinson is the later BMFont swap behind the existing `fontFor` seam — document the deviation; native faces have no 700 weight).

- [x] **Task 8 — Finished mode in `PlaybackView` + input contract (AC2, AC4).** (AC: 2, 4)
  - [x] `onUpdate`: when `_engine.isFinished()`, draw ONLY the Finished screen (private `drawFinished(dc, w, h)`: `StatusLayout.formatFinished(totalReadingMs(), null)` centered in Ink-Dim, status-view style) and `return`. Epic-3 stat input = total content reading time computed purely: `totalReadingMs()` = `wordCount * (60000 / wpm) + PausedLayout.sumBonusMs(source, 0, wordCount - 1)` (mirrors the paused readout math; the wall-clock "across N days" stat is wired when persistence/day-tracking lands in Story 3.6 — pass `days` then).
  - [x] BACK exits: already true (`PlaybackDelegate.onKey` returns false for `ACTION_EXIT`). Confirm UP/DOWN/START in FINISHED are harmless: `drawWpmReadout` is already gated on `isPlaying||isRamping` (3.3 patch) so a stray WPM step paints nothing; `play()` no-ops FINISHED; rewind is intentionally absent. **Recommended (resolves deferred #107 cleanly):** make rewind/context view-actions no-op while finished or carded — guard `rewindOne()` / `openContextView()` / `stepWpm()` with `if (_chapterCard || _engine.isFinished()) { return; }` so a chapter card / end screen can't be driven into text. Document that this is the deliberate "re-read is phone-side" contract, not a missing feature.

- [x] **Task 9 — Build, host tests, on-device check (AC1–AC4).** (host build + suite DONE; on-device PASS Fenix 8 2026-06-28)
  - [x] Strict L3 release build clean (warning-free) + unit-test build green. Run the matco/action-connectiq-tester host suite (see "Testing" below) — all prior tests still pass; new `ChapterCatalogTest` / `StatusLayoutTest` / extended `ReaderEngineTest` / `SettingsTest` green.
  - [x] On-device (Fenix 8 sideload) — PASS 2026-06-28 (Nerya): cards fire at words 81 & 170 with correct number/title/progress; Finished screen shows and BACK exits. Confirm: (a) cards appear at the two canned-book boundaries (words 81 & 170) with the right number+title+progress; (b) Auto card auto-resumes ~2 s, Wait card resumes on START; (c) reading to the end shows the Finished screen and BACK exits; (d) playback/paused/context flows from 3.2–3.4 unchanged. Status shells can be eyeballed by temporarily pointing `getInitialView` at a `StatusView` during dev (do **not** commit that swap — the shells have no Epic-3 trigger). Record the result in the sprint note (machine-readable, per repo memory).

## Dev Notes

### Scope boundary (read first)
This story builds **shells + the two end-of-flow screens reachable over the canned source**. In scope: the chapter card (reachable — the canned book has 3 chapters), the Finished screen (reachable — the canned book ends), and the four render-only status views. **Out of scope (Epic 4 / later):** the prefetch trigger the card "doubles as", BookChanged's one-tap acknowledge, the real manifest-driven chapter titles, the actual triggers that route to WaitingForPhone/Buffering/BookChanged/StorageFull, day-level Finished stats (needs Story 3.6 persistence), and the settings-menu UI for `chapterResume` (Story 3.8). Do not wire transport, Storage, or navigation triggers here.

### Where chapter titles come from in Epic 3 (the key decision)
The watch has **no manifest yet** — `ProtocolClient` + the manifest's `ch` array (`Protocol.KEY_CHAPTERS`/`KEY_CHAPTER_OFFSET`/`KEY_TITLE`) arrive in Epic 4 (Story 4.1). So Epic 3 bundles the dev book's chapter metadata exactly like it already bundles the word stream: `CannedWordSource` carries the 3 chapters (offsets + titles) sourced from the committed fixture `dev_sample_book.manifest.json`, and exposes them via the new `chapters()` seam. `ChunkedWordSource` (Epic 4) will build the *same* `ChapterCatalog` from the live manifest — the view code does not change. This mirrors the existing pattern where `WORD_COUNT = 228` and `devSampleStream` are tied to the fixture with a regenerate comment.
- Crossing detection uses the per-word `Protocol.FLAG_CHAPTER_START` flag (the baker sets it at chapter starts — Story 2.2), which is the natural per-advance signal in the render loop. The catalog's offsets supply number+title and must agree with where the flags sit (the companion drift test `dev_sample_book_test.dart` guards the fixture; on device, verify cards fire at 81 & 170).

### Why a tiny engine method (`pauseAtCurrent`)
The card must freeze on the chapter's **first word** the instant it appears. `requestPause()` is wrong: in the default `PAUSE_COAST` mode it coasts to the next sentence end, overrunning the chapter start. We need an instant, mode-independent freeze. `pauseAtCurrent()` reuses the engine's existing instant-pause path (`finalizePause`) unconditionally. Resume is plain `play(now)` (PAUSED→ramp→playing), which is the only public lever that re-anchors `_lastAdvance` — so a 2-second card does **not** trigger the catch-up burst that re-arming the playback timer after a long gap otherwise would (`onTick` would see ~2000 ms elapsed → step up to `CATCHUP_CAP`=4 words then resync; that would skip words). The ramp on chapter resume is the intended "breath," consistent with EXPERIENCE.md (start ramp on Resume/play).

### View structure (chapter card + Finished are PlaybackView modes; status views are standalone)
- **Chapter card & Finished live inside `PlaybackView`** as draw modes (like the existing ramp / paused / wpm-readout branches), because both must coordinate the engine + the timer loop that `PlaybackView` already owns. Adding `_chapterCard` / `isFinished()` early-returns in `onUpdate` matches the file's existing structure (it already early-returns for the ramp and the null-record cases). Do **not** make them pushed views — the resume/timer coupling would force a back-reference into `PlaybackView` and risk a GC cycle (AR15).
- **Status views are a standalone `StatusView`** (one parameterized class for the four system states), because they have no engine/timer relationship and no Epic-3 trigger — they are pure render-only shells. Keeping them out of `PlaybackView` keeps that file focused and lets Epic 4 push/route them freely.
- All three are "card regime": centered text inside the `watch-safe-square` (~320 px), corners empty (DESIGN.md:132).

### Status copy (exact strings — UX, do not paraphrase)
From EXPERIENCE.md:106–110 / DESIGN.md:155:
- WaitingForPhone → `"Waiting for phone"`
- Buffering → `"Loading…"` (plus the minimal dot cycle)
- BookChanged → `"Book changed on phone — starting {title}"` (title interpolated)
- StorageFull → `"Storage full — manage books on your phone"`
- Finished → `"Finished. {readingTime}."` (Epic 3) — the example in the docs is `"Finished. 6h 41m across 19 days."`; the "across N days" half is deferred to 3.6 (no day-tracking yet), so Epic 3 renders `"Finished. 6h 41m."`.

### Design tokens (DESIGN.md)
- **Colors** (already named in `PlaybackView`): Void `0x000000`, Ink `0xEAE6DF`, Ink-Faint `0x45423E`, Ink-Dim `0x8A867F`, Pivot `0xFF5349`. The chapter title is **Ink** (focal text) on Void; the card's progress line and ALL status sentences are **Ink-Dim**. No status colors, no second accent, no icons (DESIGN.md:113,165).
- **Typography:** `chapter-title` = 28 px / **700** ("the one place bold is allowed", DESIGN.md:121) — native faces have no guaranteed bold, so use the largest native face via the existing `fontFor`/`FONT_SYSTEM_*` seam now; the Atkinson Hyperlegible BMFont (true 700) is the same deferred font-swap story behind that seam. `watch-meta` (22 px, `FONT_SYSTEM_TINY`) is the precedent for the Ink-Dim meta/status lines (see `drawPausedReadout`).
- Reuse `PausedLayout.bookPercent(index, count)` for the card's progress and `PausedLayout.sumBonusMs(...)` for the Finished total — don't reinvent.

### Files being modified — current behavior to preserve (READ THESE before editing)
- `watch/source/views/PlaybackView.mc` — owns the engine/source/settings/timer and the drift-free loop. Existing `onUpdate` early-returns: ramp branch (draws the 3-2-1 count), null-record branch (draws guides + readouts), normal branch (word + guides + readouts). `onTimerTick` re-arms while playing/ramping, else stops + recomputes jitter. Existing draw helpers: `drawGuides`, `drawWord`, `drawWpmReadout` (gated `isPlaying||isRamping`), `drawPausedReadout` (gated `isPaused`). Your card/finished draws are two more early-return modes; do not disturb the others. The action API (`pauseOrResume`/`stepWpm`/`rewindOne`/`openContextView`) and the `onShow` STATE_IDLE auto-play guard must keep working.
- `watch/source/engine/ReaderEngine.mc` — pure, Lang-only (no System/WatchUi/Comms — AC7 of 3.1; keep it that way). `pauseAtCurrent()` is additive; do not change existing transitions/timing.
- `watch/source/Settings.mc` — pure defaults + `applyDict`/`toDict` + thin `loadFrom`/`save` adapter. Add the field through all four (default, apply, serialize, key) following the existing helpers exactly.
- `watch/source/source_data/CannedWordSource.mc` — decodes the stream once at startup; add the catalog build beside it. `wordAt`/`wordCount`/`prefetchAround` unchanged.
- `watch/source/engine/BookWordSource.mc` — the typed seam; `chapters()` is additive with an empty-catalog default so a misconfigured subclass degrades, not crashes (matches the existing base-class posture).
- `watch/source/input/PlaybackDelegate.mc` — thin adapter; START in a Wait-card must reach resume. The engine is PAUSED during a card, so `actionForKey` already yields `ACTION_PAUSE_RESUME` for START → `pauseOrResume()`. Make `pauseOrResume()` card-aware: if `_chapterCard`, call `resumeFromCard()` instead of the normal resume. Guard `rewindOne`/`openContextView` against card/finished (Task 8) so UP/DOWN-while-"paused" during a card don't rewind or open context.

### Project structure & naming (architecture.md:243–265)
- Monkey C: `PascalCase.mc`, one public class per file; modules `UPPER_SNAKE` consts; private fields `_camelCase`. New views go under `watch/source/views/`, tests under `watch/source-test/` with `(:test)` annotations (jungle includes `source-test` only in unit-test builds — `monkey.jungle`).
- Pure logic stays UI-free: `ChapterCatalog`, `StatusLayout`, and the `ReaderEngine` addition import **only** `Toybox.Lang` so the host tester runs them (mirrors `OrpLayout`/`PausedLayout`/`ReaderEngine`). `StatusView` is the thin `WatchUi.View`.
- Never inline a protocol/flag constant — reference `Protocol.FLAG_CHAPTER_START` (etc.).

### Testing standards
- Host tests run under `matco/action-connectiq-tester` (SDK 8.4.0, fenix847mm) at **Strict level 3**, via Docker locally (`ghcr.io/matco/connectiq-tester`; `rm` any stale `app.prg` first — repo memory). This repo uses **no `Test.assert*` API**: assert via conditionals + `logger.error(...)` + `return false`, with a `(:test) function name(logger as Test.Logger) as Boolean` per case (see `PausedLayoutTest.mc`/`ReaderEngineTest.mc`). Build the new fixtures as `*TestSupport` helper modules like `PausedLayoutTestSupport`.
- Current suite: 63 host tests passing (Story 3.4). New pure tests should push that up; the views (`PlaybackView` modes, `StatusView`) are exercised on device, not host (they need a `Dc`/`WatchUi`).

### Resolves / touches prior deferred work
- **deferred-work.md:107** — "No button-path rewind from the FINISHED state." Resolved by **decision**: per UX-DR14 re-read is a phone-side action and BACK exits Finished; there is intentionally no rewind-into-text from the end screen. Document it; do not add a rewind path. (Optionally pass `isFinished` into `InputMap.actionForKey` to map UP/DOWN→`ACTION_NONE` in FINISHED for tidiness, but the existing readout gating already makes them harmless no-ops — keep the change minimal unless it reads cleaner.)

### Project Structure Notes
- No `manifest.xml` / permission / Storage changes (no transport, no persistence in this story). The GateV2 spike code in `PaceTurnerApp.mc` stays untouched/compiled (git-preserved reference; `getInitialView` already enters `PlaybackView`).
- `chapterResume` is the 9th Settings field; it joins the per-device, never-synced settings (AR16). It is read here, edited in Story 3.8.

### References
- [Source: _bmad-output/planning-artifacts/epics.md#Story 3.5] — ACs (lines 652–670), cut-line note FR6 (line 532).
- [Source: _bmad-output/planning-artifacts/epics.md] — UX-DR9 chapter card (153), UX-DR11 status views (155), UX-DR14 Finished (161), FR5 explicit ending (29).
- [Source: ux-designs/.../DESIGN.md] — chapter-card/status-view components (77–83), typography chapter-title 28/700 (34–37,121), card regime safe-square (132), reading screens spec (154–155), colors/anti-patterns (108,113,165).
- [Source: ux-designs/.../EXPERIENCE.md] — chapter card Auto/Wait (84), start ramp on resume (85), status states + exact copy (106–110), Finished BACK-exits/re-read phone-side (110), Flow 4 finishing (213–216).
- [Source: architecture.md] — four-class watch separation (207), settings model over `"settings"` key + Atkinson/native-font escape hatch (209), naming/structure/test-placement patterns (243–265).
- [Source: companion/test/fixtures/streams/dev_sample_book.manifest.json] — chapter offsets [0,81,170] + titles; tw=228, tb=12772, fp 4bd588b9.
- [Source: watch/source/Protocol.mc] — `FLAG_CHAPTER_START=0x04` (49), manifest chapter keys (28–34).
- [Source: watch/source/engine/ReaderEngine.mc] — states/transitions (18–31), instant-pause path `finalizePause` (254–258), `play` ramp/no-op contract (79–96), catch-up resync (144–166).
- [Source: watch/source/views/PlaybackView.mc] — onUpdate mode branches (244–279), draw helpers (294–349), `onTimerTick`/`armTimer` (217–239), action API (140–193).
- [Source: watch/source/views/PausedLayout.mc] — reuse `bookPercent` (18–26), `sumBonusMs` (43–52).
- [Source: watch/source/Settings.mc] — field/apply/serialize pattern to mirror.
- [Source: _bmad-output/implementation-artifacts/deferred-work.md:107] — FINISHED rewind item resolved here.

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Amelia / dev-story), 2026-06-28.

### Debug Log References

- Strict L3 release build (`-r`): BUILD SUCCESSFUL, 41,964 B, warning-free.
- Strict L3 unit-test build (`--unit-test`): BUILD SUCCESSFUL.
- Host suite (matco/action-connectiq-tester, `ghcr.io/matco/connectiq-tester`, fenix847mm, Strict L3): **73/73 PASS, 0 failed, 0 errors** (was 63 → +10).
- Initial unit-test build caught Strict-L3 nullability: `.equals()` called directly on `ChapterCatalog.titleAt/titleForWord` (return `String?`) — fixed with null-guards in `ChapterCatalogTest` before the green run.

### Completion Notes List

- **All 9 tasks complete.** On-device Fenix 8 sideload **PASS 2026-06-28 (Nerya)**: cards fire at words 81 & 170 with the right number/title/progress, the Finished screen shows, and BACK exits. (Status-view shells not eyeballed — no Epic-3 trigger; they're render-only and host-covered via `StatusLayout`.)
- **+10 host tests** (63→73): `ChapterCatalogTest` (3), `StatusLayoutTest` (4), `ReaderEngineTest` `pauseAtCurrent` (3). `chapterResume` Settings coverage folded into the existing `settingsDefaultsAreStorageFree` / `settingsApplyDictIsPureAndValidated` cases (default + apply/serialize round-trip + out-of-range degrade), mirroring `pauseMode`/`handedness`.
- **Deviation (documented): no `_cardUntil` field.** The story listed both a `_cardUntil` deadline AND a one-shot Auto timer (`armCardTimer`). These are redundant; I kept the single one-shot `_timer` → `onCardTimeout` (reuses the lone Timer instance the view already owns — no second Timer, no GC cycle, consistent with the 3.3 review's "single Timer instance" praise) and dropped `_cardUntil`. AC1 Auto behavior (~2 s then resume) is delivered by the timer. No polling against a deadline is needed.
- **Deviation (documented): chapter-title face.** Native faces have no guaranteed 700 weight, so the `chapter-title` role uses the largest native face that fits the title on one line (fit-to-width via `OrpLayout.needsMarginClamp`, starting from `FONT_SYSTEM_LARGE`, independent of the reading `fontSize`). The true-bold Atkinson Hyperlegible BMFont is the same deferred font-swap behind the existing `fontFor` seam — not this story.
- **Card & Finished are PlaybackView draw-modes** (two more `onUpdate` early-returns, like ramp/paused/null-record), keeping engine+timer coupling in one file (no pushed view, no back-reference, no GC cycle — AR15). `StatusView` is a standalone render-only `WatchUi.View` (no delegate, no controls, no Epic-3 trigger).
- **Resolves deferred-work #107 by decision:** no rewind-into-text from FINISHED (BACK exits; re-read is phone-side, UX-DR14). `rewindOne()`/`openContextView()`/`stepWpm()` now no-op while `_chapterCard || isFinished()` so a card / end screen can't be driven into text (a card pauses the engine, so the existing `isPaused()` guard alone was insufficient).
- **`pauseAtCurrent()`** (engine, Lang-only) is an instant mode-independent freeze (reuses `finalizePause`) so a `PAUSE_COAST` reader doesn't coast past the chapter's first word; resume is plain `play(now)`, the only lever that re-anchors the accumulator, so the ~2 s card triggers no catch-up burst (3-beat ramp = the intended "breath").
- **Known limitation (inherent to the spec'd detection):** a chapter boundary crossed *inside* a single catch-up tick (>1 word advanced after a stall) would not raise its card, since detection reads "the now-current word carries `FLAG_CHAPTER_START`" after `onTick`. At normal reading pace (one word per tick) cards fire at 81 & 170 as specified. Candidate deferred item if it ever matters on device.
- No `manifest.xml` / permission / Storage changes. GateV2 spike preserved; `getInitialView` still enters `PlaybackView`.

### File List

**New (source):**
- `watch/source/views/ChapterCatalog.mc` — pure chapter offsets/titles + lookups (Lang-only).
- `watch/source/views/StatusLayout.mc` — pure status copy + Finished/reading-time formatting (Lang-only).
- `watch/source/views/StatusView.mc` — render-only parameterized shell for the 4 system states.

**New (tests):**
- `watch/source-test/ChapterCatalogTest.mc`
- `watch/source-test/StatusLayoutTest.mc`

**Modified:**
- `watch/source/Settings.mc` — `chapterResume` field (const/default/apply/serialize/key).
- `watch/source/engine/ReaderEngine.mc` — `pauseAtCurrent()`.
- `watch/source/engine/BookWordSource.mc` — `chapters()` seam (empty-catalog default).
- `watch/source/source_data/CannedWordSource.mc` — bundled `ChapterCatalog` from the fixture; `chapters()` override.
- `watch/source/views/PlaybackView.mc` — chapter-card + Finished draw-modes, card lifecycle, card-aware `pauseOrResume`, card/finished guards on `stepWpm`/`rewindOne`/`openContextView`, `totalReadingMs`/`fitTitleFont`.
- `watch/source-test/ReaderEngineTest.mc` — `chapterResume` Settings cases + 3 `pauseAtCurrent` tests.

## Change Log

- 2026-06-28 — Story 3.5 dev-story (Amelia): chapter card + Finished screen + 4 render-only status shells (FR5/FR6). New pure modules `ChapterCatalog` + `StatusLayout`; new `StatusView`; `chapterResume` setting; `ReaderEngine.pauseAtCurrent()`; `BookWordSource.chapters()` seam fed by `CannedWordSource` from the committed fixture. Resolves deferred-work #107 (no FINISHED rewind, by decision). 73/73 host tests @ Strict L3 (+10); release + unit-test builds clean. Status → review; on-device Fenix 8 check PENDING human.

## Review Findings

Code review 2026-06-28 (Amelia) — 3 adversarial layers (Blind Hunter / Edge Case Hunter / Acceptance Auditor) over commit `339dbba` vs baseline `355eecb`. **All 4 ACs MET** (auditor), on-device PASS confirmed, 73/73 host tests. 2 patches, 6 deferred, 8 dismissed (no decision-needed, no Critical/High reachable in Epic 3).

- [x] [Review][Patch] Finished screen ignores burn-in jitter — `drawFinished` is the only draw path that omits `+_jitterX/+_jitterY`; it is also the longest-lived static frame (persists until BACK) on AMOLED. [`watch/source/views/PlaybackView.mc:531-538`] — FIXED 2026-06-28: `drawFinished` now applies the session jitter offset like every other draw path.
- [x] [Review][Patch] Auto chapter card stranded as a Wait card after a hide/show — `onHide` stops the one-shot card timer; on re-show the carded engine is PAUSED, so `onShow` re-arms nothing and `_chapterCard` stays true with no Auto resume timer (a system overlay/notification during the ~2 s window converts Auto→Wait until START). [`watch/source/views/PlaybackView.mc:131-147`] — FIXED 2026-06-28: `onShow` re-arms the Auto card timer when shown while `_chapterCard && chapterResume==AUTO`.
- [x] [Review][Defer] Catch-up burst overshoots/skips a chapter boundary — `maybeEnterChapterCard` inspects only the landed `_engine.index()` after `onTick`; a delayed tick advancing >1 word (up to `CATCHUP_CAP`=4) steps OVER a chapter-start word and raises no card. Dev-documented limitation; unreachable at 1-word/tick (cards verified at 81 & 170 on device); more likely with Epic-4 buffering stalls. [`watch/source/views/PlaybackView.mc:300-326`] — deferred to Epic 4
- [x] [Review][Defer] Chapter start reached during the resume RAMP is not carded — the card gate is `!_engine.isPlaying()`, excluding `STATE_RAMP`; a chapter whose start falls within the 3-beat resume ramp would be silently skipped. Unreachable in the canned source (chapters 81/170 are far past the only ramp at book start, where word 0 never cards). [`watch/source/views/PlaybackView.mc:300-303`] — deferred to Epic 4
- [x] [Review][Defer] `_cardedIndex` is never reset on rewind/finish — rewinding back across a boundary then reading forward re-hits `idx == _cardedIndex` and shows no chapter card on the re-cross (marginal UX). [`watch/source/views/PlaybackView.mc:208-219, 300-315`] — deferred to Epic 4
- [x] [Review][Defer] Catalog/Finished hardening for the live manifest — final-word-is-chapter-start → card-then-finish; `offsets[0] != 0` unenforced; empty-catalog-but-FLAG_CHAPTER_START renders "Chapter 1"/blank; `count()` silently truncates to the shorter of offsets/titles; `totalReadingMs` 32-bit overflow on multi-million-word books. All guarded-by-construction in the 228-word canned source; reachable only with the Epic-4 `ChunkedWordSource`. [`watch/source/views/ChapterCatalog.mc`, `watch/source/views/PlaybackView.mc:545-552`] — deferred to Epic 4
- [x] [Review][Defer] `StatusView` render-only shell edges — long status sentences have no max-lines/vertical clamp (`drawCenteredWrapped` can push lines off a round face) nor horizontal fit; Buffering "Loading…" (steady) vs "Loading..." (dot cycle) disagree and the 0-dot branch is dead live; `splitWords` is O(n²) char-concat re-run every Buffering repaint. No Epic-3 trigger — shells aren't shown until Epic 4 wires triggers + on-device verification. [`watch/source/views/StatusView.mc`] — deferred to Epic 4
- [x] [Review][Defer] Finished stat single-line non-wrap — `drawFinished` draws one `FONT_SYSTEM_SMALL` line; fits the Epic-3 "Finished. 6h 41m." (on-device PASS) but risks horizontal clip when Story 3.6 adds the "across N days" tail. [`watch/source/views/PlaybackView.mc:531-538`] — deferred to Story 3.6

**Dismissed (8):** `totalReadingMs` div-by-zero (false positive — `_wpm` clamped ≥ `WPM_MIN`, never 0, per `beatMs()`); `totalReadingMs` integer-division "rounding" and "stat is fiction if WPM changed" (by spec — current-wpm content-time estimate that mirrors the engine's per-word truncation exactly; wall-clock is Story 3.6); `fitTitleFont` font-ordering off-by-one (false positive — `fontFor(0)=LARGE … (4)=XTINY`, loop returns largest-that-fits, fallback smallest); `onCardTimeout` stale fire (handled — `!_chapterCard` guard + single Timer instance reschedule); `_cardChapterNum = 0` dead default (benign — always set before the card draws); `numberForWord` "clamps to 1" phrasing (implementation correct); `chapters()` null guard (non-nullable return type under Strict).

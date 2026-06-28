---
baseline_commit: 74772bcbadf58ea762ae144e79965f3846c243ab
---
# Story 3.4: Paused view & context-on-pause

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a reader,
I want the paused screen to show where I am and the surrounding text,
so that I can recover after a glance away (FR11).

## Acceptance Criteria

**AC1 — Paused progress readout (book %, time-remaining, WPM) in Ink-Dim, never during playback**
**Given** a pause (the word frozen on screen)
**When** the paused still-frame shows
**Then** a progress readout appears in Ink-Dim (`#8A867F`, `watch-meta` font) carrying **book %**, **time-remaining** (derived from the remaining words' cumulative durations: `60000/wpm` per word + each word's `bonusMs`), and the **current WPM**
**And** the readout is drawn **only while `engine.isPaused()`** — never during the ramp, playback, FINISHED, or IDLE (UX-DR8: "while words flow, the screen owes the reader nothing but the word").

**AC2 — DOWN / swipe-up while paused opens a scrollable context view with the current word marked**
**Given** the paused view
**When** I press DOWN (or swipe up, touch on)
**Then** a scrollable context view is pushed showing the **surrounding paragraph** (the words between the `FLAG_PARAGRAPH_START` at-or-before the current index and the next paragraph start / end of book) as wrapped multi-line `context-body` text, **left-aligned in the watch-safe-square**, with the **current word marked** (rendered in bright Ink against the Ink-Dim paragraph body)
**And** it opens scrolled so the current word's line is visible, and UP/DOWN (or swipe up/down) scroll the paragraph.

**AC3 — BACK from the context view returns to Paused, does NOT exit**
**Given** the context view
**When** I press BACK
**Then** the context view is **popped** (`WatchUi.popView`) and the reader is back on the Paused still-frame — the app does **not** exit to the watch face (BACK-exits-the-app remains the Paused-screen behavior, but from the pushed context view BACK pops one level).

**AC4 — START from Paused resumes with the start ramp**
**Given** Paused
**When** I press START (or tap, touch on)
**Then** playback resumes with the 3-beat start ramp (`engine.play()` re-arms the ramp), the paused readout disappears (it is gated on `isPaused`), and words flow again.

## Tasks / Subtasks

- [x] **Task 1 — Pure paused/context math + paragraph navigation, host-tested (AC1, AC2)**
  - [x] Create `watch/source/views/PausedLayout.mc` — a `module PausedLayout` of **pure** functions (imports **only `Toybox.Lang`**; NO `Toybox.WatchUi`/`Graphics` — the pixel work lives in the views, exactly like `OrpLayout`). Host-testable under the matco tester. [Source: OrpLayout.mc:1-13; architecture.md:355-358 "pure logic"]
  - [x] `bookPercent(index as Number, wordCount as Number) as Number` → integer 0–100: `wordCount <= 1 ? (wordCount <= 0 ? 0 : 100) : (index * 100) / (wordCount - 1)`. Bounds: clamp result to [0,100]; index is 0-based absolute (FR13). (Use `wordCount - 1` so the last word reads 100%.) [Source: ReaderEngine.mc:47, 205, 284 — 0-based index, atEnd = `index >= count-1`]
  - [x] `timeRemainingMs(wordsRemaining as Number, wpm as Number, bonusRemainingMs as Number) as Number` → `wordsRemaining * (60000 / wpm) + bonusRemainingMs` (integer ms; the `60000/wpm` beat mirrors the engine's `beatMs()` exactly — SPEC §5.1, never float). `wpm` is the live engine WPM (clamped ≥ `WPM_MIN`, never zero). **Pure number math — host-tested with literals, no source needed.** [Source: ReaderEngine.mc:264-280 `computeDuration`/`beatMs`; SPEC §5.1]
  - [x] `sumBonusMs(source as BookWordSource, fromIndex as Number, toIndexInclusive as Number) as Number` → Σ `wordAt(k).bonusMs` over `[fromIndex, toIndexInclusive]`, skipping null records (bounds-check-and-degrade). Host-tested with `FakeWordSource`. [Source: BookWordSource.mc:21-36; FakeWordSource.mc; StreamDecoder.mc:13-25 `WordRecord.bonusMs`]
  - [x] `formatRemaining(ms as Number) as String` → human time-left. Rule: `< 1 h` → `"M:SS"` (e.g. `0:42`, `12:05`); `>= 1 h` → `"H:MM:SS"` (e.g. `1:02:05`). Negative/zero → `"0:00"`. Integer division only; zero-pad seconds and the minutes field in the hour form. Host-tested with literals (0, 42000, 65000, 3725000). [Source: DESIGN.md:122 watch-meta "time remaining"; EXPERIENCE.md:83]
  - [x] `paragraphStartAtOrBefore(source as BookWordSource, index as Number) as Number` → the nearest index `<= index` whose record has `FLAG_PARAGRAPH_START` set, else `0`. Mirrors the engine's `sentenceStartAtOrBefore` shape but keyed on `Protocol.FLAG_PARAGRAPH_START` (`0x02`). Bounds-check-and-degrade (null record → keep scanning / return 0). [Source: ReaderEngine.mc:299-309; Protocol.mc:48]
  - [x] `paragraphEndAtOrAfter(source as BookWordSource, index as Number) as Number` → the index just **before** the next `FLAG_PARAGRAPH_START` after `index`, else `wordCount - 1` (last word). Inclusive end of the current paragraph. [Source: Protocol.mc:48; ReaderEngine.mc:284]
  - [x] Host tests `watch/source-test/PausedLayoutTest.mc` (mirror `OrpLayoutTest.mc`/`ReaderEngineTest.mc` `(:test)` + `logger.error`/`return false`, **no `Test.assert*`**). Build a `FakeWordSource` fixture with **known paragraph-start indices and bonusMs** (reuse the `ReaderEngineTestSupport.sampleWords()` shape — note word 0 there carries `FLAG_PARAGRAPH_START | FLAG_CHAPTER_START`). Assert: `bookPercent` at 0 / mid / last (= 100) and the `wordCount<=1` edges; `timeRemainingMs` literals incl. a non-divisor WPM (e.g. 350) to pin integer truncation; `formatRemaining` for sub-minute, minutes, and ≥1h; `sumBonusMs` over a range; `paragraphStartAtOrBefore`/`paragraphEndAtOrAfter` mid-paragraph, at a boundary, and the **no-paragraph-flags degrade** (a fixture with no `FLAG_PARAGRAPH_START` after 0 → start 0, end `count-1`). **Test count must RISE** (3.2/3.3 "not flat" rule). [Source: ReaderEngineTest.mc:1-44; 3-3 story Task 1 last bullet]

- [x] **Task 2 — Paused progress readout in PlaybackView (AC1)**
  - [x] In `watch/source/views/PlaybackView.mc`, add `private function drawPausedReadout(dc, w, h) as Void` and call it from `onUpdate` **only on the paused still-frame**. Gate: `if (!_engine.isPaused()) { return; }` (so ramp/playing/FINISHED/IDLE draw nothing — UX-DR8). This is **distinct from** the existing `drawWpmReadout` (the *transient playing* overlay, gated on `isPlaying()||isRamping()`); the two never draw together. [Source: PlaybackView.mc:210-269]
  - [x] Content: `PausedLayout.bookPercent(_engine.index(), _source.wordCount())`, `PausedLayout.formatRemaining(PausedLayout.timeRemainingMs(wordsRemaining, _engine.wpm(), bonusRemaining))`, and `_engine.wpm()`. Compute `wordsRemaining = _source.wordCount() - _engine.index()` (words from the current word to end inclusive — document this convention) and `bonusRemaining = PausedLayout.sumBonusMs(_source, _engine.index(), _source.wordCount() - 1)`. **This sum runs once per pause (on the still-frame repaint), NOT per word** — paused is not the hot path. [Source: PlaybackView.mc:69-72 (`_source`,`_engine`); ReaderEngine.mc:205,207,223]
  - [x] Render in `COLOR_INK_DIM` (already defined, `0x8A867F`) using the small native face (`FONT_SYSTEM_TINY` ≈ `watch-meta` 22px, as `drawWpmReadout` uses), centered horizontally, seated in the **lower third** of the safe square clear of the focal word and the bottom split-hairline, carrying `_jitterX`/`_jitterY` like the rest of the composition. Compose as **one or two short centered lines** (e.g. line 1 `"<pct>%"`, line 2 `"<time> left · <wpm> wpm"`) inside the `watch-safe-square` (~320px). Dev picks the exact split; pin: Ink-Dim, watch-meta, lower third, jittered, **paused-only**. [Source: DESIGN.md:21,74-76,108,122,131-134; PlaybackView.mc:34-35,253-268]
  - [x] **"Fades in" → MVP renders immediately** in Ink-Dim. A true opacity fade is OUT: Garmin `drawText` has no alpha, and the paused state intentionally runs **no timer** (a multi-frame brightness ramp would require re-arming one on pause — explicitly avoided). Document this at the draw site as a deliberate MVP simplification; on-device review may revisit. [Source: PlaybackView.mc:110-112,178-205 (timer self-stops on pause); EXPERIENCE.md:197]
  - [x] **Do NOT** stop/arm the timer here and **do NOT** touch the engine — the readout is a pure draw over the already-frozen paused frame produced by the existing `onTimerTick` paused branch. [Source: PlaybackView.mc:183-205]

- [x] **Task 3 — PausedContextView: scrollable surrounding-paragraph view (AC2)**
  - [x] Create `watch/source/views/PausedContextView.mc` — `class PausedContextView extends WatchUi.View`. Constructor takes **`(source as BookWordSource, currentIndex as Number)`** — a **snapshot** of the position (paused, so the index won't change while open). It holds the source (read-only) and the index; it does **NOT** hold the engine or PlaybackView — input flows one-directionally and there is no back-reference, so no GC cycle (AR15). [Source: architecture.md:106,287,374 (`PausedContextView.mc # context-on-pause scroll view (FR11)`); PlaybackView.mc:8-12 (no-cycle rule)]
  - [x] On first `onUpdate` (lazy, cached): compute the paragraph range `pStart = PausedLayout.paragraphStartAtOrBefore(source, idx)`, `pEnd = PausedLayout.paragraphEndAtOrAfter(source, idx)`; build the word list `[pStart..pEnd]` (each carrying its absolute index so the current word can be marked); **wrap to lines by measuring `dc.getTextWidthInPixels(word, font)`** against the usable width (`dc.getWidth() - 2*WATCH_EDGE`, or the safe-square width). Cache the wrapped lines + the line index that contains `currentIndex` so scroll can be clamped and the initial scroll can land on the current word. (Wrapping needs `dc`, so it can't live in pure `PausedLayout` — same split as `PlaybackView.fitFontIndex`.) [Source: PlaybackView.mc:299-394 (dc-measured layout in the view); OrpLayout.mc:6-9 (pure vs view split); DESIGN.md:132 "left-aligned in the scrolling context view"]
  - [x] Font: a native face at the **`context-body` 26px** target (e.g. `FONT_SYSTEM_SMALL`/`MEDIUM` — dev picks the closest). The Atkinson Hyperlegible BMFont is the same deferred font-swap seam as PlaybackView's word face (its own later story) — use the native fallback here too, by name, no inline magic. [Source: DESIGN.md:42-46,120; PlaybackView.mc:54-58,371-379 (native ramp = documented escape hatch)]
  - [x] Render: `dc.clear()` to `COLOR_VOID`; draw the visible lines from `_scrollLine` downward, **left-aligned** within the safe square. Body words in `COLOR_INK_DIM`; the **current word (absolute index == `currentIndex`) in `COLOR_INK`** (bright) — marking is **brightness**, not a second accent color (DESIGN: "hierarchy is brightness `ink → ink-dim → ink-faint`, never shadow", "one red, one job"). Draw word-by-word advancing x by measured width + a space so the single current word can be the bright one. [Source: DESIGN.md:108-113,140; PlaybackView.mc:32-36,361-368]
  - [x] Scroll API for the delegate: `function scrollDown() as Void` / `function scrollUp() as Void` — adjust `_scrollLine` clamped to `[0, max(0, totalLines - visibleLines)]` (`visibleLines = safeHeight / dc.getFontHeight(font)`) and `WatchUi.requestUpdate()`. Initial `_scrollLine` positions the current-word line into view (center it if possible). [Source: PlaybackView.mc:139-159 (view action API pattern + requestUpdate)]
  - [x] **Degrade, never crash** (NFR8/AR24): empty paragraph / null records / `currentIndex` out of range → draw nothing or the available words, no crash. A stream with **no `FLAG_PARAGRAPH_START`** degrades to the whole book as one (scrollable) paragraph — bounded and safe; document it. [Source: ReaderEngine.mc:288-294; Protocol.mc:48; StreamDecoder.mc:6-9]
  - [x] **No watchdog risk:** wrapping a single paragraph (tens of words) is built **once** and cached; `onUpdate` only blits the cached visible lines (cheap — the same discipline as `PlaybackView.onUpdate`). No decode, no per-frame rebuild. [Source: PlaybackView.mc:207-243; watch-decode-watchdog memo]

- [x] **Task 4 — PausedContextDelegate + InputMap swipe-up, wired through PlaybackView (AC2, AC3)**
  - [x] Create `watch/source/input/PausedContextDelegate.mc` — `class PausedContextDelegate extends WatchUi.InputDelegate` (**NOT `BehaviorDelegate`** — same rule as `PlaybackDelegate`: raw events, no `onSelect`/`onBack` remap, AC of 3.3 carried forward). Holds the `PausedContextView` it scrolls. [Source: PlaybackDelegate.mc:5-24; architecture.md:301,382]
    - `onKey`: `KEY_ESC` → `WatchUi.popView(WatchUi.SLIDE_DOWN); return true;` (**AC3 — pop, not exit; consume it** so the system does NOT additionally pop/exit). `KEY_UP` → `_view.scrollUp(); return true;`; `KEY_DOWN` → `_view.scrollDown(); return true;`. Everything else (LIGHT/MENU/ENTER) → `return false`. [Source: WatchUi.InputDelegate docs; 3-3 Dev Notes "Connect IQ input API"]
    - `onSwipe`: swipe up → `_view.scrollDown()` (content moves up); swipe down → `_view.scrollUp()`; `return true` for those, else `false`. (Touch is a mirror; buttons are the guarantee — FR12.) [Source: EXPERIENCE.md:137,146]
  - [x] Extend the pure map in `watch/source/input/InputMap.mc`: change `actionForSwipe` to be **paused-aware** so a **swipe-up while paused (touch on)** opens the context view. New signature: `actionForSwipe(direction, touchEnabled, rewindDir, isPaused) as Number` → return `ACTION_REWIND` if `touchEnabled && direction == rewindDir`; **`ACTION_CONTEXT` if `touchEnabled && isPaused && direction == WatchUi.SWIPE_UP`**; else `ACTION_NONE`. (`ACTION_CONTEXT` already exists — 3.3 reserved it.) Keep all other mappings unchanged. [Source: InputMap.mc:25-69; EXPERIENCE.md:137]
  - [x] In `watch/source/input/PlaybackDelegate.mc`: handle `ACTION_CONTEXT` in **`onKey`** (DOWN-while-paused already maps to it) → `_view.openContextView(); return true;` (was `return false` no-op in 3.3). Update the **`onSwipe`** call site to pass `_view.isPausedState()` as the new `isPaused` arg and dispatch `ACTION_CONTEXT` → `_view.openContextView(); return true;`. Leave `ACTION_EXIT`/`ACTION_NONE` returning `false`. [Source: PlaybackDelegate.mc:33-76]
  - [x] Add `function openContextView() as Void` to `PlaybackView`: guard `if (!_engine.isPaused()) { return; }` (degrade — context is a paused-only affordance) and `if (_engine.currentRecord() == null) { return; }`; then construct the view + delegate and push:
    `var ctx = new PausedContextView(_source, _engine.index()); WatchUi.pushView(ctx, new PausedContextDelegate(ctx), WatchUi.SLIDE_UP);`
    PlaybackView owns `_source` and reads `_engine.index()`; it constructs and pushes — it does **not** keep a reference to the pushed view/delegate after pushView (no cycle). [Source: PlaybackView.mc:69-72,114-176; WatchUi.pushView docs]
  - [x] Update `watch/source-test/InputMapTest.mc` for the new `actionForSwipe` arity: pass `isPaused` in existing cases (rewind swipe unaffected), and add: swipe-up + paused + touch-on → `ACTION_CONTEXT`; swipe-up + **playing** → `ACTION_NONE`; swipe-up + paused + **touch-off** → `ACTION_NONE`; a non-up swipe while paused → unchanged. **Test count must rise.** [Source: InputMap.mc:67-69; 3-3 File List "InputMapTest.mc — 5 host tests"]

- [x] **Task 5 — Fix PlaybackView.onShow auto-play so returning from the context view stays PAUSED (AC3, regression guard)**
  - [x] **CRITICAL:** `PlaybackView.onShow` currently calls `_engine.play()` + `armTimer()` unconditionally (Story 3.2 demo auto-play). When the context view is **popped**, the revealed PlaybackView fires `onShow` again → it would **resume playback**, breaking AC3 ("returns to Paused, not playing"). Change `onShow` to auto-play **only from a never-played engine**:
    ```
    function onShow() as Void {
        recomputeJitter();
        if (_engine.state() == Reader.STATE_IDLE) {
            _engine.play(System.getTimer()); // first-launch demo auto-play (3.2)
            armTimer();
        } else if (_engine.isPlaying() || _engine.isRamping()) {
            armTimer(); // became visible while live — keep the loop running
        }
        // PAUSED / FINISHED: stay frozen, no timer (return-from-context → AC3)
        System.println(...existing readiness marker...);
        WatchUi.requestUpdate();
    }
    ```
    This **preserves** the first-launch auto-play (engine starts IDLE → plays — unchanged 3.2/3.3 behavior) and **fixes** the pop-back-to-paused regression. It also pre-aligns with Story 3.6 "resume lands Paused". Keep the single machine-readable readiness `println` (no per-word logging, AR25). [Source: PlaybackView.mc:99-112; ReaderEngine.mc:17-23,79-96,210-213; 3-3 Completion Notes "AC1 resume"]
  - [x] Note `onHide` already `_timer.stop()`s when the context view is pushed over PlaybackView — correct, leave as-is. [Source: PlaybackView.mc:110-112]

- [x] **Task 6 — Verify (Strict L3 + host tests green + on-device check)**
  - [x] Compile clean at **Strict (level 3)** for BOTH builds — unit-test build and release (`monkeyc -l 3 -r`). Strictness never lowered. Watch the new `actionForSwipe` 4-arg signature, the `WatchUi.pushView`/`popView`/`SLIDE_*` enums, and `dc.getFontHeight`/`getTextWidthInPixels` typings at L3. [Source: architecture.md:314; 3-3 Debug Log; 3-2 Debug Log]
  - [x] Run host tests in the CI image (`ghcr.io/matco/connectiq-tester`, **bare positional** `… fenix847mm` form — NOT a trailing `-c`, which the matco ENTRYPOINT swallows and hangs; see 3-3 Debug Log) **after `rm -f watch/bin/app.prg`** (stale-binary trap). The current **55** tests + new `PausedLayoutTest` + new `InputMapTest` cases must all pass and the **count must rise**. [Source: watch-tests-local-via-ci-docker-image memo; 3-3 Debug Log lines 180-182]
  - [x] **On-device check on the real Fenix 8 (sideload — host tests can't see view-stack push/pop, scroll, or readout legibility; REQUIRED).** Confirm: (1) on pause (coast→sentence-end) the Ink-Dim readout appears with plausible %, time-left, WPM and is **gone** the instant you resume; (2) DOWN **and** swipe-up (touch on) open the context view scrolled to the current word, which is visibly **brighter** than the surrounding paragraph; (3) UP/DOWN + swipe up/down scroll; (4) **BACK returns to Paused, does NOT exit the app**; (5) START from Paused resumes with the 3-2-1 ramp and the readout clears; (6) with **Touch controls Off**, DOWN→context and BACK→Paused still work by buttons (swipe is a no-op). Use the existing `(:debug)` input trace — **no per-word/persistent `println`** (AR25). Record the result in Completion Notes (mirror 3.3's on-device block). [Source: garmin-ciq-ubuntu-2404-appimage memo; EXPERIENCE.md:131-138,194-202; architecture.md:323]

### Review Findings (code-review 2026-06-28 — 3 layers: Blind / Edge / Acceptance)

Acceptance Auditor: all 4 ACs MET, all constraints PASS (View→CustomMenu redesign judged legitimate). No crash-class findings — the pure layer is clamped and the concrete `CannedWordSource` is fully buffered.

- [x] [Review][Decision→Dismissed] Last-word readout shows "100%" alongside non-zero time-left — resolved 2026-06-28 (Nerya): correct by design. `bookPercent` measures *position*; time-left measures *reading time including the current word*, which still has its beat+bonus to elapse. On-device passed; kept as-is. [PlaybackView.mc:305-308]
- [x] [Review][Patch] Misleading "runs ONCE per pause" comment on `sumBonusMs` — FIXED 2026-06-28: comment now states it is O(remaining), recomputed on every paused repaint (cheap on the canned source), with the Epic-4 manifest O(1) swap still noted. Comment-only, no behavior change. [PausedLayout.mc:37-42; PlaybackView.mc:301-305]
- [x] [Review][Defer] Context focus-line lands wrong when a null/unbuffered record precedes the current word — `wrap()` skips null records via `continue`, so `currentLine` stays 0 and the bright current word can open off-screen. [PausedContextView.mc:122,139] — deferred, unreachable under the fully-buffered CannedWordSource; activates with the Epic-4 chunked `BookWordSource`.
- [x] [Review][Defer] `drawPausedReadout` lacks the null-`currentRecord` guard that `openContextView` has — computes %/time over a possibly-null record. [PlaybackView.mc:294-308 vs :188] — deferred, safe under CannedWordSource; add the guard when a non-buffered source lands (Epic 4).
- [x] [Review][Defer] `_wpmReadoutUntil` deadline has no `getTimer()` wraparound guard — near the 32-bit wrap the transient WPM flash silently drops. [PlaybackView.mc:160,340] — deferred, pre-existing from Story 3.3 (already tracked in deferred-work.md).
- [x] [Review][Defer] Context lines wrapped to full diameter may clip at round-screen top/bottom rows — `usable = screenW - 2*MARGIN` is applied to every line; only the centered line has that chord on a round face. [PausedContextView.mc:59,110-154] — deferred, on-device passed; visual polish, revisit if a long paragraph clips.

Dismissed (4, noise/false-positive): `timeRemainingMs` per-word integer truncation [intentional — mirrors the engine's `beatMs()` exactly per spec §5.1, so the estimate matches real playback, not an under-report]; `paragraphStartAtOrBefore` `i>0` word-0-flag conflation [correct result, no consequence]; empty-word invisible-mark [outside the baker's valid input domain — words are non-empty]; `measuringDc` 50px buffer magic constant [measurement APIs don't use buffer height — harmless].

## Dev Notes

### What this story owns (scope boundary)
The **paused progress readout** and the **context-on-pause** view: pure `views/PausedLayout.mc` (book %, time-remaining, `formatRemaining`, bonus sum, paragraph bounds), a paused-only readout added to the existing `PlaybackView`, a new pushed `views/PausedContextView.mc` (scrollable surrounding paragraph, current word marked) with its `input/PausedContextDelegate.mc`, a paused-aware `actionForSwipe` + `ACTION_CONTEXT` wiring in the existing map/delegate, and the `onShow` auto-play fix that keeps pop-back PAUSED.
**New:** `views/PausedLayout.mc`, `views/PausedContextView.mc`, `input/PausedContextDelegate.mc`, `source-test/PausedLayoutTest.mc`. **Modify:** `views/PlaybackView.mc`, `input/InputMap.mc`, `input/PlaybackDelegate.mc`, `source-test/InputMapTest.mc`.

**OUT of scope (do NOT build here):**
- **Persistence / force-save** of position on pause/BACK/rewind (`SyncManager.commitPosition(force)`) — **Story 3.6**. There is no `SyncManager` yet and the source is the canned dev stream; **3.4 writes NO Storage.** BACK from the *context view* pops (no save); BACK from the *Paused screen* still just exits (3.3 behavior, save is 3.6). [Source: 3-3 Dev Notes "BACK & force-save"; architecture.md:366; deferred-work.md]
- **Chapter card / Finished / status shells** — **Story 3.5** (no Finished/empty-state shells here). **Settings menu** (MENU) — **Story 3.8**. **Display-survival / dim-AON** — **Story 3.7**. `ChunkedWordSource`/real transfer + manifest delivery — **Epic 4**. [Source: epics.md#Epic-3; architecture.md:374-382]
- A true **opacity fade-in** animation for the readout — MVP appears immediately (see Task 2 rationale); optional polish only.
- The architecture's separate **`PausedDelegate.mc`** (for the *paused playback screen*) — its routing (START=resume, UP=rewind, DOWN=context) is already handled by the **state-aware `PlaybackDelegate`** carried from 3.3 (it reads `isPaused` via the view and maps through `InputMap`). The new `PausedContextDelegate` serves the *pushed context view*, which is a genuinely separate view needing pop/scroll. See "Project Structure Notes". [Source: 3-3 Project Structure Notes; architecture.md:382]

### REUSE — do not reinvent
- **`Reader.ReaderEngine`** — read-only here: `index()`, `wpm()`, `isPaused()`, `state()`, `currentRecord()`, `play()` (resume/ramp), `STATE_IDLE`. AC4 (resume-with-ramp) is **already implemented** by `PlaybackView.pauseOrResume()` → `engine.play()` (3.3) — **do not duplicate**; 3.4's job is to not regress it (the `onShow` fix) and to clear the readout on resume (gating on `isPaused`). [Source: ReaderEngine.mc:79-96,205-225; PlaybackView.mc:125-134]
- **`PlaybackView`** — owns `_source`/`_engine`/`_timer`/`_jitterX/Y`/color consts/`armTimer`/`recomputeJitter`/`onTimerTick`. Add only `drawPausedReadout` + `openContextView` + the `onShow` guard. The paused still-frame already exists (the `onTimerTick` paused branch + `onUpdate`); the readout is a pure overlay on it. [Source: PlaybackView.mc:27-243]
- **`InputMap`** — `ACTION_CONTEXT = 5` already exists (3.3 reserved it for "DOWN while paused"); just wire it (delegate) and add the swipe-up case. Action constants stay typed, no magic numbers. [Source: InputMap.mc:25-52]
- **`Protocol.FLAG_PARAGRAPH_START` (`0x02`)** — the paragraph-boundary flag baked phone-side (Story 2.1/2.2). The watch never recomputes linguistics; it reads flags. [Source: Protocol.mc:48; epics.md#Story-2.1]
- **`StreamDecoder.WordRecord`** — `word`/`flags`/`orpPivot`/`bonusMs`; reuse, no new struct. `FakeWordSource` (test double) and `CannedWordSource` (the running Epic-3 source) both extend `BookWordSource`. [Source: StreamDecoder.mc:13-25; FakeWordSource.mc; CannedWordSource.mc]
- **Test pattern** — copy `OrpLayoutTest.mc`/`ReaderEngineTest.mc`/`SmokeTest.mc`: `import Toybox.Test; (:test) function x(logger as Test.Logger) as Boolean { if (a != b) { logger.error("..."); return false; } return true; }`. **No `Test.assert*` anywhere in this repo.** [Source: ReaderEngineTest.mc:1-9; 3-3 Dev Notes]

### Time-remaining: how "cumulative durations" maps onto the Epic-3 canned source
The UX/epics phrase is "time-remaining from **cumulative durations**" — in the shipped delivery path (Epic 4) the **manifest** carries the precomputed cumulative-duration data: `tw` (total words), `tb` (total bonus ms), and per-chapter `cb` (cumulative bonus ms) [Source: Protocol.mc:29-34; architecture.md:193; epics.md#Story-2.2 "cumulative durations"]. The reading-time of any span = `wordCount * (60000/wpm) + Σ bonusMs` (the `60000/wpm` beat is WPM-dependent and recomputed each readout; the `bonusMs` part is WPM-invariant and is exactly what the manifest precomputes). **There is no manifest on the canned `CannedWordSource` path yet**, so 3.4 computes the bonus-remaining by summing `bonusMs` over the remaining words **once per pause** via `PausedLayout.sumBonusMs` — correct and cheap for the 228-word canned book (paused is not the hot path). **Forward note (Epic 4 / Story 4.1):** when `ChunkedWordSource` + the manifest land, swap `sumBonusMs(...)` for `manifest.totalBonusMs − cumulativeBonusUpTo(index)` (O(1)) so the readout never iterates a chunked/partial buffer. Keep `timeRemainingMs` as the pure seam so only the *bonus source* changes. [Source: architecture.md:362,193; deferred-work.md "Forward to Epic 4"]

### View-stack & GC discipline (AR15 — no cycle)
- Push/pop is a real Garmin view stack: `WatchUi.pushView(view, delegate, WatchUi.SLIDE_UP)` to open the context view; `WatchUi.popView(WatchUi.SLIDE_DOWN)` (from the context delegate's BACK) to return to the paused PlaybackView beneath. [Source: developer.garmin.com Toybox.WatchUi.pushView/popView/SlideType]
- Reference graph stays acyclic: `PlaybackDelegate → PlaybackView → {engine, source}`; the pushed `PausedContextDelegate → PausedContextView → source` (read-only). The context view does **NOT** reference the engine or PlaybackView; PlaybackView does **NOT** retain the pushed view/delegate after `pushView`. The shared `source` is referenced by multiple owners but references nothing back — no cycle, safe under refcount GC. [Source: architecture.md:106,287; PlaybackView.mc:8-12; 3-3 Dev Notes line 123]
- **onShow/onHide lifecycle is the trap.** Pushing the context view fires PlaybackView `onHide` (timer stops — fine, it was already paused). Popping fires PlaybackView `onShow` — which today auto-plays. Task 5's guard (auto-play only from `STATE_IDLE`) is what makes AC3 hold. **Verify on-device**, since the push/pop lifecycle is exactly what host tests cannot exercise.

### Marking the current word — brightness, not a second color
Mark the current word by **brightness** (`COLOR_INK` bright against an `COLOR_INK_DIM` paragraph body), never by introducing a second accent. DESIGN is explicit: "hierarchy is brightness (`ink → ink-dim → ink-faint`), never shadow or layering" and "One red, used for one job" (Pivot = the pivot letter + anchor ticks only, never chrome) [Source: DESIGN.md:108-113,140,152]. Brightness-only marking is also color-blind safe (the same principle that put geometry, not color, on the playback guide ticks — UX-DR24). If on-device legibility wants the body brighter, a reviewer may flip to body-`Ink` + an `Ink-Faint` underline on the current word — but default to dim-body / bright-current-word.

### Composition / colors (DESIGN authority)
- Paused readout: **Ink-Dim `#8A867F`**, `watch-meta` 22px (`FONT_SYSTEM_TINY`), lower third, jittered, **paused-only** ("Appears only when paused" — DESIGN.md:153). Reuse the existing `COLOR_INK_DIM` const; no inline hex at draw sites (the 3.2 rule). [Source: DESIGN.md:74-76,108,122,153; PlaybackView.mc:34-35]
- Context view: `context-body` 26px / line-height 1.45, **left-aligned** in the `watch-safe-square` (~320px centered; the circle's corners stay empty; the circle itself is the scroll boundary — no card with corners on the round display). `COLOR_VOID` background. [Source: DESIGN.md:42-46,120,131-134,144]
- Burn-in citizenship: the readout rides the existing `±2px` session/per-pause jitter; the context view is a transient pushed surface (not a fixed-pixel indefinite element) so it needs no separate jitter, but it must not paint persistent bright chrome at a fixed pixel — it's text on void, scrolled by the user. [Source: DESIGN.md:134; PlaybackView.mc:75-80,396-407]

### Monkey C conventions (verified in-repo)
- One public class per `PascalCase.mc`; modules `UPPER_SNAKE` consts; methods/vars `camelCase`; private fields `_camelCase`. New views go in `watch/source/views/`, the new delegate in `watch/source/input/`. [Source: architecture.md:245-258,371-382; observed]
- **Strict typing (level 3)** — every signature typed, `?` on nullables; cast at the seam, never lower strictness. `WatchUi.pushView` takes `(WatchUi.Views, WatchUi.InputDelegates or Null, WatchUi.SlideType)`; `popView(WatchUi.SlideType)`. `dc.getFontHeight(font)` and `dc.getTextWidthInPixels(text, font)` return `Number`. [Source: architecture.md:314; Toybox.WatchUi/Graphics.Dc docs; 3-3 Debug Log "enum seam"]
- Callbacks use `method(:symbol)` not closures. `System.println` is budgeted (~10KB) — lifecycle only, verbose input logs behind `(:debug)`; **never per-word/per-scroll**. Error posture: bounds-check-and-degrade, never crash (NFR8/AR24). [Source: architecture.md:289,323; PlaybackView.mc:101-108; 3-3 Dev Notes lines 124-125]

### Edge cases to handle (bounds-check-and-degrade)
- **No `FLAG_PARAGRAPH_START` in the stream** → `paragraphStartAtOrBefore`=0, `paragraphEndAtOrAfter`=`wordCount-1`: the whole book becomes one scrollable paragraph. Bounded and safe (no crash); document. The real baked stream sets paragraph flags (Story 2.1/2.2), so this is the degrade path, not the norm. [Source: epics.md#Story-2.1; Protocol.mc:48]
- **Current word is the paragraph's first word** (carries `FLAG_PARAGRAPH_START`) → it IS `pStart`; mark it, scroll to top. [Source: PausedLayout paragraph helpers]
- **`bookPercent` with `wordCount <= 1`** → 0 (empty) / 100 (single word); never divide by zero. [Source: Task 1]
- **`timeRemainingMs` at the WPM floor** (`WPM_MIN=10` → beat 6000ms) → large but finite; `formatRemaining` renders `H:MM:SS`. At the cap (`WPM_MAX=1000` → 60ms beat) → small. [Source: Settings.mc:36-38]
- **Open context on a FINISHED or non-paused frame** → `openContextView` guard returns early (no-op). `InputMap` only emits `ACTION_CONTEXT` when `isPaused`, but the guard is the belt-and-braces. [Source: Task 4]
- **Readout/scroll vs `System.getTimer()` wraparound** — not applicable: the paused readout uses no timer deadline (unlike the transient WPM readout's known wrap caveat, deferred-work.md), and scrolling is input-driven. [Source: deferred-work.md line 101]
- **Stackable rewind while the readout is up** — `rewindOne` already recomputes jitter + repaints; the readout re-reads `index()` so % / time-left / paragraph update on the next pause frame. [Source: PlaybackView.mc:155-159]

### Build / harness facts (carried from Stories 3.1–3.3)
- Manifest `minApiLevel` per repo, product `fenix847mm`; CI pins **SDK 8.4.0** (`matco/action-connectiq-tester`). On-host sim can't run (missing `libwebkit2gtk-4.0`) — run host tests via the container (`ghcr.io/matco/connectiq-tester`, **bare** `tester.sh fenix847mm`), the authoritative gate; **`rm -f watch/bin/app.prg` before every run** (stale-binary trap). The matco ENTRYPOINT swallows a trailing `-c '…'` and hangs — release build is the `--entrypoint bash … -c '<monkeyc … -l 3 -r>'` form with its own temp cert. [Source: 3-3 Debug Log lines 180-182; watch-tests-local-via-ci-docker-image memo; manifest.xml]
- Real-hardware sideload: USB Mode → MTP, `gio copy` the `.prg` (`091e:51b8`). View-stack push/pop, scroll feel, and readout legibility are exactly what host tests can't see — the on-device check (Task 6) is required. [Source: garmin-ciq-ubuntu-2404-appimage memo; 3-3 Debug Log line 140]
- No `manifest.xml` / permission change (context view + readout need none; `Communications` stays for the preserved GateV2 spike only). GateV2 spike stays compiled-but-not-entered. [Source: PaceTurnerApp.mc:80-91; 3-3 Task 5]

## Project Structure & Conventions

### File locations (canonical tree — architecture.md lines 349-395)
- `watch/source/views/PausedLayout.mc` — pure paused/context math + paragraph nav (NEW; imports `Toybox.Lang` only). Host-testable seam, mirrors `OrpLayout.mc`.
- `watch/source/views/PausedContextView.mc` — `class PausedContextView extends WatchUi.View`, the context-on-pause scroll view (NEW). Architecture names this exact file at line 374 ("context-on-pause scroll view (FR11)").
- `watch/source/input/PausedContextDelegate.mc` — `class PausedContextDelegate extends WatchUi.InputDelegate` for the pushed context view: BACK→pop, UP/DOWN + swipe→scroll (NEW).
- `watch/source-test/PausedLayoutTest.mc` — host tests for the pure module (NEW).
- `watch/source/views/PlaybackView.mc` — add `drawPausedReadout` + `openContextView` + `onShow` IDLE-guard (MODIFY).
- `watch/source/input/InputMap.mc` — `actionForSwipe` gains `isPaused`, returns `ACTION_CONTEXT` for swipe-up-while-paused (MODIFY).
- `watch/source/input/PlaybackDelegate.mc` — wire `ACTION_CONTEXT` (key + swipe) → `_view.openContextView()` (MODIFY).
- `watch/source-test/InputMapTest.mc` — update for the new `actionForSwipe` arity + swipe-up-context cases (MODIFY).
- Reused unchanged: `engine/{ReaderEngine,BookWordSource}.mc`, `Settings.mc`, `source_data/{StreamDecoder,CannedWordSource,StorageKeys}.mc`, `Protocol.mc`, `views/OrpLayout.mc`, `PaceTurnerApp.mc` (getInitialView already returns `[view, delegate]`).

### Project Structure Notes
- Architecture (line 382) names a separate **`PausedDelegate.mc`** ("START=resume(ramp), UP=rewind, DOWN=context view") for the *paused playback screen*. **Decision (carried from 3.3, confirmed for 3.4):** that routing is already provided by the single **state-aware `PlaybackDelegate`** — `InputMap.actionForKey(key, isPaused)` returns `ACTION_REWIND`/`ACTION_CONTEXT`/`ACTION_PAUSE_RESUME` by paused state, and the delegate dispatches them. Splitting a `PausedDelegate` for the same screen would duplicate the dispatch with no behavioral gain. The genuinely-separate surface — the **pushed context scroll view** — gets its own `PausedContextDelegate` (it needs pop/scroll semantics the playback delegate doesn't). **Flag for a reviewer** if they prefer the literal `PausedDelegate.mc` split landed now; the paused mappings are already isolated in `InputMap`, so it stays cheap. [Source: architecture.md:380-382; 3-3 Project Structure Notes line 155]
- `CannedWordSource` remains the Epic-3 dev stand-in (228 records, paragraph + chapter flags baked); 3.4 adds no new source and no `manifest.xml` change.

### References
- [Source: _bmad-output/planning-artifacts/epics.md#Story-3.4] — story statement + 4 ACs (FR11); cut-line note (FR11 is a demote-able item)
- [Source: _bmad-output/planning-artifacts/architecture.md (lines 46, 106, 193, 287, 293, 314, 349-395 esp. 374 `PausedContextView.mc` / 382 `PausedDelegate.mc`, 362 ChunkedWordSource, AR15/AR24/AR25)] — context-on-pause owned by parsing-pipeline flags, no-cycle GC, manifest cumulative durations, file tree, error/logging posture
- [Source: _bmad-output/planning-artifacts/ux-designs/ux-garmin_RSVP-2026-06-06/EXPERIENCE.md (lines 40-41, 83, 131-138, 194-202)] — Paused/Context surfaces, progress-readout content "from cumulative-duration array", paused input map (DOWN/swipe-up=context, BACK from context returns to Paused), Flow 2 "Glance away and recover"
- [Source: _bmad-output/planning-artifacts/ux-designs/ux-garmin_RSVP-2026-06-06/DESIGN.md (lines 21, 42-46, 74-76, 108-113, 120-122, 131-134, 140, 144, 152-154)] — ink-dim role, context-body/watch-meta typography, progress-readout component "appears only when paused", card-regime/safe-square, brightness hierarchy / one-red, scroll-boundary
- [Source: watch/source/views/PlaybackView.mc:27-243, 299-394] — view owns engine/source/timer/jitter; onShow auto-play; paused still-frame; readout/draw patterns to extend
- [Source: watch/source/input/InputMap.mc:25-69 + PlaybackDelegate.mc:24-92] — ACTION_CONTEXT reserved, actionForSwipe, InputDelegate (no onSelect), consume/pass-through semantics
- [Source: watch/source/engine/ReaderEngine.mc:17-23, 79-96, 205-225, 284-309] — STATE_IDLE/play/index/wpm/isPaused/currentRecord + sentence/paragraph-nav shape
- [Source: watch/source/Protocol.mc:29-34, 48] — manifest cumulative-duration keys (tb/cb), FLAG_PARAGRAPH_START=0x02
- [Source: watch/source/source_data/CannedWordSource.mc + watch/source-test/FakeWordSource.mc] — running Epic-3 source (228 records) + test double for PausedLayout tests
- [Source: watch/source-test/{OrpLayoutTest,ReaderEngineTest,InputMapTest,SmokeTest}.mc] — (:test) host pattern, no Test.assert*, fixture shape, CI-image run + stale-binary trap
- [Source: _bmad-output/implementation-artifacts/3-3-playback-controls-input-mapping.md] — InputDelegate/no-onSelect/BACK-exit, AR15 no-cycle, build/harness facts, on-device check format, "test count must rise", PausedDelegate-split decision
- [Source: _bmad-output/implementation-artifacts/deferred-work.md (lines 100-102)] — FINISHED-rewind / readout-wraparound / rewind double-jitter forward notes (not 3.4's scope but adjacent)

## Dev Agent Record

### Agent Model Used

Amelia (dev-story) — claude-opus-4-8[1m]. dev-story workflow, red-green discipline:
pure `PausedLayout` + tests first (host-tested before the view code that consumes it).

### Debug Log References

- **Host test gate (authoritative):** `rm -f watch/bin/app.prg` then
  `docker run --rm -v $PWD/watch:/work -w /work ghcr.io/matco/connectiq-tester:latest fenix847mm`
  (bare positional device form — NOT a trailing `-c`, which the matco ENTRYPOINT
  swallows and hangs; carried from 3.3 Debug Log). `Ran 63 tests … PASSED
  (passed=63, failed=0, errors=0)`. **Count rose 55 → 63 (+8: 7 PausedLayout + 1
  InputMap swipe-context), not flat.**
- **Release gate:** in-container `--entrypoint bash … -c '<openssl temp cert + monkeyc
  -f monkey.jungle -d fenix847mm -y <temp.der> -o bin/release.prg -l 3 -w -r>'` (Strict
  L3, warnings-on) → `BUILD SUCCESSFUL`, exit 0, 38,492-byte `release.prg`. Strictness
  never lowered.
- **L3 warning caught + fixed:** first release build warned `_currentLine is not used`
  in `PausedContextView` (assigned in build() but only the local `currentLine` was read
  to seed the initial scroll). Removed the dead field — re-built warning-clean.
- **CustomMenu redesign gate (2026-06-24):** after the on-device discrete-scroll feedback,
  re-ran both gates on the redesigned tree. Release `monkeyc -l 3 -r` → `BUILD SUCCESSFUL`,
  38,284-byte `release.prg`, warning-clean. Host tests `Ran 63 tests … PASSED` (PausedLayout
  unaffected, still 63). L3 fix needed: `createBufferedBitmap(...).get()` returns a broad
  resource union, narrowed with `if (buf instanceof Graphics.BufferedBitmap)` before `getDc()`.
- **Toolchain incident (recorded so it isn't re-debugged):** mid-session the Docker context
  flipped from `desktop-linux` (Docker Desktop) to `default` (`/var/run/docker.sock`). The two
  daemons hold DIFFERENT cached `ghcr.io/matco/connectiq-tester:latest` builds — `default` had
  a 5-month image (`07145d472aae`), `desktop-linux` the 13-day image (`12a6ed1a80e2`). Both report
  compiler 8.4.0, but the old image's per-device API DB **spuriously rejects `Settings.mc:115`
  (`toDict() as Storage.ValueType`)** — confirmed by stashing all changes and building the pristine
  committed tree (same failure), so NOT introduced here. The project's Strict-L3 gate is the
  `desktop-linux` image; `docker context use desktop-linux` restores it. After switching daemons,
  `watch/bin/*` had root-owned stale `.mir` cache → `Permission denied`; clean it in-container
  (`docker run --entrypoint bash … -c 'rm -rf /work/bin/*'`) before rebuilding.

### Completion Notes List

Story 3.4 — paused progress readout + context-on-pause scroll view. **Code complete;
both builds clean; 63/63 host tests. On-device check (Task 6, Fenix 8 sideload) is the
one remaining gate — PENDING human (view-stack push/pop, scroll feel, and readout
legibility are exactly what host tests cannot exercise; mirrors 3.2/3.3).**

- **AC1 — paused readout:** new pure `views/PausedLayout.mc` (`bookPercent`,
  `timeRemainingMs`, `sumBonusMs`, `formatRemaining`, `paragraphStartAtOrBefore`,
  `paragraphEndAtOrAfter` — imports only `Toybox.Lang`, host-tested). `PlaybackView.
  drawPausedReadout` draws book %, time-left, and WPM in `COLOR_INK_DIM` (`FONT_SYSTEM_TINY`
  ≈ watch-meta), lower third, jittered, **gated on `_engine.isPaused()`** so ramp/playing/
  FINISHED/IDLE draw nothing (UX-DR8). `wordsRemaining = wordCount − index` (current word
  through end, inclusive); bonus summed ONCE per pause (Story 4.1 swaps for the manifest's
  O(1) cumulative). "Fades in" → MVP renders immediately (no alpha in Garmin `drawText`,
  paused runs no timer); documented at the draw site.
- **AC2 — context view:** new `views/PausedContextView.mc` (snapshot of source + current
  index, no engine/PlaybackView back-ref → no GC cycle, AR15). Paragraph `[pStart..pEnd]`
  wrapped to lines ONCE via `dc.getTextWidthInPixels` and cached (no watchdog risk);
  `onUpdate` blits only visible lines. Left-aligned in the centered watch-safe-square
  (70% side, corners empty). Current word marked by **brightness** (`COLOR_INK` against the
  `COLOR_INK_DIM` body) — never a second accent (DESIGN "one red, one job"). Opens scrolled
  to center the current word's line. New `input/PausedContextDelegate.mc` (UP/DOWN + swipe
  up/down scroll). `InputMap.actionForSwipe` gained an `isPaused` arg → `ACTION_CONTEXT` on
  swipe-up-while-paused-touch-on; `PlaybackDelegate` wires `ACTION_CONTEXT` (key DOWN-paused
  + swipe-up) → `PlaybackView.openContextView()` (guarded on isPaused/currentRecord).
- **AC3 — BACK pops, not exit:** `PausedContextDelegate.onKey` consumes `KEY_ESC` →
  `WatchUi.popView(SLIDE_DOWN); return true`. Crucially, **Task 5 fixed `PlaybackView.onShow`**
  to auto-play ONLY from `STATE_IDLE` (was unconditional `play()`); a pop-back now reveals
  PlaybackView and stays PAUSED instead of resuming. First-launch demo auto-play (IDLE→play)
  is preserved; live-on-show re-arms the loop. Pre-aligns with Story 3.6.
- **AC4 — START resumes with ramp:** unchanged — already provided by 3.3's
  `pauseOrResume()` → `engine.play()`; the readout self-clears because it is gated on
  `isPaused`. Not duplicated.
- **Scope honored:** no Storage writes (force-save = 3.6), no `manifest.xml`/permission
  change, no Finished/settings shells (3.5/3.8). GateV2 spike preserved.

**ON-DEVICE PASS (Fenix 8 sideload, Nerya 2026-06-24):** all 6 checks green on the
CustomMenu-redesign build (`PaceTurner.PRG`, 38,284 B). (1) Paused readout shows plausible
%/time-left/WPM and clears on resume; (2) DOWN **and** swipe-up open the context view scrolled
to the brighter current word; (3) scroll is now **native fluid/kinetic** on swipe AND UP/DOWN
(the discrete-step feedback from the first build drove the View→CustomMenu redesign — see
"Context-view redesign" above); (4) **BACK returns to Paused, does NOT exit**; (5) START resumes
with the 3-2-1 ramp and the readout clears; (6) touch-off → DOWN/BACK still work by buttons.
**Note (no action):** the native menu scroll **haptic** rides along with CustomMenu — it is a
firmware-level haptic on all native scrolling lists, with NO Connect IQ per-view/per-app suppress
API; the only control is the device-global haptic setting. Confirmed working-as-intended, kept
as-is (the haptic is the flip side of the native fluid scroll; removing it means reverting to the
rejected discrete custom-view scroll). [forums.garmin.com Fenix scrolling-haptics threads]

### File List

**New:**
- `watch/source/views/PausedLayout.mc`
- `watch/source/views/PausedContextView.mc` (a `WatchUi.CustomMenu` — native fluid scroll; see redesign note)
- `watch/source/views/PausedContextLine.mc` (a `WatchUi.CustomMenuItem` — one wrapped line; added in redesign)
- `watch/source/input/PausedContextDelegate.mc` (a `WatchUi.Menu2InputDelegate` — BACK pops; scroll is the widget's)
- `watch/source-test/PausedLayoutTest.mc`

**Modified:**
- `watch/source/views/PlaybackView.mc` (drawPausedReadout + openContextView + onShow IDLE-guard + scope comment)
- `watch/source/input/InputMap.mc` (actionForSwipe gains isPaused → ACTION_CONTEXT on swipe-up-paused)
- `watch/source/input/PlaybackDelegate.mc` (wire ACTION_CONTEXT in onKey + onSwipe)
- `watch/source-test/InputMapTest.mc` (4-arg actionForSwipe + new inputSwipeContextMap)

### Context-view redesign — raw View → CustomMenu (on-device feedback, 2026-06-24)

**Driver:** the first on-device build's context view scrolled in **discrete one-line steps**, not the fluid kinetic scrub of the native watch lists. (A second observation — "sometimes I can scroll past the paused word, sometimes only up to it" — is correct/as-designed: the view shows exactly the surrounding paragraph, so how much sits ahead of the paused word is just paragraph geometry.)

**Research (community, before committing):** the native momentum scroll is a property of Garmin's `CustomMenu`/`Menu2` widgets — devs confirm replicating it by hand is "significant effort." The usual objection to `CustomMenu` (`Menu2InputDelegate` can't report tap coordinates within an item) doesn't apply to a read-only reading view. `CustomMenu` also scrolls natively by **both** swipe and UP/DOWN buttons (FR12/AC5). Measuring text to wrap before items exist uses the standard offscreen-`BufferedBitmap` Dc workaround. [forums.garmin.com Menu2/CustomMenu threads; BufferedBitmap minimal example]

**Change:** `PausedContextView` is now a `WatchUi.CustomMenu` (one `PausedContextLine` `CustomMenuItem` per wrapped line); `PausedContextDelegate` is now a `WatchUi.Menu2InputDelegate` (`onBack`→`popView` for AC3; scroll handled natively). Menu chrome suppressed (`:theme => null`, `:dividerType => null`, void background) to keep "text on void." Wrapping measures via `Graphics.createBufferedBitmap({...}).get().getDc()` once at construction (narrowed with `instanceof Graphics.BufferedBitmap` for L3), degrading to one-word-per-line if no buffer. `PausedLayout` paragraph math + brightness-marking of the current word are unchanged. **Replaces** the prior hand-painted scroll (`scrollUp/scrollDown/onUpdate`) — no hand-rolled scroll remains.

### Change Log

- 2026-06-24 — Story 3.4 dev-story: paused progress readout (PausedLayout pure math +
  PlaybackView.drawPausedReadout, Ink-Dim paused-only) + context-on-pause scroll view
  (PausedContextView + PausedContextDelegate, brightness-marked current word) +
  paused-aware actionForSwipe/ACTION_CONTEXT wiring + onShow IDLE-guard (pop-back stays
  PAUSED). 63/63 host tests @ Strict L3 (rose 55→63), release build clean (38,492 B). On-device
  check pending human.
- 2026-06-24 — Context-view redesign after on-device feedback (discrete scroll): reimplemented
  PausedContextView as a WatchUi.CustomMenu (+ new PausedContextLine CustomMenuItem) for native
  fluid kinetic scroll, PausedContextDelegate → Menu2InputDelegate (BACK pops, AC3). Community-
  validated approach. PausedLayout/readout/wiring unchanged. 63/63 host tests @ Strict L3, release
  build clean (38,284 B, warning-free). Re-sideloaded; on-device re-check of the context view pending.

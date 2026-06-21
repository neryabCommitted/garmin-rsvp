---
baseline_commit: 30b7fda8533f248a718057058ced71ed3e2e587a
---
# Story 3.1: ReaderEngine & settings model — drift-free advance, timing, WPM, rewind (pure logic)

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer,
I want the reading engine and a defaulted settings model as pure, host-testable logic over a fake word source,
so that pacing, position, rewind, and configurable behavior are correct and available before any pixels or menus exist (FR2, FR3, FR13).

## Acceptance Criteria

**AC1 — Settings model with pure, Storage-independent defaults**
**Given** the `Settings` model
**When** instantiated
**Then** it exposes per-device defaults (WPM 250, pause mode coast, touch on, font size 0, handedness right, focus highlight on, phantom words on, anchor 35%) with **pure default values testable without Storage** (the `"settings"` Storage key is a thin persistence adapter) — establishing the configuration source that Stories 3.2/3.3 read and Story 3.8 later edits via a menu.

**AC2 — Drift-free advance with baked timing and catch-up cap**
**Given** a `FakeWordSource` and a clock
**When** the engine plays
**Then** it advances via `lastAdvance += duration` (drift-free), applying `60000/wpm + bonus` per word, with catch-up capped (~4 words).

**AC3 — WPM change takes effect next word, no re-fetch, no drift**
**Given** playback
**When** WPM changes
**Then** it takes effect on the next word with no content re-fetch and no drift.

**AC4 — Start ramp**
**Given** a play/resume
**When** it starts
**Then** a 3-beat start ramp precedes the stream.

**AC5 — Two-stage pause (coast / instant)**
**Given** a pause request
**When** issued in coast mode
**Then** the engine advances to the next `sentenceEnd` then stops; in instant mode it stops immediately.

**AC6 — Stackable sentence rewind with auto-pause**
**Given** a rewind request
**When** issued
**Then** the index moves to a previous sentence boundary and the engine auto-pauses; rewind is stackable.

**AC7 — Host-testable: no UI/Comms imports**
**Given** the engine
**When** tests run
**Then** it imports no `Toybox.WatchUi`/`Toybox.Communications` and passes host-side under the CI test harness (`matco/action-connectiq-tester`, SDK 8.4.0).

## Tasks / Subtasks

- [x] **Task 1 — `Settings` model with pure defaults (AC1)**
  - [x] Create `watch/source/Settings.mc` — `class Settings` (PascalCase file, one public class).
  - [x] Expose the eight per-device defaults as pure values returnable with **zero Storage calls**: `wpm=250`, `pauseMode=coast`, `touchControls=true`, `fontSize=0`, `handedness=right`, `focusHighlight=true`, `phantomWords=true`, `anchorPct=35`. Use module constants (`UPPER_SNAKE`) for the default literals.
  - [x] Model `pauseMode` and `handedness` as small enum-style `Number` constants (e.g. `PAUSE_COAST=0`, `PAUSE_INSTANT=1`; `HAND_RIGHT=0`, `HAND_LEFT=1`) — typed, no magic numbers at call sites.
  - [x] Provide a constructor that yields defaults with no Storage access, plus a separate `loadFrom(...)`/`save()` seam that routes through `StorageKeys` for the `"settings"` key. **Do NOT call Storage in the default path** — the AC requires defaults testable without Storage.
  - [x] Do NOT build the settings *menu* (Story 3.8) or the *touch/handedness input wiring* (Story 3.3) — only the model + defaults.
- [x] **Task 2 — `BookWordSource` seam + `FakeWordSource` test double (AC2, AC7)**
  - [x] Create `watch/source/engine/BookWordSource.mc` — the 3-method seam: `wordCount() as Number`, `wordAt(index as Number) as StreamDecoder.WordRecord?`, `prefetchAround(index as Number) as Void`. (Interface/abstract-base or documented duck-typed contract per Monkey C idiom.)
  - [x] Create `watch/source-test/FakeWordSource.mc` — a hand-written test double implementing `BookWordSource`, returning `StreamDecoder.WordRecord`-shaped data (reuse the existing `StreamDecoder.WordRecord` class — do NOT define a new word struct). Include words with `FLAG_SENTENCE_END` set at known indices, a multi-sentence body, and `bonusMs` values, so pacing/pause/rewind are exercisable.
  - [x] `FakeWordSource` must support `atEnd()` semantics meaning **last word of the book** (see Dev Notes — `atEnd()` contract).
- [x] **Task 3 — `ReaderEngine` drift-free advance + timing (AC2, AC3, AC7)**
  - [x] Create `watch/source/engine/ReaderEngine.mc` — `class ReaderEngine`, imports **only** `Toybox.Lang` (+ `Toybox.System` for the clock if needed). NO `Toybox.WatchUi`, NO `Toybox.Communications`.
  - [x] Implement per-word duration: `displayMs = 60000 / wpm + record.bonusMs` (integer ms; `Number` is signed 32-bit). `bonusMs` comes straight from the `WordRecord` — the engine never recomputes linguistics.
  - [x] Implement drift-free scheduling: maintain `lastAdvance`; on each tick advance with `lastAdvance += duration` (never `lastAdvance = now`). Cap catch-up at ~4 words (absorb scheduling jitter without accumulating drift).
  - [x] Inject the clock (pass a "now" value / clock seam into the advance method) so host tests drive time deterministically — do NOT read `System.getTimer()` internally in a way tests can't control. Guard against `System.getTimer()` wraparound (negative-elapsed arithmetic) at the seam.
  - [x] WPM is read live: a `setWpm(...)` mutator changes the field; the next computed `duration` uses it. No content re-fetch, no drift (AC3).
- [x] **Task 4 — Start ramp (AC4)**
  - [x] On play/resume, emit a 3-beat (3-2-1) lead-in at current WPM before the first real word advances. Model it as engine state (e.g. a ramp counter) so the view layer (Story 3.2) can render it; 3.1 owns the *count and timing*, not the pixels.
- [x] **Task 5 — Two-stage pause: coast vs instant (AC5)**
  - [x] `requestPause()`: in coast mode (default), continue advancing until a word with `FLAG_SENTENCE_END` (OR `atEnd()`), then stop; in instant mode, stop immediately.
  - [x] Pause finalization check must be `endsSentence(word) || atEnd()` (see `atEnd()` contract in Dev Notes).
- [x] **Task 6 — Stackable sentence rewind with auto-pause (AC6)**
  - [x] `rewind()`: move the index to the previous sentence boundary (clamp-at-start, never below 0), then auto-pause. Repeated calls step back additional sentences (stackable).
  - [x] Implement `sentenceStartAtOrBefore(index)` clamp logic mirroring RSVP Nano (see Dev Notes).
- [x] **Task 7 — Position & transition surface for SyncManager (design-only, AC supporting)**
  - [x] Expose the current **0-based absolute word index** and clean transition events (pause / rewind / chunk-boundary / finished) so Story 3.6's `SyncManager.commitPosition(force)` can hook them WITHOUT engine rework. Do NOT implement `SyncManager` or write to Storage here.
- [x] **Task 8 — Host-side tests (AC2–AC7) — RED → GREEN → REFACTOR**
  - [x] Create `watch/source-test/ReaderEngineTest.mc` with `(:test) function …(logger as Test.Logger) as Boolean` functions (mirror `SmokeTest.mc` / `ProtocolTest.mc`). Assert literal expected values; `logger.error("…"); return false` on mismatch.
  - [x] Tests cover: defaults (Settings, no Storage); `60000/wpm+bonus` math; drift-free `+= duration`; ~4-word catch-up cap; WPM change applies next-word; 3-beat ramp; coast stops at next `sentenceEnd`; instant stops immediately; rewind to previous boundary + auto-pause + stackable + clamp-at-start; `atEnd()` finalizes pause at book end.
  - [x] Verify compile at **Strict (level 3)** and that the `(:test)` suite is green in the CI image. Lowering the strictness level is a defect, not a fix.

## Dev Notes

### What this story owns (scope boundary)
Pure host-testable logic only. **Three new source files** (`Settings.mc`, `engine/BookWordSource.mc`, `engine/ReaderEngine.mc`) + **two test files** (`source-test/ReaderEngineTest.mc`, `source-test/FakeWordSource.mc`). No views, no delegates, no menus, no Storage writes, no Communications. The pure-logic surface: WPM model, `60000/wpm + bonus` integer-ms timing, drift-free `lastAdvance += duration` with ~4-word catch-up cap, 3-beat start ramp, coast/instant pause keyed on `FLAG_SENTENCE_END`, stackable auto-pausing sentence rewind, absolute-index position, and the Settings model with eight defaults. [Source: epics.md#Story-3.1 lines 534–568; architecture.md#Enforcement-Guidelines]

### REUSE — do not reinvent
- **`StreamDecoder.WordRecord`** already exists at `watch/source/source_data/StreamDecoder.mc:13–25` — the word struct is `{ word: String, flags: Number, orpPivot: Number, bonusMs: Number }`. The engine and `FakeWordSource` **consume this exact class**; do NOT define a new word record. [Source: watch/source/source_data/StreamDecoder.mc:13–25]
- **`Protocol.FLAG_*` constants** already exist at `watch/source/Protocol.mc:47–52`: `FLAG_SENTENCE_END = 0x01`, `FLAG_PARAGRAPH_START = 0x02`, `FLAG_CHAPTER_START = 0x04`, `FLAG_CONTINUATION = 0x08` (reserved, MUST be 0 in v1), `FLAG_RTL = 0x10` (reserved). **Reference `Protocol.FLAG_SENTENCE_END`, never inline `0x01`.** sentence-end is detected via `record.flags & Protocol.FLAG_SENTENCE_END`. [Source: watch/source/Protocol.mc:47–52]
- **`StreamDecoder.decodeChunk(payload, n) as Array<WordRecord>?`** exists and demonstrates the exact pure-logic discipline (imports only `Toybox.Lang` + `Toybox.StringUtil`, returns null on malformed, never throws). Mirror this style. [Source: watch/source/source_data/StreamDecoder.mc:1–9, 30]

### CRITICAL — `atEnd()` means "last word of the book," not "end of buffer" (carry-forward from Story 2.1 review)
The reader's two-stage pause (AC5) and sentence rewind (AC6) must apply `endsSentence(word) || atEnd()` and clamp-at-start, where `atEnd()` means **the last word of the entire book**, not "last word currently in heap." The phone bakes a terminal `sentenceEnd=true` on the last word, but under chunked delivery (Epic 4) "end of buffered window ≠ end of book." Mirror RSVP Nano's `shouldFinalizeReaderPause()` (`App.cpp:1883–1894`) and `sentenceStartAtOrBefore()` clamp (`ReadingLoop.cpp:867–885`). Design `FakeWordSource.atEnd()` / `wordCount()` so the engine asks the source for the true book length, not the buffer length. [Source: deferred-work.md#L49; epic-2-retro-2026-06-21.md#L71,L82]

### `BookWordSource` seam (Nano pattern)
The engine sits on top of a 3-method content seam: `wordCount`, `wordAt(index)`, `prefetchAround(index)`. `FakeWordSource` (this story) and `ChunkedWordSource` (Epic 4 / Story 4.1) both implement it. The engine asks for words by **absolute index** and never owns transfer/buffering. [Source: architecture.md#AR11 line 102, line 358; addendum#5]

### Timing model (authority: SPEC §5.1)
- `displayMs(word) = 60000 / wpm + record.bonusMs`. `bonusMs` is a **WPM-invariant additive** value baked phone-side; the watch applies it as-is and computes NO linguistics. Changing WPM never re-bakes/re-fetches content. [Source: architecture.md#SPEC-§5.1; addendum#2; PRD#FR2,FR3]
- All durations and indices are **integer milliseconds / integer word indices** — `Number` is signed 32-bit. Never float seconds. [Source: architecture.md line 276; SPEC §1.2]
- Drift-free invariant: `lastAdvance += duration` (NOT `= now`); catch-up capped at **~4 words**. The 50 ms platform timer floor (≈1200 WPM ceiling) is a *view-layer* concern (Story 3.2 arms the timer) — 3.1 only produces correct durations and the drift-free accumulator. [Source: architecture.md#AR13 line 104; PRD#NFR1]
- WPM: default **250**, range **10–1000**, adaptive step **10 below 100 WPM / 25 at-or-above** (the adaptive *stepping* is consumed in Story 3.3's input mapping; 3.1 owns the WPM field + `60000/wpm` math + next-word application). The epics.md FR3 still shows a stale `[ASSUMPTION] 100–900 / default 300` — **the resolved UX/addendum values (250, 10–1000, 10/25 step) and the Story 3.1 AC govern.** [Source: PRD#FR3; EXPERIENCE.md#RSVP-Presentation; addendum#2; implementation-readiness-report#L194]

### Start ramp (AC4)
3-beat (3-2-1) word-cadence lead-in at current WPM before the stream begins, on every play/resume. This is the explicit anti-pattern fix for RSVPnano's cold start. The "3 beats at current WPM" is the spec; what each beat *displays* is a Story 3.2 (view) concern — 3.1 owns the count and timing as engine state. [Source: EXPERIENCE.md#Component-Patterns; addendum#5; UX-DR10]

### Pause semantics (AC5)
- **Coast (default):** on pause, advance to the next word with `FLAG_SENTENCE_END` (OR `atEnd()`), then freeze. Preserves comprehension. [Source: PRD#FR8; EXPERIENCE.md#Interaction-Primitives]
- **Instant:** stop immediately. Available as a settings option (`pauseMode`). [Source: PRD#FR8; DESIGN.md#decision-log-r1]

### Rewind (AC6)
Move index to the previous sentence boundary, **auto-pause**, persist position (the persist hook is Story 3.6 — 3.1 just emits the transition). **Stackable** — repeated calls step back additional sentences. Clamp at start (never below word 0). [Source: PRD#FR10; EXPERIENCE.md#Interaction-Primitives]

### Position is the sacred coordinate
Position = **0-based absolute word index** per book — the single universal coordinate for resume/rewind/progress/sync (FR13). Every index change is a position change. 3.1 does NOT implement `SyncManager` (Story 3.6 / Epic 4) but MUST expose index + transition events cleanly so `SyncManager.commitPosition(force)` hooks in later without engine rework. No code writes position to Storage in this story. [Source: PRD#FR13; architecture.md#AR14 line 105]

### Settings locality — per-device, never synced
Watch settings live behind the `Settings` model over the `"settings"` Storage key (accessed via `StorageKeys`); they **never cross the protocol — per-device, never synced.** Only *position* syncs. Defaults must be returnable with **zero Storage access** (the AC's explicit requirement); the `"settings"` key is a thin adapter layered on top. [Source: architecture.md#AR16 line 107, line 303; PRD#FR15,NFR4]

## Project Structure & Conventions

### File locations (canonical tree — architecture.md#Complete-Project-Directory-Structure lines 349–395)
- `watch/source/Settings.mc` — settings model (NEW)
- `watch/source/engine/ReaderEngine.mc` — pure engine (NEW; create the `engine/` dir — does not exist yet)
- `watch/source/engine/BookWordSource.mc` — 3-method seam (NEW)
- `watch/source-test/ReaderEngineTest.mc` — host tests (NEW)
- `watch/source-test/FakeWordSource.mc` — test double (NEW)
- `watch/source/source_data/StorageKeys.mc` — referenced for the `"settings"` key; if it does not yet exist, introduce a minimal version owning only the `"settings"` key here (full key set is Story 3.6/Epic 4). Confirm before expanding scope.
- Reused (do not modify behavior): `watch/source/source_data/StreamDecoder.mc`, `watch/source/Protocol.mc`

### Monkey C conventions (verified in-repo)
- Classes PascalCase, one public class per `PascalCase.mc` file. Methods/vars `camelCase`; private fields `_camelCase`. Module-level constants `UPPER_SNAKE`. [Source: architecture.md#Naming-Patterns lines 245–258; observed in Protocol.mc / StreamDecoder.mc]
- **Strict typing (level 3) from commit 1** — every signature typed (`as Number`, `as Boolean`, `as Array<WordRecord>`, nullable `?`). A build that needs the level lowered is a defect. [Source: architecture.md#Enforcement-Guidelines item 5, lines 73, 144, 314]
- Callbacks use `method(:symbol)` (see `PaceTurnerApp.mc`), not closures.
- Reference-counting GC, **no cycle collection** → use `WeakReference` for any back-pointer; the engine must never hold a strong ref to a view (it must not reference views at all). [Source: architecture.md#AR15 line 106, line 287]
- `System.println` is budgeted (~10 KB on-device log) — log state transitions/errors only, **never per-word** (a per-word println at 700 WPM is a named anti-pattern). Verbose logs behind `(:debug)`. [Source: architecture.md#AR25 line 122, line 323]
- Error posture (NFR8 / AR24): bounds-check-and-degrade, never crash mid-read; no silent `catch {}`. Bounds-check word indices and `wordAt` returns. [Source: architecture.md#AR24 line 121; PRD#NFR8]
- NFR2: peak heap ≤600 KB of 768 KB — keep engine render state small (decoded window + render state only). [Source: PRD#NFR2; architecture.md#AR12 line 179]

### Test pattern (copy verbatim from `watch/source-test/SmokeTest.mc`)
```monkey-c
import Toybox.Lang;
import Toybox.Test;

(:test)
function someEngineTest(logger as Test.Logger) as Boolean {
    // arrange / act
    if (expected != actual) { logger.error("describe the failure"); return false; }
    return true;
}
```
No `Test.assert*` API is used in this codebase — assert via explicit conditionals + `logger.error(...)` + `return false`. Test files live in `watch/source-test/`; `monkey.jungle` includes `source;source-test`; `(:test)` code is stripped from release builds. Run host-side via the CI image. [Source: watch/source-test/SmokeTest.mc; watch/source-test/ProtocolTest.mc:70–119; watch/monkey.jungle]

### Build / harness facts
- Manifest `minApiLevel = 5.2.0` — keep it; the engine has no API-6.0 floor. CI image pins **SDK 8.4.0** (`matco/action-connectiq-tester`, "Run No Evil"). Target product `fenix847mm`. [Source: watch/manifest.xml; architecture.md#ADR-0001; epic-1-retro-2026-06-13.md#L16,L34]
- **The host harness provably cannot catch the firmware watchdog class** — that is a Story 4.1 hardware concern, NOT a 3.1 issue (3.1 does no BLE decode). Green CI here is evidence about pure timing/advance logic only. [Source: deferred-work.md#L53; epic-1-retro-2026-06-13.md#L39]

## Previous Story Intelligence

This is the first story of Epic 3; no prior Epic-3 story exists. Cross-epic carry-forward (verified by analysis of the Epic 2 retro, deferred-work, and readiness report):
- **Pre-3.1 cleanup is DONE — 0 blockers.** Theme seed (`#FF5349`), the Epic-3 dev word-stream fixture (228 words / 3 chapters / fp `4bd588b9`), and the `atEnd()` reader-contract note were all cleared before 3.1. [Source: deferred-work.md#L3–11; epic-2-retro-2026-06-21.md#L103,L119]
- **Settings model was folded into Story 3.1** (resolving the original Epic-3 forward dependency where Settings was Story 3.8). 3.1 now *owns* the pure Storage-independent Settings model + defaults; Story 3.3 reads from it; Story 3.8 is reframed as the menu UI. The plan has zero forward dependencies. [Source: implementation-readiness-report-2026-06-09.md#L194,L217]
- **Watch-spike robustness bundle** (8 items in `PaceTurnerApp.mc`, e.g. ignored `session.start()` Boolean, unguarded `Storage.setValue`, `getTimer()` wraparound) is a caution **NOT to copy spike code into the session/display modules (Stories 3.7/3.9)** — only the `getTimer()` wraparound guard is relevant to 3.1's clock seam. [Source: deferred-work.md#L36; epic-1-retro-2026-06-13.md#L62]

### Dev fixture note
The committed dev word-stream fixture is phone-side Dart (`companion/test/fixtures/streams/dev_sample_book.{stream,manifest.json,jsonl,dart}`, fp `4bd588b9`, 228 words, 3 chapters, including accented words and a long word `counterrevolutionaries`). It is primarily for Story 3.2 rendering and the eventual real `ChunkedWordSource`. For **this** pure-logic story, write a small hand-authored `FakeWordSource` in Monkey C that returns `StreamDecoder.WordRecord`-shaped data with known sentence-end flags — deterministic and minimal beats decoding a binary blob in a host test. [Source: deferred-work.md#L10; companion/test/fixtures/streams/README.md]

## Latest Technical Information

Toolchain is version-pinned and the canonical patterns already exist in-repo (`StreamDecoder.mc`, `ProtocolTest.mc`, `SmokeTest.mc`), which are authoritative for this story — no external library version research is warranted. Connect IQ SDK is pinned at **8.4.0** in CI; manifest floor **5.2.0**. Use only `Toybox.Lang`, `Toybox.Test` (tests), and — if a clock is read at all — `Toybox.System` behind an injectable seam. Avoid introducing any other Toybox module in the pure engine. If the dev encounters a Monkey C / Toybox API uncertainty during implementation, prefer the in-repo working examples over recollection.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story-3.1 (lines 534–568)] — story statement + 7 ACs
- [Source: _bmad-output/planning-artifacts/architecture.md#Complete-Project-Directory-Structure (lines 349–395)] — file paths
- [Source: _bmad-output/planning-artifacts/architecture.md#AR13 (line 104), #AR11 (line 102), #AR14 (line 105), #AR16 (line 107), #SPEC-§5.1 (lines 266–277)] — advance algorithm, word-source seam, persistence discipline, settings locality, timing model
- [Source: _bmad-output/planning-artifacts/architecture.md#Enforcement-Guidelines (lines 309–316)] — strict typing, no-UI-imports, constant references
- [Source: watch/source/source_data/StreamDecoder.mc:1–30] — `WordRecord` struct + pure-logic discipline to mirror
- [Source: watch/source/Protocol.mc:47–67] — `FLAG_*` and `ERR_*` constants
- [Source: watch/source-test/SmokeTest.mc, watch/source-test/ProtocolTest.mc:70–119] — host test pattern
- [Source: watch/monkey.jungle, watch/manifest.xml] — build config, min API, target product
- [Source: _bmad-output/implementation-artifacts/deferred-work.md#L10,L36,L49,L53] — dev fixture, spike-robustness caution, `atEnd()` contract, watchdog scope
- [Source: _bmad-output/implementation-artifacts/epic-2-retro-2026-06-21.md#L71–119] — 0 blockers, forwarded dependencies
- [Source: _bmad-output/planning-artifacts/implementation-readiness-report-2026-06-09.md#L194,L217] — Settings folded into 3.1, zero forward deps
- [Source: _bmad-output/planning-artifacts/prds/prd-garmin_RSVP-2026-06-06/prd.md#FR2,FR3,FR8,FR10,FR13,NFR1,NFR2,NFR8] — functional/non-functional requirements
- [Source: _bmad-output/planning-artifacts/prds/prd-garmin_RSVP-2026-06-06/addendum.md#2,#4,#5] — pacing algorithm, drift-free scheduling, start ramp / word-source seam
- [Source: _bmad-output/planning-artifacts/ux-designs/ux-garmin_RSVP-2026-06-06/EXPERIENCE.md#RSVP-Presentation, #Component-Patterns, #Interaction-Primitives] — WPM, ramp, pause, rewind behavior

## Dev Agent Record

### Agent Model Used

Amelia (bmad-dev-story) — Claude Opus 4.8 (`claude-opus-4-8[1m]`).

### Debug Log References

- Verification gate ran the **exact CI harness locally**: pulled `ghcr.io/matco/connectiq-tester:latest` (the image behind `matco/action-connectiq-tester@v1`) and ran its `tester.sh fenix847mm` (Xvfb + simulator + `monkeydo -t`, compile at `-l 3`). The on-host SDK 9.1.0 simulator can't run here (missing `libwebkit2gtk-4.0`), so the container is the authoritative host gate — equivalent to CI (SDK 8.4.0). Helper: scratchpad `run-tests.sh`.
- **Stale-binary trap:** `tester.sh` only fails closed when `bin/app.prg` is absent; a failed compile silently re-runs the previous `app.prg`. First run showed 24 tests (mine missing) because a strict-typing compile error left the prior binary in place. `rm -f watch/bin/app.prg` before each run; fixed the error; new count is 36.
- **Strict (level 3) fix:** `Storage.setValue(key, toDict())` failed the poly-type check (a heterogeneous `Dictionary` doesn't unify with `Storage.ValueType`). Resolved with an explicit `as Storage.ValueType` cast at the single persistence call site — strictness was NOT lowered.
- **Red-check (non-vacuous tests):** temporarily replaced the drift-free `_lastAdvance += duration` with `= now`; `engineDriftFreeAccumulator` and `engineCatchUpCapFourWords` went FAIL (34/36), then reverted to 36/36 — proving those tests actually pin the AR13 invariant.

### Completion Notes List

All 7 ACs met; 36/36 host tests green (24 prior + 12 new), strict `-l 3` release **and** unit-test builds clean, working tree free of build artifacts (`watch/bin` is gitignored).

- **AC1** — `SettingsModel.Settings` (in `Settings.mc`) yields all 8 per-device defaults from its constructor with **zero Storage access**; the `"settings"` key is a thin adapter (`save()`/`loadFrom()`) over the pure `toDict()`/`applyDict()` seam (the only Storage touch). `applyDict` type/range-checks every field and degrades to the current value (NFR8/AR24).
- **AC2** — `60000/wpm + bonusMs` integer-ms timing; drift-free `lastAdvance += duration`; catch-up capped at `CATCHUP_CAP = 4` per tick with a resync after the cap so a long stall resumes at normal pace rather than bursting through text.
- **AC3** — `setWpm()` is pure math: the current word keeps its already-computed duration, the next word picks up the new value; a `FakeWordSource.wordAtCalls` counter proves no content re-fetch on WPM change.
- **AC4** — `play()` (== resume) re-arms a 3-beat ramp (`RAMP_BEATS = 3`) at the current WPM before the first real word, on every play/resume.
- **AC5** — coast advances to the next `FLAG_SENTENCE_END` (or `atEnd()`) then freezes; instant (and a pause during the ramp) stops immediately. Coast at the last word finalizes a pause via `endsSentence || atEnd` and never leaks into FINISHED.
- **AC6** — `rewind()` moves to the start of the current sentence, then steps to previous sentences on repeat (stackable), clamps at word 0, and always auto-pauses; emits a `TRANSITION_REWIND`.
- **AC7** — `ReaderEngine` imports only `Toybox.Lang` (no `WatchUi`/`Communications`/`System`); the clock is injected; the whole suite passes host-side in the CI image.
- **Scope reconciliation:** the story's "no Storage writes" boundary refers to **position** persistence (SyncManager / Story 3.6); the Settings `save()`/`loadFrom()` adapter is explicitly required by Task 1 + AC1 and is in scope. `StorageKeys.mc` was created **minimal** (only the `SETTINGS` key), exactly as the story pre-authorized — no scope expansion.
- **Task 7 (design-only):** the position/transition surface is exposed as polling getters (`index()`, `state()`, `lastTransition()`, `lastAdvance()`, `currentDuration()`) so `SyncManager.commitPosition(force)` can hook in later without engine rework. `TRANSITION_CHUNK_BOUNDARY` is defined but reserved for Epic 4 (no chunks in 3.1).
- **Convention note:** following the `StreamDecoder` precedent, the public classes are module-wrapped — `SettingsModel.Settings` and `Reader.ReaderEngine` (constants `SettingsModel.PAUSE_COAST`, `Reader.STATE_*`, etc.). `BookWordSource` is a top-level base class (the typed seam). Stories 3.2/3.3/3.8 should reference these qualified names.

### File List

- `watch/source/Settings.mc` (NEW) — `SettingsModel` module: `Settings` class + 8 defaults + pause/handedness enum constants + pure `toDict`/`applyDict` seam + thin `save`/`loadFrom` Storage adapter.
- `watch/source/source_data/StorageKeys.mc` (NEW) — minimal: only `StorageKeys.SETTINGS`.
- `watch/source/engine/BookWordSource.mc` (NEW) — 3-method content seam base class (`wordCount`/`wordAt`/`prefetchAround`).
- `watch/source/engine/ReaderEngine.mc` (NEW) — `Reader` module: pure `ReaderEngine` (timing, drift-free advance, ramp, pause, rewind, position/transition surface).
- `watch/source-test/FakeWordSource.mc` (NEW) — in-memory `BookWordSource` test double with a `wordAtCalls` counter.
- `watch/source-test/ReaderEngineTest.mc` (NEW) — 12 host tests (AC1–AC7 + natural finish) under the CI harness.

## Review Findings

_Code review 2026-06-21 (3 adversarial layers — Blind Hunter / Edge Case Hunter / Acceptance Auditor). **All 7 ACs and all 8 tasks MET** (Acceptance Auditor); even exceeds AC7 (zero `Toybox.System` import). 0 decision-needed, 3 patch, 4 deferred, 6 dismissed as noise._

### Patch (applied + verified 2026-06-21, 38/38 green)

- [x] [Review][Patch] Empty-book source fakes a completed read — `atEnd()` is `_index >= wordCount() - 1`, so `wordCount()==0` → `0 >= -1` → true; `play()`→ramp→first `stepOnce()` hits `atEnd()` → `STATE_FINISHED` + `TRANSITION_FINISHED` for a book with zero words. `BookWordSource`'s own base returns `wordCount()==0` to "degrade quietly," so the path is reachable (a not-yet-buffered `ChunkedWordSource`, Epic 4). The bogus `TRANSITION_FINISHED` is exactly what SyncManager (3.6) hooks. Fix: guard a 0-word source so it never enters a playable/false-finished state. [watch/source/engine/ReaderEngine.mc:245-247] (blind+edge+auditor)
- [x] [Review][Patch] `rewind()` from `STATE_IDLE` flips a never-played engine to PAUSED and emits a spurious `TRANSITION_REWIND` — `rewind()` has no state guard (unlike `play`/`requestPause`/`onTick`). A consumer reading `lastTransition()` sees a rewind that never logically happened. Fix: `if (_state == STATE_IDLE) { return; }` at the top of `rewind()`. (Rewind-from-FINISHED is intended — "FINISHED terminal until a rewind repositions" — and is NOT this finding.) [watch/source/engine/ReaderEngine.mc:108-119] (edge)
- [x] [Review][Patch] Header/comment claims the engine is "decoupled from Settings" but it compile-time depends on `SettingsModel` — `clampWpm` reads `SettingsModel.WPM_MIN/WPM_MAX` and `requestPause` reads `SettingsModel.PAUSE_INSTANT`. The dependency is benign and intentional (constants only, no Storage), but the comment "the caller passes primitives so the engine stays decoupled from Settings/Storage" is false and would mislead a future reader. Fix: correct the comment to state the engine depends on `SettingsModel` *constants* (not Storage). [watch/source/engine/ReaderEngine.mc:55-56] (blind)

### Deferred (checked = logged to deferred-work.md)

- [x] [Review][Defer] `Settings.fontSize` has no upper bound — routed through `readNonNegative` (rejects only `< 0`); a corrupted/persisted `fontSize=99` survives validation and reaches Story 3.2's font-ramp index. No valid max exists at this layer (ramp length is a device/3.2 concern). [watch/source/Settings.mc:132-135] — deferred to Story 3.2 (renderer must clamp to its ramp length)
- [x] [Review][Defer] Per-word `wordAt` amplification — each advance reads the same index 2-3× (`computeDuration` + `currentRecord` + `endsSentenceAt`). Free against the in-memory `FakeWordSource`; against `ChunkedWordSource` (Epic 4) under the decode-watchdog budget, redundant per-tick fetches bite. [watch/source/engine/ReaderEngine.mc:192-213] — deferred to Epic 4 / Story 4.1 (memoize in source or cache current record in engine)
- [x] [Review][Defer] Test suite uses only a 10-word book at divisor-friendly WPMs — drift test ticks once during the ramp (no bonusMs, no cumulative span); catch-up test never spans the RAMP→PLAYING boundary; all WPMs (250/500/600) divide 60000 evenly, so `60000/wpm` integer truncation (e.g. 350→171ms, ~+0.25% pace) is invisible. — deferred: add a multi-beat cumulative-drift test across a bonusMs word, a ramp-spanning catch-up test, and a non-divisor-WPM duration assertion
- [x] [Review][Defer] High-WPM timer arming — the catch-up cap resyncs `_lastAdvance = now`; at `WPM_MAX` (60ms beat) a fixed coarse view tick (~250ms) would hit the cap every tick and defeat drift-free accumulation. Engine is correct; the view must arm per `currentDuration()`, not a fixed interval. — deferred to Story 3.2 (timer-arming contract)

### Dismissed (6, false-positive / handled / by-design)

- `rewind()` from `STATE_FINISHED` reactivating to PAUSED — documented-intended (re-read); lands at last-sentence start by design.
- Coast-pause precedence dropping a pending pause into FINISHED (blind #3) — self-acknowledged unreachable: `requestPause` short-circuits on `atEnd()` before setting `_pausePending`.
- `currentDuration()` returns a live value while PAUSED (blind #4) — `onTick` no-ops while paused and views check state before arming; standard API.
- Engine `pauseMode` not validated like WPM (blind #7) — an unknown value degrades to coast, which is the documented safe default (bounds-check-and-degrade).
- Catch-up cap delays FINISHED by ≤1 duration after a long stall (edge #5) — self-dismissed; correct stall-recovery behavior.
- `requestPause()` re-press while a coast pause is pending is a no-op (auditor) — reasonable; pending-pause cancel is a Story 3.3 input concern.

> _Note: the Acceptance Auditor flagged the Dev Agent Record's "36/36 green" claim as unverifiable from the diff alone. **Corroborated live** — ran the exact CI image (`ghcr.io/matco/connectiq-tester`, `tester.sh fenix847mm`, strict `-l 3`) after applying the 3 patches: **38/38 PASS** (36 prior + 2 new guard tests: `engineEmptyBookDoesNotPlayOrFinish`, `engineRewindFromIdleIsNoOp`), 0 failures, 0 errors._

### Status

Status: done

## Change Log

- 2026-06-21 (dev-story): Implemented Story 3.1 — pure `ReaderEngine` (drift-free `lastAdvance += duration`, `60000/wpm + bonusMs`, ~4-word catch-up cap, 3-beat ramp, coast/instant pause, stackable auto-pausing rewind, 0-based position + transition surface) and `SettingsModel.Settings` (8 Storage-free defaults + thin `"settings"` adapter), on the new `BookWordSource` seam + `FakeWordSource` double. 12 new host tests; 36/36 green at Strict (level 3) in the CI image; release + unit-test builds clean. Status → review.

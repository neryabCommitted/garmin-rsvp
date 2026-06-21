---
baseline_commit: 49af5c7cbad07d13839f73fbafd6c3edfce02d09
---
# Story 3.2: PlaybackView — ORP word rendering

Status: review

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a reader,
I want one word at a time with the pivot anchored and the page dark,
so that RSVP reading is stable and legible (FR1, FR7).

## Acceptance Criteria

**AC1 — ORP word composition: pivot anchored on a true-black canvas**
**Given** a word
**When** rendered
**Then** the pivot letter is in Pivot (`#FF5349`) and the rest in Ink (`#EAE6DF`) on a true-black (`#000000`) canvas, with the pivot's center on the anchor line at 35% of display width (tunable 30–60% via `Settings.anchorPct`)
**And** the anchor does not shift between words.

**AC2 — Split guide marks point at the pivot geometrically (color-blind safe, UX-DR24)**
**Given** guide marks
**When** drawn
**Then** they are split hairlines above/below in Ink-Faint (`#45423E`) with a gap at the anchor column, and short anchor ticks in Pivot — the geometry (not color alone) points at the pivot.

**AC3 — Phantom words flank the focal word**
**Given** phantom words enabled (`Settings.phantomWords`)
**When** playing
**Then** previous/next words flank the focal word in Ink-Faint at the same baseline; when disabled, neither is drawn.

**AC4 — Long word shown whole, margin-clamped, never truncated**
**Given** a word wider than the usable width
**When** rendered
**Then** it shows whole, margin-clamped at the 28px watch edge, with the pivot allowed to drift off-anchor rather than truncating (continuation flag honored if present — reserved, MUST be 0 in v1).

**AC5 — Typeface, burn-in jitter, draw-only-the-selected-word, no persistent chrome**
**Given** playback
**When** the composition draws
**Then** the word-display typeface is used (Atkinson Hyperlegible BMFont per DESIGN, or the documented native-font escape hatch — see Dev Notes "Font decision"), a per-session ±2px jitter is applied to the whole composition (burn-in), `onUpdate` draws only the already-selected word (no advancement in `onUpdate`), and no persistent bright chrome appears while words flow.

## Tasks / Subtasks

- [x] **Task 1 — Pure ORP layout helpers, host-testable (AC1, AC2, AC4)**
  - [x] Create `watch/source/views/OrpLayout.mc` — a `module OrpLayout` of **pure** functions importing **only** `Toybox.Lang` (+ `Toybox.StringUtil` for byte work). NO `Toybox.WatchUi`, NO `Toybox.Graphics`. This is the host-testable seam (mirrors how Story 3.1 kept logic out of any view).
  - [x] `splitAtPivot(word as String, orpPivot as Number) as [String, String, String]` → `[before, pivot, after]`, splitting by **UTF-8 BYTE index** (see Dev Notes "CRITICAL — orpPivot is a byte index"). The pivot segment is the single UTF-8 character whose lead byte is at `orpPivot`; compute its byte-length from the lead byte (1–4). Bounds-check-and-degrade: an out-of-range or non-lead `orpPivot` returns the whole word as `before` with empty pivot/after (never crash, NFR8/AR24). [returns `Array<String>` — strict-typed; `[String,String,String]` tuple types are not what `convertEncodedString` slicing needs]
  - [x] `anchorX(displayWidth as Number, anchorPct as Number) as Number` → integer pivot-center column = `displayWidth * anchorPct / 100`. (454 × 35 / 100 = 158.)
  - [x] `clampFontIndex(fontSize as Number, rampLength as Number) as Number` → clamps the persisted `Settings.fontSize` to `[0, rampLength-1]`. **This resolves the Story 3.1 deferred item:** `Settings.fontSize` is unbounded above (`readNonNegative` only rejects `< 0`); the renderer MUST clamp to its ramp length here. [Source: 3-1 Review Findings "Deferred" #1]
  - [x] `needsMarginClamp(wordWidthPx as Number, usableWidthPx as Number) as Boolean` → pure decision (true when the measured whole-word width exceeds usable width). The *measurement* (`dc.getTextWidthInPixels`) happens in the view; the *decision* given widths is pure and tested here.
  - [x] Host tests `watch/source-test/OrpLayoutTest.mc` (mirror `ReaderEngineTest.mc` / `SmokeTest.mc` `(:test)` pattern): ASCII pivot split; **multibyte pivot split for `Café` and `naïve`** (byte index ≠ char index — the explicit reason this fixture exists; fixture carries them lowercase, exercised via after-segment-multibyte, before-segment byte≠char, and pivot-is-multibyte cases); `anchorX` at 30/35/60%; `clampFontIndex` clamps a corrupted `fontSize=99`; `needsMarginClamp` boundary at exactly usable width. Assert literal values; `logger.error(...); return false` on mismatch.

- [x] **Task 2 — Canned `BookWordSource` for the dev render path (Epic-3 local source)**
  - [x] Create a shipping (`source/`, NOT `source-test/`) `BookWordSource` so PlaybackView has real words to render before Epic 4's transfer exists. `FakeWordSource` lives in `source-test/` and is **stripped from release builds** — it cannot feed the running app.
  - [x] **Decided path (Nerya, 2026-06-22 — see Dev Notes "Canned source decision"):** bundle `companion/test/fixtures/streams/dev_sample_book.stream` (228 words, 3 chapters, fp `4bd588b9`, includes `Café`/`naïve` accented byte-pivots and the long word `counterrevolutionaries`) as a **base64 string resource** in `resources/strings/`, decode with `StringUtil.convertEncodedString(... REPRESENTATION_STRING_BASE64 → REPRESENTATION_BYTE_ARRAY)`, then `StreamDecoder.decodeChunk(payload, 228)` into an in-memory `watch/source/source_data/CannedWordSource.mc` (extends `BookWordSource`). Decode **once at startup, outside any callback** — done in `CannedWordSource.initialize()`, never inside a BLE/timer callback (the whole-chunk-decode-in-callback watchdog is an Epic-4/Story-4.1 concern, but keep the discipline).
  - [x] **Contingency only** (base64 round-trip worked on SDK 8.4.0 — contingency NOT needed): a ~12-record hand-coded `CannedWordSource` was the fallback. The base64 path round-trips cleanly (verified live: 228 records decode, café/naïve/counterrevolutionaries byte-pivots intact).
  - [x] Do NOT build `ChunkedWordSource` (Epic 4 / Story 4.1) — that is the Storage-bucket + fetch source. This canned source is the dev stand-in only. (Not built; `CannedWordSource` is clearly marked Epic-3-only.)

- [x] **Task 3 — `PlaybackView` composition (AC1–AC5)**
  - [x] Create `watch/source/views/PlaybackView.mc` — `class PlaybackView extends WatchUi.View`. Imports `Toybox.WatchUi`, `Toybox.Graphics`, `Toybox.Lang` (+ `Toybox.Math` for jitter, `Toybox.Timer`/`Toybox.System` for the loop). The view owns the engine and only **reads** engine state — the engine never references the view (AR15, refcount GC, no cycle; no back-pointer needed so no `WeakReference` required).
  - [x] `onUpdate(dc)`: clear to `void` (`#000000`), then draw the **already-selected** word (`engine.currentRecord()`), guides, phantoms, and nothing else (no paused readout — Story 3.4). **No advancement in `onUpdate`** — all advancement is in `onTimerTick` (Task 4). [Source: architecture.md line 287]
  - [x] Composition geometry (AC1): split the focal word with `OrpLayout.splitAtPivot`; measure `before`/`pivot`/`after` widths with `dc.getTextWidthInPixels`; place the pivot glyph's **center** on `OrpLayout.anchorX(dc.getWidth(), settings.anchorPct)`, vertically centered; before/pivot/after drawn left-justified from a single computed origin so the anchor (layout origin) does **not** move between words (AC1).
  - [x] Colors (AC1, AC2, AC3): focal `before`/`after` in Ink; pivot letter in Pivot **iff `Settings.focusHighlight`** is on, else in Ink (the guide gap + ticks still point at it — color-blind safe, AC2); guide hairlines + phantoms in Ink-Faint; anchor ticks in Pivot. Four watch colors defined as `private const` (`0xEAE6DF`, `0x45423E`, `0xFF5349`, `0x000000`) — by name, no inline hex at draw sites. [Source: DESIGN.md colors]
  - [x] Guide marks (AC2): split horizontal hairlines above and below the word line in Ink-Faint with a gap at the anchor column; short vertical ticks in Pivot at the anchor (down tick from top hairline, up tick from bottom). Geometry recalibrated against `dc.getWidth()` (gap ±16px around anchor, hairline offset ±44px from center; no hardcoded 454).
  - [x] Phantom words (AC3): when `Settings.phantomWords`, draw `wordAt(index-1)` to the left and `wordAt(index+1)` to the right of the focal word, same baseline, Ink-Faint, with a gap; null neighbours (book start/end) draw nothing. Uses the source's bounds-checked `wordAt`.
  - [x] Long-word handling (AC4): if `OrpLayout.needsMarginClamp(fullWordWidth, dc.getWidth() - 2*WATCH_EDGE)` (WATCH_EDGE = 28) **or** the before-segment would cross the left margin, clamp the word's left edge to the margin and let the pivot **drift off-anchor** — whole word, never truncate/hyphenate. `FLAG_CONTINUATION` reserved (MUST be 0 in v1) — no branch on it (noted in comment).
  - [x] Font (AC5): resolved through the one-line `fontFor()` seam (Task 5), sized via `OrpLayout.clampFontIndex(settings.fontSize, RAMP_LENGTH)`. Same face for phantoms (same size per DESIGN).
  - [x] Burn-in jitter (AC5): per-session ±2px offset applied to the **whole composition** (anchor column + center y carry `_jitterX/_jitterY`; guides/word/phantoms all derive from those), recomputed per session (`onShow`) and per pause/finish (NOT per-word). Bounded random walk clamped to ±2px via `Toybox.Math.rand`. [Source: DESIGN.md line 134]
  - [x] Ramp rendering (AC5 support): while `engine.isRamping()`, render `engine.rampRemaining()` ("3"/"2"/"1") centered on the anchor in Ink, no phantoms, no word (guides still drawn as the stable frame). Engine owns count/timing (Story 3.1); this story owns the pixels.
  - [x] No persistent bright chrome while playing (AC5): no progress readout, no WPM, no icons during flow. Paused readout is **Story 3.4** — not added.

- [x] **Task 4 — Timer-driven render loop (drives the Story 3.1 engine; honors the deferred timer-arming contract)**
  - [x] Own a `Toybox.Timer.Timer` that, on each fire (`onTimerTick`), calls `engine.onTick(System.getTimer())` then `WatchUi.requestUpdate()` so `onUpdate` repaints the now-selected word. Engine = `Reader.ReaderEngine` over the Task-2 canned source.
  - [x] **Arm the timer per `engine.currentDuration()`, NOT a fixed coarse interval** (`armTimer()` one-shot, re-armed after every tick), clamped to the ≥50ms platform floor. Resolves Story 3.1 deferred #4 — no fixed coarse tick to hit the catch-up cap at high WPM. [Source: 3-1 Review Findings "Deferred" #4; architecture.md AR13]
  - [x] Feed the engine the injected clock via `System.getTimer()` (the engine imports no `System`; the view supplies `now`).
  - [x] **Auto-play on view show**: `onShow()` → `engine.play(System.getTimer())` (re-arms the 3-beat ramp) + arm timer. No `InputDelegate` with playback controls (Story 3.3). No BACK delegate needed — BACK exits the initial view by default.
  - [x] Stop/clear the timer in `onHide()` and on pause/finish (the tick stops re-arming once the engine leaves PLAYING/RAMP) — no runaway timer, no per-tick work while frozen.

- [x] **Task 5 — Make PlaybackView reachable + font seam (integration)**
  - [x] `PaceTurnerApp.getInitialView()` now returns `[new PlaybackView()]`. GateV2 spike view/delegate left in place (git-preserved, no longer entered); app compiles at Strict L3 with the spike present. The spike's `Communications` lifecycle in `onStart()` is harmless to the playback path (no UI binding) and left intact as run evidence.
  - [x] Font seam (native ramp): `fontFor(index)` resolves the word-display face in ONE place using the device native font ramp (`Graphics.FONT_SYSTEM_LARGE/MEDIUM/SMALL`, index 0 = largest = default) — the documented escape hatch. The Atkinson Hyperlegible BMFont is a localized later swap behind this same seam (its own follow-up story).
  - [x] `resources/strings/strings.xml` updated with the base64 `devSampleStream` string (Task 2 bundles the stream).

- [x] **Task 6 — Verify (Strict L3 + host tests green + visual on device)**
  - [x] Compile clean at **Strict (level 3)** — unit-test build (`tester.sh`, `-l 3 -t`) AND release build (`monkeyc -l 3 -r`, BUILD SUCCESSFUL, 33KB `.prg`). Strictness never lowered.
  - [x] `OrpLayoutTest.mc` green in the CI image (`ghcr.io/matco/connectiq-tester`, `tester.sh fenix847mm`); `rm -f watch/bin/app.prg` before the run. **Test count rose 38 → 46 (+8 new orp tests), not flat.** PASSED (passed=46, failed=0, errors=0).
  - [x] The View's `onUpdate` drawing is not host-unit-testable (no `Dc` in the harness) — correctness covered by the pure helpers (Task 1, 8 tests) + Strict-L3 compile (both builds). A one-line readiness marker is printed on `onShow` (`System.println`, machine-readable, NOT per-word). **Visual check DONE on the real Fenix 8 (Nerya, 2026-06-22):** all 5 ACs confirmed — anchor stays put, red pivot aligns with the guide ticks on normal words, `café`/`naïve` accents intact, and `counterrevolutionaries` renders WHOLE (margin-snug, pivot drifted ~1 letter off-anchor) after the AC4 fit-to-width fixes below. See Completion Notes.

## Dev Notes

### What this story owns (scope boundary)
The watch RSVP **render surface** and the **timer-driven render loop** that drives the Story 3.1 engine over a **local/canned word source** — the first pixels of Epic 3. New: `views/OrpLayout.mc` (pure helpers), `views/PlaybackView.mc` (composition + loop), `source_data/CannedWordSource.mc` (dev source), `source-test/OrpLayoutTest.mc`. Modify: `PaceTurnerApp.getInitialView()`; possibly `resources/strings/strings.xml`. **OUT of scope:** the input map / playback controls (pause, WPM ±, rewind gestures — **Story 3.3**); the paused progress readout + context view (**Story 3.4**); chapter card + Finished/status shells (**Story 3.5**); persistence/resume (**Story 3.6**); screen-survival/session strategy (**Story 3.7**); the settings menu (**Story 3.8**); `ChunkedWordSource`/transfer (**Epic 4**). [Source: epics.md#Story-3.2 lines 570–597; architecture.md tree lines 370–395]

### CRITICAL — `orpPivot` is a UTF-8 **byte** index, not a character index
`WordRecord.orpPivot` is "a **byte index into the UTF-8 word** as precomputed by the phone" (SPEC §5; architecture line 277 — "Watch never recomputes pivots"). For ASCII, byte index == char index; for the fixture's `Café`/`naïve` it does **not**. Monkey C `String` has no byte-slice — you MUST convert the word to a `ByteArray` (`StringUtil.convertEncodedString` STRING→BYTE_ARRAY, UTF-8), slice three ranges, and convert each back to a `String`. The pivot segment length is the UTF-8 char length derived from the lead byte at `orpPivot` (`<=0x7F`→1, `0xC2–0xDF`→2, `0xE0–0xEF`→3, `0xF0–0xF4`→4 — the exact rule already implemented in `StreamDecoder.isValidUtf8`, lines 100–110; reuse that logic, do not reinvent). The phone guarantees `orpPivot < wordLen` and that it lands on a char-lead boundary (decoder enforces `orpPivot < wordLen`, StreamDecoder.mc:52). **The watch never recomputes the ORP tier** — the EXPERIENCE.md tier table (`≤1→1st … ≥14→5th`, EXPERIENCE.md:94) is informational; the byte index is authoritative. [Source: architecture.md line 277; SPEC §5; companion fixture README]

### REUSE — do not reinvent
- **`StreamDecoder.WordRecord`** (`watch/source/source_data/StreamDecoder.mc:13–25`) — `{ word: String, flags: Number, orpPivot: Number, bonusMs: Number }`. The source and view consume this exact class; do NOT define a new word struct. [Source: StreamDecoder.mc:13–25]
- **`StreamDecoder.decodeChunk(payload, n)`** (`StreamDecoder.mc:30`) — decode the bundled dev stream in one call (n=228); returns null on malformed (surface as a degraded empty render, never a crash). [Source: StreamDecoder.mc:30]
- **`StreamDecoder.isValidUtf8` lead-byte rule** (`StreamDecoder.mc:100–110`) — the exact UTF-8 char-length logic the byte-split needs; reuse it. [Source: StreamDecoder.mc:94–134]
- **`Reader.ReaderEngine`** (`watch/source/engine/ReaderEngine.mc`) — module-qualified `Reader.ReaderEngine`. The view OWNS one engine instance, drives it via `play(now)` / `onTick(now)`, and READS `currentRecord()`, `index()`, `state()`/`isRamping()`/`isPaused()`/`isFinished()`, `rampRemaining()`, `currentDuration()`. The engine NEVER references the view. Note the empty-book guard: `play()` no-ops on a 0-word source — the canned source must report a real `wordCount()`. [Source: ReaderEngine.mc:79–96, 144–166, 183–203]
- **`SettingsModel.Settings`** (`watch/source/Settings.mc`) — module-qualified `SettingsModel.Settings`. The view reads `anchorPct`, `phantomWords`, `focusHighlight`, `fontSize`. Construct with defaults (`new SettingsModel.Settings()`); `loadFrom()` is fine to overlay persisted values (the menu that writes them is Story 3.8). [Source: Settings.mc:50–112]
- **`Protocol.FLAG_*`** (`watch/source/Protocol.mc:47–52`) — `FLAG_CHAPTER_START = 0x04` (ramp/chapter rendering cues if needed), `FLAG_CONTINUATION = 0x08` (reserved, MUST be 0 in v1 — long-word continuation honor-if-present). Reference the constants, never inline hex. [Source: Protocol.mc:47–52]
- **Test pattern** — copy `watch/source-test/SmokeTest.mc` verbatim: `import Toybox.Test; (:test) function x(logger as Test.Logger) as Boolean { if (a != b) { logger.error("..."); return false; } return true; }`. No `Test.assert*` is used in this repo. [Source: SmokeTest.mc; ReaderEngineTest.mc]

### Carry-forward from Story 3.1 review (two deferred items land HERE)
1. **`Settings.fontSize` is unbounded above** — `readNonNegative` rejects only `< 0`; a persisted `fontSize=99` reaches this renderer. Task 1's `clampFontIndex` MUST clamp to the font ramp length. [Source: 3-1 Review Findings "Deferred" #1, Settings.mc:132–135]
2. **High-WPM timer arming** — the engine's catch-up cap resyncs `_lastAdvance = now`; a fixed coarse view tick would hit the cap every tick at high WPM and defeat drift-free accumulation. Task 4 MUST arm the timer per `currentDuration()`, clamped to the ≥50ms floor. [Source: 3-1 Review Findings "Deferred" #4]

### Font decision (RESOLVED — native font behind a seam; Nerya, 2026-06-22)
AC5 / DESIGN name **Atkinson Hyperlegible BMFont**, but **no font resources exist** (`watch/resources/` has only `drawables/` + `strings/`; `resources/fonts/` from the architecture tree is not yet created), and generating a CIQ BMFont (TTF → BMFont tool → `.fnt` + glyph PNGs + widths, ~48px ±2 steps, load-on-demand) is a meaningful asset-tooling task. **Decision:** build the full render pipeline now behind the one-line font seam (Task 5) using the **device native font ramp** — the documented escape hatch ("fall back to Garmin's largest native system font and re-tune sizes" — DESIGN typography; architecture line 305). This validates geometry/jitter/byte-split/long-word on hardware immediately. The Atkinson Hyperlegible BMFont is a **localized later swap** behind the same seam — its own small follow-up story, NOT this one. So AC5's "word-display typeface is used" is satisfied here by the native face; the seam is the durable contract. [Source: DESIGN.md Typography; architecture.md line 305; decision-log line 17]

### Canned source decision (RESOLVED — bundle the dev stream as base64; Nerya, 2026-06-22)
**Decision:** bundle `companion/test/fixtures/streams/dev_sample_book.stream` (228 words, 3 chapters, fp `4bd588b9`, `Café`/`naïve` byte-pivots + `counterrevolutionaries`) as a **base64 string resource** in `resources/strings/`, decode it **once at startup** via `StringUtil.convertEncodedString(... REPRESENTATION_STRING_BASE64 → REPRESENTATION_BYTE_ARRAY)` → `StreamDecoder.decodeChunk(payload, 228)` → an in-memory `CannedWordSource` in `source/`. This is what the Epic-1-retro prep emitted the fixture for, and it exercises real ORP byte pivots / long word / chapters. CIQ has no generic binary-resource→ByteArray type, so base64-string is the route. **Contingency only** (if base64 round-trip proves awkward on SDK 8.4.0): a ~12-record hand-coded `CannedWordSource` (one accented word with correct byte `orpPivot`, the long word, `FLAG_SENTENCE_END`/`FLAG_CHAPTER_START` at known indices). Either way the source ships in `source/` (NOT `source-test/` — `FakeWordSource` is stripped from release builds). [Source: companion/test/fixtures/streams/README.md; deferred-work.md#L10]

### Composition reference (spine wins on conflict)
`mockups/key-playback.html` is the 1:1 rendered reference for Playing + Paused (anchor at 35%, split guides with anchor-column gap + red ticks, phantoms flanking same-baseline, progress readout PAUSED-ONLY). The HTML's pixel constants (anchor 158.9px, hairline ±44px, gap ±16px, phantom offsets) are a 454-px starting point — recalibrate to the actual `dc.getWidth()`/measured text widths; do NOT hardcode 454. [Source: mockups/key-playback.html; DESIGN.md Components lines 146–158]

### Colors & typography (DESIGN authority)
- `void #000000` canvas (AMOLED off-pixels), `ink #EAE6DF` focal word, `ink-dim #8A867F` paused chrome (NOT this story), `ink-faint #45423E` guides + phantoms, `pivot #FF5349` pivot letter + anchor ticks. **One red, one job** — never use pivot for chrome/decoration. [Source: DESIGN.md Colors lines 102–113]
- Word-display 48px / weight 400 (regular, not bold — bold closes counters at flash speed); same face/size for phantoms; `watch-meta` 22px is paused-chrome only. The user font-size setting is ±2 steps around 48px `[ASSUMPTION]`. [Source: DESIGN.md Typography lines 116–125; EXPERIENCE.md:169]

### Burn-in discipline (load-bearing, not taste)
Mostly-black, one accent, **no element on fixed pixels indefinitely** → per-session ±2px composition jitter; no persistent bright chrome while words flow. This is an AMOLED burn-in requirement and a battery/gate-V4 concern, not decoration. [Source: DESIGN.md "Layout & Spacing" line 134, "Do's and Don'ts" line 167; architecture.md line 72]

### Monkey C conventions (verified in-repo)
- Classes PascalCase, one public class per `PascalCase.mc`; methods/vars `camelCase`, private fields `_camelCase`, module constants `UPPER_SNAKE`. [Source: architecture.md Naming lines 245–258; observed in repo]
- **Strict typing (level 3) from commit 1** — every signature typed, nullable `?` where applicable. A build needing the level lowered is a defect. Watch the `Storage.ValueType`-style poly-type traps the 3.1 dev hit; cast explicitly at the seam, never lower strictness. [Source: architecture.md Enforcement item 5; 3-1 Debug Log]
- Callbacks use `method(:symbol)` (see `PaceTurnerApp.mc`), not closures. Timer callback is `method(:onTimerTick)`.
- **Refcount GC, no cycle collection** → the engine must never hold a strong ref to the view; if any back-pointer is unavoidable use `WeakReference`. Views read engine state; the engine never references views (AR15). [Source: architecture.md AR15 line 106, line 287]
- `System.println` is budgeted (~10KB on-device log) — log lifecycle/transitions only, **NEVER per-word** (a per-word println at 700 WPM is a named anti-pattern). Verbose logs behind `(:debug)`. [Source: architecture.md AR25 line 122, line 323]
- Error posture (NFR8/AR24): bounds-check-and-degrade, never crash mid-read; no silent `catch {}`. Null `wordAt`/neighbour/record → draw nothing for that element, keep going. [Source: architecture.md AR24 line 121]
- **NFR2 heap ≤600KB of 768KB** — only the active word-display font size is heap-resident (load-on-demand on size change, never all steps at startup). [Source: architecture.md line 305; PRD#NFR2]

### Build / harness facts
- Manifest `minApiLevel = 5.2.0`, target product `fenix847mm`; CI pins **SDK 8.4.0** (`matco/action-connectiq-tester`). The on-host SDK 9.1.0 simulator can't run here (missing `libwebkit2gtk-4.0`) — run host tests via the container (`ghcr.io/matco/connectiq-tester`, `tester.sh fenix847mm`), the authoritative gate. **`rm -f watch/bin/app.prg` before every run** (stale-binary trap). [Source: 3-1 Debug Log References; watch-tests-local-via-ci-docker-image memo; manifest.xml]
- Real-hardware visual check: sideload to the Fenix 8 per the toolchain memo (USB Mode → MTP, `gio copy` the `.prg`). The render surface is the one thing host tests can't see; gate V4 (battery) is later (Story 3.9) but a visual confirm here de-risks 3.3+. [Source: garmin-ciq-ubuntu-2404-appimage memo]
- The firmware `onUpdate` watchdog (and the BLE-decode watchdog) are real but: this story does no BLE decode; keep `onUpdate` to drawing the single selected word + guides + phantoms (cheap), and decode the canned stream **once at startup, outside callbacks**. [Source: deferred-work.md#L53; watch-decode-watchdog-constraint memo]

## Project Structure & Conventions

### File locations (canonical tree — architecture.md lines 349–395)
- `watch/source/views/OrpLayout.mc` — pure ORP geometry/byte-split helpers (NEW; create `views/` dir).
- `watch/source/views/PlaybackView.mc` — `class PlaybackView extends WatchUi.View`: composition + timer loop (NEW). Architecture names this file at line 372.
- `watch/source/source_data/CannedWordSource.mc` — shipping dev `BookWordSource` (NEW).
- `watch/source-test/OrpLayoutTest.mc` — host tests for the pure helpers (NEW).
- `watch/source/PaceTurnerApp.mc` — `getInitialView()` returns `PlaybackView` (MODIFY; preserve spike code).
- `watch/resources/strings/strings.xml` — base64 canned stream string (MODIFY, only if Task 2 bundles the stream).
- Reused unchanged: `engine/ReaderEngine.mc`, `engine/BookWordSource.mc`, `Settings.mc`, `source_data/StreamDecoder.mc`, `Protocol.mc`.

### Project Structure Notes
- `views/` does not exist yet — create it (architecture's canonical home for PlaybackView and the later view shells). `OrpLayout.mc` is a pure module living under `views/` for locality with its only consumer, but imports no UI (host-testable). An alternative home is `display/`; `views/` keeps it next to `PlaybackView`. Confirm if a reviewer prefers `display/`.
- `CannedWordSource` is an Epic-3-only dev artifact. Mark it clearly as the local stand-in for `ChunkedWordSource` (Epic 4) so it is not mistaken for the production source path.
- No `manifest.xml` change: no new permissions (rendering needs none; `Communications` stays for the preserved spike but the playback path uses it not at all).

### References
- [Source: _bmad-output/planning-artifacts/epics.md#Story-3.2 (lines 570–597)] — story statement + 5 ACs
- [Source: _bmad-output/planning-artifacts/architecture.md (lines 277, 287, 305, 349–395, line 72, AR12/AR15/AR24/AR25)] — pivot-is-byte-index, onUpdate-draws-selected-only, font load-on-demand, file tree, burn-in, heap/GC/error/logging posture
- [Source: _bmad-output/planning-artifacts/ux-designs/ux-garmin_RSVP-2026-06-06/DESIGN.md (Colors 102–113, Typography 116–125, Layout 127–136, Components 146–158, Do/Don't 162–169)] — colors, type, jitter, composition, one-red rule
- [Source: _bmad-output/planning-artifacts/ux-designs/ux-garmin_RSVP-2026-06-06/EXPERIENCE.md (lines 81–82, 94, 121–168, 169, 175–176)] — word-display behavior, ORP tier table (informational), long-word, phantom/guide toggles, font rationale
- [Source: _bmad-output/planning-artifacts/ux-designs/ux-garmin_RSVP-2026-06-06/mockups/key-playback.html] — 1:1 composition reference
- [Source: _bmad-output/planning-artifacts/ux-designs/ux-garmin_RSVP-2026-06-06/.decision-log.md (line 17, 38)] — Atkinson BMFont feasibility-assumed; font-size MVP
- [Source: watch/source/source_data/StreamDecoder.mc:13–25, 30, 94–134] — WordRecord, decodeChunk, UTF-8 lead-byte rule to reuse
- [Source: watch/source/engine/ReaderEngine.mc:79–96, 144–203, 245–264] — engine drive/read surface, empty-book guard, currentDuration
- [Source: watch/source/Settings.mc:50–112, 132–135] — settings read surface; unbounded fontSize (clamp here)
- [Source: watch/source/Protocol.mc:47–52] — FLAG_* constants
- [Source: watch/source-test/SmokeTest.mc; watch/source-test/ReaderEngineTest.mc] — host test pattern; CI-image run + stale-binary trap
- [Source: _bmad-output/implementation-artifacts/3-1-readerengine-settings-model-drift-free-advance-timing-wpm-rewind-pure-logic.md (Review Findings — Deferred #1, #4; Debug Log)] — fontSize clamp + timer-arming carry-forward; Strict-L3 + CI-image facts
- [Source: companion/test/fixtures/streams/README.md, dev_sample_book.{stream,manifest.json}] — canned dev stream (228 words, fp 4bd588b9, accented + long word)
- [Source: _bmad-output/planning-artifacts/prds/prd-garmin_RSVP-2026-06-06/prd.md#FR1,FR7,FR4,NFR2,NFR8] — single-word ORP display, long-word handling, hands-off display, heap, error posture

## Dev Agent Record

### Agent Model Used
Amelia (dev-story) — Claude Opus 4.8 (claude-opus-4-8[1m]).

### Debug Log References
- **Strict-L3 type trap (caught + fixed):** first compile failed at `OrpLayout.mc:46–48` — `String.toUtf8Array()` returns `Array<Number>` (verified against Connect IQ API docs), and `Array<Number>.slice()` is `Array<Number>`, which `StringUtil.convertEncodedString` will not accept (it requires `String` or `ByteArray`). Fix: convert the word to a real `ByteArray` via `convertEncodedString(STRING_PLAIN_TEXT → BYTE_ARRAY)` first (mirrors `StreamDecoder.mc:68` slice-and-convert), then slice the `ByteArray` (whose `.slice()` IS a `ByteArray`). Re-compiled clean.
- **Test gate:** `docker run … ghcr.io/matco/connectiq-tester:latest -c 'tester.sh fenix847mm'` after `rm -f watch/bin/app.prg` (stale-binary trap). `Ran 46 tests … PASSED (passed=46, failed=0, errors=0)` — 38 (Story 3.1) + 8 new orp tests.
- **Release gate:** in-container `monkeyc -f monkey.jungle -d fenix847mm -y <temp-key> -l 3 -w -r` → `BUILD SUCCESSFUL`, exit 0, 33,324-byte `release.prg`. Confirms app code (PlaybackView/CannedWordSource) compiles at Strict L3 with `(:test)` stripped.
- **Fixture verification (pre-impl):** decoded `dev_sample_book.stream` — 228 records consumed exactly; `café`@byte-pivot 1 (`[63 61 66 C3 A9]`), `naïve`@byte-pivot 1 (`[6E 61 C3 AF 76 65]`), `counterrevolutionaries` (22 bytes) confirmed present. Note: accented words are LOWERCASE in the committed fixture (story text said `Café`/`naïve`); tests use the actual lowercase forms and additionally exercise a pivot-on-multibyte and a before-segment byte≠char case.

### Completion Notes List
- **All 5 ACs implemented AND confirmed on the real Fenix 8 (visual check passed, 2026-06-22).** Sideloaded via MTP (`gio copy` per the toolchain memo) and run on-device: anchor stable, pivot/guide-tick alignment correct, accented byte-pivots (`café`/`naïve`) intact, long word whole.
- **AC4 long-word handling required 3 on-device iterations** (the visual check earned its keep — none of this is host-testable):
  1. Initial left-only margin-clamp pinned the left edge → the long word's tail ran off the RIGHT (the pivot is near the word's start, so most of the word extends rightward).
  2. Added fit-to-width (shrink the focal word down the font ramp until it fits) + bidirectional margin-clamp (shift left OR right so the whole word sits within the margins, pivot drifts). But the native ramp (LARGE/MEDIUM/SMALL) couldn't get `counterrevolutionaries` under the 28px-inset usable width — clipped the last letter.
  3. Extended the ramp with `FONT_SYSTEM_TINY`/`XTINY` (RAMP_LENGTH 3→5) AND dropped the FOCAL word's inset to `FOCAL_EDGE=8` (the full diameter is available at the vertical centerline of a round display; guides keep the 28px inset). Fit-to-width now picks the LARGEST native size that fills the available width. Final on-device result: whole word, snug to the margin, pivot drifted ~1 letter off-anchor — AC4 satisfied. The Atkinson-BMFont swap (own story) will replace the coarse native steps with fine-grained 48±2px sizing behind the same `fontFor()` seam.
- **Pure layout math covered by 8 host tests; both builds compile clean at Strict L3.** The `onShow` readiness marker (`"PlaybackView ready: words=228 wpm=250 fontIdx=0"`) prints for log-based confirmation. Gate V4 (battery) remains Story 3.9.
- **Resolved 2 carried-forward Story 3.1 deferred items:** (#1) `Settings.fontSize` unbounded-above → `OrpLayout.clampFontIndex` clamps to the ramp (tested with corrupted `fontSize=99` → 2); (#4) high-WPM timer arming → `armTimer()` arms per `currentDuration()` clamped to the 50ms floor, never a fixed coarse tick.
- **Font decision honored:** native ramp behind the `fontFor()` seam (Atkinson BMFont swap is a later story behind the same seam). **Canned-source decision honored:** base64 string resource round-tripped successfully on SDK 8.4.0 — the hand-coded contingency was not needed.
- **`splitAtPivot` returns `Array<String>`** rather than a `[String,String,String]` tuple type — the tuple form gave no benefit and the strict checker is happy with `Array<String>` (consistent with the repo's `Array<…>` usage). Functionally identical (3-element array).
- **No new permissions / no manifest change.** Spike code (`GateV2View/Delegate`, `PaceTurnerApp` receive path) preserved, just no longer entered.

### File List
**New:**
- `watch/source/views/OrpLayout.mc` — pure ORP byte-split / anchor / font-clamp / margin-clamp helpers (host-testable seam)
- `watch/source/views/PlaybackView.mc` — `class PlaybackView extends WatchUi.View`: ORP composition + timer-driven render loop
- `watch/source/source_data/CannedWordSource.mc` — Epic-3 dev `BookWordSource` (decodes the bundled base64 stream once at startup)
- `watch/source-test/OrpLayoutTest.mc` — 8 host tests for the pure helpers

**Modified:**
- `watch/source/PaceTurnerApp.mc` — `getInitialView()` returns `PlaybackView` (spike preserved)
- `watch/resources/strings/strings.xml` — added `devSampleStream` base64 string resource

### Change Log
- 2026-06-22 — Story 3.2 implemented (dev-story): OrpLayout pure helpers + PlaybackView ORP render surface + timer loop over CannedWordSource (base64 dev stream). 5/5 ACs met; resolves 3.1 deferred #1 (fontSize clamp) + #4 (per-duration timer arming). 46/46 host tests green @ Strict L3, release build clean.
- 2026-06-22 — AC4 long-word fixes from on-device visual check: fit-to-width (shrink focal word down the font ramp to the largest size that fits) + bidirectional margin-clamp (shift left/right, pivot drifts) + ramp extended to TINY/XTINY (RAMP_LENGTH 5) + focal-word inset `FOCAL_EDGE=8` (round-display centerline width). `counterrevolutionaries` now renders whole. All 5 ACs visually confirmed on the real Fenix 8.

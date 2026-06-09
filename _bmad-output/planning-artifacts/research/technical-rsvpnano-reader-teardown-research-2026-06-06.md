---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments:
  - '_bmad-output/planning-artifacts/briefs/brief-garmin_RSVP-2026-06-05/brief.md'
  - '_bmad-output/planning-artifacts/research/technical-epub-parsing-flutter-dart-research-2026-06-06.md'
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'RSVP Nano reader-side teardown — what the reference project already figured out'
research_goals: 'Extract every reusable design decision from the RSVP Nano reader implementation: ORP rendering, reading loop, rewind/pause UX, buffering and indexed seeking on a constrained device, position persistence, controls, and settings — and map each to the Garmin watch-app design'
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

This report is a direct source-code teardown of RSVP Nano (https://github.com/ionutdecebal/rsvpnano, MIT, release v0.0.5), the ESP32 reading device that the garmin_RSVP project is the Garmin analogue of. Every claim below was verified by reading the actual files (raw.githubusercontent.com fetches, downloaded and read line-by-line; access date 2026-06-06) and is cited to a specific path. A prior report already covered the `.rsvp` directive format, `web/library.js` tokenization, and the headline `ReadingLoop.cpp` pacing percentages, so those are not re-derived here except where they bear on a transfer decision. The focus is everything else the author solved on the reader side: the playback state machine, ORP rendering, rewind/pause/recovery UX, the flash-backed indexed word source, position persistence, controls, and the host-side test suite.

The repository is larger and more mature than the brief implies. It is roughly 25k LOC of firmware plus a full SwiftUI iOS companion (`ios/RSVPNanoCompanion/`, ~150 KB of Swift) and a web flasher/converter (`web/`). The firmware is monolithic and centered on a 6,154-line `src/app/App.cpp` god-object, but the reader core itself is cleanly separated: `src/reader/ReadingLoop.{h,cpp}` (the pacing/state engine, no I/O), `src/reader/BookWordSource.h` (a 12-line virtual interface), and `src/storage/IndexedBookStore.{h,cpp}` (the flash-backed word source). That separation is the single most directly portable thing in the project: the reading loop is pure logic, fully unit-tested host-side (`test/test_pacing/test_main.cpp`, ~60 tests), and decoupled from both the display and the storage backend through one tiny interface. The architecture maps almost one-to-one onto the watch: `BookWordSource` is exactly the seam where a Garmin app would plug in "words from a buffered chunk in watch storage" instead of "words from an SD index."

The central architectural finding — and the central conflict with our prior garmin_RSVP planning — is that **RSVP Nano computes all timing at read time, not in the stream.** The `.rsvp` intermediate and the `.ridx`/`.rdat` index both carry plain words and structure (chapter/paragraph offsets) but *zero* per-word duration; `ReadingLoop::durationForWord()` derives dwell time live from the word string and WPM on every advance. Our prior reports recommend baking timing into the phone-produced stream. Both positions are defensible and the report spells out exactly when each wins for the watch. The rest of the teardown is overwhelmingly "copy the design": his ORP geometry, two-stage "pause at sentence end," edge-tap sentence rewind, absolute-word-index persistence with per-book keys, and 256-word windowed flash reads are all directly applicable to a Monkey C reader fed by BLE-delivered chunks.

---

## Technical Research Scope Confirmation

**Research Topic:** RSVP Nano reader-side teardown — mining the reference project (https://github.com/ionutdecebal/rsvpnano) for already-solved design decisions
**Research Goals:** Extract every reusable design decision from the RSVP Nano reader implementation — ORP rendering, reading loop, rewind/pause UX, buffering and indexed seeking on a constrained device, position persistence, controls, settings — and map each to the Garmin watch-app design, noting where the Garmin context (BLE streaming, AMOLED, Monkey C) forces divergence.

**Technical Research Scope:**

- Architecture Analysis - reader firmware structure, reading loop, buffering/seek design
- Implementation Approaches - ORP rendering, rewind/pause, position persistence
- Technology Stack - what is ESP32-specific vs portable design
- Integration Patterns - library/converter↔reader contract (.rsvp/.ridx/.rdat)
- Performance Considerations - constrained-device techniques transferable to the watch

**Research Methodology:**

- Direct source-code reading of the RSVP Nano repository (raw fetches, cited per file)
- Cross-reference against the four 2026-06-06 garmin_RSVP research reports
- Confidence level framework for uncertain information

**Scope Confirmed:** 2026-06-06

<!-- Content will be appended sequentially through research workflow steps -->

---

## Repository Map and Maturity

The repo (root `README.md`, accessed 2026-06-06; full tree via the GitHub trees API) is markedly larger and more mature than "an ESP32 demo." It ships a real firmware, a SwiftUI iOS companion, and a web-based flasher/converter, at release **v0.0.5** (`docs/releases/v0.0.5.md`, "first public firmware release").

**Component breakdown:**

- **Firmware (`src/`, ~25k LOC of C++ excluding the embedded font headers).** The reader core is small and clean; the application shell is a monolith:
  - `src/app/App.cpp` — **6,154 lines**, the god-object that owns state machine, menus, touch, persistence, battery, OTA, WiFi, screensavers, focus-timer, sync.
  - `src/reader/ReadingLoop.{cpp,h}` — 886 + 61 lines, the pacing/playback engine (pure logic, no I/O).
  - `src/reader/BookWordSource.h` — 12-line abstract interface (`wordCount`, `wordAt`, `prefetchAround`).
  - `src/reader/BookContent.h` — book metadata structs (`ChapterMarker`, `paragraphStarts`, in-RAM `words`).
  - `src/storage/IndexedBookStore.{cpp,h}` — 175 + 71 lines, the flash-backed `BookWordSource`.
  - `src/storage/StorageManager.{cpp,h}` — 85k of book discovery, EPUB→`.rsvp` conversion, index build.
  - `src/display/DisplayManager.cpp` — 127k of rendering; six embedded fonts (`Embedded*Font*.h`) totalling ~5.4 MB of generated glyph tables (serif, Atkinson Hyperlegible, OpenDyslexic at two sizes each).
  - `src/sync/CompanionSyncManager.cpp` (64k), `src/usb/UsbMassStorageManager.cpp`, `src/storage/EpubConverter.cpp` (82k) — on-device EPUB conversion.
- **iOS companion (`ios/RSVPNanoCompanion/`).** Full SwiftUI app: `ContentView.swift` (61k), `EpubConverter.swift`, `RsvpConverter.swift` (18k), `NanoClient.swift` (BLE), share extension. The README notes Android is served only by the web companion; native Android is "next areas of work."
- **Web (`web/`).** `index.html` (29k) + `library.js` (40k, the browser-side EPUB→`.rsvp` converter covered in the prior report) + `install-firmware.js` (WebSerial flasher).
- **Tooling (`tools/`).** `epub_to_rsvp.py`, `sd_card_converter/convert_books.py`, font generator, release scripts.
- **Tests (`test/test_pacing/test_main.cpp`, 626 lines).** Host-side Unity tests over `ReadingLoop` (see Other Solved Problems).

**Maturity:** Active, single-author, structured project — CI workflows (`.github/workflows/test.yml`, `release.yml`, `pages.yml`), versioned releases, OTA update path, three companion surfaces. The reader logic is production-grade and tested; the app shell is a large, tightly-coupled single file. For garmin_RSVP, the lesson is the inverse topology the brief already calls out: RSVP Nano does conversion *on-device* (EpubConverter in firmware), which is exactly what the watch cannot do — so only the reader core and its `BookWordSource` seam transfer, not the storage/conversion stack.

→ **garmin_RSVP mapping:** Copy the module boundary (`ReadingLoop` + `BookWordSource` interface) as-is conceptually. Do **not** copy the App.cpp monolith pattern — Monkey C with 768 KB heap and a watchdog needs the reader, view, and input as separate classes from day one. The on-device EPUB/index pipeline (`StorageManager`, `EpubConverter`) does not transfer: that work lives in the Android companion.

---

## Reading Loop and Playback State

**Where the state lives.** Playback state is *not* in `ReadingLoop` — the loop is a pure pacing engine. The app-level state machine is `enum class AppState { Booting, Paused, Playing, Menu, CompanionSync, UsbTransfer, Standby, Sleeping }` (`src/app/AppState.h`). `ReadingLoop` only holds `currentIndex_`, `lastAdvanceMs_`, `wpm_`, `pacingConfig_`, the current word, and the word source (`src/reader/ReadingLoop.h:54-60`).

**Advancing words.** `ReadingLoop::update(nowMs, allowCatchUp)` (`ReadingLoop.cpp:596-614`) is time-driven, not tick-driven. Each call computes `currentWordDurationMs()` and, if `nowMs - lastAdvanceMs_ >= durationMs`, does `lastAdvanceMs_ += durationMs; advance(1)`. Crucially it advances by **adding the duration back** rather than snapping `lastAdvanceMs_ = nowMs`, so timing does not drift, and it can **catch up to 4 words** in one call (`kMaxCatchUpWords = 4`, line 131) if the main loop stalled — but only when `allowCatchUp` is true.

**Per-word duration is computed at read time.** `currentWordDurationMs()` (lines 624-634) = `60000/wpm` base interval + `pacingBonusMsForWord()`, derived live from the word's characters and the *next* word's leading case. This is the architecture's defining choice: the stream carries no timing (see Buffering section and the Conflicts section).

**WPM changes mid-playback** take effect on the very next word. `adjustWpm(delta)` (lines 726-752) uses an adaptive step: `kLowWpmStep=10` below 100 WPM, `kHighWpmStep=25` at/above it, clamped to `[kMinWpm=10, kMaxWpm=1000]`, and snaps cleanly to the 100 boundary when crossing. `setWpm` clamps to the same range. Because duration is recomputed every `update()`, no state needs flushing — the change is just `wpm_ = nextWpm`.

**Start-of-session behavior: no countdown, no ramp-up.** `setState(Playing)` calls `reader_.start(nowMs)` which is literally `lastAdvanceMs_ = nowMs;` (line 594) — the first word displays for its normal duration and playback begins immediately. There is no Spritz-style "3-2-1" countdown and no speed ramp. The only "settling" affordance is the chapter-transition card (below). `begin()` (lines 564-568) resets index to 0.

**End-of-chapter behavior: a 1.4 s transition card.** When `advance()` crosses a chapter marker, `maybeStartChapterTransition()` (`App.cpp:5258-5287`) seeks to the chapter's word index, sets `chapterTransitionVisible_`, and shows `renderChapterTransition()` — a `CHAPTER N` + title status screen — for `kChapterTransitionMs = 1400` (line 79). During the card, `updateReader` short-circuits; when it expires, `updateChapterTransition` (lines 5243-5256) calls `reader_.start(nowMs)` and resumes. This is the closest thing to a "settling pause," and it only happens at chapter boundaries.

**End-of-book behavior: silent stop at the last word, auto-pause.** `advance()` for a loaded book clamps at `count-1` and returns `false` when it cannot move (`ReadingLoop.cpp:783-798`); `atEnd()` is `currentIndex_+1 >= count` (lines 658-661). When `update()` gets `advance(1) == false` it stops. There is no "book finished" screen — the reader simply parks on the final word. Because `updateState()` (App.cpp:946-979) drops to `Paused` whenever `touchPlayHeld_/playLocked_/pauseAtSentenceEndRequested_` are all false, finishing a book leaves you paused on the last word. (The demo-text path instead *wraps* via modulo, lines 789-791 — book mode does not.)

→ **garmin_RSVP mapping:** Copy the time-driven, drift-free advance (`lastAdvanceMs_ += duration`) and the "recompute interval each word so WPM changes are instant" pattern — both translate directly to a Monkey C `Timer`/`onUpdate` loop. Copy the catch-up cap (bound how many words you skip after a stall) — relevant on a watch where the UI thread can be preempted. Copy the chapter transition card as the natural place to *also* trigger a chunk pre-fetch over BLE. **Reconsider the missing countdown/ramp:** on a wrist at arm's length the first word arriving instantly is jarring; a 3-word ramp or a 1 s "ready" beat is cheap to add and the author simply didn't. The "park silently on last word" end-of-book is a small UX gap worth closing with an explicit "Finished" state given success-criterion #2 (finish a real book).

---

## ORP Rendering and Display Design

**Pivot-letter selection.** `findFocusLetterIndex(word)` (`DisplayManager.cpp:749-774`) counts only "word characters" (letters/digits, punctuation excluded) and picks an ordinal by length via `orpOrdinalForLength()` (lines 733-747): length ≤1 → 0th char, ≤5 → 1st, ≤9 → 2nd, ≤13 → 3rd, else 4th. So short words anchor near the front, long words drift toward (but never past) the middle — the classic Spritz heuristic, capped at the 5th letter. Punctuation is skipped when counting, so leading quotes/brackets don't shift the pivot.

**Horizontal alignment around the ORP.** The pivot is pinned to a vertical anchor line at `anchorX = virtualWidth * anchorPercent / 100`, and the word is positioned so the pivot letter's center sits on it: `x = anchorX - layout.focusCenterX` (`rsvpStartX`, lines 776-797). Default `anchorPercent = 35` (`DisplayManager.h:21`), configurable 30–60% (`kTypographyAnchorMin/Max = 30/60`, DisplayManager.cpp:80-81) — i.e. the focal point sits left of center, not centered. Long words are clamped to side margins (`kRsvpSideMargin = 12`) so they never run off-screen, which can pull the pivot off the anchor for very wide words (lines 789-796) — he prioritizes showing the whole word over perfect anchor alignment.

**Pivot highlight color.** The focus letter is drawn in **red**: `kFocusLetterColor = 0xF800` (pure RGB565 red), or `kNightFocusColor = 0xFA80` in night mode (lines 33, 35; `focusColor()` 1078-1083). The highlight is a per-glyph color swap in the draw loop: `(highlightFocus && i == focusIndex) ? focusColor() : wordColor()` (e.g. lines 1651-1657). It is toggleable via `TypographyConfig::focusHighlight` (default `true`).

**Guide marks / crosshair.** `drawRsvpAnchorGuide(anchorX, textY, textHeight)` (lines 1611-1629) draws a Spritz-style guide: a thin horizontal line above and below the word, each **split with a gap** around the anchor (`guideHalfWidth=20`, `guideGap=4`, both configurable), plus a short vertical **tick** at the anchor on the top and bottom edges (`kRsvpGuideTickHeight = 5`). The ticks use the focus color when highlight is on, so the eye is led to the pivot column. This is two horizontal rules + two centered ticks, not a full crosshair through the word.

**Context / "phantom" words.** Beyond the focal word, `renderPhantomRsvpWord` (lines 1927+) draws the preceding and following text *dimmed* (alpha-blended `kPhantomAlphaMedium`) immediately left and right of the current word, with a small gap (`kPhantomCurrentGapMedium`). This gives peripheral context without competing with the focal word — toggled by `phantomWordsEnabled_` (default true, App.cpp). Distinct from the full scroll/context view (Rewind section).

**Long words / fonts.** Multiple font scales exist (`fontSizeLevel`, `chooseTextScale`); a dedicated 70-px font (`drawRsvp70WordAt`, `EmbeddedSerifFont70.h`) is used at the medium size. Three typefaces: Standard serif, OpenDyslexic, Atkinson Hyperlegible (`ReaderTypeface`, DisplayManager.h:10-14). Words wider than the panel are not truncated or wrapped — they are margin-clamped and shown whole (the pivot just drifts off-anchor).

→ **garmin_RSVP mapping:** Copy the ORP algorithm wholesale — `orpOrdinalForLength` is a 6-line pure function, trivially portable to Monkey C, and is the exact Spritz behavior MVP feature #1 needs. Copy the anchor-at-35% (not centered) decision and the per-glyph red pivot. **Adapt the geometry to the 454×454 round AMOLED:** the side-margin clamp matters more on a *round* screen — long words near the edges hit the bezel curve, so compute usable width per text row (chord of the circle at that y), not a flat rectangle. The split-guide-with-ticks transfers but should be drawn inside the safe circular area. The dimmed phantom-context words are a strong feature to copy (cheap, improves recovery) but cost peripheral horizontal space the round screen lacks — consider a single trailing/leading faded word rather than full lines. Font choice: AMOLED on a watch wants a bold, high-contrast face; Atkinson Hyperlegible is a good copy candidate and is OFL-licensed (`third_party/atkinson-hyperlegible/OFL.txt`).

---

## Rewind, Pause, and Recovery UX

This is the area the author invested the most UX thought in, and it directly answers MVP feature #5.

**Two-stage pause ("pause at sentence end").** A tap while playing does **not** stop instantly by default. `requestReaderPauseAtSentenceEnd()` (`App.cpp:1860-1881`) sets `pauseAtSentenceEndRequested_ = true`; `shouldFinalizeReaderPause()` (1883-1894) then waits until the current word both *fully elapsed* and `currentWordEndsSentence() || atEnd()`, only then calling `finalizeReaderPause()` → `Paused`. The rationale (README "Settings → Word pacing"): stopping mid-sentence loses context, so it coasts to the next sentence boundary. This is user-selectable: `PauseMode::{SentenceEnd, Instant}` (`App.h:117-120`); Instant pauses immediately (1867-1870). Sentence detection reuses the pacing engine's `wordEndsSentenceAt()` (`ReadingLoop.cpp:846-865`), which honors abbreviations (`Mr.`, `e.g.`) and dotted initialisms so it doesn't false-stop.

**Sentence rewind via an edge tap.** Tapping a dedicated far-left hint region (`handlePreviousSentenceTap`, `App.cpp:1728-1750`; hint drawn by `drawPreviousSentenceHint`) calls `ReadingLoop::rewindSentence()` (`ReadingLoop.cpp:711-724`): it jumps to the start of the current sentence, or — if already *at* a sentence start — to the start of the **previous** sentence. Implemented via `sentenceStartAtOrBefore()` (867-885) walking back until the prior word ends a sentence. After a rewind it auto-pauses (if playing) and immediately persists position (`saveReadingPosition(true)`). This is his answer to "I glanced away" — sentence-granular, one tap, no menu.

**Word-granular scrub + browse (while paused).** On a paused screen, the author overloads touch into intents (`enum TouchIntent { None, PlayHold, Scrub, BrowseScroll, Wpm }`, `App.h:72-78`):
- **Horizontal swipe = scrub by words.** `applyScrubTarget` → `reader_.seekRelative(startWordIndex, targetSteps)` (`App.cpp:2111-2124`), relative to where the gesture started, so it's a rubber-band scrub, not incremental.
- **Hold near top/bottom = continuous browse-scroll.** `applyBrowseHoldScroll` (2167-2194) integrates a velocity (`browseScrollRatePermille`, faster the further from center, with a neutral dead-zone) into a fractional word offset — a momentum-free auto-scroll for skimming.
- **Vertical swipe = WPM.** Up/down adjusts WPM with on-screen feedback.
- **Hold-to-play / release-to-pause.** `touchPlayHeld_`: holding the screen plays, releasing pauses (release path at `applyPausedTouchGesture` 1938-1946). **Double-tap toggles a locked play** (`playLocked_`, `handleReaderTap` 1832-1842) so you don't have to keep a finger down.

**What's shown on pause.** Pausing flips on the **context view**: `contextViewVisible_` triggers `renderContextPreview()` (`App.cpp:6067-6084`), which renders a multi-word **scroll view** (`DisplayManager::renderScrollView` over a window of `ContextWord`s, with paragraph-start flags and the current word marked) — so the moment you stop, you see the sentence/paragraph around your position, not a frozen single word. Scrubbing and browsing keep this context view live so you can read while seeking.

→ **garmin_RSVP mapping:** Copy the **two-stage "pause at sentence end" with an Instant toggle** — it is the single best recovery idea in the project and is pure logic over the word stream (sentence-end flags can come from the phone in the stream, even cheaper than his read-time detection). Copy **sentence rewind** (`rewindSentence` is ~12 lines, portable) as the primary implementation of MVP #5; an edge tap or a dedicated button maps cleanly to the Fenix 8's 5 buttons. Copy **"show context on pause"** — directly serves the "glanced away" failure mode and reframes pause from "frozen word" to "here's where you are." **Adapt the gesture overloading:** his rich touch-intent model assumes a flat rectangular touchscreen; on a round watch with 5 physical buttons, map play/pause and WPM to buttons (reliable, eyes-free) and reserve touch for the scrub/context-browse, which needs the larger gesture surface. Word-granular scrub requires random `wordAt(index)` access — fine on the watch *if* the target word is in a buffered chunk; scrubbing past the buffer must trigger a BLE fetch (a real latency consideration his SD-backed design doesn't have).

---

## Buffering, Indexing, and Seeking

This is the most structurally relevant section for the watch: RSVP Nano reads arbitrarily large books from flash through a small RAM window — exactly the watch's "buffer a chunk, request more" problem.

**The seam: `BookWordSource`.** A 3-method virtual interface (`src/reader/BookWordSource.h`): `wordCount()`, `wordAt(index)`, `prefetchAround(index)`. `ReadingLoop` holds a `BookWordSource*` and is otherwise storage-agnostic (`ReadingLoop.cpp:807-810, 813-831`). Small books can also be loaded fully into a `std::vector<String>` (`setWords`); large books use the indexed store. **This is the exact extension point for a Garmin "words from a BLE-delivered chunk" source.**

**The `.ridx`/`.rdat` sidecar design** (`src/storage/IndexedBookStore.h`). On first open, the firmware builds two files next to the book (README: "rebuilt automatically if the source book changes"):
- **`.rdat`** — the normalized word *data*: all words concatenated as bytes (no separators).
- **`.ridx`** — a fixed-layout binary index. **Header (52 bytes, static-asserted)**: `magic = 0x58444952` ("RIDX"), `version = 4`, header/record sizes, `sourceSize`, `sourceFingerprint` (for staleness detection), `wordCount`, `paragraphCount`, `chapterCount`, and offsets to the records/paragraphs/chapters sections + `dataSize` (`IndexedBookStore.h:12-26`, asserts at `IndexedBookStore.cpp:6-8`). **Per-word record (8 bytes)**: `uint32 offset` into `.rdat`, `uint16 length`, `uint16 flags` (`WordRecord`, lines 28-32). **Chapter record (72 bytes)**: `uint32 wordIndex` + a 64-char inline title (lines 34-38).

So the **index granularity is one record per word** — every word is randomly addressable by absolute index in O(1): read the 8-byte record at `recordsOffset + index*8`, then read `length` bytes at `offset` in `.rdat`. There is no compression and no delta-coding; it trades flash space for dead-simple seeking.

**The RAM window.** `IndexedBookStore` never holds the whole book. `wordAt(index)` checks an in-RAM cache of **256 words** (`kWordCacheSize = 256`, `IndexedBookStore.h:42`); on a miss, `loadWordWindow(index)` (`IndexedBookStore.cpp:123-174`) computes the aligned block `(index/256)*256`, bulk-reads those 256 records (one seek + one read), then bulk-reads the contiguous `.rdat` byte span `[firstOffset, lastOffset+lastLen)` in a single read, and slices it into 256 `String`s. So a cache miss is **two file reads** regardless of where you jump. `prefetchAround(index)` (lines 85-93) warms the same window and is called from `ReadingLoop::setCurrentWordFromIndex()` on every position change (`ReadingLoop.cpp:807-808`) — so sequential reading triggers a refill only every 256 words, and a seek triggers exactly one refill.

**Seeking.** Absolute: `ReadingLoop::seekTo(wordIndex)` clamps and sets index (`ReadingLoop.cpp:667-680`). Relative: `seekRelative(base, steps)` clamps for books (wraps for demo) (682-709). Both just move the index; the window reload is lazy on the next `wordAt`. **Chapter navigation** uses `chapterMarkers_` (absolute word indices from the index) — the chapter picker calls `reader_.seekTo(chapterWordIndex)` (App.cpp). Paragraph starts (`paragraphStarts_`) are likewise absolute word indices, used for context-view paragraph flags.

**Validation/robustness.** `open()` rejects on magic/version/size mismatch or `wordCount==0`; `loadWordWindow` bounds-checks every record's `offset+length` against `dataEnd`/`dataSize` and bails on corruption (lines 138, 157-160), returning empty strings rather than crashing.

→ **garmin_RSVP mapping (map this onto the watch explicitly):**
- **Copy the absolute-word-index model as the universal coordinate.** Everything — position, chapters, paragraphs, seek — is an absolute word index into the book. This is exactly what our "resume never lies" and chunked-storage plans need: the watch stores chunks, but position is one integer (absolute word index) that is stable across re-chunking. Adopt this as the protocol's position unit.
- **`BookWordSource` → a `ChunkedWordSource` on the watch.** Replace SD reads with "is word N in a resident chunk? if yes return it; if no, request the chunk containing N over BLE and show a brief buffering state." The 256-word window is a good starting chunk size; tune to BLE message size and the Fenix 8 heap (768 KB).
- **The per-word 8-byte index transfers as the *phone-side* chunk manifest.** The watch does not need to build `.ridx` (it can't parse EPUB), but the companion can produce the same offset/length table so the watch can locate word N within a delivered chunk in O(1). The `sourceFingerprint` staleness field maps to a book-version/hash in the protocol so the watch can detect "this chunk is from an old conversion."
- **Conflict surfaced here:** his `flags` (uint16 per word) are unused for timing — timing is computed at read time. Our plan would instead put per-word *duration* (or sentence/paragraph/pause flags) into that 16-bit field at conversion time. See the Conflicts section; the watch favors baking at least the *structural* flags (sentence-end, paragraph-start, dwell multiplier) into the per-word record, because recomputing them in Monkey C per word is more expensive than on ESP32.

---

## Position Persistence

RSVP Nano's persistence model is the reference implementation of "resume never lies," and it is simple.

**Storage.** ESP32 NVS via the Arduino `Preferences` library (`App.h:420`, `App.cpp` `preferences_`). Keys are per-book, derived from a hash of the book path: `bookPositionKey` = `"p%08lx"`, `bookWordCountKey` = `"c%08lx"`, `bookRecentKey` = `"r%08lx"` (`App.cpp:4954-4970`). So each book has its own bookmark; switching books and back resumes each independently.

**What is saved.** On save (`saveReadingPosition`, `App.cpp:4863-4883`): the current word index (`reader_.currentIndex()` — an **absolute word index**), the book path, the book's word count, a legacy global word index (migration), and the current WPM. Plus a monotonically increasing "recent" sequence number per book (`markBookRecent`) used to sort the library by recency.

**When it is saved (debounced + on transitions, not every word):**
- **Periodically while playing:** `maybeSaveReadingPosition` runs every main-loop tick but no-ops unless `state_ == Playing` and `kProgressSaveIntervalMs = 15000` (15 s) have elapsed (`App.cpp:55, 1020-1031`). NVS has limited write endurance, so he debounces to ~once per 15 s rather than per word.
- **Forced on every meaningful transition:** `saveReadingPosition(true)` (the `force` path) on play→pause (`setState`, `App.cpp:937-939`), on opening the menu while playing (1224-1226), after a sentence rewind (1744), after a chapter jump, etc. The `force` flag bypasses both the 15 s debounce and the "index unchanged" guard (`4869-4871`).

**What survives power-off.** NVS is flash-resident, so the last *saved* position survives reboot and power loss. Worst case you lose ≤15 s of *unforced* progress (if it died mid-play between debounced saves), but every deliberate stop (pause/menu/power-off path) forces a save first, so normal use never loses your place.

**Resume on open.** `loadBookAtIndex` (`App.cpp:4885-4952`) opens the index, then `savedWordIndexForBook()` (4994-5009) reads the per-book key (with one-time migration from the legacy global key) and `reader_.seekTo(savedWordIndex)`. If no saved position, it starts at 0. The restore is logged.

→ **garmin_RSVP mapping:** Copy this model almost verbatim — it is precisely the "resume never lies" success criterion. **Position = one absolute word index per book**, persisted to watch storage (Monkey C `Storage`/`Application.Properties`, the NVS analogue). Copy the **debounce-while-playing + force-on-transition** discipline: watch flash also has write-endurance limits and a 15 s debounce with forced saves on pause/exit is a good default. **Adapt for the watch↔phone sync** the brief requires: his model is single-device; garmin_RSVP must reconcile watch and phone positions (last-writer-wins on a timestamp, or "max word index" — both are trivial because position is one comparable integer). Copy the per-book keying (hash of book id) so multiple books resume independently. The `force`-on-every-stop pattern is what makes "survives app restart / watch reboot" true — replicate it on every state exit and on BLE disconnect.

---

## Controls and Settings

**Physical controls (two buttons + capacitive touch; `App.cpp`, README control table).** The board has a **BOOT** and a **PWR** button plus the AXS15231B touch panel (`TouchHandler.cpp`). Mapping:
- **PWR short-press** = toggle menu / back (`toggleMenuFromPowerButton`, `App.cpp:1193-1214`).
- **PWR long-hold** (`kPowerOffHoldMs`) = power off (`handlePowerButton`, 1175-1179).
- **BOOT short-press** = cycle brightness; **BOOT long-hold** (`kThemeToggleHoldMs`) = cycle theme (`handleBootButton`, 1091-1136). Note: the *physical buttons do not control play/pause or WPM* — those are touch-only.
- **PWR + BOOT together** = standby combo (`handleStandbyCombo`, 1033+).
- **Touch** carries all reading control: hold-to-play/release-to-pause, double-tap = locked play, tap-left-edge = sentence rewind, swipe horizontal = scrub, swipe vertical = WPM, hold top/bottom = browse-scroll (see Rewind section). Buttons are debounced edge-detectors with press/release/hold-duration events (`ButtonHandler.cpp`).

**Settings (on-device menus; `App.h` `MenuScreen`, README Settings).** A real settings tree: `SettingsHome → SettingsDisplay / SettingsPacing / WifiSettings / TypographyTuning`, plus `BookPicker`, `ChapterPicker`, `FocusTimer`, OTA confirm, SD-repair confirm.
- **WPM:** 10 → 1000, adaptive step (10 below 100, 25 above) — see Reading Loop.
- **Word pacing:** three independent delays (`pacingLongWordDelayMs_`, `pacingComplexWordDelayMs_`, `pacingPunctuationDelayMs_`, default 200 ms each, `App.h:458-460`) plus scale percents; pause mode (Instant vs SentenceEnd); RSVP vs Scroll reader mode (`ReaderMode`, `App.h:26-29`).
- **Typography:** typeface (Standard / OpenDyslexic / Atkinson Hyperlegible), font size, focus highlight on/off, letter tracking, anchor position (30–60%), guide half-width, guide gap (`TypographyConfig`, `DisplayManager.h:16-23`).
- **Display:** theme (dark/night), brightness levels, UI language (localized — `Localization.h`), **handedness** (left/right, flips the UI orientation — `HandednessMode`, `App.h:31-34`), and per-overlay toggles for battery / chapter / progress while playing (`readerBatteryVisibleWhilePlaying_` etc., `App.h:542-544`).
- **Footer metric** cycles percentage / chapter-time-remaining / book-time-remaining by tapping the footer (`handleFooterMetricTap`, 1752-1788); **battery label** cycles percent / time / voltage by tapping it (`handleBatteryBadgeTap`, 1790-1819).
- **ASCII mode:** not a setting per se, but `LatinText.h` provides an ASCII-fallback that maps accented letters to base letters (tested: `test_ascii_fallback_*`) for the limited glyph set.

→ **garmin_RSVP mapping:** The Fenix 8 has **5 buttons + touch** — *more* physical input than RSVP Nano. **Reject his touch-only play/pause/WPM** and instead bind the reading-critical controls to buttons (eyes-free, reliable, glove-friendly, no false touches while running): e.g. START/STOP = play/pause, UP/DOWN = WPM, BACK = sentence rewind, and reserve touch for scrub/context-browse. Copy the *settings set* (WPM range + adaptive step, three pacing delays, pause mode, typeface, anchor %, focus-highlight toggle, handedness) — these are exactly the knobs a polished reader needs and he has validated the defaults. Copy the tap-to-cycle footer/battery metric idea (cheap, no menu). The localization, themes, focus-timer, WiFi, and OTA menus do **not** transfer (CIQ has its own settings/Connect IQ Store mechanisms and no WiFi/OTA). Keep the watch settings minimal for MVP (brief defers typography options to "later") — the value here is knowing *which* knobs proved worth having.

---

## Other Solved Problems

**Host-side test suite (`test/test_pacing/test_main.cpp`, ~60 tests).** Runs on the dev host (Unity framework, `test/support/Arduino.h` stubs `String`/Arduino types), so the pure reader logic is testable without hardware. Coverage:
- WPM interval math, adaptive stepping, 100-boundary crossing, clamping (`test_wpm_*`, `test_adjust_wpm_*`).
- Pacing bonuses: long-word tiers, compound words, all-caps, comma/clause/dash/ellipsis/sentence pauses, abbreviation and dotted-initialism suppression, closing-quote/paren preservation (`test_comma_pause` … `test_compound_word_bonus`).
- **Internationalization:** accented/Baltic/Czech/Hungarian/Sámi letters counted as readable, custom vowels affecting syllable bonus, ASCII fallback mapping, Spanish inverted punctuation (`test_*_latin_*`, `test_ascii_fallback_*`).
- **Seek/scrub/rewind:** `seekTo` clamping, scrub forward/back/clamped, `seekRelative` from a base index, `rewindSentence` to current/previous sentence start, clamped at book start, ignoring abbreviation periods (`test_seek_*`, `test_scrub_*`, `test_rewind_sentence_*`).
- **Streaming:** `FakeWordSource` verifies `wordAt` streaming and that `prefetchAround` is called (`test_word_source_streams_words_and_prefetches`).
- **The timing-is-WPM-invariant contract:** `test_word_pacing_bonus_at_is_invariant_to_wpm` and `test_word_pacing_bonus_plus_interval_equals_current_duration` assert that the per-word *bonus* depends only on the word (not WPM) and that `duration = 60000/wpm + bonus`. This is the formal statement of the read-time-timing design.

**Malformed-book / error handling.** `IndexedBookStore::open` validates magic/version/sizes and refuses bad indices; `loadWordWindow` bounds-checks every record against `dataSize` and returns empty rather than reading OOB (`IndexedBookStore.cpp:138, 157-160`). At the app level, `ensureCurrentBookWordAvailable` / `handleCurrentBookReadFailure` (`App.h:369-370`) handle a mid-read failure, and the README states "If a book cannot be prepared, the device should return to the menu with a readable reason instead of silently failing." There is also an SD-card diagnostic/repair flow (`StorageManager::diagnoseSdCard`, `repairSdCardFolders`).

**Battery/power decisions.** `BatteryLabelMode` (percent/time/voltage), a filtered voltage→percent estimate with a runtime-remaining anchor, low-battery warning overlay, and battery-protection logic (`updateBatteryStatus`, `handleBatteryProtection`, `showLowBatteryWarning`, `App.h:195-198`). Standby screensavers (Game-of-Life / Maze / Voronoi / screen-off) and a Sleeping state for power saving.

**Multi-book library on device.** `/books/books` and `/books/articles` folders; `StorageManager` lists books with titles/authors/progress; library sorted by the per-book "recent" sequence; per-book resume. Articles (from RSS, `RssFeedManager.cpp`) are a second content type alongside books.

**Reading-time estimation.** A prefix-sum cache of per-block pacing bonuses (`wordBonusBlockPrefixSumMs_`, built incrementally in `updateTimeEstimateBuild` to avoid blocking) powers "time remaining in chapter/book" — computed by summing the same read-time bonuses over the remaining words (`estimatedReadingTimeRemainingMs`).

→ **garmin_RSVP mapping:** **Copy the host-side test discipline** — extract the watch's pacing/seek/sentence logic into pure functions and unit-test them off-device (Monkey C has a test runner; or test the shared logic in the Kotlin companion if timing is baked there). Copy the **index-validation + bounds-check-and-degrade** posture for malformed/incomplete chunks arriving over BLE (return empty/buffering, never crash the watch app). The **battery/standby/screensaver** machinery does **not** transfer (Garmin OS owns power management and the always-on display). The **reading-time-remaining prefix-sum** is a nice copy *if* timing is baked into the stream — the phone can ship a cumulative-duration array so the watch shows "time remaining" with no computation. The article/RSS path is out of scope for garmin_RSVP MVP.

---

## Research Synthesis

### Executive Summary

RSVP Nano is a far more complete reference than "an ESP32 demo" — a v0.0.5 release with a tested reader core, on-device EPUB conversion, three companion surfaces, and a thoughtfully designed reading UX. For garmin_RSVP, the high-value finding is that the **reader is a clean, pure, fully unit-tested engine** (`ReadingLoop`) decoupled from storage through a 3-method interface (`BookWordSource`) and from rendering through `DisplayManager`. That seam is exactly where the watch plugs in BLE-delivered chunks. The author has already solved, and the code documents, the hard reader-side problems: Spritz ORP geometry, drift-free time-driven advancement, instant mid-play WPM changes, two-stage "pause at sentence end," sentence-granular rewind, "show context on pause," O(1) absolute-word-index seeking over a small RAM window, and debounced-but-forced position persistence with per-book bookmarks. Almost all of it copies or adapts.

The one strategic divergence is timing: RSVP Nano **computes per-word dwell at read time** from the word string + WPM (the `.rsvp`/`.ridx` stream carries no timing), whereas our prior reports plan to **bake timing into the phone-produced stream**. The evidence says the watch should bake it — Monkey C is slower per word than ESP32-C++, the companion already parses the text, and the brief explicitly wants variable timing "baked into the word-stream format from day one." His engine is still valuable as the *reference algorithm* for the companion to implement.

### Decisions to Copy

1. **The `BookWordSource` seam** — a tiny interface between the reading loop and "where words come from." (`BookWordSource.h`)
2. **Absolute word index as the universal coordinate** for position, chapters, paragraphs, seek, and persistence. (`IndexedBookStore`, `App.cpp` persistence)
3. **Spritz ORP algorithm** — `orpOrdinalForLength` (front-loaded, capped at 5th letter) + anchor at ~35% width + red per-glyph pivot. (`DisplayManager.cpp:733-797`)
4. **Drift-free time-driven advance** (`lastAdvanceMs_ += duration`) with a catch-up cap. (`ReadingLoop.cpp:596-614`)
5. **Two-stage "pause at sentence end" with an Instant toggle.** (`App.cpp:1860-1894`)
6. **Sentence rewind** (`rewindSentence`, ~12 lines) as MVP feature #5. (`ReadingLoop.cpp:711-724`)
7. **"Show context window on pause"** instead of a frozen single word. (`renderContextPreview`, `App.cpp:6067-6084`)
8. **Position persistence: per-book key, save WPM+index, debounce-while-playing + force-on-every-transition.** (`App.cpp:4863-4883, 1020-1031, 937-939`)
9. **256-word windowed reads** as the chunk model (two reads per cache miss). (`IndexedBookStore.cpp:123-174`)
10. **Host-side unit tests over the pure reader logic.** (`test/test_pacing/test_main.cpp`)
11. **Bounds-check-and-degrade** on malformed/short data — return empty, never crash. (`IndexedBookStore.cpp:138, 157-160`)
12. **The proven settings set** — WPM 10–1000 adaptive step, three pacing delays, pause mode, typeface, anchor %, focus-highlight, handedness.

### Decisions to Adapt

1. **Controls → buttons.** Fenix 8 has 5 buttons + touch (more than Nano's 2 + touch). Bind play/pause/WPM/rewind to buttons (eyes-free, no false touches while moving); reserve touch for scrub/context-browse. (vs. Nano's touch-only reading control, `App.cpp` handlers)
2. **ORP geometry for a round 454×454 AMOLED.** Compute usable text width per row as the circle's chord, not a flat rectangle; keep guides/phantom words inside the safe circle; consider one faded leading/trailing word instead of full phantom lines (less horizontal room). (`drawRsvpAnchorGuide`, `renderPhantomRsvpWord`)
3. **Word source → `ChunkedWordSource` over BLE.** Same interface, but a `wordAt` miss triggers a chunk request + brief buffering state (Nano's SD reads are effectively instant; BLE is 1–2 s). (`IndexedBookStore` → watch)
4. **Persistence → two-device reconciliation.** Single integer position makes watch↔phone sync trivial (max-index or timestamped last-writer-wins). (`saveReadingPosition`)
5. **Reading-time-remaining** — ship a cumulative-duration array from the phone instead of computing prefix sums on-watch. (`wordBonusBlockPrefixSumMs_`)

### Decisions to Reject (and why)

1. **On-device EPUB conversion / index build** (`EpubConverter.cpp`, `StorageManager::buildIndexedBook`) — the watch cannot and should not parse EPUB; this is the inverted-topology core of the brief. The companion does it.
2. **The App.cpp monolith** (6,154 lines, one class) — fine for a single-purpose firmware, wrong for a learning-curve Monkey C project; separate reader/view/input/sync from the start.
3. **Battery/standby/screensaver machinery** — Garmin OS owns power management and the always-on display; don't reimplement.
4. **WiFi/OTA/RSS/focus-timer/localization subsystems** — out of MVP scope and largely provided by the CIQ platform.
5. **No start-of-session countdown/ramp and silent end-of-book** — these are *gaps* in Nano, not features; garmin_RSVP should add a brief ready-state and an explicit "Finished" screen (success criterion #2).

### Conflicts with Prior Research Reports

**Conflict 1 — Where timing is computed (the big one).** RSVP Nano computes per-word dwell **at read time**: `ReadingLoop::durationForWord()` = `60000/wpm + pacingBonusMsForWord(word, nextWordLowercase, config)`, derived live from the word string every advance; the `.rsvp` stream and the `.ridx` per-word record (8 bytes: offset/length/flags) carry **no duration** (`ReadingLoop.cpp:534-560`, `IndexedBookStore.h:28-32`, `docs/demo-books/european-letter-demo.rsvp` is plain words). The host tests even formalize this: the bonus is *WPM-invariant* and `duration = interval + bonus` (`test_word_pacing_bonus_at_is_invariant_to_wpm`, `test_word_pacing_bonus_plus_interval_equals_current_duration`). Our prior reports recommend **baking timing into the phone-produced word-stream**. 
*Resolution — evidence favors our side for the watch.* (a) The brief explicitly wants variable timing baked into the format "from day one." (b) Monkey C is interpreted and slower per-operation than ESP32 C++; recomputing syllable/abbreviation heuristics per word on the watch wastes the cycles and heap the brief flags as tight. (c) The companion already parses the full text, so it can run *his exact algorithm* once at conversion time and emit a per-word duration (or a compact dwell-multiplier in the unused `flags` field). His read-time engine remains the **reference implementation** the companion should port. Caveat where *his* side wins: read-time timing makes live WPM changes free and keeps the stream tiny; the watch preserves the free WPM change by shipping the *bonus* (WPM-independent) and applying `60000/wpm + bonus` on-watch — i.e. bake the per-word *bonus*, not the absolute duration. That is the best-of-both synthesis.

**Conflict 2 — Chunk/window sizing.** Nano uses a fixed **256-word** RAM window with instant SD refills (`IndexedBookStore.cpp:128-129`). Prior reports discuss pre-loading chapter chunks into watch storage. These don't truly conflict — they operate at different layers — but the lesson is that Nano's *fine* 256-word window works because refill latency is ~0; over BLE (1–2 s) the watch needs **coarser pre-fetched chunks plus look-ahead** (prefetch the next chunk before the current one is exhausted), which his `prefetchAround` hook already models — just triggered earlier. Evidence favors prior reports' coarser chunking for the BLE layer, while copying his windowed-slice mechanics within a resident chunk.

**No conflict on ORP, rewind, pause, or persistence** — his implementations align with or strengthen the prior reports' recommendations and are adopted directly.

### Source Documentation

All files read directly from `https://github.com/ionutdecebal/rsvpnano` (branch `main`), via `raw.githubusercontent.com` and the GitHub trees API. **Access date: 2026-06-06.**

- `README.md` — controls table, settings overview, `.ridx`/`.rdat` purpose, library folders, error-handling intent, maturity (v0.0.5).
- `src/reader/ReadingLoop.cpp` / `.h` — pacing constants, read-time duration, time-driven advance, WPM stepping, seek/scrub/`rewindSentence`, sentence detection.
- `src/reader/BookWordSource.h` — the storage-abstraction interface.
- `src/reader/BookContent.h` — `ChapterMarker`, `paragraphStarts`, book metadata.
- `src/storage/IndexedBookStore.cpp` / `.h` — `.ridx` header/word/chapter record layout, magic/version, 256-word window, two-read refill, bounds checks.
- `src/storage/StorageManager.h` — book discovery, index build, EPUB conversion entry points.
- `src/app/App.cpp` (6,154 lines) / `App.h` / `AppState.h` — state machine, play/pause, sentence-end pause, sentence rewind, scrub/browse/WPM touch intents, chapter transition, position persistence (per-book keys, debounce + force), settings, controls.
- `src/display/DisplayManager.cpp` / `.h` — ORP pivot selection (`orpOrdinalForLength`, `findFocusLetterIndex`), anchor geometry (`rsvpStartX`), red focus color (`0xF800`), guide marks (`drawRsvpAnchorGuide`), phantom-context rendering, typography config, fonts.
- `src/input/ButtonHandler.cpp` / `.h`, `src/input/TouchHandler.cpp` / `.h` — button edge/hold detection; AXS15231B touch polling and orientation mapping.
- `test/test_pacing/test_main.cpp` — ~60 host-side Unity tests (WPM, pacing, i18n, seek/scrub/rewind, streaming, WPM-invariant-bonus contract).
- `docs/demo-books/european-letter-demo.rsvp` — confirms `.rsvp` carries plain words + `@chapter`/`@para` structure and **no per-word timing**.
- GitHub trees API (`/git/trees/main?recursive=1`) — full file inventory and sizes for the repository map.

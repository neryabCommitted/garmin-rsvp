# Precedent Extraction — RSVPnano Teardown + EPUB Parsing Research

UX-relevant facts extracted from the two technical research reports, for designing the
Garmin Fenix 8 RSVP watch app + Flutter companion. Source files:

- `technical-rsvpnano-reader-teardown-research-2026-06-06.md`
- `technical-epub-parsing-flutter-dart-research-2026-06-06.md`

RSVPnano = an existing ESP32 RSVP reading device (github.com/ionutdecebal/rsvpnano, v0.0.5),
torn down source-line-by-line. It is the direct precedent we are the Garmin analogue of.

---

## 1. How RSVPnano Presents Words (presentation layer)

### ORP / pivot-letter selection
- Picks one focal ("pivot") letter per word via `orpOrdinalForLength()` — counts only
  **word characters (letters/digits)**, punctuation excluded so leading quotes/brackets don't
  shift the pivot. Length-to-ordinal table (classic Spritz heuristic, capped at the 5th letter):
  - len ≤1 → 0th char
  - len ≤5 → 1st char
  - len ≤9 → 2nd char
  - len ≤13 → 3rd char
  - len ≥14 → 4th char
- Short words anchor near the front; long words drift toward (never past) the middle.
- (EPUB report cross-check: OpenSpritz uses ~length/2-capped instead; both are valid. Same
  discrete table is the "folk-standard" — confidence Medium, not an official Spritz spec.)

### Horizontal alignment around the ORP
- Pivot is pinned to a fixed vertical **anchor line**, NOT centered. `anchorX = width * anchorPercent/100`.
- **Default anchorPercent = 35%** (left of center). User-configurable 30–60%.
- Word positioned so the pivot letter's *center* sits on the anchor (`x = anchorX - focusCenterX`).
- Very wide words are **margin-clamped** (side margin 12 px) and shown whole — the pivot is
  allowed to drift off-anchor rather than truncating/wrapping the word. Whole-word visibility
  is prioritized over perfect anchor alignment.

### Focal-letter highlighting
- Pivot letter drawn in **red** (`0xF800` RGB565; `0xFA80` in night mode).
- Implemented as a per-glyph color swap in the draw loop.
- Toggleable via `focusHighlight` (default ON).

### Guide marks / crosshair
- Spritz-style guide: a thin horizontal line **above and below** the word, each split with a
  gap around the anchor (guideHalfWidth 20, guideGap 4, both configurable), plus a short
  vertical **tick** at the anchor column on top and bottom edges (tick height 5).
- Ticks use the focus (red) color when highlight is on, leading the eye to the pivot column.
- It is two horizontal rules + two centered ticks — NOT a full crosshair through the word.

### Context / "phantom" words
- Beyond the focal word, preceding and following text is drawn **dimmed** (alpha-blended)
  immediately left/right of the current word, with a small gap. Gives peripheral context
  without competing with the focal word. Toggled by `phantomWordsEnabled_` (default ON).
- Distinct from the full scroll/context view shown on pause.

### Per-word timing adjustments (computed at READ time from word string + WPM)
RSVPnano stores NO timing in the stream; it derives dwell live each advance:
`duration = 60000/wpm (base interval) + pacingBonus(word, nextWord, config)`.
The bonus is **WPM-invariant** (formally unit-tested). Bonus structure:
- **Word-length tiers** (extra chars beyond threshold, % per char): >6 chars +6%/char;
  >10 +9%/char; >14 +12%/char; **capped +170%**. Compound joiners (hyphen/slash) +14% each.
- **Complexity:** syllable groups beyond 2 → +%/group up to +50%; mixed letter+digit +22%;
  ALL-CAPS +14%; complexity **capped +85%**.
- **Trailing punctuation pauses:** comma +45%; dash +60%; semicolon/colon +80%; ellipsis +110%;
  sentence-end `! ?` +150%; period +135% — UNLESS `looksLikeAbbreviation()` (dotted initialisms,
  known titles like "Mr." get no pause). All three delays default 200 ms, separately configurable.

### Chunking
- One word at a time (no multi-word chunks). "Chunking" here = the windowed loading model
  (256-word RAM windows), not visual multi-word display.

### KEY DIVERGENCE for garmin_RSVP
RSVPnano computes timing on-device; the Flutter+Garmin plan **bakes timing into the phone-
produced stream**. Best-of-both synthesis recommended: ship the **WPM-invariant bonus** (or a
dwell tier) per word, and apply `60000/wpm + bonus` on-watch — keeps live WPM changes free while
not making Monkey C recompute heuristics per word.

---

## 2. Controls + noted strengths/weaknesses

### Physical controls (RSVPnano: 2 buttons + capacitive touch)
- **PWR short** = toggle menu / back. **PWR long-hold** = power off.
- **BOOT short** = cycle brightness. **BOOT long-hold** = cycle theme. **PWR+BOOT** = standby.
- NOTE: physical buttons do NOT control play/pause or WPM — those are **touch-only**.

### Touch (all reading control lives here)
- **Hold-to-play / release-to-pause.** Double-tap toggles a **locked play** (so you needn't keep
  a finger down).
- **Tap far-left edge region** = sentence rewind.
- **Horizontal swipe (while paused)** = scrub by words (rubber-band, relative to gesture start).
- **Vertical swipe** = WPM up/down with on-screen feedback.
- **Hold near top/bottom (while paused)** = continuous browse-scroll (velocity-integrated,
  faster further from center, neutral dead-zone).
- Touch intents modeled as `enum {None, PlayHold, Scrub, BrowseScroll, Wpm}`.

### WPM control
- Range **10–1000 WPM**, adaptive step: **10 below 100 WPM, 25 at/above 100**, snaps cleanly to
  the 100 boundary. Changes take effect on the **very next word** (duration recomputed each update).
- No start-of-session countdown and no speed ramp — first word displays immediately at full speed.

### Start / chapter / end behavior
- **Start:** instant, `start()` = `lastAdvanceMs_ = now`. No 3-2-1, no ramp.
- **Chapter transition:** a **1.4 s "CHAPTER N + title" card** when crossing a chapter marker —
  the only built-in "settling pause"; reader resumes after.
- **End of book:** silent — clamps on the last word and drops to Paused. No "Finished" screen.

### Strengths noted in teardown
- Drift-free, time-driven advance (`lastAdvanceMs_ += duration`, not `= now`) so timing doesn't
  drift; catch-up capped at 4 words after a stall.
- Two-stage "pause at sentence end" (below) — called the single best recovery idea in the project.
- Sentence-granular rewind (~12 lines, portable).
- "Show context on pause" reframes pause from a frozen word to "here's where you are."
- Clean separation: pure `ReadingLoop` engine + 3-method `BookWordSource` seam + `DisplayManager`.

### Weaknesses / gaps noted in teardown (see also §4)
- No start-of-session countdown/ramp — jarring at arm's length on a wrist.
- Silent end-of-book (no completion state) — a UX gap vs the "finish a real book" success criterion.
- Touch-only play/pause/WPM is wrong for a watch (false touches while moving, not eyes-free).
- The 6,154-line `App.cpp` god-object monolith — an anti-pattern to NOT copy.

---

## 3. Reading-position / progress model + resume

- **Universal coordinate = absolute word index** into the book. Position, chapters, paragraphs,
  seek, and persistence are ALL expressed as one integer absolute word index. Stable across
  re-chunking.
- **Per-book bookmark:** keys derived from a hash of the book path
  (`p%08lx` position, `c%08lx` word count, `r%08lx` recency). Each book resumes independently;
  switching books and back preserves each place.
- **What's saved:** current absolute word index, book path, book word count, current WPM, plus a
  monotonic "recent" sequence number used to sort the library by recency.
- **When saved — debounce + force discipline:**
  - Periodically while playing: every 15 s (`kProgressSaveIntervalMs = 15000`), no-op otherwise
    (flash write-endurance protection).
  - **Forced** on every meaningful transition: play→pause, opening menu, after sentence rewind,
    after chapter jump, etc. (bypasses the 15 s debounce + the "index unchanged" guard).
- **Survives power-off:** flash-resident; worst case lose ≤15 s of *unforced* progress, but every
  deliberate stop forces a save first, so normal use never loses your place.
- **Resume on open:** reads the per-book key, seeks to saved index (one-time migration from a
  legacy global key); starts at 0 if none.

### On-pause display (how users see where they are)
- Pausing flips on a **context view** — a multi-word **scroll view** of the surrounding
  sentence/paragraph with the current word marked and paragraph-start flags. Scrub/browse keep
  this live so you can read while seeking.

### Progress metrics shown
- **Footer metric** taps to cycle: percentage / chapter-time-remaining / book-time-remaining.
- **Battery label** taps to cycle: percent / time / voltage.
- Time-remaining is powered by a prefix-sum cache of per-block pacing bonuses.

### garmin_RSVP implications
- Adopt absolute-word-index as the protocol position unit — makes **watch↔phone sync trivial**
  (max-index, or timestamped last-writer-wins; one comparable integer).
- Copy debounce-while-playing + force-on-transition; also force on BLE disconnect.
- Per-book keying so multiple books resume independently.

---

## 4. UX failures / complaints / anti-patterns noted

1. **No start-of-session countdown or speed ramp.** First word arrives instantly at full WPM —
   jarring on a wrist. Teardown recommends garmin_RSVP ADD a brief ready-state / 3-word ramp.
2. **Silent end-of-book** (parks on last word, drops to Paused, no "Finished" screen). Teardown
   recommends an explicit "Finished" state for the finish-a-book success criterion.
3. **Touch-only reading controls** (play/pause/WPM not on buttons). Wrong for a watch worn while
   moving: false touches, not eyes-free, not glove-friendly. Bind to physical buttons instead.
4. **`App.cpp` 6,154-line monolith** — one god-object owns state machine/menus/touch/persistence/
   battery/OTA/WiFi. Explicitly an anti-pattern to NOT replicate; separate reader/view/input/sync.
5. **256-word RAM window assumes ~0 refill latency** (instant SD). Over BLE (1–2 s) a fine 256-word
   window would stall; needs coarser pre-fetched chunks + look-ahead (prefetch next chunk before
   exhausting current). Not a Nano "bug," but a transfer hazard.
6. **Margin-clamped long words** let the pivot drift off-anchor — acceptable trade, but on a round
   AMOLED long words near edges hit the bezel curve; must compute per-row usable width (chord).

---

## 5. Settings RSVPnano exposes

A real on-device settings tree (`SettingsHome → SettingsDisplay / SettingsPacing / WifiSettings /
TypographyTuning`, plus BookPicker, ChapterPicker, FocusTimer, OTA, SD-repair):

- **WPM:** 10–1000, adaptive step (10 below 100, 25 above).
- **Word pacing:** three independent delays (long-word, complex-word, punctuation; default 200 ms
  each) + scale percents; **pause mode (Instant vs SentenceEnd)**; reader mode (RSVP vs Scroll).
- **Typography:** typeface — **Standard serif / OpenDyslexic / Atkinson Hyperlegible**; font size
  (multiple scales incl. a dedicated 70-px font); **focus highlight on/off**; letter tracking;
  **anchor position 30–60%** (default 35); guide half-width; guide gap.
- **Display:** theme (dark / night); brightness levels; UI language (localized);
  **handedness (left/right, flips UI orientation)**; per-overlay toggles for battery / chapter /
  progress while playing.
- **Footer metric** + **battery label** tap-to-cycle (see §3).
- **ASCII fallback mode** (maps accented letters to base letters for the limited glyph set).

Fonts shipped: serif, Atkinson Hyperlegible, OpenDyslexic (two sizes each). Atkinson Hyperlegible
is OFL-licensed and flagged as a good copy candidate for the AMOLED watch (bold, high-contrast).

### garmin_RSVP implications
- Fenix 8 has **5 buttons + touch** (more input than Nano). Bind reading-critical controls to
  buttons (START/STOP=play/pause, UP/DOWN=WPM, BACK=sentence rewind); reserve touch for
  scrub/context-browse.
- Copy the *proven settings set* (WPM range+adaptive step, three pacing delays, pause mode,
  typeface, anchor %, focus-highlight, handedness) — but keep MVP minimal; the value is knowing
  WHICH knobs proved worth having.
- Reject localization/themes/focus-timer/WiFi/OTA menus (CIQ provides its own, or out of scope).

---

## 6. EPUB parsing — content structure: what survives, what's lost, navigation implications

### What SURVIVES parsing (available for presentation/navigation)
- **Reading order** — via the OPF `<spine>` (ordered idrefs); walk spine → resolve to XHTML →
  concatenate. This is the canonical reading-order content.
- **Chapters** — from EPUB2 `toc.ncx` (navMap) or EPUB3 `nav.xhtml`; epub_pro reconciles both.
  **Recommendation: use spine-file boundaries as the primary chapter unit, TOC labels for naming.**
  (Pure TOC-driven splitting breaks when one XHTML holds multiple TOC entries via fragment anchors.)
- **Chapter titles/labels** — from the TOC; stored as inline title with the chapter marker
  (Nano uses a 64-char inline title per chapter record).
- **Paragraph boundaries** — extract per block element (`p`, `div`, `li`, headings) and emit
  `@para`-style markers (NOT one giant `.text` call), so the reader gets paragraph pauses + nav.
- **Headings** — are block elements, so survive as paragraph-level breaks (no distinct heading
  styling is preserved into an RSVP word stream — they become text + a paragraph boundary).
- **Metadata** — title, author, language (OPF `<metadata>`), for library display + resume.

### What is LOST / dropped
- **Images** — contribute only `alt` text (often empty); skipped silently. No visual images in RSVP.
- **Tables** — linearize poorly; read row-major or skip (pre-filter `table` out of the DOM).
- **CSS / styling / fonts** — irrelevant to a word stream; not carried.
- **Ruby annotations** (`<rt>`) — dropped, keep base text.
- **Footnotes/endnotes** (`<a epub:type="noteref">` + aside bodies) — must be detected and skipped
  or they appear as stray words mid-sentence.
- **Smart quotes / em-dashes / ellipsis / soft hyphens / NBSP / zero-width chars** — normalized:
  strip soft hyphens, NBSP→space, drop zero-width, NFC-normalize; optionally fold to ASCII for the
  watch's limited glyph set. Failing to do this gives words phantom characters and breaks ORP indexing.
- **DRM'd EPUBs** — out of scope (DRM-free only).

### Navigation / presentation implications (phone + watch)

**On the phone (Flutter companion):**
- **Library:** SQLite (drift/sqflite) table — book id, title, author, source path, total words,
  import date. Sort by recency (mirror Nano's per-book "recent" sequence).
- **Chapter index:** chapter → start absolute word index + label, stored in SQLite. Enables a
  chapter list and chapter-jump.
- **Parsed word stream:** flat file (binary-packed ~9 bytes/word, ~0.9 MB / 100k-word novel),
  NOT a SQLite blob; index into it for cheap BLE chunk range-reads.
- **Resume position:** single indexed word offset per book in SQLite, updated frequently.
- Import via `file_picker` + `receive_sharing_intent` (Android intent / iOS Share Extension);
  parse in a worker isolate, write stream file inside the isolate, return only path + index.

**On the watch (Garmin):**
- **Position/seek/chapter/paragraph all keyed on absolute word index** (one integer; syncs to phone).
- **Chapter list / chapter jump:** chapter markers = absolute word indices + inline titles
  delivered with the book; chapter-jump = seek to that index.
- **Chapter transition card** (Nano's 1.4 s card) is the natural place to trigger a BLE chunk
  pre-fetch.
- **Progress within book:** percentage + time-remaining (ship a cumulative-duration array from
  the phone so the watch shows time-remaining with no computation).
- **Chunking for BLE:** ~200–500 words/chunk (~1.8 KB binary for 200), never split a word,
  prefer paragraph/sentence boundaries (so a chunk gap = a natural pause), header carries the
  absolute word index for exact resume/seek/sync.
- **Paragraph-start / sentence-end flags** baked per word enable paragraph pauses, sentence-end
  pause mode, and the on-pause context view's paragraph flags — cheaper than recomputing on-watch.

---

## 7. RSVP comprehension / ergonomics research noted

The reports are engineering/architecture teardowns and **do NOT contain a dedicated
comprehension/fatigue study**. The RSVP-cognition facts that DO appear:

- **Perceptual span ≈ 13 characters** (the basis for the ORP length tiers capping at the
  13–14-char boundary). Source: Spritz "how it works" + The Conversation article (confidence Medium).
- **ORP sits slightly left of center and moves further left as words lengthen** — the perceptual
  rationale for front-loaded pivot placement and the 35% anchor.
- **WPM range used in practice: 10–1000** (Nano's clamp). Adaptive stepping (finer below 100,
  coarser above) implicitly treats ~100 WPM as a regime boundary.
- **Variable per-word timing matters for comprehension/coasting:** longer words, complex/ALL-CAPS/
  numeric tokens, and especially punctuation (commas, sentence-ends) get extended dwell — i.e. the
  system deliberately slows at clause/sentence boundaries to preserve comprehension. Pausing
  mid-sentence is treated as a comprehension hazard, hence "pause at sentence end."
- The EPUB report explicitly flags that **Nano's percentages are tuned for its device and may need
  recalibration** for a 454×454 AMOLED at the reader's WPM (confidence Medium). The "optimal WPM /
  fatigue / comprehension-drop-off" question is NOT empirically answered in these sources — treat
  it as an open UX/testing item.

---

## Two-stage pause + sentence rewind (detail — the headline recovery UX)

- **Pause at sentence end (default):** a tap while playing does NOT stop instantly; it requests a
  pause that finalizes only when the current word has fully elapsed AND ends a sentence (or is the
  last word). Coasts to the next sentence boundary so context isn't lost mid-sentence. Sentence
  detection honors abbreviations / dotted initialisms so it doesn't false-stop.
- **Instant pause:** user-selectable alternative (`PauseMode {SentenceEnd, Instant}`).
- **Sentence rewind:** a dedicated edge tap jumps to the start of the current sentence, or — if
  already at a sentence start — to the start of the **previous** sentence. Auto-pauses (if playing)
  and immediately force-persists position. This is the "I glanced away" answer: sentence-granular,
  one action, no menu.

Both translate to pure logic over the word stream; with sentence-end flags baked in the stream,
they're even cheaper on the watch than Nano's read-time detection.

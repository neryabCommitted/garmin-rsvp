# Reconciliation — RSVP Nano Reader-Side Teardown vs. PaceTurner PRD + Addendum

**Input:** `_bmad-output/planning-artifacts/research/technical-rsvpnano-reader-teardown-research-2026-06-06.md`
**Checked against:** `prd.md` and `addendum.md` (prd-garmin_RSVP-2026-06-06)
**Date:** 2026-06-06

## Method

Each substantive design decision, behavior, setting, constraint, and risk in the teardown was traced to either the PRD body or the addendum. Items that are clearly captured (possibly in different words) are listed as "covered" for completeness; the body of this report is the set of items present in the INPUT but in NEITHER downstream document, filtered to those that actually change requirements, risk, or scope. Pure implementation detail that correctly belongs in downstream architecture docs is noted as "correctly downstream" and not flagged.

---

## Coverage confirmation (no action needed)

These INPUT findings are already carried by the PRD and/or addendum and need no further action:

- BookWordSource 3-method seam → addendum §5 (adopted), §4.
- Absolute word index as universal coordinate → FR12; addendum §3.
- Spritz ORP algorithm + 35% anchor + per-glyph red highlight → FR1; addendum §2.
- Drift-free time-driven advance + 4-word catch-up cap → NFR1; addendum §4.
- Read-time vs baked timing conflict, resolved as "bake the bonus, not the duration" → addendum §2 (timing model).
- Pacing percentages (length/complexity/punctuation tiers) → addendum §2 (ported as reference, recalibration flagged).
- Two-stage pause-at-sentence-end + Instant toggle → FR7; addendum §5.
- Sentence rewind (auto-pause + persist) → FR9; addendum §5.
- Context-on-pause scroll view → FR10; addendum §5.
- 256-word window / chunked word source over BLE + prefetch → FR17; addendum §3, §5.
- Position persistence: per-book key, debounce-while-playing + force-on-transition → FR13; addendum §4, §5.
- Two-device reconciliation → FR14; addendum §5, §6.
- Reading-time-remaining shipped as phone-side cumulative data → addendum §5.
- Button-first controls (5 buttons) vs Nano touch-only → FR11; addendum §4 (input map).
- Round-screen ORP geometry (chord per row) → FR6/FR1; addendum §2, §4.
- Host-side unit-test discipline (~60 tests) → addendum §4, §6.
- Bounds-check-and-degrade on malformed/short data → NFR8; addendum §5.
- Rejected: on-device EPUB conversion, App.cpp monolith, battery/standby/screensaver, WiFi/OTA/RSS/focus-timer/localization → addendum §5.
- Gaps to fix: silent end-of-book (FR5) and missing start ramp/ready-state → addendum §5 notes "brief ready-state."

---

## GAPS — in INPUT, in neither PRD nor addendum, and worth carrying

### GAP 1 — Phantom / dimmed context words during *playback* (not just on pause) — UX pattern dropped
**INPUT:** "ORP Rendering" section. Beyond the focal word, `renderPhantomRsvpWord` draws the preceding and following words *dimmed* (alpha-blended) immediately left/right of the current word during normal playback, giving peripheral context without competing with the focal word (toggleable, default on). The teardown explicitly recommends carrying it ("a strong feature to copy — cheap, improves recovery") with a round-screen adaptation: a single faded leading/trailing word instead of full phantom lines.

**Status:** NOT in PRD or addendum. The documents capture context-on-*pause* (FR10) but never the *during-playback* dimmed adjacent word(s). These are distinct features in the INPUT (the teardown calls them "Distinct from the full scroll/context view").

**Why it matters / recommendation:** This is a concrete rendering requirement and a deliberate UX recommendation the teardown flagged for carry-over. It affects FR1 (what the playback screen shows) and the round-screen rendering budget. At minimum it should appear in the addendum's watch-app design notes as a candidate playback-screen feature ("single faded leading/trailing word") with the round-screen caveat, so the architecture/UX phase can decide it consciously rather than silently dropping a recommended pattern. Low effort, recovery-relevant. **Flag.**

### GAP 2 — Chapter-transition card (1.4 s) as the natural BLE pre-fetch trigger — behavior + design decision dropped
**INPUT:** "Reading Loop" section. On crossing a chapter marker, Nano shows a `CHAPTER N` + title transition card for ~1400 ms, during which the reader short-circuits, then resumes. The teardown's mapping makes a specific architectural recommendation: "Copy the chapter transition card as the natural place to *also* trigger a chunk pre-fetch over BLE."

**Status:** NOT in PRD or addendum. Chapter/paragraph navigation is explicitly Fast-follow (PRD §4), and the addendum's pre-load model (§3) triggers next-chapter fetch "mid-chapter ... in the background" — but the *chapter-transition card itself* (a brief settling beat at chapter boundaries) and its pairing with pre-fetch are absent.

**Why it matters / recommendation:** Two things were dropped: (a) a small UX beat (chapter card) that doubles as the only "settling pause" in normal reading, and (b) a design decision about *when* to pre-fetch. The pre-fetch timing partly lives in addendum §3 ("mid-chapter ... background"), so that half is arguably covered. The chapter-card UX beat is genuinely absent and interacts with the deferred chapter-navigation scope. Worth a one-line note in the addendum so the fast-follow chapter work inherits the card idea. **Flag (lower priority — partially mitigated by the mid-chapter pre-fetch already documented).**

### GAP 3 — Word-granular scrub + browse-scroll while paused — control surface dropped
**INPUT:** "Rewind, Pause, Recovery" section. While paused, Nano overloads touch into rich intents: horizontal swipe = rubber-band word-granular scrub (`seekRelative` from gesture start), hold near top/bottom = continuous velocity-based browse-scroll for skimming, double-tap = locked play. The teardown recommends keeping scrub/context-browse on touch (the larger gesture surface) while moving play/pause/WPM to buttons.

**Status:** Partially covered, partially dropped. The addendum's input map (§4) and FR11 cover tap=play/pause and swipe=rewind, and FR10 covers the paused context view. But the *scrub-to-seek* and *browse-scroll/skim* capabilities — i.e., moving your position by an arbitrary number of words while paused, with the context view live — are not a requirement anywhere. FR9 only gives *sentence* rewind; there is no forward seek or word-granular reposition.

**Why it matters / recommendation:** This is a scope question, not just detail. The teardown flags scrubbing-past-the-buffer as "a real latency consideration his SD-backed design doesn't have" (touch scrub → BLE fetch → buffering). If PaceTurner intends any free-seek/skim beyond sentence rewind, it needs (a) a functional requirement and (b) the protocol implication (random-access seek may cross chunk boundaries → fetch + buffering state). If it is deliberately out of scope for MVP, that should be stated. Currently it is neither in scope nor explicitly excluded — a silent drop of a documented capability with a protocol consequence. **Flag.**

### GAP 4 — Source-staleness / book-version fingerprint in the protocol — constraint not registered
**INPUT:** "Buffering, Indexing, Seeking" section. The `.ridx` header carries a `sourceSize` + `sourceFingerprint`; the index is "rebuilt automatically if the source book changes." The teardown maps this explicitly: "The `sourceFingerprint` staleness field maps to a book-version/hash in the protocol so the watch can detect 'this chunk is from an old conversion.'"

**Status:** NOT in PRD or addendum. The protocol section (addendum §3) and FR19 cover idempotency, offset-addressing, and retry safety, but there is no notion of a book-version/content hash that lets the watch detect a *stale* chunk produced by an earlier conversion of the same book (e.g., after re-import or a converter change).

**Why it matters / recommendation:** This is a correctness constraint, not gold-plating. If a book is re-imported/re-converted on the phone while chunks from the old conversion are still resident (or the resume index points into an old word ordering), absolute-word-index positions and chunk content can silently desync — exactly the "resume never lies" / "never corrupted or out-of-order text" failure the PRD takes as a primary goal (Goal 4, FR19, NFR4). The protocol should carry a per-book content fingerprint/version so the watch invalidates stale chunks and validates that a resumed index belongs to the current conversion. This belongs in the protocol spec (addendum §3) and arguably as a clause under FR19/NFR4. **Flag — highest correctness relevance.**

### GAP 5 — Sentence detection must honor abbreviations / dotted initialisms — behavior detail with a requirements edge
**INPUT:** "Rewind, Pause, Recovery" and "Other Solved Problems." Sentence-boundary detection (`wordEndsSentenceAt`) honors abbreviations (`Mr.`, `e.g.`) and dotted initialisms so two-stage pause and sentence rewind don't false-stop; this is explicitly unit-tested (`test_rewind_sentence_ignores_abbreviation`, etc.).

**Status:** Mostly downstream, lightly dropped. The pacing-algorithm reference in addendum §2 mentions "period 135% with abbreviation suppression" — so abbreviation handling is acknowledged for *pacing*. But the *sentence-boundary* dimension (FR7 pause-at-sentence-end and FR9 sentence rewind both depend on correct sentence detection) does not state that abbreviation/initialism handling is required for those features to behave. Since timing is now baked phone-side, the *sentence-end flag* that drives FR7/FR9 is produced by the phone — so the phone's segmenter, not the watch, must get abbreviations right.

**Why it matters / recommendation:** Mostly an implementation detail correctly destined for the converter, so this is borderline. The one requirements-level point worth registering: the *sentence-end flag in the stream* (which FR7 and FR9 consume) carries the same abbreviation-correctness obligation the teardown calls out, and the phone tokenizer (addendum §1 "hand-roll Unicode-aware tokenization") is where it must live. A single sentence in the addendum tying sentence-end flag quality to abbreviation handling would close it. **Flag (low — largely downstream).**

---

## Items reviewed and deliberately NOT flagged (correctly downstream or out of scope)

- **8-byte per-word index record layout / 52-byte `.ridx` header / two-read window mechanics** — pure storage implementation; correctly belongs in architecture, and the watch doesn't build `.ridx` anyway. Addendum §2/§3 capture the relevant abstraction (~9 B/word stream, offset-addressed chunks). Not flagged.
- **NVS `Preferences` storage specifics / key formats (`p%08lx` etc.)** — platform-specific; the *pattern* (per-book key) is in addendum §4/§5. Not flagged.
- **Footer-metric / battery-badge tap-to-cycle** — INPUT calls these "cheap, no menu" nice-to-haves; progress visibility is covered (FR15 phone-side; reader overlays are minor UX). Genuinely minor; arguably a tiny dropped idea but below the "changes requirements/scope" bar. Not flagged (optional: a one-liner in a future UX backlog).
- **ASCII fallback / accented-letter mapping (`LatinText.h`)** — superseded by NFR7 script-agnostic stream + addendum §2 Unicode tokenization; Nano's glyph-set workaround doesn't transfer. Not flagged.
- **Adaptive WPM step (10 below 100, 25 above), WPM range** — FR3 + addendum §2 cover adaptive step; ranges differ (Nano 10–1000 vs PRD assumption 100–900 with headroom to 1000) but that divergence is an intentional `[ASSUMPTION]` in FR3/NFR1, not a drop. Not flagged.
- **Multi-book on-device library, articles/RSS** — explicitly out of scope (PRD §4: "multi-book watch library" out of scope; single active book FR23). Not flagged.
- **Standby screensavers / Game-of-Life etc.** — rejected (battery/standby machinery). Not flagged.
- **Three pacing delays default 200 ms, guide half-width/gap, letter tracking** — settings detail; the proven-settings-set lesson is in addendum §2 and the teardown itself defers most typography to "later" matching PRD §4. Not flagged.
- **Demo-text modulo-wrap behavior** — Nano test affordance, not a product behavior. Not flagged.

---

## Summary table

| # | Gap | Type | Where it should land | Priority |
|---|-----|------|----------------------|----------|
| 1 | Dimmed phantom adjacent word(s) during playback | UX pattern (recommended carry) | Addendum §4 / UX phase | Medium |
| 2 | Chapter-transition card as pre-fetch trigger | Behavior + design decision | Addendum §3/§4 (fast-follow) | Low–Med |
| 3 | Word-granular scrub + browse-scroll while paused | Scope + protocol (random-access seek) | PRD §4/FR + addendum §3 | Medium |
| 4 | Book-version/content fingerprint vs stale chunks | Correctness constraint | Addendum §3, FR19/NFR4 | High |
| 5 | Abbreviation-aware sentence-end flag obligation | Behavior (phone segmenter) | Addendum §1/§2 | Low |

GAP 4 is the one with real correctness stakes against the PRD's own "resume never lies / never corrupted text" goals. GAPs 1 and 3 are genuine UX/scope drops the teardown explicitly recommended carrying. GAPs 2 and 5 are minor / largely downstream.

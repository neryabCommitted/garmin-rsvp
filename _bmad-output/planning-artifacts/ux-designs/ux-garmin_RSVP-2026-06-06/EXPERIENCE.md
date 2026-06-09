---
name: PaceTurner
status: final
created: 2026-06-06
updated: 2026-06-06
project: garmin_RSVP
sources:
  - "{planning_artifacts}/briefs/brief-garmin_RSVP-2026-06-05/brief.md"
  - "{planning_artifacts}/prds/prd-garmin_RSVP-2026-06-06/prd.md"
  - "{planning_artifacts}/prds/prd-garmin_RSVP-2026-06-06/addendum.md"
  - "{planning_artifacts}/research/technical-fenix-8-watch-app-constraints-research-2026-06-06.md"
  - "{planning_artifacts}/research/technical-rsvpnano-reader-teardown-research-2026-06-06.md"
  - "{planning_artifacts}/research/technical-connect-iq-phone-watch-communication-research-2026-06-06.md"
  - "{planning_artifacts}/research/technical-epub-parsing-flutter-dart-research-2026-06-06.md"
  - "{planning_artifacts}/architecture.md"
---

# PaceTurner — Experience Spine

> Dual-surface: Garmin Fenix 8 Connect IQ watch app (the reader) + Flutter phone companion (the librarian). `DESIGN.md` owns how it looks; this spine owns how it works. Spines win on conflict with any mock, wireframe, or import.

## Foundation

Two surfaces with a hard division of labor, fixed by the architecture:

- **Watch (Garmin Fenix 8, CIQ 6.0+)** — the reading surface. Runs as a full watch-app with an activity session (the screen-on mechanism, gate V1). Buttons-first, touch mirrors (FR12). Consumes a pre-baked word stream — every pivot index, dwell duration, sentence flag, and paragraph flag is computed phone-side; the watch only plays it.
- **Phone (Flutter, Android first)** — import, parse, library, sync. Material 3 dark (see `DESIGN.md`). Owns the durable position store and the EPUB pipeline; deliberately bare-bones (FR22–FR24).

The single shared coordinate everywhere is the **absolute word index**. Position, chapters, progress, rewind, sync — one integer. The resume guarantee inherited from architecture: **resume never lies** — on any restart, the reader resumes at or *before* the last word seen, never after.

Garmin Connect Mobile is a hard pairing prerequisite; reading is activity-grade battery draw. Both are onboarding expectations, not surprises.

## Information Architecture

**Watch:**

| Surface | Reached from | Purpose |
|---|---|---|
| Playback | App launch (with active book) | The RSVP stream — one word at the anchor |
| Paused | Playback ⏯ | Word frozen + progress readout ({components.progress-readout}) |
| Context view | Paused → scroll/DOWN | Surrounding text, current word marked (FR11) |
| Chapter card | Automatic at chapter boundary | Breath + title + prefetch trigger |
| Settings menu | MENU | WPM, pause mode, chapter-card resume (Auto / Wait), touch controls (On / Off), font size, handedness, focus highlight, phantom words |
| Status views | System-driven | WaitingForPhone · Buffering · BookChanged · StorageFull |
| Finished | Last word of book | Explicit end state + stats |

→ Composition reference: `mockups/key-playback.html` (Playback playing + paused). All other surfaces are spine-only by Nerya's call. Spine wins on conflict.

**Phone:**

| Surface | Reached from | Purpose |
|---|---|---|
| Library | App open | Books: cover, title, author, progress; active book marked |
| Book detail | Library row tap | Cover, metadata, progress, chapter list, actions |
| Import | FAB / OS share sheet | File pick or share-target → parse → appears in library |
| Transfer | Send-to-watch (detail primary action or row overflow) | Inline progress; one active book on watch at a time |
| Settings | Overflow | Defaults, about, licenses |

Book detail (Nerya's call, 2026-06-06): cover art extracted from the EPUB when present `[ASSUMPTION: covers survive phone-side even though images are dropped from the watch stream]`, title/author/metadata, progress as % + time remaining, chapter list with jump-to-chapter `[ASSUMPTION: jump sets the absolute word index and syncs to the watch — cheap, position is one integer]`, and the actions: Send to watch, Restart book, Remove.

Surface closure: every FR-implied need lands on a surface above; every surface is reached by a flow below.

## Voice and Tone

Microcopy. Brand posture lives in `DESIGN.md.Brand & Style`. The product reads like a quiet librarian: short, factual, no exclamation marks, no mascot energy. `[ASSUMPTION]`

| Do | Don't |
|---|---|
| "Waiting for phone" | "Connection error!" |
| "Chapter 12 — The Long Road" | "🎉 New chapter unlocked" |
| "Finished. 6h 41m across 19 days." | "Congratulations! You did it!" |
| "Storage full — remove a book on your phone" | "Error 507" |
| "Sending to watch — chapter 4 of 31" | Indeterminate spinner with no words |

## Component Patterns

Behavioral. Visual specs live in `DESIGN.md.Components`.

| Component | Use | Behavioral rules |
|---|---|---|
| Word display | Playback | Advances on baked per-word dwell (`60000/wpm` + baked bonuses). Drift-free scheduling (`+= duration`, never `= now`). WPM changes take effect next word. Long words shown whole, margin-clamped, pivot drifts before any truncation. |
| Guide marks + phantom words | Playback | Static composition (within session jitter). Phantom words update with the stream; both toggleable in settings. |
| Progress readout | Paused only | Book % + time remaining (from cumulative-duration array) + current WPM. Never visible during playback. |
| Chapter card | Chapter boundary | Auto-shows. Resume behavior is a setting (Nerya, 2026-06-06): **Auto** (~2s, then flow resumes) or **Wait** (resumes on START). Default Auto `[ASSUMPTION]`. Doubles as the prefetch window for the next chapter. |
| Start ramp | Resume/play | Brief 3-2-1 word-cadence lead-in before the stream starts — the anti-pattern fix for RSVPnano's cold start `[ASSUMPTION: 3 beats at current WPM]`. |
| Library row | Phone library | Tap → Book detail; overflow shortcuts → Send to watch / Remove. Active-on-watch book gets a marker. |
| Book detail | Phone | Send to watch is the primary action. Chapter tap → confirm → repositions (and re-syncs the watch). Restart asks once. |
| Transfer bar | Phone | Inline, cancellable, survives app backgrounding. Never blocks the library. |

## RSVP Presentation & Timing

The contract for the reading surface itself — inherited from the RSVPnano teardown, baked phone-side, consumed by the watch:

- **ORP pivot per word** by character count (punctuation excluded): ≤1→1st, ≤5→2nd, ≤9→3rd, ≤13→4th, ≥14→5th letter. Pivot's center sits on the anchor line at 35% of display width (user-tunable 30–60%).
- **Variable dwell** = WPM base + WPM-invariant bonuses baked per word: length tiers (cap +170%), complexity (cap +85%), trailing punctuation (comma +45% … sentence-end +150%, with abbreviation suppression). Baking keeps live WPM changes free.
- **WPM 10–1000**, adaptive step (10 below 100 WPM, 25 at/above). Default 250 `[ASSUMPTION]` — sources don't name a starting default; conservative beats impressive for first contact.
- **Timing floor honored**: 50ms timer floor supports 1000+ WPM; no UI promise beyond that.
- Optimal-WPM/fatigue research is empirically unanswered in sources — Nerya's own daily use is the instrument. Open item, not a spec.

## State Patterns

Mandatory named states from architecture — every network/storage moment is a visible, worded state, never a hang:

| State | Surface | Treatment |
|---|---|---|
| WaitingForPhone | Watch | "Waiting for phone" in {components.status-view}. Shown only when playback *cannot* proceed from local storage — never interrupts buffered reading. |
| Buffering | Watch | "Loading…" + minimal dot cycle. Target: rare — current+next chapter residency means BLE never blocks mid-chapter. |
| BookChanged | Watch | "Book changed on phone — starting {title}". One-tap acknowledge `[ASSUMPTION]`. |
| StorageFull | Watch | "Storage full — manage books on your phone". Non-blocking for current book. |
| Finished | Watch | Explicit end screen + stats. START returns to beginning? No — BACK exits; re-read is a phone-side decision `[ASSUMPTION]`. |
| Dim/AON fallback | Watch | If the activity-session screen-on path fails (gate V1), playback auto-pauses when the display dims; touch-to-wake resumes paused, never mid-stream `[ASSUMPTION]`. Words must never flow on a screen the user can't read. |
| Abrupt kill (carousel hazard) | Watch | No graceful-exit assumption. Persistence: debounced ~15s while playing + force-save on every transition (pause, menu, rewind, chapter, disconnect). Relaunch lands on Paused at-or-before the last word. |
| Disconnected reading | Watch | Fully functional within stored chapters; reconnect reconciles position (timestamped last-writer-wins, watch-wins tiebreak — resolved 2026-06-06, see architecture). Silent unless the reader hits the buffer edge. |
| Import failure | Phone | Inline on library: "Couldn't read {filename} — {reason}". The book never half-appears. |
| Empty library | Phone | "Add a DRM-free EPUB to begin." + import action. |

## Interaction Primitives

**Buttons always work; touch is an opt-in mirror** (Nerya, 2026-06-06): a "Touch controls" setting gates all tap/swipe input, default On `[ASSUMPTION]`. LIGHT is off-limits; `onKey` + `onTap`, never `onSelect`. **BACK keeps its Garmin meaning everywhere** (Nerya, 2026-06-06).

**Playing:**

| Input | Action |
|---|---|
| START / tap | Pause — coasts to the sentence end, then freezes (FR8); Instant pause mode available in settings |
| UP / DOWN | WPM ± (adaptive step), applied next word; transient WPM readout flashes in {colors.ink-dim} `[ASSUMPTION]` |
| Swipe right | Pause **and** rewind one sentence — the "I lost it" gesture (FR10) |
| MENU | Pause + open settings |
| BACK | Exit to watch face (position force-saved) |

**Paused:**

| Input | Action |
|---|---|
| START / tap | Resume (with start ramp) |
| Swipe right / UP | Rewind one more sentence (stackable; UP is the button mirror while paused) `[ASSUMPTION]` |
| DOWN / swipe up | Open context view (FR11) |
| BACK | Exit to watch face (force-saved); from context view, BACK returns to Paused |

`[NOTE]` Resolved 2026-06-06: BACK stays untouched per Nerya, and touch is settable Off. Consequence: with touch on, in-flow rewind is the swipe; with touch off, the rewind path is START (pause) → UP — two presses, fully button-operable, restoring FR12's buttons-first guarantee in its strictest mode.

**Banned:** remapping BACK away from exit; multi-level menus on the watch; double-tap semantics; any action available *only* via touch (every touch gesture must have a button path, since touch can be switched off).

Handedness setting mirrors swipe directions — MVP (Nerya, 2026-06-06).

`[NOTE]` The entire input map above is provisional until the first real on-watch test (Nerya, 2026-06-06) — he has gesture/button opinions queued for hardware. Treat the map as a starting layout, the *principles* (BACK sacred, buttons always work, touch opt-in, every gesture has a button path) as fixed.

## Screen Survival (AMOLED & Session)

The product-specific concern that outranks all others (FR4, R1, gate V1): a hands-off ≥60-minute readable display on a panel that wants to sleep.

- Primary path: activity session keeps the display lit; reading is honest about being activity-grade battery draw.
- Burn-in citizenship: mostly-black composition, per-session jitter, no persistent chrome (all specified in `DESIGN.md`).
- Fallback path: if gate V1 fails on hardware, the dim/AON state pattern above governs — auto-pause on dim, never flash words on an unreadable screen. The UX survives the gate failing; the *product promise* (uninterrupted hands-off reading) does not — which is why V1 is a gate, not a footnote.

## Sync & Continuity

- One active book on the watch at a time (FR24). Sending a new book produces the BookChanged state on the watch — never a silent swap mid-read.
- Chunked BLE transfer (~200–500 words on paragraph/sentence boundaries, header carries absolute word index); playback never blocks on BLE — current + next chapter resident in watch storage (~80KB cap).
- Position syncs both ways, keyed per book; conflict resolution = **timestamped last-writer-wins**, with a watch-wins tiebreak inside the clock-skew window (resolved 2026-06-06 with Nerya — see architecture). `[RESOLVED: max-index-wins was considered and rejected because it would silently undo the deliberate backward repositions this spec itself specifies — Restart book and jump-to-chapter; the "never lose your place to a stale phone record" concern is covered by the watch-wins tiebreak.]`
- Transfers degrade gracefully: Android BLE flakiness (first-send-works-then-stops) means the transfer bar must support retry without restarting from chunk zero.

## Accessibility Floor

Behavioral. Visual contrast lives in `DESIGN.md`.

- The pivot is never marked by color alone — the anchor ticks and guide-mark gap point at it geometrically, so the red is redundant, not load-bearing (color-blind safe).
- Focus highlight, phantom words, and guide marks all individually toggleable — RSVP visual load varies per reader.
- Word size follows `{typography.word-display}` with a user font-size setting — MVP (Nerya, 2026-06-06) `[ASSUMPTION: ±2 steps around 48px]`; Atkinson Hyperlegible chosen specifically for glyph disambiguation at flash speed.
- Phone surface: Material 3 defaults give TalkBack labels, 48dp targets, dynamic type — keep them; every custom widget (transfer bar) labeled with role + state.
- Watch: every status view is plain text, not iconography; physical buttons mean the reading-critical path requires zero touch precision.

## Inspiration & Anti-patterns

- **Lifted from RSVPnano:** the entire presentation layer — ORP tiers, 35% anchor, split guide marks, phantom context, variable dwell with punctuation pauses, pause-at-sentence-end default. It works; we port it, recalibrated for 454×454.
- **Rejected — RSVPnano's cold start and silent ending:** we add the start ramp and an explicit Finished screen. Finishing a book is a success criterion, not an absence of words.
- **Rejected — touch-only anything:** wrong on a wrist in motion. Buttons always work; touch is an opt-in mirror behind a setting (the in-flow swipe-rewind is its one real luxury), and every gesture keeps a button path.
- **Rejected — feature-rich companion:** no annotations, no reading stats dashboards, no social. The phone is a librarian, not a destination.
- **Rejected — graceful-exit assumptions:** Garmin's carousel kills apps without warning. Persistence discipline is the feature.

## Key Flows

### Flow 1 — The demo moment (Nerya, evening, couch)

1. Nerya gets an EPUB recommendation, downloads it, shares it from the file manager to PaceTurner.
2. Import parses; the book appears in the library with title and author.
3. He taps the new book — detail screen, cover and all — and hits "Send to watch." Transfer bar walks chapters across BLE; he puts the phone down before it finishes — chapter 1 is already resident.
4. On the watch: PaceTurner opens to Playback, paused at word 0 of the new book (BookChanged acknowledged).
5. START. Three-beat ramp, then the stream at 250 WPM.
6. **Climax:** the phone is face-down on the table, forgotten. One luminous word after another on the wrist, sixty minutes, zero interventions. The demo *is* the absence of interaction.

Failure: transfer stalls at chapter 4 mid-read of chapter 1 → nothing happens on the watch; the reader never knows. Buffering appears only if he outreads the buffer.

### Flow 2 — Glance away and recover (Nerya, reading at 400 WPM, doorbell)

1. Doorbell. Eyes leave the watch; words keep flowing.
2. He hits START walking to the door — stream finishes the sentence and freezes (SentenceEnd pause). Progress readout fades in.
3. Two minutes later he's back. The frozen word means nothing to him.
4. Two right-swipes — two sentences back, each flashing the rewound-to position.
5. DOWN — context view: the surrounding paragraph, current word marked. *Oh, right.*
6. BACK to Paused, START to resume — ramp, then flow.
7. **Climax:** total recovery cost: two presses, two swipes, no menu — and the thread of the book never actually broke.

### Flow 3 — Resume never lies (Nerya, next morning, carousel hazard)

1. Mid-chapter yesterday, a calendar glance: he swiped to the watch face. Garmin killed PaceTurner on the spot — no exit hook ran.
2. This morning: launches PaceTurner from the carousel.
3. App opens to Paused — at the last force-saved transition, ≤15s before the kill, *behind* his true position, never past it.
4. **Climax:** START — and the words he re-reads for ten seconds are familiar, not missing. The trust contract holds: PaceTurner may cost you a paragraph; it will never skip one.

### Flow 4 — Finishing (Nerya, 19 days into a novel, on a flight)

1. Phone in airplane mode in the seat pocket; final two chapters already resident on the watch.
2. He reads through the last chapter card. Disconnected the whole time; no status noise.
3. The last word's dwell ends.
4. **Climax:** "Finished. 6h 41m across 19 days." A book — a whole book — read on a watch. The screen says so, plainly, then lets him exit.
5. On landing, the phone reconciles: library marks the book finished `[ASSUMPTION: finished state surfaces in library row]`.

## Open Questions

- To confirm on first hardware test: chapter-card Auto delay (~2s), touch default On, font-size steps, word-display 48px, ink/pivot exact values — and the input map itself (Nerya has queued gesture/button input pending real-wrist feel).

Resolved 2026-06-06 (Nerya): default WPM 250 ✓ · BACK untouched ✓ · FR8 conformed to PRD verbatim (coast-to-sentence-end; instant mode in settings) ✓ · Book detail screen added; restart lives there ✓ · Chapter-card resume is a setting (Auto / Wait) ✓ · Touch controls are an opt-in mirror behind a setting; buttons always work ✓.

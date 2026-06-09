# UX Extraction — PaceTurner (RSVP Speed Reader for Garmin)

> Source extraction for UX design. Sources: brief (2026-06-05), PRD (2026-06-06), addendum (2026-06-06).
> **Companion is Flutter** — supersedes the brief's earlier Kotlin/Android decision (confirmed in PRD/addendum, pivoted 2026-06-06).
> Product name: **PaceTurner**.

---

## 1. Product Vision, Users, Stakes

### Vision
- **One-liner (PRD):** "Open an e-book on your phone, raise your wrist, and read it — one word at a time, at your pace, without friction."
- RSVP (Rapid Serial Visual Presentation), Spritz-style: the watch flashes **one word at a time** at a **fixed focal point**.
- Division of labor: **phone companion does the heavy lifting** (import, parse, bake per-word timing into a compact word stream); **the watch does exactly one thing well — display the next word at the right moment.**
- Topology deliberately inverted vs RSVP Nano: phone parses/stores, watch streams (watch can't convert or store full books).
- Positioning: **free, open-source, and book-first** (EPUB-to-wrist pipeline, not a standalone watch gadget).

### Target users / personas
- **User #1 (guaranteed):** the author — Fenix 8 on wrist, Android phone, library of DRM-free EPUBs. *User #1's daily use is the validation instrument.*
- **Adopters (hypothesis):** RSVP/speed-reading enthusiasts who own Garmins; Connect IQ tinkerers; readers who want to clear a backlog without pulling out their phone.
- **Contributors (open-source):** CIQ and mobile developers — served by clean architecture, documented streaming protocol, permissive license.
- PRD note: "No further persona work is warranted at these stakes."

### Stakes
- **Hobby / personal open-source project first, a product for others second** — but with **publish-quality ambitions**. Success = a working, polished, publishable reader, not revenue.
- Not regulated, not internal-enterprise, not a commercial consumer launch. Quality bar is "polished and publishable" but scope is right-sized for one developer.

---

## 2. Functional Requirements That Imply a Screen / Surface / Flow / Interaction

Verbatim FR names. Grouped by device surface.

### A. RSVP Playback (WATCH)
- **FR1 — One word, fixed focal point.** Single word at a time; ORP (optimal recognition point) pivot letter **visually highlighted** and **anchored at a fixed horizontal position (~35% of text width)**. Anchor does not shift between words (stable rendering).
- **FR2 — Variable timing.** Per-word display duration varies with word length/complexity and punctuation (sentence ends, commas, dashes pause longer). Flat WPM "feels robotic." Watch applies baked metadata; does not compute linguistics.
- **FR3 — WPM control.** Reading speed user-adjustable during playback. `[ASSUMPTION]` Range **100–900 WPM**, adaptive step size, **default 300**. Changes take effect immediately, never re-fetch content.
- **FR4 — Hands-off playback.** Display stays readable without interaction for a **full session (≥60 minutes continuous)**. If platform forces degradation, acceptable fallback is a **dim always-on display that a single button press restores**. Requiring interaction every minute is a non-starter.
- **FR5 — Explicit ending.** Reaching end of book shows a clear **"Finished" state** — never a silent stop on the last word.
- **FR6 — Chapter-transition beat.** Crossing a chapter boundary shows a **brief transition card (~1.4 s settling pause with the chapter title)** rather than running chapters together. (Doubles as background pre-fetch window — FR18.) *Cut-line candidate: demotes to fast-follow under schedule pressure.*
- **FR7 — Long-word handling.** Words wider than the display handled gracefully. `[ASSUMPTION]` **Scale font down for the outlier word and extend its dwell**, rather than splitting. Stream reserves a continuation flag in case splitting becomes necessary on the round display.

### B. Reading Controls (WATCH)
- **FR8 — Play/pause, two-stage.** Primary button toggles playback. **Pause coasts to the next sentence end before stopping** (preserves comprehension); an **instant-pause mode available in settings.**
- **FR9 — Speed adjust in flow.** Dedicated buttons adjust WPM up/down **during playback without interrupting it.**
- **FR10 — Sentence rewind.** A single control **rewinds to a previous sentence boundary, auto-pauses, and persists position.** Recovery path for RSVP's classic failure mode (glance away → lost).
- **FR11 — Context on pause.** Paused view shows **surrounding text (scrollable, current word marked)** rather than a frozen single word — "here's where you are," not "here's where you froze." *Cut-line candidate: demotes to fast-follow under schedule pressure.*
- **FR12 — Buttons first, touch mirrors.** All core actions operable via **physical buttons** (eyes-free, sweat-proof); touch gestures mirror them. `[ASSUMPTION]` **Tap = play/pause, horizontal swipe = rewind.**

### C. Resume & Position Sync (WATCH + PHONE)
- **FR13 — Absolute position.** Reading position is a single **absolute word index per book** — universal coordinate for resume, rewind, progress, sync.
- **FR14 — Eager persistence.** Watch persists position on **every pause, app exit, chunk boundary, and disconnect.** Survives watch reboot, app crash, BLE drop, phone app restart, and **abrupt session loss from navigating away to the watch-face/glance carousel.**
- **FR15 — Two-way sync.** Position syncs watch↔phone whenever connected. On reconnect: **timestamped last-writer-wins** reconciliation; within clock-skew window, ties resolve to the watch.
- **FR16 — Progress visible.** Per-book reading progress visible in the **phone library.**

### D. Book Delivery (PHONE↔WATCH)
- **FR17 — Phone does the heavy lifting.** Companion converts books into a timed word stream; watch never parses source formats.
- **FR18 — Pre-load ahead of playback.** Content loads in chapter-sized units ahead of need; wireless transfer never on playback's critical path. Next chapter fetches in background mid-chapter.
- **FR19 — Phone-free reading.** Already-loaded content fully readable with **phone absent or disconnected.** Fetching new content requires the phone; position reconciles on reconnect.
- **FR20 — Resilient transfer.** Idempotent, offset-addressed. Documented transfer failures **degrade to a visible "waiting for phone" state** — never corrupted/out-of-order text. Content fingerprint prevents stale-chunk blending; mismatch forces clean re-fetch.
- **FR21 — Transfer visibility.** **Book-to-watch delivery progress is visible on the phone.**

### E. Companion Library (PHONE)
- **FR22 — Import.** EPUB (first-class), .txt, .md via **file picker and the OS share sheet.**
- **FR23 — Library list.** Books listed with **title, author (where available), reading progress, and last-read time.**
- **FR24 — Send to watch.** **One book active on the watch at a time;** user selects and switches the active book from the phone.
- **FR25 — Remove.** Books can be deleted from the library.
- **FR26 — Import failures are survivable.** Malformed/unsupported file → **clear, actionable error** — never a crash, never a silently broken book.

### F. Openness (release; minimal UX surface)
- **FR27 — Published artifacts.** Ships on Connect IQ Store (free) + public GitHub (MIT). (Release path / store listing.)
- **FR28 — Documented protocol.** Streaming protocol documented for third-party compatibility.

---

## 3. Named User Journeys / Scenarios

There are no formally numbered journeys, but these named scenarios/moments are explicit and load-bearing:

- **"The demo moment" (Goal §3.1 / Scope cut-line):** import a real EPUB on the phone → open it on the Fenix 8 → read — uninterrupted playback at chosen WPM, **no manual chunk-wrangling.** *Never cut.*
- **"The author finishes one real book entirely on the watch" (Goal §3.2):** frictionless proven by use.
- **"Resume never lies" (Goal §3.4 / FR14 / NFR4):** position survives disconnects, app restarts, watch reboots. After abrupt termination, resume may **trail** last word read by a few seconds (one persistence interval ~15 s) but **never overshoots past unread text** and is never wholly lost. Trailing = re-read a sentence (acceptable); overshooting = miss one (a lie, unacceptable).
- **RSVP recovery / "glance away and you're lost" (FR10):** sentence rewind is the explicit recovery flow.
- **Phone-free reading (FR19):** read loaded content with phone absent; reconcile on reconnect.
- **"Waiting for phone" state (FR20):** transfer failure degradation flow.
- **Carousel hazard (addendum §4):** navigating from the activity app to watch-face/glance carousel stops the session and discards state → resume must feel instant. A UX wrinkle to soften.

---

## 4. Stated UX/UI Requirements, Constraints, Principles

### Display & rendering (watch)
- **ORP/pivot letter:** anchor at **~35% of text width**; pivot letter highlighted; **per-glyph highlight**. Anchor does not shift between words.
- **ORP length→pivot table** (addendum §2): ≤1 char → 0th letter, ≤5 → 1st, ≤9 → 2nd, ≤13 → 3rd, else 4th.
- **Custom bitmap font** sized for **454×454 round AMOLED**; precompute glyph widths for ORP alignment; usable text width = the **circle's chord at the text row** (round-display constraint).
- **Small per-word position jitter for burn-in protection** (AMOLED).
- **Chapter-transition card:** ~1.4 s settling pause showing chapter title (FR6).
- **"Finished" state** explicit (FR5).
- Long words: scale-down-and-extend dwell (FR7); splitting reserved via continuation flag.

### Controls / input mapping (watch)
- **Buttons-first, touch mirrors** (FR12). Eyes-free, sweat-proof.
- **Input map (addendum §4, `[ASSUMPTION]`-adjacent):**
  - START/ENTER = play/pause
  - UP/DOWN = WPM ± (adjust in flow)
  - BACK short = sentence rewind; BACK long = exit
  - **Avoid LIGHT button for core actions.**
  - Touch: **tap = play/pause, horizontal swipe = rewind.**
- **Two-stage pause:** coasts to sentence end; instant-pause toggle in settings (FR8).

### Settings (watch)
- At least one settings surface implied: **instant-pause mode toggle** (FR8). WPM is a live control, not buried in settings.

### Companion app (phone) UX
- **Library list** with title / author / progress / last-read time (FR23).
- **Import** via file picker + OS share sheet (FR22).
- **Send-to-watch / switch active book** (one active at a time) (FR24).
- **Remove book** (FR25).
- **Progress visible per book** (FR16).
- **Transfer progress visible** (FR21).
- **Clear actionable error messaging** on import failure (FR26).
- Scope explicitly **bare-bones:** "No covers, no metadata polish" (brief). Full library management (covers, metadata) is **Later**.

### Principles (stated)
- "The watch renders, the phone thinks" (R5) — minimize watch-side logic.
- Flat WPM "feels robotic" — variable timing is core to the product feel (FR2).
- "Resume never lies" — the single most-protected guarantee.
- Comprehension-preserving controls (coast-to-sentence-end pause; sentence rewind).

---

## 5. Non-Functional Requirements Affecting UX

- **NFR1 — Timing fidelity.** Drift-free advance over a full session; solid at **700 WPM**, headroom to **1000**. (Render loop: one-shot timer re-armed per word; 50 ms platform floor.)
- **NFR4 — Position durability.** Never wholly lost, never jumps ahead. Abrupt termination may trail by **at most one persistence interval (~15 s while playing; zero on any pause/exit/boundary).**
- **NFR5 — Responsiveness.** Opening active book to **first displayed word ≤3 s** when content is on the watch. `[ASSUMPTION]` Importing a typical **100k-word novel ≤30 s** on phone **without blocking the UI.**
- **NFR8 — Crash posture.** Malformed/truncated data degrades gracefully (skip, refetch, report) — **never crash mid-read.**
- **Battery counter-metric (§3):** 60-min continuous session in primary screen-on mode, **target ≤10%/hour**; a session must **never silently trip low-battery behavior.** `[ASSUMPTION]` on the 10% threshold.
- **NFR6 — Compatibility:** Fenix 8 (CIQ API 6.0, firmware ≥12.35); Android first, Flutter keeps iOS in reach; Garmin Connect Mobile is a prerequisite.
- **NFR2/NFR3 — Memory/storage caps** (≤600 KB heap; 32 KB/value, ~100 KB total storage) — mostly invisible to UX but bound chunking behavior.
- **Offline:** FR19 — phone-free reading of loaded content is a hard requirement.
- **Latency note (addendum §3):** BLE round-trip 1–2 s — why transfer must never be on playback's critical path; long word-granular seeks are "a UX problem to solve" (deferred).

---

## 6. Scope Boundaries — Explicitly OUT of Scope

### MVP includes (this PRD)
RSVP playback w/ ORP pivot, variable timing, on-watch controls, per-book resume + two-way sync, sentence rewind, context-on-pause, chapter-transition beat, bare-bones phone library (import EPUB/.txt/.md, send to watch).

### Fast-follow (v1.x)
- **Chapter/paragraph navigation on the watch.**
- **Dimmed phantom adjacent words during playback** (teardown-recommended recovery pattern — deferred to keep MVP playback view minimal).

### Later
- **Word-granular scrub/seek while paused** (protocol is random-access-ready from day one; BLE latency makes it a UX problem).
- Full library management (covers, metadata).
- Typography options.
- Reading stats.
- Additional CIQ devices.
- iOS companion.

### OUT of scope (hard)
- Kindle / DRM formats (Calibre-convert path instead).
- Read-it-later integrations.
- **Multi-book watch library** (one active book on the watch at a time).
- **Hebrew/RTL scripts** — explicitly deferred; but word-stream format must not preclude them (NFR7 — RTL later is a renderer change, not a format migration).

### Cut line (under schedule pressure)
- **FR11 (context-on-pause)** and **FR6 (chapter-transition beat)** demote to fast-follow first.
- **Never cut:** the demo moment (§3.1) and the resume guarantee (§3.4).

---

## 7. Open Questions / Deferred Decisions Touching UX

- **OQ1 — Competitor specifics (deferred).** What the existing paid CIQ RSVP reader gets wrong (import friction? no companion? pacing?) is uncaptured; differentiation claims stay directional. Revisit before writing the store listing.
- **OQ2 — Companion bridge sufficiency.** Whether the thin community Flutter↔CIQ bridge suffices or a custom platform-channel layer is needed — resolves during gate V2. Shifts effort, not requirements.
- **R1 / Gate V1 (HIGH, UX-critical):** AMOLED screen-on during hands-off reading. Primary path (activity-recording session) is medium-confidence; **fallback "dim always-on" floor (~10% luminance) may render a single bright word illegible** — itself an assumption until tested on hardware. If both fail, the product premise needs rework. **This directly gates whether FR4's hands-off reading experience is achievable and what the degraded UX looks like.**
- **Assumptions flagged `[ASSUMPTION]` that touch UX:** WPM range/default (100–900, default 300, FR3); long-word scale-down approach (FR7); touch gesture mapping (tap/swipe, FR12); import time ≤30 s (NFR5); 10%/hour battery threshold.
- **Pacing percentages** (addendum §2) were tuned for RSVP Nano hardware; expect recalibration on Fenix 8 — affects perceived reading feel.

---

## 8. Brand / Tone / Naming / Voice

- **Product name: PaceTurner.** (Brief used the working title "RSVP Speed Reader for Garmin"; PRD/addendum name it PaceTurner.)
- Name connotes pacing + page-turning — fits the "set your pace, turn pages hands-free" concept.
- **Tone (inferred from copy):** plainspoken, confident, slightly wry ("builder's itch," "the watch does exactly one thing well," "resume never lies," "here's where you are, not here's where you froze"). Functional and honest rather than marketing-glossy.
- **Voice principles for UI copy (derived):** terse and reassuring on the watch (tiny screen); clear, actionable, non-blaming error copy on the phone (FR26). States named in human terms: "Finished," "waiting for phone."
- **Brand positioning words:** free, open-source, book-first.
- Open-source ethos: MIT license, documented protocol, clean architecture — the brand promise extends to developers/contributors, not just readers.

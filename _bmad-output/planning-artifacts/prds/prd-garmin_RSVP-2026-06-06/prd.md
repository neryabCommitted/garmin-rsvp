---
title: PaceTurner PRD
status: final
created: 2026-06-06
updated: 2026-06-06
---

# PaceTurner — Product Requirements Document

**One-liner:** Open an e-book on your phone, raise your wrist, and read it — one word at a time, at your pace, without friction.

PaceTurner is a free, open-source RSVP (Rapid Serial Visual Presentation) reader for Garmin watches. A Flutter companion app does the heavy lifting — importing and parsing books, baking per-word timing into a compact word stream — while the watch does exactly one thing well: display the next word at the right moment. Initial target is the Garmin Fenix 8 with an Android phone.

## 1. Why This Exists

The honest founding motivation is builder's itch: the author owns a Fenix 8, saw RSVP Nano (an ESP32 RSVP reader), and wants the Garmin version to exist. But the niche is real and underserved — as of June 2026 the Connect IQ Store has exactly one paid RSVP reader (tried, found unsatisfying) and one page-based eBook app, while book-reading on Garmin has been a forum request for years. The paid competitor validates demand; its existence defines the positioning: **free, open-source, and book-first**.

This is a personal project first, a product for others second — but with publish-quality ambitions: success is a working, polished, publishable reader, not a revenue line.

## 2. Users

- **User #1 (guaranteed):** the author — Fenix 8 on wrist, Android phone, library of DRM-free EPUBs.
- **Adopters (hypothesis):** RSVP/speed-reading enthusiasts who own Garmins; Connect IQ tinkerers; readers who want to clear a backlog without pulling out their phone.
- **Contributors (open-source):** CIQ and mobile developers — served by clean architecture, a documented streaming protocol, and a permissive license.

No further persona work is warranted at these stakes; User #1's daily use is the validation instrument.

## 3. Goals & Success Criteria

1. **The demo moment works end-to-end:** import a real EPUB on the phone, open it on the Fenix 8, and read — uninterrupted playback at chosen WPM, no manual chunk-wrangling.
2. **The author finishes one real book entirely on the watch.** Frictionless is proven by use, not claimed.
3. **Published:** live on the Connect IQ Store (free) and on a public GitHub repo (MIT) with a README explaining the architecture and a documented phone↔watch streaming protocol.
4. **Resume never lies:** position sync survives disconnects, app restarts, and watch reboots. A book reader that loses your place has failed its one job. Defined precisely: after abrupt termination, resume may trail the last word read by a few seconds (one persistence interval) — but it never overshoots past unread text and is never wholly lost. Trailing means re-reading a sentence; overshooting means missing one. Only the second is a lie.

**Counter-metric (validation gate, not promise):** battery cost of a reading session — measured as a 60-minute continuous session in the primary screen-on mode (active display, sync connected). Target ≤10%/hour, measured on real hardware; a session must never silently trip the watch into low-battery behavior. `[ASSUMPTION]` 10%/hour is the right threshold for "guilt-free daily use" — revisit after first hardware measurement.

## 4. Scope

**MVP (this PRD):** RSVP playback with ORP pivot, variable word timing, on-watch controls, per-book resume with two-way sync, sentence rewind, context-on-pause, chapter-transition beat, bare-bones phone library (import EPUB/.txt/.md, send to watch).

**Fast-follow (v1.x):** chapter/paragraph navigation on watch; dimmed phantom adjacent words during playback (the teardown-recommended recovery pattern — deferred to keep the MVP playback view minimal).

**Later:** word-granular scrub/seek while paused (the transfer protocol is designed for random access from day one, so nothing blocks it); full library management (covers, metadata), typography options, reading stats, additional CIQ devices, iOS companion.

**Out of scope:** Kindle/DRM formats (Calibre-convert path instead), read-it-later integrations, multi-book watch library, Hebrew/RTL scripts (explicitly deferred — but the word-stream format must not preclude them, see NFR7).

**Cut line (one developer, schedule pressure is a when, not an if):** FR11 (context-on-pause) and FR6 (chapter-transition beat) demote to fast-follow first. The demo moment (§3.1) and the resume guarantee (§3.4) are never cut — without them there is no product.

## 5. Functional Requirements

### A. RSVP Playback (watch)

- **FR1 — One word, fixed focal point.** The watch displays a single word at a time with the ORP (optimal recognition point) pivot letter visually highlighted and anchored at a fixed horizontal position (~35% of text width). Rendering is stable: the anchor does not shift between words.
- **FR2 — Variable timing.** Per-word display duration varies with word length/complexity and punctuation (sentence ends, commas, dashes pause longer) — flat WPM is what makes RSVP feel robotic. Timing derives from metadata baked into the word stream by the phone; the watch applies it without computing linguistics.
- **FR3 — WPM control.** Reading speed is user-adjustable during playback. Range 10–1000 WPM with adaptive step size (10 below 100 WPM, 25 at/above), default 250 (resolved with UX 2026-06-06; supersedes the earlier 100–900/300 assumption). WPM changes take effect immediately and never require re-fetching content.
- **FR4 — Hands-off playback.** During playback the display stays readable without user interaction for a full session (≥60 minutes continuous). If platform constraints force degradation (see Risk R1), the acceptable fallback is a dim always-on display that a single button press restores. Requiring an interaction every minute to keep reading is a non-starter.
- **FR5 — Explicit ending.** Reaching the end of a book shows a clear "Finished" state — never a silent stop on the last word.
- **FR6 — Chapter-transition beat.** Crossing a chapter boundary shows a brief transition card (~1.4 s settling pause with the chapter title) rather than running chapters together. This beat doubles as the natural window for background pre-fetch (FR18).
- **FR7 — Long-word handling.** Words wider than the usable display are handled gracefully. `[ASSUMPTION]` Scale font down for the outlier word and extend its dwell, rather than splitting words. The stream format reserves a continuation flag in case splitting proves necessary on the round display.

### B. Reading Controls (watch)

- **FR8 — Play/pause, two-stage.** Primary button toggles playback. Pause coasts to the next sentence end before stopping (preserves comprehension); an instant-pause mode is available in settings.
- **FR9 — Speed adjust in flow.** Dedicated buttons adjust WPM up/down during playback without interrupting it.
- **FR10 — Sentence rewind.** A single control rewinds to a previous sentence boundary, auto-pauses, and persists position. This is the recovery path for RSVP's classic failure mode: one glance away and you're lost.
- **FR11 — Context on pause.** The paused view shows the surrounding text (scrollable, current word marked) rather than a frozen single word — "here's where you are," not "here's where you froze."
- **FR12 — Buttons first, touch mirrors.** All core actions are operable via physical buttons (eyes-free, sweat-proof); touch gestures mirror them. `[ASSUMPTION]` Tap = play/pause, horizontal swipe = rewind.

### C. Resume & Position Sync

- **FR13 — Absolute position.** Reading position is a single absolute word index per book — the universal coordinate for resume, rewind, progress, and sync.
- **FR14 — Eager persistence.** The watch persists position on every pause, app exit, chunk boundary, and disconnect. Position survives watch reboot, app crash, BLE drop, phone app restart, and abrupt session loss from navigating away to the watch-face/glance carousel.
- **FR15 — Two-way sync.** Position syncs watch↔phone whenever connected. On reconnect after independent updates, reconciliation is deterministic — **decision:** timestamped last-writer-wins (not max-index, which would fight deliberate rewinds). Clock skew is bounded because the watch syncs time from the phone; within the skew window, ties resolve to the watch — the device where reading actually happens.
- **FR16 — Progress visible.** Per-book reading progress is visible in the phone library.

### D. Book Delivery (phone↔watch)

- **FR17 — Phone does the heavy lifting.** The companion converts imported books into a timed word stream. The watch never parses source formats.
- **FR18 — Pre-load ahead of playback.** Content loads to the watch in chapter-sized units ahead of need; wireless transfer is never on playback's critical path. Mid-chapter, the next chapter fetches in the background.
- **FR19 — Phone-free reading.** Already-loaded content is fully readable with the phone absent or disconnected. Fetching new content requires the phone; position reconciles on reconnect (FR15).
- **FR20 — Resilient transfer.** The delivery protocol is idempotent and offset-addressed: retries are safe, duplicates are harmless, and documented platform transfer failures (see R2) degrade to a visible "waiting for phone" state — never to corrupted or out-of-order text. Every delivered chunk is tied to a content fingerprint of the converted book version, so re-importing or re-converting a book can never blend stale chunks with a new position index — a mismatch forces a clean re-fetch.
- **FR21 — Transfer visibility.** Book-to-watch delivery progress is visible on the phone.

### E. Companion Library (phone)

- **FR22 — Import.** EPUB (first-class), .txt, and .md import via file picker and the OS share sheet.
- **FR23 — Library list.** Books listed with title, author where available, reading progress, and last-read time.
- **FR24 — Send to watch.** One book is active on the watch at a time; the user selects and switches the active book from the phone.
- **FR25 — Remove.** Books can be deleted from the library.
- **FR26 — Import failures are survivable.** A malformed or unsupported file produces a clear, actionable error — never a crash, never a silently broken book.

### F. Openness (release requirements)

- **FR27 — Published artifacts.** PaceTurner ships on the Connect IQ Store (free) and as a public GitHub repository under the MIT license. Release path: Garmin developer verification (a store precondition since Feb 2025) → beta-channel listing for hardware validation with early adopters → public listing.
- **FR28 — Documented protocol.** The phone↔watch streaming protocol is documented well enough for a third party to build a compatible companion (e.g., an iOS port) without reading the source.

## 6. Non-Functional Requirements

- **NFR1 — Timing fidelity.** Playback advance is drift-free over a full session (errors don't accumulate); sustained playback is solid at 700 WPM with headroom to 1000.
- **NFR2 — Watch memory.** Peak watch-app heap stays ≤600 KB of the Fenix 8's 768 KB watch-app budget, leaving headroom for fonts, transfer buffers, and framework overhead.
- **NFR3 — Platform storage limits.** Persistent watch storage respects the 32 KB/value and ~100 KB total platform caps; bulk book content lives in memory/app storage accordingly, never in the settings store.
- **NFR4 — Position durability.** Reading position is never wholly lost and never jumps ahead of unread text. On abrupt termination it may trail live reading by at most one persistence interval (~15 s while playing; zero on any pause/exit/boundary, per FR14). Book content is always re-fetchable from the phone; position is the only state that must not be sacrificed.
- **NFR5 — Responsiveness.** Opening the active book to first displayed word takes ≤3 s when content is already on the watch. `[ASSUMPTION]` Importing a typical 100k-word novel completes in ≤30 s on the phone without blocking the UI.
- **NFR6 — Compatibility.** Watch: Garmin Fenix 8 (Connect IQ API 6.0, firmware ≥12.35). Phone: Android first; the companion codebase (Flutter) keeps iOS in reach. Garmin Connect Mobile installed is an accepted prerequisite.
- **NFR7 — Script-agnostic stream.** The word-stream format carries per-word rendering metadata (pivot index, dwell) rather than assuming Latin script, so RTL/Hebrew support later is a renderer change, not a format migration.
- **NFR8 — Crash posture.** Malformed or truncated data on either device degrades gracefully (skip, refetch, or report) — bounds-check and degrade, never crash mid-read.

## 7. Risks & Validation Gates

Ordered; the first two gate the architecture and must be validated on real hardware before it hardens. **Sequencing discipline:** V1 and V2 are not just engineering tasks — they block downstream planning. Do not break playback or transfer epics into implementation stories until their gates pass; everything else (companion library, parsing pipeline, protocol design on paper) can proceed in parallel.

- **R1 — AMOLED screen-on during hands-off reading (HIGH).** A normal watch-app cannot keep the display lit (forced backlight throws after ~1 minute on burn-in-protected AMOLED); the documented mitigation (running playback inside an activity-recording session) is medium-confidence. **Gate V1:** validate on Fenix 8 hardware in the first build spike — and validate the FR4 fallback too: always-on mode runs on a ~10% luminance budget, which may render a single bright word illegible, so the "dim AON" floor is itself an assumption until tested. If both the primary path and the fallback fail, the product premise needs rework.
- **R2 — Android transfer reliability (HIGH).** A documented platform bug can silently fail repeat phone→watch sends. **Gate V2:** multi-send integration test on real hardware, week one. The protocol (FR20) is designed assuming this failure.
- **R3 — Transfer chunk ceiling (MEDIUM).** Per-message size limits are undocumented and device-specific. **Gate V3:** empirically calibrate chunk size on Fenix 8.
- **R4 — Battery cost (MEDIUM).** Screen-on + session + sync drain is unquantified. **Gate V4:** measure a 1-hour reading session against the ≤10%/hour target (§3).
- **R5 — New language risk (MEDIUM).** Monkey C is new to the author. Mitigated by strict typing from commit 1, exemplar-repo CI, and keeping watch-side logic minimal — the watch renders, the phone thinks.
- **R6 — EPUB-in-the-wild variability (MEDIUM).** Real-world EPUBs are malformed, obfuscated, footnote-riddled, and creatively encoded; the extraction pipeline is untested at scale. Mitigated by the extraction pre-filter and Unicode-sanitation constraints (addendum §2), the FR26 error posture, and an ugly-EPUB fixture corpus for the importer's tests.

## 8. Open Questions

- **OQ1 — Competitor specifics (deferred by choice).** What the existing paid CIQ RSVP reader concretely gets wrong remains uncaptured; differentiation claims stay directional (free, open-source, book-first) until someone does the teardown. Owner: PM. Revisit: before writing the store listing.
- **OQ2 — Companion bridge sufficiency.** Whether the thin community Flutter↔CIQ bridge plugin suffices, or a custom platform-channel layer is needed, resolves during V2. Either answer is acceptable; it shifts effort, not requirements.

## 9. Document Map

- **Technical depth** (stream format, protocol design, library choices, patterns adopted from RSVP Nano): `addendum.md` — input to architecture, deliberately kept out of this PRD.
- **Decisions and their history:** `.decision-log.md`.
- **Source inputs:** product brief (2026-06-05) and five technical research reports (2026-06-06) in `_bmad-output/planning-artifacts/`.

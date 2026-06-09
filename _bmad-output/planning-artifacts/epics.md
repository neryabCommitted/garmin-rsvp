---
stepsCompleted: [1, 2, 3]
inputDocuments:
  - '_bmad-output/planning-artifacts/prds/prd-garmin_RSVP-2026-06-06/prd.md'
  - '_bmad-output/planning-artifacts/prds/prd-garmin_RSVP-2026-06-06/addendum.md'
  - '_bmad-output/planning-artifacts/architecture.md'
  - '_bmad-output/planning-artifacts/ux-designs/ux-garmin_RSVP-2026-06-06/EXPERIENCE.md'
  - '_bmad-output/planning-artifacts/ux-designs/ux-garmin_RSVP-2026-06-06/DESIGN.md'
---

# PaceTurner - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for PaceTurner, decomposing the requirements from the PRD, UX Design, and Architecture into implementable stories.

**Standing sequencing discipline (PRD §7, Architecture C1):** hardware gates **V1** (AMOLED screen-on) and **V2** (Android transfer reliability) must pass on a real Fenix 8 *before* the playback and transfer epics are hardened or story-split into implementation. Companion parse pipeline, stream format, and protocol-on-paper proceed in parallel.

## Requirements Inventory

### Functional Requirements

**A. RSVP Playback (watch)**

- **FR1 — One word, fixed focal point.** Single word at a time, ORP pivot letter highlighted and anchored at a fixed horizontal position (~35% of text width); anchor does not shift between words.
- **FR2 — Variable timing.** Per-word display duration varies with word length/complexity and punctuation; timing derives from metadata baked into the word stream by the phone — the watch applies it without computing linguistics.
- **FR3 — WPM control.** Reading speed user-adjustable during playback. `[ASSUMPTION]` Range 100–900 WPM (UX/addendum widen to 10–1000), adaptive step, default 300 (UX sets 250). Changes take effect immediately, never re-fetch content.
- **FR4 — Hands-off playback.** Display stays readable without interaction for ≥60 min continuous. If platform forces degradation (R1), acceptable fallback is a dim always-on display restored by one button press. *(Gate V1 conditional.)*
- **FR5 — Explicit ending.** Reaching end of book shows a clear "Finished" state — never a silent stop on the last word.
- **FR6 — Chapter-transition beat.** Crossing a chapter boundary shows a brief transition card (~1.4 s settling pause + chapter title); doubles as the background pre-fetch window (FR18). *(Cut-line demotable to fast-follow.)*
- **FR7 — Long-word handling.** Words wider than the usable display handled gracefully. `[ASSUMPTION]` Scale font down + extend dwell rather than splitting; stream reserves a continuation flag in case splitting proves necessary.

**B. Reading Controls (watch)**

- **FR8 — Play/pause, two-stage.** Primary button toggles playback; pause coasts to the next sentence end before stopping. Instant-pause mode available in settings.
- **FR9 — Speed adjust in flow.** Dedicated buttons adjust WPM up/down during playback without interrupting it.
- **FR10 — Sentence rewind.** Single control rewinds to a previous sentence boundary, auto-pauses, and persists position.
- **FR11 — Context on pause.** Paused view shows surrounding text (scrollable, current word marked) rather than a frozen single word. *(Cut-line demotable to fast-follow.)*
- **FR12 — Buttons first, touch mirrors.** All core actions operable via physical buttons (eyes-free, sweat-proof); touch gestures mirror them and are toggleable off. `[ASSUMPTION]` Tap = play/pause, horizontal swipe = rewind.

**C. Resume & Position Sync**

- **FR13 — Absolute position.** Reading position is a single absolute word index per book — the universal coordinate for resume, rewind, progress, and sync.
- **FR14 — Eager persistence.** Watch persists position on every pause, app exit, chunk boundary, and disconnect; survives watch reboot, app crash, BLE drop, phone app restart, and carousel-navigate-away.
- **FR15 — Two-way sync.** Position syncs watch↔phone whenever connected; on reconnect, reconciliation is deterministic timestamped last-writer-wins (watch-wins tiebreak inside the clock-skew window).
- **FR16 — Progress visible.** Per-book reading progress visible in the phone library.

**D. Book Delivery (phone↔watch)**

- **FR17 — Phone does the heavy lifting.** Companion converts imported books into a timed word stream; the watch never parses source formats.
- **FR18 — Pre-load ahead of playback.** Content loads to the watch in chapter-sized units ahead of need; wireless transfer never on playback's critical path. Mid-chapter, the next chapter fetches in the background.
- **FR19 — Phone-free reading.** Already-loaded content fully readable with the phone absent or disconnected; fetching new content requires the phone; position reconciles on reconnect.
- **FR20 — Resilient transfer.** Delivery protocol idempotent and offset-addressed; retries safe, duplicates harmless; documented platform failures degrade to a visible "waiting for phone" state — never corrupted/out-of-order text. Every chunk tied to a content fingerprint of the converted book version; mismatch forces a clean re-fetch.
- **FR21 — Transfer visibility.** Book-to-watch delivery progress visible on the phone.

**E. Companion Library (phone)**

- **FR22 — Import.** EPUB (first-class), .txt, and .md import via file picker and the OS share sheet.
- **FR23 — Library list.** Books listed with title, author where available, reading progress, and last-read time.
- **FR24 — Send to watch.** One book active on the watch at a time; user selects and switches the active book from the phone.
- **FR25 — Remove.** Books can be deleted from the library.
- **FR26 — Import failures are survivable.** Malformed/unsupported file produces a clear, actionable error — never a crash, never a silently broken book.

**F. Openness (release requirements)**

- **FR27 — Published artifacts.** Ships on the Connect IQ Store (free) and as a public GitHub repo under MIT. Release path: Garmin developer verification → beta-channel listing for hardware validation → public listing.
- **FR28 — Documented protocol.** The phone↔watch streaming protocol documented well enough for a third party to build a compatible companion without reading the source.

### NonFunctional Requirements

- **NFR1 — Timing fidelity.** Playback advance drift-free over a full session (errors don't accumulate); sustained playback solid at 700 WPM with headroom to 1000.
- **NFR2 — Watch memory.** Peak watch-app heap ≤600 KB of the Fenix 8's 768 KB budget, leaving headroom for fonts, transfer buffers, framework overhead.
- **NFR3 — Platform storage limits.** Persistent watch storage respects 32 KB/value and ~100 KB total caps; bulk book content lives in memory/app storage, never the settings store.
- **NFR4 — Position durability.** Position never wholly lost and never jumps ahead of unread text; on abrupt termination may trail live reading by at most one persistence interval (~15 s playing; zero on any pause/exit/boundary).
- **NFR5 — Responsiveness.** Open active book to first displayed word ≤3 s when content already on watch. `[ASSUMPTION]` Import of a typical 100k-word novel ≤30 s on phone without blocking the UI.
- **NFR6 — Compatibility.** Watch: Fenix 8 (CIQ API 6.0, firmware ≥12.35). Phone: Android first, Flutter codebase keeps iOS in reach. Garmin Connect Mobile installed is an accepted prerequisite.
- **NFR7 — Script-agnostic stream.** Word-stream format carries per-word rendering metadata (pivot index, dwell) rather than assuming Latin script; RTL/Hebrew later is a renderer change, not a format migration.
- **NFR8 — Crash posture.** Malformed/truncated data on either device degrades gracefully (skip, refetch, or report) — bounds-check and degrade, never crash mid-read.

### Additional Requirements

*Technical/infrastructure requirements from Architecture + Addendum that drive story creation.*

**Project setup & toolchain**

- **AR1 — Starter scaffolds.** Watch: VS Code "Monkey C: New Project" generator (watch-app, API 6.0, fenix8 family). Companion: `flutter create` (org `dev.paceturner`, platforms android,ios, app template). No forked starters. `matco/badminton` adopted as CI/structure *reference*, not a fork.
- **AR2 — Monorepo topology.** Single public MIT monorepo: `watch/`, `companion/`, `protocol/`, `docs/`. Nothing imports across `watch/`↔`companion/`; the only shared artifact is `protocol/SPEC.md` + mirrored constants.
- **AR3 — CI from first commit.** GitHub Actions: `matco/action-connectiq-tester` (watch) + `flutter analyze` & `flutter test` (companion); both green from first commit.
- **AR4 — Strict typing.** Monkey C compiled at Strict (level 3) from commit 1; companion uses a strict `analysis_options.yaml`.
- **AR5 — Developer key + verification.** 4096-bit RSA developer key (hard build prerequisite); Garmin developer verification (required since Feb 2025) started early, not at submission.

**Protocol & stream format (the public contract)**

- **AR6 — Protocol SPEC.md.** Author `protocol/SPEC.md` (envelope, message types, binary word-record layout, flag bits, fingerprint, versioning, error semantics) — implementation story #2; prerequisite to V2/V3 harnesses (FR28).
- **AR7 — Message envelope.** CIQ `Dictionary` envelope + binary `ByteArray` payload `{t, v, fp, off, n, p}`; explicit version field from message one; message types `manifest`, `chunkRequest`, `chunkData`, `position`, `error`.
- **AR8 — Mirrored constants.** Protocol keys/types/version defined once in SPEC.md, mirrored as `Protocol.mc` (watch) and `protocol_keys.dart` (companion). No inline protocol strings anywhere; encode/decode sites cite SPEC.md section numbers.
- **AR9 — Word-stream format.** Binary-packed ~9 B/word (UTF-8 word + ORP pivot byte index + dwell bonus metadata + flags: paragraph-start, sentence-end, reserved continuation + direction bits); little-endian; debuggable JSONL master kept phone-side.
- **AR10 — Timing model.** Bake the WPM-invariant *bonus* per word at parse time (not the duration); watch applies `60000/wpm + bonus`. Pacing algorithm ports RSVP Nano's (length/complexity/punctuation tiers; abbreviation-aware sentence-end flagging).

**Watch architecture & runtime**

- **AR11 — Four-class separation.** `ReaderEngine` (pure logic, host-testable), `ChunkedWordSource` / `BookWordSource` seam, thin `Views`+`InputDelegates`, `SyncManager`. `DisplayStrategy` isolated behind its own seam so a gate-V1 failure swaps a module, not the architecture.
- **AR12 — Watch content residency.** Resident chapters persist to `Storage` in ≤32 KB buckets (current + next chapter), hard-capped ~80 KB of the ~100 KB total store; heap holds only the decoded reading window + render state. Oversized chapters split virtually by the delivery layer.
- **AR13 — Drift-free render loop.** One-shot timer re-armed per word (50 ms floor); `onUpdate` draws only the already-selected word; advance via `lastAdvance += duration` with catch-up capped (~4 words).
- **AR14 — Persistence discipline.** Every position write routes through `SyncManager.commitPosition(force)` — debounced ~15 s while playing, `force: true` on every transition (pause/exit/rewind/chunk-boundary/disconnect/onStop). Storage layout carries a schema-version key; mismatch wipes content cache, never position.
- **AR15 — Memory hygiene.** Reference-counting GC, no cycle collection → `WeakReference` for back-pointers; run markw65 optimizer before measuring size; sideload to real hardware early (simulator lies about memory/watchdog).
- **AR16 — Storage keys.** All Storage key construction in one `StorageKeys` module (`pos_<bookId>`, `chunk_<bookId>_<bucket>`, `meta_<bookId>`, `schemaVersion`, `settings`); never ad-hoc literals.
- **AR17 — Managed Communications API only.** `Raw.sendMessage()` forbidden (known-broken); ≤2 outstanding transfers (under 3-cap); next request only from `onComplete()` or watchdog timeout.

**Companion architecture**

- **AR18 — Phone data layer.** drift (2.x) for metadata/positions (reactive queries → live FR16); flat files for word streams (+ JSONL debug master); never multi-MB blobs in SQLite. Migrations via drift schema migrations.
- **AR19 — State management.** Riverpod (flutter_riverpod 3.3.1); `ui/ → services/ → data/` layering; UI never touches the CIQ bridge or drift directly; `services/import/` pure Dart, isolate-run.
- **AR20 — Import pipeline.** epub_pro (OCF/OPF/spine/TOC) + DIY `html` DOM-pre-filtered extraction (drop noteref/footnote/ruby/img-alt; table policy); Unicode sanitation (NFC, strip soft-hyphen/zero-width, NBSP→space, optional ASCII-fold); abbreviation-aware tokenizer; pacing/ORP/fingerprint stages. Ugly-EPUB fixture corpus for tests (R6).
- **AR21 — CIQ bridge seam.** `watch_connectivity_garmin` v0.1.12 wrapped behind `ciq_bridge.dart` (swap seam for custom MethodChannel fallback — OQ2, resolves during V2).
- **AR22 — Android foreground service.** Active transfers run under an Android foreground service (transfer bar = its notification) so pull-based delivery survives app backgrounding.
- **AR23 — Transfer engine.** Chunking (~200–500 words on sentence/paragraph boundaries, never split a word), ≤2 in-flight, idempotent offset-addressed re-request; V2 defense (timeout → SDK re-init → resend) in one place; V3 chunk-size calibration hook; progress reporting (FR21).

**Error posture & quality**

- **AR24 — Named-state error handling.** Every failure surfaces as a member of an enumerated state set — watch: `WaitingForPhone`, `Buffering`, `BookChanged`, `StorageFull`, `Finished`; companion: typed import/transfer failure results with user-facing message + next step. No silent `catch {}`; bounds-check-and-degrade at every byte-ingest boundary (NFR8).
- **AR25 — Logging budget.** Dart: `dart:developer log` with service prefixes. Monkey C: `System.println` budgeted (~10 KB on-device log) — state transitions/errors only, never per-word; verbose behind `(:debug)` excluded from release.

**Release & ops**

- **AR26 — Release machinery.** Beta-channel listing precedes public listing; ERA crash monitoring enabled from the first store build (field signal for "resume never lies" violations).

**Validation gates (hardware)**

- **AR27 — Gate V1.** Validate AMOLED screen-on (ActivityRecording session) for ≥60-min hands-off reading on Fenix 8 hardware in the first build spike — and validate the FR4 dim-AON fallback legibility. Blocks hardening/story-splitting of the playback epic.
- **AR28 — Gate V2.** Multi-send phone→watch integration test on real hardware, week one (Android first-send bug defense). Blocks hardening/story-splitting of the transfer epic; also resolves OQ2 (bridge sufficiency).
- **AR29 — Gate V3.** Empirically calibrate per-message chunk size on Fenix 8 (`BLE_REQUEST_TOO_LARGE` ceiling undocumented; start ≤1 KB).
- **AR30 — Gate V4.** Measure a 1-hour reading session against the ≤10%/hour battery target on real hardware.
- **AR31 — Gate tracking.** `docs/gates.md` is the single status page for V1–V4 (procedure, status, results); gate-blocked work references it. Font memory cost joins the on-device validation list.

### UX Design Requirements

*Extracted from EXPERIENCE.md (behavior) + DESIGN.md (visual). Each is specific enough to generate testable stories.*

**Design system & tokens**

- **UX-DR1 — Watch palette & rule.** Four-value AMOLED-native palette — Void `#000000` (canvas), Ink `#EAE6DF` (current word only at full brightness), Ink-Dim `#8A867F` (paused chrome/status), Ink-Faint `#45423E` (phantoms/guide marks), Pivot `#FF5349` (pivot letter + anchor ticks only). Rule: "if it isn't the current word, it doesn't get to be bright." No status colors, gradients, or second accent on the watch.
- **UX-DR2 — Watch typography.** Atkinson Hyperlegible as BMFont resources across roles: `word-display` 48px/400, `context-body` 26px/1.45, `chapter-title` 28px/700, `watch-meta` 22px. Only the active word-display size heap-resident (load-on-demand on size change); native-font fallback is the documented escape hatch.
- **UX-DR3 — Phone design system.** Material 3 with dynamic color (Material You), system light/dark followed, full M3 semantic palette; seed `#FF5349` as fallback + active-book marker. M3 type roles (Title Large / Body Large / Body Small); single column, 16dp margin, no tablet layout, no custom chrome/hero animations.
- **UX-DR4 — Burn-in citizenship.** No element occupies fixed pixels indefinitely; playback composition applies a slow per-session jitter (±2px random walk, per-session/per-pause not per-word). Mostly-black composition, no persistent chrome while words flow. Flat (no elevation/shadow on watch); hierarchy is brightness.

**Watch reading-surface components**

- **UX-DR5 — Word display.** One word, pivot letter in Pivot color, rest in Ink, pivot center on the anchor line at 35% width (user-tunable 30–60%). Advances on baked per-word dwell; drift-free `+= duration`; WPM change takes effect next word. Long words shown whole, margin-clamped at 28px edge, pivot drifts off-anchor before any truncation.
- **UX-DR6 — Guide marks + anchor ticks.** Split horizontal hairlines above/below the word in Ink-Faint with a gap at the anchor column and short anchor ticks in Pivot (not a full crosshair). Toggleable.
- **UX-DR7 — Phantom words.** Previous/next words flanking the focal word in Ink-Faint, same baseline/size; update with the stream; toggleable in settings.
- **UX-DR8 — Progress readout.** Book % + time remaining (from cumulative-duration array) + current WPM, in Ink-Dim `watch-meta`. **Visible only when paused**, never during playback.
- **UX-DR9 — Chapter card.** Chapter number + title (`chapter-title`) on Void, progress beneath in Ink-Dim. Resume behavior is a setting: **Auto** (~2 s then resume) or **Wait** (resume on START), default Auto. Doubles as the next-chapter prefetch window.
- **UX-DR10 — Start ramp.** Brief 3-beat (3-2-1) word-cadence lead-in before the stream starts on resume/play (fixes RSVP Nano's cold start); implemented in `ReaderEngine` (host-testable).
- **UX-DR11 — Status views.** WaitingForPhone, Buffering (minimal indeterminate dot cycle), BookChanged, StorageFull, Finished — each one plain-text sentence in Ink-Dim, centered in the ~320px safe square. No icons, no spinners (except the Buffering dot cycle).

**Watch states & continuity**

- **UX-DR12 — Named state treatments.** WaitingForPhone shown only when playback cannot proceed from local storage (never interrupts buffered reading). Buffering target rare (current+next residency). BookChanged: "Book changed on phone — starting {title}", one-tap acknowledge. StorageFull non-blocking for current book. Dim/AON fallback: playback auto-pauses when display dims, touch-to-wake resumes paused never mid-stream — words never flow on an unreadable screen.
- **UX-DR13 — Abrupt-kill resume.** No graceful-exit assumption (carousel hazard); relaunch lands on **Paused** at-or-before the last force-saved word, never past it.
- **UX-DR14 — Finished screen.** Explicit end state + stats (e.g. "Finished. 6h 41m across 19 days."); BACK exits; re-read is a phone-side decision.

**Watch input (map provisional; principles fixed)**

- **UX-DR15 — Input principles (fixed).** Buttons always work; touch is an opt-in mirror behind a "Touch controls" setting (default On); BACK keeps its Garmin exit meaning everywhere; LIGHT off-limits; `onKey` + `onTap`, never `onSelect`; every touch gesture has a button path. Handedness setting mirrors swipe directions.
- **UX-DR16 — Input map (provisional, revalidate on hardware).** Playing: START/tap = pause-coast (instant mode in settings), UP/DOWN = WPM± (transient readout), swipe-right = pause+rewind one sentence, MENU = pause+settings, BACK = exit (force-saved). Paused: START/tap = resume (ramp), swipe-right/UP = rewind (stackable), DOWN/swipe-up = context view, BACK = exit (from context → back to Paused). Banned: remapping BACK, multi-level menus, double-tap semantics, touch-only actions.

**Watch settings surface**

- **UX-DR17 — Settings menu.** Menu2 surface over the `"settings"` Storage key: WPM, pause mode (coast/instant), chapter-card resume (Auto/Wait), touch controls (On/Off), font size (±2 steps), handedness, focus highlight, phantom words, anchor position. Per-device, never synced.

**Phone surfaces & components**

- **UX-DR18 — Library.** M3 ListTile rows: cover thumbnail, title, author, thin linear progress bar (M3 primary), last-read meta; active-on-watch book marked; tap → book detail; overflow → Send to watch / Remove. Empty state: "Add a DRM-free EPUB to begin." + import action.
- **UX-DR19 — Book detail.** Cover art (when the EPUB carries one), title/author/metadata, progress (% + time remaining), chapter list with jump-to-chapter (confirm → sets absolute word index + re-syncs watch). Actions: Send to watch (prominent M3 filled button), Restart book (asks once), Remove.
- **UX-DR20 — Import.** FAB + OS share-sheet entry → parse → appears in library. Import failure inline on library: "Couldn't read {filename} — {reason}"; the book never half-appears.
- **UX-DR21 — Transfer bar.** M3 linear progress + one-line label ("Sending to watch — chapter 4 of 31"); inline never modal; cancellable; survives app backgrounding; supports retry without restarting from chunk zero; never blocks the library.
- **UX-DR22 — Cover extraction.** Cover art extracted from the EPUB phone-side (`cover_extractor`), stored as a file + `cover_path` on the Books table; never enters the protocol or the watch.

**Voice, accessibility, screen survival**

- **UX-DR23 — Microcopy/voice.** Quiet-librarian tone: short, factual, no exclamation marks, no mascot energy ("Waiting for phone" not "Connection error!"; "Storage full — remove a book on your phone" not "Error 507").
- **UX-DR24 — Accessibility floor.** Pivot never marked by color alone (anchor ticks + guide-mark gap point geometrically — color-blind safe); focus highlight / phantom words / guide marks each individually toggleable; user font-size setting (±2 steps); Atkinson Hyperlegible for glyph disambiguation at flash speed. Phone: keep M3 TalkBack labels, 48dp targets, dynamic type; every custom widget (transfer bar) labeled with role + state. Watch: every status view is plain text not iconography.
- **UX-DR25 — Screen survival.** Primary path: activity session keeps the display lit (honest about activity-grade battery draw). Fallback: if gate V1 fails, the dim/AON auto-pause-on-dim pattern governs. The UX survives the gate failing; the product promise (uninterrupted hands-off reading) does not — V1 is a gate, not a footnote.

### FR Coverage Map

- **FR1** — Epic 3 — ORP single-word display, fixed anchor
- **FR2** — Epic 3 — Variable per-word timing from baked stream metadata
- **FR3** — Epic 3 — WPM control during playback (immediate, no re-fetch)
- **FR4** — Epic 3 — Hands-off ≥60-min readable display (gate V1 path + dim-AON fallback)
- **FR5** — Epic 3 — Explicit Finished state
- **FR6** — Epic 3 — Chapter-transition card (doubles as prefetch window)
- **FR7** — Epic 3 — Long-word handling (scale-down + extend; continuation flag reserved)
- **FR8** — Epic 3 — Two-stage play/pause (coast to sentence end; instant mode in settings)
- **FR9** — Epic 3 — Speed adjust in flow without interrupting playback
- **FR10** — Epic 3 — Sentence rewind (auto-pause + persist)
- **FR11** — Epic 3 — Context on pause (scrollable surrounding text)
- **FR12** — Epic 3 — Buttons-first, touch mirrors (toggleable)
- **FR13** — Epic 3 — Absolute word index as universal coordinate
- **FR14** — Epic 3 — Eager local persistence; resume-never-lies on the watch
- **FR15** — Epic 4 — Two-way watch↔phone position sync (timestamped LWW)
- **FR16** — Epic 4 — Per-book progress visible in phone library
- **FR17** — Epic 2 — Phone converts books to the timed word stream; watch never parses
- **FR18** — Epic 4 — Chapter-granular pre-load ahead of playback
- **FR19** — Epic 4 — Phone-free reading of already-loaded content
- **FR20** — Epic 4 — Resilient idempotent offset-addressed transfer; fingerprint-keyed
- **FR21** — Epic 4 — Transfer progress visible on phone
- **FR22** — Epic 2 — Import EPUB/.txt/.md via picker + share sheet
- **FR23** — Epic 2 — Library list (title, author, progress, last-read)
- **FR24** — Epic 4 — Send to watch; one active book at a time
- **FR25** — Epic 2 — Remove books from library
- **FR26** — Epic 2 — Survivable import failures (clear, actionable errors)
- **FR27** — Epic 5 — Published on CIQ Store (free) + public MIT GitHub repo
- **FR28** — Epic 1 — Documented phone↔watch protocol (`protocol/SPEC.md` authored as the living contract; release-polished in Epic 5)

**Validation gates:** V1, V2, V3 → Epic 1 (architecture-gating, hardware). V4 (battery) → Epic 3 (measured during a real reading session).

## Epic List

### Epic 1: Foundation & Hardware Feasibility

Stand up the public MIT monorepo, both scaffolds (Monkey C watch-app + Flutter companion), the 4096-bit RSA developer key, strict typing on both sides, and green CI from the first commit; author `protocol/SPEC.md` as the public contract (envelope, message types, binary word-record layout, flag bits, fingerprint, versioning, error semantics); then retire the two product-killing hardware risks on a real Fenix 8 — gate V1 (AMOLED screen-on for ≥60-min hands-off reading, plus dim-AON fallback legibility) and gate V2 (reliable phone→watch multi-send) — and calibrate gate V3 (per-message chunk-size ceiling). Outcome: the product is proven buildable on this hardware and the protocol contract exists; all downstream epics are unblocked.
**FRs covered:** FR28
**Gates:** V1, V2, V3 — **ARs:** AR1, AR2, AR3, AR4, AR5, AR6, AR7, AR8, AR27, AR28, AR29, AR31

### Epic 2: Phone Library & Book Conversion

Import EPUB (first-class), .txt, and .md via file picker and the OS share sheet; run the isolate-based parse pipeline (epub_pro structure + DOM-pre-filtered extraction, Unicode sanitation, abbreviation-aware tokenization, RSVP-Nano-derived pacing baked as WPM-invariant bonuses, ORP byte index, content fingerprint) to produce the binary word stream + extracted cover; list books with title/author/cover; show a book-detail screen; remove books; and make every malformed/unsupported file produce a clear, actionable error — never a crash or a half-imported book. Gate-independent, parallelizable with Epic 3. Outcome: a working phone librarian that turns real books into the wire format.
**FRs covered:** FR17, FR22, FR23, FR25, FR26
**ARs:** AR9, AR10, AR18, AR19, AR20, AR24 (companion error states) — **UX-DR:** 3, 18, 19, 20, 22, 23, 24

### Epic 3: RSVP Reading on the Wrist

Build the watch reader over a local/canned word source: ORP-anchored single-word playback with variable baked timing, immediate WPM control, hands-off ≥60-min display (gate-V1 activity-session path with the dim-AON auto-pause fallback), two-stage pause coasting to sentence end, speed-in-flow, sentence rewind, context-on-pause, buttons-first input with the opt-in touch mirror, chapter-transition card, long-word handling, Finished screen, and the start ramp — all over the four-class watch architecture with the drift-free render loop, full design-token/component fidelity, accessibility floor, and burn-in citizenship; plus eager local persistence so resume-never-lies holds on the watch alone (absolute word index, force-save on every transition, survives the carousel kill). Measure gate V4 (battery) on a real reading session. Outcome: words flash on the wrist and you can read and resume hands-off.
**FRs covered:** FR1, FR2, FR3, FR4, FR5, FR6, FR7, FR8, FR9, FR10, FR11, FR12, FR13, FR14
**Gate:** V4 — **ARs:** AR11, AR13, AR15, AR25, AR30, AR31 — **UX-DR:** 1, 2, 4, 5, 6, 7, 8, 9, 10, 11 (Finished), 13, 14, 15, 16, 17, 25

### Epic 4: Content Delivery & Two-Way Sync

Wire the two halves together: the phone transfer engine (Android foreground service, chunking on sentence/paragraph boundaries, ≤2 in-flight, the V2 timeout→re-init→resend defense, V3 chunk-size hook, cancellable progress bar) feeding the watch ProtocolClient + ChunkedWordSource + Storage-bucket residency (current + next chapter, ~80 KB cap); send-to-watch with one active book at a time and the BookChanged handshake; phone-free reading of resident content; resilient fingerprint-keyed idempotent transfer with the WaitingForPhone/Buffering/StorageFull named states; two-way LWW position sync; and live per-book progress in the phone library. Swap the reader's fake source for real delivered chapters. Gated on V2/V3 from Epic 1. Outcome: the demo moment — import on the phone, read on the wrist, position survives everything.
**FRs covered:** FR15, FR16, FR18, FR19, FR20, FR21, FR24
**ARs:** AR7, AR12, AR14, AR16, AR17, AR21, AR22, AR23, AR24 — **UX-DR:** 11 (transfer/connection states), 12, 13, 21

### Epic 5: Open-Source Publish

Finalize the public MIT repository and the README architecture story, polish `protocol/SPEC.md` plus worked byte-level examples to a third-party-implementable standard (FR28's release form), complete Garmin developer verification, ship the beta-channel Connect IQ Store listing for early-adopter hardware validation and then the public free listing, and enable ERA crash monitoring as the field signal for resume-never-lies violations. Outcome: PaceTurner is live and open.
**FRs covered:** FR27
**ARs:** AR2, AR5, AR26

## Epic 1: Foundation & Hardware Feasibility

Stand up the public MIT monorepo, both scaffolds, the developer key, strict typing, and green CI; author `protocol/SPEC.md` as the public contract; then retire the two product-killing hardware risks (V1 screen-on, V2 transfer reliability) and calibrate V3 (chunk-size ceiling) on a real Fenix 8. Outcome: the product is proven buildable on this hardware and all downstream epics are unblocked.

### Story 1.1: Monorepo, dual scaffolds, dev key & green CI

As a developer,
I want the monorepo standing with both app scaffolds, the signing key, and CI passing,
So that every later story lands in a buildable, tested, releasable skeleton.

**Acceptance Criteria:**

**Given** a fresh clone
**When** I inspect the repo root
**Then** it contains `watch/`, `companion/`, `protocol/`, `docs/`, `LICENSE` (MIT), and a `README.md` stub
**And** `watch/` and `companion/` share no cross-imports.

**Given** the Monkey C toolchain
**When** the watch app builds
**Then** it targets CIQ API 6.0 / fenix8 family at Strict (level 3) type-checking
**And** produces a runnable build in the simulator.

**Given** the Flutter toolchain
**When** the companion builds
**Then** the `flutter create` output (org `dev.paceturner`, platforms android+ios with iOS untargeted) compiles
**And** `flutter analyze` passes under a strict `analysis_options.yaml`.

**Given** a 4096-bit RSA developer key generated and stored per Garmin's process
**When** a release-mode watch build runs
**Then** it signs successfully
**And** Garmin developer verification has been initiated with status tracked in `docs/setup.md`.

**Given** a push to the repo
**When** CI runs
**Then** `action-connectiq-tester` (watch) and `flutter analyze` + `flutter test` (companion) both run and pass green.

### Story 1.2: Protocol SPEC.md and mirrored constants

As a developer (and a future third-party implementer),
I want the phone↔watch protocol written down as the single source of truth with mirrored constants on both sides,
So that the transfer and gate-test work has a stable contract to build against (FR28).

**Acceptance Criteria:**

**Given** `protocol/SPEC.md`
**When** I read it
**Then** it fully specifies the `{t, v, fp, off, n, p}` envelope, the five message types (`manifest`, `chunkRequest`, `chunkData`, `position`, `error`), the little-endian binary word-record layout (~9 B/word), the flag-bit positions (sentenceEnd, paragraphStart, chapterStart, reserved continuation + direction), fingerprint semantics, the versioning rule, and error semantics.

**Given** the spec
**When** I inspect `watch/source/Protocol.mc` and `companion/lib/protocol/protocol_keys.dart`
**Then** every message-type and field key is defined once per side as a named constant mirroring the spec
**And** no inline protocol string literals exist at call sites.

**Given** the spec's worked byte-level examples
**When** round-trip encode/decode tests run on both sides
**Then** each side reproduces the spec's example bytes exactly.

**Given** an unknown protocol-version value
**When** either side decodes it
**Then** it is rejected and reported, never guessed.

### Story 1.3: Gate V1 — hands-off screen-on feasibility (hardware)

As a developer,
I want to prove on a real Fenix 8 that the display can stay readable hands-off for a full reading session,
So that the playback epic's core premise (FR4) is validated before it hardens.

**Acceptance Criteria:**

**Given** a minimal spike app opening an `ActivityRecording.Session`
**When** it runs on Fenix 8 hardware with no user interaction
**Then** the display stays lit and legible for ≥60 continuous minutes without tripping the backlight timeout.

**Given** the dim always-on fallback path
**When** the activity-session path is unavailable or fails
**Then** a single bright word is tested for legibility on the ~10% luminance budget
**And** the result (legible / not) is recorded.

**Given** either outcome
**When** the spike completes
**Then** `docs/gates.md` records V1 status, method, and result
**And** if both the primary and fallback paths fail, the premise-rework flag is raised explicitly.

### Story 1.4: Gate V2 — transfer reliability & bridge sufficiency (hardware)

As a developer,
I want to prove reliable repeated phone→watch sends on real hardware and decide whether the community bridge suffices,
So that the delivery epic's protocol design (FR20) is validated and OQ2 is resolved before it hardens.

**Acceptance Criteria:**

**Given** a spike using the managed Communications API over `watch_connectivity_garmin`
**When** the phone sends many chunks in sequence to the Fenix 8
**Then** the documented "first-send-works-then-fails" Android bug is either not observed or is defeated by the timeout → SDK re-init → resend defense
**And** a measured success rate is recorded.

**Given** the spike results
**When** bridge sufficiency is assessed
**Then** OQ2 is resolved with a decision (keep `watch_connectivity_garmin` vs build a custom MethodChannel bridge) recorded in `docs/decisions/`.

**Given** the run
**When** it completes
**Then** `docs/gates.md` records V2 status, method, success rate, and the bridge decision.

### Story 1.5: Gate V3 — chunk-size calibration (hardware)

As a developer,
I want the empirical per-message size ceiling on Fenix 8,
So that the transfer engine ships with a calibrated chunk size instead of a guess.

**Acceptance Criteria:**

**Given** the V2 transfer harness
**When** chunk sizes are swept upward from a conservative ≤1 KB
**Then** the `BLE_REQUEST_TOO_LARGE` (-102) threshold is found
**And** the safe working chunk size is recorded.

**Given** the calibrated value
**When** it is captured
**Then** it is recorded in `docs/gates.md` as the V3 result
**And** it is referenced by the transfer engine's chunk-size config (Epic 4).

## Epic 2: Phone Library & Book Conversion

Import EPUB/.txt/.md via file picker and the OS share sheet; run the isolate-based parse pipeline to produce the binary word stream + extracted cover; list books; show a book-detail screen; remove books; and make every malformed file produce a clear, actionable error. Outcome: a working phone librarian that turns real books into the wire format. Gate-independent — parallelizable with Epic 3.

### Story 2.1: Text sanitation & tokenization

As a developer,
I want raw book text sanitized and tokenized into words carrying sentence/paragraph flags,
So that the downstream stream baking has clean, correctly-segmented input (the FR8/FR10 correctness foundation).

**Acceptance Criteria:**

**Given** raw text with soft hyphens, zero-width characters, and NBSPs
**When** the sanitizer runs
**Then** output is NFC-normalized, soft-hyphens and zero-width stripped, NBSP→space
**And** glyphs missing from the watch font are optionally ASCII-folded.

**Given** sanitized text
**When** the tokenizer runs (Unicode `\p{L}\p{N}`, `unicode: true`)
**Then** it emits a word list where each word carries `paragraphStart` and `sentenceEnd` flags.

**Given** abbreviations and initialisms ("Dr.", "U.S.", "e.g.")
**When** sentence-end flagging runs
**Then** those periods do not set `sentenceEnd` (abbreviation-aware), verified against a fixture set.

**Given** the tokenizer
**When** tests run
**Then** it is pure Dart (no Flutter imports) and runs in an isolate.

### Story 2.2: Word-stream baking (pacing, ORP, fingerprint, encode)

As a developer,
I want tokens baked into the compact binary word stream with per-word timing and pivot metadata,
So that the watch can play a book without computing any linguistics (FR17, NFR7).

**Acceptance Criteria:**

**Given** flagged tokens
**When** pacing runs
**Then** each word gets a WPM-invariant bonus (length/complexity/punctuation tiers per the addendum), never an absolute duration.

**Given** each word
**When** ORP runs
**Then** the pivot is computed by the length→ordinal table and stored as a UTF-8 byte index into the word.

**Given** a converted book
**When** baking completes
**Then** it produces a binary stream (~9 B/word, little-endian, flag bits per `protocol/SPEC.md`) plus a JSONL debug master
**And** a content fingerprint for the conversion.

**Given** the encoder output
**When** decoded by the watch-side decoder against the SPEC examples
**Then** it round-trips exactly (cross-checked with the Story 1.2 fixtures).

**Given** a baked book
**When** the manifest is produced
**Then** it carries the chapter index, cumulative durations, and the fingerprint.

### Story 2.3: Import .txt/.md into the library

As a reader,
I want to import a .txt or .md file and see it appear in my library,
So that the simplest book path works end-to-end before EPUB complexity.

**Acceptance Criteria:**

**Given** a .txt or .md file
**When** I import it via the file picker or the OS share sheet
**Then** `import_service` runs the 2.1→2.2 pipeline in an isolate and persists a stream file + a drift `Books` row (md → HTML → same extractor).

**Given** the import completes
**When** I view the library
**Then** the book appears as an M3 ListTile with a filename-derived title and a last-read placeholder, with a thin progress bar at 0%.

**Given** an empty library
**When** I open the app
**Then** I see "Add a DRM-free EPUB to begin." with an import action.

**Given** the import runs
**When** parsing a large file
**Then** the UI does not block (isolate)
**And** a typical 100k-word file completes in ≤30 s (NFR5).

**Given** the drift schema
**When** this story lands
**Then** only the `Books` (and `Chapters`) tables needed here are created — no unused tables.

### Story 2.4: Import EPUB with cover and chapters

As a reader,
I want to import an EPUB and get its real chapters and cover,
So that first-class books look and read properly.

**Acceptance Criteria:**

**Given** an EPUB
**When** I import it
**Then** epub_pro reads OCF/OPF/spine/TOC and a DOM-pre-filter spine walk extracts prose, dropping noteref/footnote anchors, `<rt>` ruby, and image alt text, with an explicit table policy.

**Given** the EPUB carries a cover
**When** import runs
**Then** `cover_extractor` writes a cover image file and sets `cover_path` on the `Books` row
**And** the cover never enters the stream or protocol.

**Given** the parsed EPUB
**When** baked
**Then** chapter boundaries set `chapterStart` flags and populate the manifest chapter index.

**Given** the library
**When** the EPUB appears
**Then** its row shows cover thumbnail, title, and author from the OPF metadata.

### Story 2.5: Book detail and remove

As a reader,
I want a detail screen for each book and the ability to remove it,
So that I can see metadata and manage my library (FR25).

**Acceptance Criteria:**

**Given** a library row
**When** I tap it
**Then** the book-detail screen shows cover, title/author/metadata, a progress area (% + time-remaining placeholder until Epic 4), and the chapter list.

**Given** book detail
**When** I view the actions
**Then** "Send to watch" (prominent M3 filled button), Restart book, and Remove are present — and Send-to-watch and jump-to-chapter render **visibly disabled (inert)** until Epic 4 wires their actions, so there is no dead button that appears functional.

**Given** a book
**When** I Remove it
**Then** its drift rows, stream file, and cover file are deleted and it disappears from the library.

**Given** Restart book
**When** I tap it
**Then** it asks once before confirming (the reposition effect lands with sync in Epic 4).

### Story 2.6: Survivable import failures

As a reader,
I want a clear message when a file can't be read,
So that a bad book never crashes the app or half-appears (FR26, R6).

**Acceptance Criteria:**

**Given** a malformed, DRM-protected, or unsupported file
**When** import fails
**Then** `import_service` returns a typed failure result, never an exception that crashes the app.

**Given** a failed import
**When** I look at the library
**Then** I see an inline message "Couldn't read {filename} — {reason}"
**And** no partial book row, stream file, or cover is left behind.

**Given** the ugly-EPUB fixture corpus (footnote-riddled, obfuscated, creatively encoded)
**When** the importer test suite runs
**Then** each fixture either imports cleanly or fails with a typed, message-bearing result — never a crash or mid-sentence pollution.

## Epic 3: RSVP Reading on the Wrist

Build the watch reader over a local/canned word source: ORP-anchored single-word playback with variable baked timing, immediate WPM control, hands-off display (gate-V1 path + dim-AON fallback), two-stage pause, speed-in-flow, sentence rewind, context-on-pause, buttons-first input with opt-in touch mirror, chapter card, long-word handling, Finished screen, start ramp, and settings menu — plus eager local persistence so resume-never-lies holds on the watch alone. Measure gate V4 (battery). Outcome: words flash on the wrist and you can read and resume hands-off. Cut-line note: FR11 (Story 3.4) and FR6 (Story 3.5) are the PRD's demote-able items.

### Story 3.1: ReaderEngine & settings model — drift-free advance, timing, WPM, rewind (pure logic)

As a developer,
I want the reading engine and a defaulted settings model as pure, host-testable logic over a fake word source,
So that pacing, position, rewind, and configurable behavior are correct and available before any pixels or menus exist (FR2, FR3, FR13).

**Acceptance Criteria:**

**Given** the `Settings` model
**When** instantiated
**Then** it exposes per-device defaults (WPM 250, pause mode coast, touch on, font size 0, handedness right, focus highlight on, phantom words on, anchor 35%) with **pure default values testable without Storage** (the `"settings"` Storage key is a thin persistence adapter) — establishing the configuration source that Stories 3.2/3.3 read and Story 3.8 later edits via a menu.

**Given** a `FakeWordSource` and a clock
**When** the engine plays
**Then** it advances via `lastAdvance += duration` (drift-free), applying `60000/wpm + bonus` per word, with catch-up capped (~4 words).

**Given** playback
**When** WPM changes
**Then** it takes effect on the next word with no content re-fetch and no drift.

**Given** a play/resume
**When** it starts
**Then** a 3-beat start ramp precedes the stream.

**Given** a pause request
**When** issued in coast mode
**Then** the engine advances to the next `sentenceEnd` then stops; in instant mode it stops immediately.

**Given** a rewind request
**When** issued
**Then** the index moves to a previous sentence boundary and the engine auto-pauses; rewind is stackable.

**Given** the engine
**When** tests run
**Then** it imports no `Toybox.WatchUi`/`Communications` and passes host-side under `action-connectiq-tester`.

### Story 3.2: PlaybackView — ORP word rendering

As a reader,
I want one word at a time with the pivot anchored and the page dark,
So that RSVP reading is stable and legible (FR1, FR7).

**Acceptance Criteria:**

**Given** a word
**When** rendered
**Then** the pivot letter is in Pivot color and the rest in Ink on a true-black canvas, with the pivot's center on the anchor line at 35% width (tunable 30–60%)
**And** the anchor does not shift between words.

**Given** guide marks
**When** drawn
**Then** they are split hairlines above/below in Ink-Faint with a gap at the anchor column and short anchor ticks in Pivot (geometry points at the pivot — color-blind safe, UX-DR24).

**Given** phantom words enabled
**When** playing
**Then** previous/next words flank the focal word in Ink-Faint at the same baseline.

**Given** a word wider than the usable width
**When** rendered
**Then** it shows whole, margin-clamped at 28px, with the pivot allowed to drift off-anchor rather than truncating (continuation flag honored if present).

**Given** playback
**When** the composition draws
**Then** Atkinson Hyperlegible BMFont is used, a per-session ±2px jitter is applied (burn-in), `onUpdate` draws only the already-selected word, and no persistent bright chrome appears.

### Story 3.3: Playback controls & input mapping

As a reader,
I want buttons-first controls with a touch mirror,
So that I can pause, adjust speed, and rewind eyes-free mid-stride (FR8, FR9, FR10, FR12).

**Acceptance Criteria:**

**Given** playback
**When** I press START (or tap, if touch on)
**Then** it pauses per the coast/instant setting read from the Settings model (established in Story 3.1).

**Given** playback
**When** I press UP/DOWN
**Then** WPM steps (adaptive: 10 below 100, 25 at/above) without interrupting the stream, with a transient WPM readout.

**Given** playback
**When** I swipe right (touch on) or use the button-path rewind
**Then** it pauses and rewinds one sentence.

**Given** the input map
**When** any action is invoked
**Then** every action has a physical-button path, BACK exits (position force-saved), LIGHT is unused, and handlers use `onKey`+`onTap` never `onSelect`.

**Given** the "Touch controls" setting Off
**When** I read
**Then** all core actions remain fully button-operable.

### Story 3.4: Paused view & context-on-pause

As a reader,
I want the paused screen to show where I am and the surrounding text,
So that I can recover after a glance away (FR11).

**Acceptance Criteria:**

**Given** a pause
**When** the frozen word shows
**Then** the progress readout fades in (book %, time-remaining from cumulative durations, current WPM) in Ink-Dim
**And** it is never visible during playback (UX-DR8).

**Given** the paused view
**When** I press DOWN (or swipe up)
**Then** a scrollable context view shows the surrounding paragraph with the current word marked.

**Given** the context view
**When** I press BACK
**Then** it returns to Paused (not exit).

**Given** Paused
**When** I press START
**Then** playback resumes with the start ramp.

### Story 3.5: Chapter card, Finished screen & status-view shells

As a reader,
I want chapter breaks, an explicit ending, and worded system states,
So that the book has rhythm and never silently stops or hangs (FR5, FR6).

**Acceptance Criteria:**

**Given** a chapter boundary
**When** crossed
**Then** a chapter card shows number + title; resume behavior follows the Auto (~2 s)/Wait setting; the card doubles as the prefetch window (the prefetch trigger is wired in Epic 4).

**Given** the last word's dwell ends
**When** the book finishes
**Then** an explicit Finished screen shows stats (e.g. "Finished. 6h 41m across 19 days.") and BACK exits — never a silent stop.

**Given** the named states (WaitingForPhone, Buffering, BookChanged, StorageFull)
**When** rendered
**Then** each is one plain-text sentence in Ink-Dim centered in the safe square (Buffering may show a minimal dot cycle), no icons — the shells are **render-only with no interactive controls** here; their triggers (and BookChanged's one-tap acknowledge) are wired in Epic 4.

### Story 3.6: Local persistence & resume-never-lies

As a reader,
I want my position saved relentlessly on the watch,
So that a crash or carousel-kill never loses my place (FR14, NFR4).

**Acceptance Criteria:**

**Given** any position change
**When** it occurs
**Then** it routes through `SyncManager.commitPosition(force)` — debounced ~15 s while playing, `force:true` on pause/exit/rewind/chunk-boundary/disconnect/`onStop`
**And** no code writes position to Storage directly.

**Given** an abrupt kill (carousel navigation, no exit hook)
**When** I relaunch
**Then** the app opens on Paused at-or-before the last force-saved word — never past it.

**Given** Storage
**When** position is stored
**Then** it uses the per-book key via `StorageKeys`, and a schema-version key governs the layout (mismatch wipes content cache, never position).

**Given** position writes
**When** they happen
**Then** they are bounded and never crash on malformed Storage reads (bounds-check-and-degrade).

### Story 3.7: Display survival — screen-on strategy & fallback

As a reader,
I want the screen to stay readable for a full session,
So that hands-off reading actually works on the wrist (FR4, gate V1).

**Acceptance Criteria:**

**Given** the gate-V1 result
**When** the primary path is viable
**Then** `ActivitySessionStrategy` (behind the `DisplayStrategy` seam) keeps the display lit for the session.

**Given** the dim/AON fallback
**When** the display dims
**Then** playback auto-pauses; touch-to-wake resumes paused, never mid-stream — words never flow on an unreadable screen.

**Given** the seam
**When** the strategy is swapped
**Then** only the `display/` module changes — the rest of the reader is untouched.

### Story 3.8: Settings menu UI

As a reader,
I want a menu to edit the settings,
So that I can tune the reading experience to my eyes and hands (UX-DR17, UX-DR24).

**Acceptance Criteria:**

**Given** the Settings model (established in Story 3.1) and the MENU action
**When** opened
**Then** a Menu2 surface presents the model's values for editing: WPM, pause mode (coast/instant), chapter-card resume (Auto/Wait), touch controls (On/Off), font size (±2 steps), handedness, focus highlight, phantom words, anchor position.

**Given** a setting change in the menu
**When** applied
**Then** it updates the model, persists to the `"settings"` Storage key, takes effect immediately, and remains per-device, never synced.

**Given** a font-size change
**When** applied
**Then** only the active word-display size is heap-resident (load-on-demand); native-font fallback is the documented escape hatch if resource cost breaks NFR2.

**Given** handedness
**When** set
**Then** swipe directions mirror accordingly.

### Story 3.9: Gate V4 — reading-session battery measurement (hardware)

As a developer,
I want the battery cost of a real reading session measured,
So that "guilt-free daily use" is validated against the ≤10%/hour target.

**Acceptance Criteria:**

**Given** the full reader with the screen-on path active
**When** a 60-minute continuous session runs on Fenix 8 hardware (screen on, sync connected)
**Then** battery drain is measured and recorded in `docs/gates.md`.

**Given** the measurement
**When** it exceeds ≤10%/hour or trips low-battery behavior
**Then** the result is flagged for revisiting the threshold/strategy (per PRD assumption).

## Epic 4: Content Delivery & Two-Way Sync

Wire the two halves together: the phone transfer engine feeding the watch ProtocolClient + ChunkedWordSource + Storage residency; send-to-watch with one active book and the BookChanged handshake; phone-free reading; resilient fingerprint-keyed transfer with named states; two-way LWW position sync; and live per-book progress in the phone library. Swap the reader's fake source for real delivered chapters. Outcome: the demo moment — import on the phone, read on the wrist, position survives everything.

### Story 4.1: Watch — receive, store & serve chapters (ProtocolClient + ChunkedWordSource)

As a reader,
I want delivered chapters stored on the watch and served to the reader,
So that I read from local storage and the engine never waits on BLE (FR18, FR20).

**Acceptance Criteria:**

**Given** incoming `chunkData`
**When** `ProtocolClient` receives it
**Then** it validates fingerprint, offset, length, and bounds before commit, and rejects malformed chunks without crashing (NFR8).

**Given** validated chunks
**When** stored
**Then** they land in ≤32 KB `Storage` buckets via `StorageKeys`, capped at ~80 KB total (current + next chapter); chapters >32 KB split virtually by offset.

**Given** stored content
**When** `ChunkedWordSource` serves the reader
**Then** it exposes the `wordCount/wordAt/prefetchAround` seam over a decoded heap window, and a cache miss surfaces `Buffering` (the renderer never awaits BLE).

**Given** the engine from Epic 3
**When** this story lands
**Then** the `FakeWordSource` is swapped for `ChunkedWordSource` behind the same seam.

**Given** flow control
**When** requesting chunks
**Then** ≤2 transfers are outstanding and the next request issues only from `onComplete()` or a watchdog timeout, via the managed Communications API (never `Raw.sendMessage`).

### Story 4.2: Phone — transfer engine & foreground service

As a reader,
I want the phone to stream a book to the watch reliably even if I put the phone down,
So that delivery survives BLE flakiness and backgrounding (FR18, FR20).

**Acceptance Criteria:**

**Given** a book to send
**When** the transfer engine chunks it
**Then** chunks fall on sentence/paragraph boundaries (never splitting a word), sized to the V3-calibrated ceiling, each carrying the envelope `{t,v,fp,off,n,p}`.

**Given** the Android first-send bug
**When** a send times out
**Then** the single-location defense (timeout → SDK re-init → resend) recovers it, and re-requests are idempotent and offset-addressed (duplicates harmless).

**Given** an active transfer
**When** the app is backgrounded
**Then** an Android foreground service keeps the process alive to answer chunk requests, with the transfer bar text as its notification.

**Given** transfers
**When** running
**Then** ≤2 are in flight (under the 3-cap) and progress is reported for the UI.

### Story 4.3: Send to watch, one active book & BookChanged

As a reader,
I want to send a book from the phone and have the watch switch to it cleanly,
So that one book is active at a time and never silently swapped (FR24, FR21).

**Acceptance Criteria:**

**Given** book detail
**When** I tap "Send to watch"
**Then** delivery begins and an inline, cancellable transfer bar shows "Sending to watch — chapter X of N" (never modal, never blocks the library).

**Given** a transfer interrupted
**When** I retry
**Then** it resumes without restarting from chunk zero.

**Given** a new book sent while another is active
**When** the watch receives it
**Then** it shows BookChanged ("Book changed on phone — starting {title}") with one-tap acknowledge — never a silent mid-read swap; one book is active at a time.

**Given** the phone walks away mid-transfer (Flow 1)
**When** chapter 1 is already resident
**Then** the watch reads it with nothing on screen about the stalled transfer unless the reader outruns the buffer.

### Story 4.4: Phone-free reading & connection states

As a reader,
I want resident content fully readable offline with honest status when the phone is needed,
So that disconnection degrades visibly, never into corruption (FR19, FR20).

**Acceptance Criteria:**

**Given** resident chapters
**When** the phone is absent or disconnected
**Then** reading proceeds fully within stored content, silent unless I hit the buffer edge.

**Given** playback that cannot proceed from local storage
**When** content is missing
**Then** WaitingForPhone shows — and it never interrupts buffered reading.

**Given** a documented transfer failure
**When** it occurs
**Then** the watch lands in a named state (WaitingForPhone/Buffering/StorageFull) — never corrupted or out-of-order text.

**Given** StorageFull
**When** the store is at cap
**Then** the message is shown and the current book remains readable (non-blocking).

### Story 4.5: Two-way position sync (LWW) & live progress

As a reader,
I want my place to sync both ways and show progress on the phone,
So that I can read on either device and the library reflects reality (FR15, FR16).

**Acceptance Criteria:**

**Given** a position change on either device
**When** connected
**Then** it propagates via the `position` message (epoch-second timestamp + source).

**Given** independent updates on reconnect
**When** reconciled
**Then** timestamped last-writer-wins applies with the watch-wins tiebreak inside the clock-skew window — verified by mirrored `SyncManager`/`position_sync` tests.

**Given** the watch app was closed
**When** the phone sends position
**Then** mailbox persistence delivers it on next connect.

**Given** Restart book or jump-to-chapter on the phone (Epic 2 book detail)
**When** invoked
**Then** the deliberate backward reposition rides the existing `position` message and is not undone by LWW on the next reconnect.

**Given** a position update
**When** it reaches the phone
**Then** drift's reactive query updates the library row's progress (% + last-read) live via Riverpod (FR16).

### Story 4.6: Fingerprint integrity & clean re-fetch

As a reader,
I want a re-imported or re-converted book to never blend stale content with my position,
So that the text is always coherent (FR20, NFR4).

**Acceptance Criteria:**

**Given** every chunk request, chunk, and position record
**When** sent
**Then** each carries the conversion content fingerprint.

**Given** a fingerprint mismatch (book re-imported/re-converted)
**When** the watch detects it
**Then** cached chunks are invalidated and a clean re-fetch is forced — stale chunks never blend with a new index.

**Given** a schema-version or fingerprint mismatch
**When** the content cache is wiped
**Then** the position record is preserved (content is re-fetchable; position is sacred).

## Epic 5: Open-Source Publish

Finalize the public MIT repository and the README architecture story, polish `protocol/SPEC.md` plus worked byte-level examples to a third-party-implementable standard, complete Garmin developer verification, ship the beta-channel Connect IQ Store listing and then the public free listing, and enable ERA crash monitoring. Outcome: PaceTurner is live and open.

### Story 5.1: Public MIT repo & README architecture story

As a contributor,
I want a public repo with a README that explains the architecture,
So that I can understand and extend PaceTurner without reading all the source (Goal 3, FR27).

**Acceptance Criteria:**

**Given** the repo
**When** it goes public
**Then** it carries the MIT LICENSE and a README that tells the architecture story (inverted topology, baked stream, pull transfer, resume-never-lies) and links `protocol/SPEC.md`.

**Given** `docs/`
**When** a contributor reads it
**Then** `setup.md` (SDK/key/sideload/CI) and `gates.md` (V1–V4 results) are complete and current.

**Given** the monorepo
**When** cloned
**Then** both CI workflows are green on the public default branch.

### Story 5.2: Protocol docs to third-party-implementable standard

As a third-party implementer (e.g. an iOS port author),
I want the protocol fully documented with worked examples,
So that I can build a compatible companion without reading the source (FR28).

**Acceptance Criteria:**

**Given** `protocol/SPEC.md`
**When** finalized
**Then** it includes a glossary (absolute word index, content fingerprint, word stream, chapter-transition card) and versioning/error semantics in release-quality prose.

**Given** `protocol/examples/`
**When** a reader follows them
**Then** worked byte-level encode/decode examples cover every message type, and the round-trip conformance tests reference them.

**Given** the spec
**When** an implementer builds against it alone
**Then** nothing required to interoperate lives only in the source.

### Story 5.3: Garmin verification & beta-channel listing

As the author,
I want verification complete and a beta listing live,
So that early adopters can hardware-validate before the public sees it (FR27).

**Acceptance Criteria:**

**Given** Garmin developer verification (initiated in Story 1.1)
**When** this story runs
**Then** it is completed and recorded.

**Given** a release build
**When** packaged
**Then** the `.iq` is exported via the markw65 optimizer and meets the store's submission requirements.

**Given** the package
**When** submitted
**Then** a beta-channel Connect IQ Store listing (free) is live for early-adopter hardware validation.

### Story 5.4: Public listing & ERA crash monitoring

As the author,
I want the public listing live with crash monitoring,
So that PaceTurner ships and I get a field signal for resume-never-lies violations (FR27, AR26).

**Acceptance Criteria:**

**Given** beta validation passing
**When** promoted
**Then** the public free Connect IQ Store listing is live.

**Given** the first store build
**When** released
**Then** ERA crash monitoring is enabled and reporting.

**Given** ERA data
**When** a resume-never-lies violation (overshoot past unread text) occurs in the field
**Then** it surfaces as a monitored signal.

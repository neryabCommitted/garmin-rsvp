# PaceTurner PRD — Addendum

Technical depth and rejected-alternative rationale that informs architecture and solution design but does not belong in the PRD's main narrative. Sources: product brief (2026-06-05), five technical research reports (2026-06-06), RSVP Nano teardown.

## 1. Platform & Stack Decisions

| Decision | Choice | Rationale / Notes |
|---|---|---|
| Watch platform | Garmin Fenix 8, Connect IQ API 6.0, full watch-app (not widget/data-field) | Watch-app heap is 786,432 B (768 KB) — 6× the 128 KB data-field limit the brief originally feared. Target firmware ≥12.35 (fixed CIQ crashes). |
| Watch language | Monkey C, **Strict typing from commit 1** | Highest-leverage de-risking for a newcomer; converts runtime type/null crashes into compile errors. SDK 9.1.0 (May 2026). |
| Companion | **Flutter (Dart)**, Android first | Supersedes the brief's original Kotlin/Android decision (pivoted 2026-06-06). Shared codebase keeps iOS in reach. |
| CIQ bridge | `watch_connectivity_garmin` v0.1.12 to start | Thin (no Application Context support); plan to fork or write a custom MethodChannel/EventChannel bridge if it falls short. Resolves during gate V2. |
| EPUB parsing | `epub_pro` v5.6.0 for OCF/OPF/spine/TOC; **DIY text extraction** via `html` package walking the spine | Avoids epub_pro's documented nested-chapter bug; epubx is the fallback (popular but ~2 years stale). No viable prose segmenter on pub.dev — hand-roll Unicode-aware tokenization (`\p{L}\p{N}`, `unicode: true`). .txt/.md support is nearly free once the tokenizer exists (md → HTML → same extractor). |
| Phone storage | SQLite (drift/sqflite) for metadata/positions; flat files for word streams | Never store multi-MB streams as SQLite blobs. Parse/tokenize in an isolate; return file path, not content. |
| License | MIT | Matches RSVP Nano. |

## 2. Word-Stream Format

- Binary-packed, ~9 bytes/word: UTF-8 word + ORP pivot index byte + dwell metadata + flags (paragraph start, sentence end). A 100k-word novel ≈ 0.9 MB (vs 2.5–4 MB JSONL). Keep a debuggable master (JSONL or SQLite-referenced) on the phone.
- **Timing model — bake the bonus, not the duration.** RSVP Nano computes timing at read time; we bake at parse time because Monkey C is interpreted and the phone already parsed the text. Best synthesis from the teardown: store the per-word *WPM-invariant bonus*; watch applies `60000/wpm + bonus` per word. WPM changes stay free, stream stays compact.
- Pacing algorithm reference (port RSVP Nano's to Dart): base `60000/wpm` ms; length bonuses 6%/char >6 chars, 9% >10, 12% >14 (cap 170%); complexity bonuses (syllable groups up to +50%, mixed alphanumeric +22%, ALL-CAPS +14%, compound-joiner +14%; cap 85%); punctuation pauses — comma 45%, dash 60%, semicolon/colon 80%, ellipsis 110%, period 135% with abbreviation suppression, sentence end 150%. Sentence-end flagging must be abbreviation/initialism-aware on the phone segmenter — two-stage pause (FR8) and sentence rewind (FR10) depend on correct flags. Percentages were tuned for Nano's hardware; expect recalibration on Fenix 8 (medium risk).
- **Extraction quality pre-filter (behind FR17/FR26, feeds R6):** naive `html` `.text` over-includes. Walk the spine with a DOM pre-filter: drop noteref/footnote anchors, `<rt>` ruby annotations, and image alt text; apply an explicit policy for tables (skip or linearize). Without it, pollution lands mid-sentence in the word stream.
- **Unicode sanitation (same pipeline):** strip soft hyphens and zero-width characters, normalize NBSP→space, optionally ASCII-fold glyphs missing from the watch font. These characters silently break the precomputed ORP byte index and the custom bitmap font if left in.
- ORP: length→pivot ordinal table (≤1 → 0th, ≤5 → 1st, ≤9 → 2nd, ≤13 → 3rd, else 4th); anchor ~35% width; per-glyph highlight.
- **Continuation flag reserved** in the flags byte: FR7 assumes scale-down-and-extend for long words, but if splitting proves necessary on the round display, split words carry a continuation marker — reserving the bit now avoids a format migration.
- **RTL future-proofing (NFR7):** pivot index and dwell are per-word metadata, not renderer assumptions; flags byte has room for direction bits. Do not encode Latin-specific assumptions into the format.

## 3. Phone↔Watch Protocol

- **Topology: pull-based, chapter-granular pre-load.** Watch keeps current + next chapter resident; requests are offset-addressed ("K words from absolute index X") and idempotent — retries safe, duplicates harmless, resume trivial. Offset addressing also makes the protocol random-access-ready for the deferred scrub/seek feature — no change needed later.
- **Content fingerprint (FR20).** Every conversion produces a book-version fingerprint (à la Nano's `sourceFingerprint`); chunk requests and position records carry it. Mismatch (book re-imported/re-converted) invalidates cached chunks and forces clean re-fetch — stale chunks must never blend with a new index. The chapter-transition card (FR6) is the natural pre-fetch trigger window.
- Throughput is a non-issue (~120–190 B/s needed at 700 WPM vs ~0.5–1 KB/s available); **reliability is the design problem**, not bandwidth.
- Known platform hazards designed around:
  - Android `sendMessage` "first send works, rest fail" bug → per-request timeout + re-init + resend; bulk pre-load sidesteps mid-playback sends. Gate V2.
  - `BLE_REQUEST_TOO_LARGE` (-102): per-message ceiling undocumented; start conservative (≤1 KB chunks), calibrate empirically on Fenix 8. Gate V3.
  - Max 3 concurrent watch→phone transfers (`BLE_QUEUE_FULL` -101).
  - Round-trip latency 1–2 s — why transfer must never be on playback's critical path.
  - Raw BLE path (`Raw.sendMessage()`) is reported broken — use the managed Communications API only; relevant guardrail if a custom Flutter bridge is built.
  - A documented BLE ATT MTU bug can truncate payloads to ~20 bytes on some stacks — abstracted away by the managed API, but a reason not to drop below it.
  - iOS note (for the eventual port): backgrounded companions get extremely low BLE priority; iOS prefetch/sync design must assume foreground-only bulk transfer.
- Chapter chunking: ~200–500 words/chunk, never split a word, prefer sentence/paragraph boundaries, header carries absolute word index. Chapters >32 KB split into buckets (watch Storage value cap).
- Phone→watch mailbox persistence (messages queue while watch app closed) underpins position-sync recovery.
- Background sync (position/manifest only): 5-min minimum interval, 32 KB background heap — never used for content streaming.

## 4. Watch-App Design Notes

- **Screen-on strategy (gate V1):** register as activity app; open an `ActivityRecording.Session` on play — documented as avoiding idle timeout and keeping the display active. Medium confidence; validate on hardware before architecture hardens. Fallback ladder: dim always-on + button re-wake (acceptable, per PM decision 2026-06-06) → if even that fails, premise rework.
- Render loop: one-shot timer re-armed per word (variable dwell; 50 ms platform floor leaves headroom past 1000 WPM); `onUpdate` only draws the already-selected word (watchdog kills slow callbacks). Drift-free advance: `lastAdvance += duration`, catch-up capped (~4 words).
- Custom bitmap font sized for 454×454 round AMOLED; precompute glyph widths for ORP alignment; usable text width is the circle's chord at the text row. Small per-word position jitter for burn-in protection.
- Memory hygiene: reference-counting GC with no cycle collection — use `WeakReference` for back-pointers (view↔model, delegate↔view); run the markw65 optimizer before measuring size; sideload to real hardware early (simulator lies).
- Input map: START/ENTER = play-pause; UP/DOWN = WPM±; BACK short = sentence rewind, long = exit; avoid LIGHT for core actions. Touch mirrors: tap = play/pause, swipe = rewind.
- Position persistence: per-book key, debounce while playing (~15 s) + force on every transition (pause/exit/disconnect/chunk boundary) — Nano's proven "resume never lies" pattern.
- **Carousel hazard:** navigating from an activity app to the watch-face/glance carousel stops the session and discards state — the reason FR14's persistence list includes navigate-away, and a UX wrinkle to soften (resume must feel instant).
- CI: `matco/action-connectiq-tester` on GitHub Actions; `matco/badminton` as exemplar (UI-free, unit-tested model classes). Host-side tests over pure reader logic, mirroring Nano's ~60-test suite.
- **Release machinery (FR27):** 4096-bit RSA developer key is a build prerequisite; Garmin developer verification (required since Feb 2025) should be completed early, not at submission time; beta-channel listing precedes public. Post-release, ERA (Garmin's crash aggregation) is the field signal for "resume never lies" violations — enable from the first store build.

## 5. Patterns Adopted / Adapted / Rejected from RSVP Nano

**Adopted:** `BookWordSource`-style 3-method seam (`wordCount` / `wordAt` / `prefetchAround`) between reading loop and content source; absolute word index as universal coordinate; two-stage pause + instant toggle; sentence rewind (auto-pause + persist); context-on-pause scroll view; drift-free advance; bounds-check-and-degrade; per-book position keys.

**Adapted:** word source backs onto BLE-delivered chunks (cache miss → request + buffering state, vs Nano's instant SD reads); controls move button-first (5 buttons + touch vs Nano's 2); ORP geometry recomputed for round display; reading-time-remaining shipped as cumulative-duration data from phone (no on-watch prefix sums); persistence extended to two-device reconciliation (timestamped last-writer-wins); chapter-transition card adopted in MVP and repurposed as the pre-fetch trigger window.

**Deferred (PM decisions, 2026-06-06):** dimmed phantom adjacent words during playback → fast-follow (keep MVP playback view minimal; stream already carries what's needed); word-granular scrub/skim while paused → later, protocol-ready (offset addressing supports random access; BLE latency makes long seeks a UX problem to solve, not a protocol one).

**Rejected:** on-device format conversion (inverted topology is the founding architecture decision); monolithic app structure (Nano's 6k-line App.cpp is wrong for a learning-curve Monkey C project — separate reader/view/input/sync from the start); battery/standby/screensaver machinery (Garmin OS owns power); WiFi/OTA/RSS/focus-timer subsystems (out of scope or platform-provided). Nano's silent end-of-book and missing start ramp are treated as gaps to fix (FR5; brief ready-state).

## 6. Options Considered & Set Aside

- **Readium / native parsing stack:** overkill for MVP; DIY Dart extraction suffices; kept as contributor escape hatch.
- **Watch pulls from a phone-local HTTP server (`makeWebRequest`):** set aside — response caps are undocumented and device-dependent (~32–44 KB observed), and it adds a server lifecycle to the companion for no reliability gain over the managed message path.
- **`PersistedContent` as book-text cache:** ruled out — platform restricts it to FIT/GPX courses/waypoints/workouts.
- **Max-index position reconciliation:** rejected in favor of timestamped last-writer-wins — max-index fights deliberate rewinds.
- **Fixed periodic playback timer:** rejected for one-shot re-armed timer (variable dwell is the product).
- **Streaming tiny word windows during playback:** rejected as the primary mode — 768 KB heap makes chapter residency comfortable; small-window streaming is a resilience fallback, not the architecture.
- **Kotlin/Android companion:** original brief decision, superseded 2026-06-06 by Flutter for iOS reach.

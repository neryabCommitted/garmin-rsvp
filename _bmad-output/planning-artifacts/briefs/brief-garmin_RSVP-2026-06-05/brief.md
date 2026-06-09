---
title: "RSVP Speed Reader for Garmin — Product Brief"
status: approved
created: 2026-06-05
updated: 2026-06-06
approved: 2026-06-06
---

# RSVP Speed Reader for Garmin — Product Brief

## Vision

**Open an e-book on your phone, raise your wrist, and read it — without friction.** A Rapid Serial Visual Presentation (RSVP) reader for Garmin smartwatches: the watch flashes one word at a time at a fixed focal point (Spritz-style), turning the smallest screen you own into a surprisingly capable book reader. The companion app on the phone does the heavy lifting; the watch does exactly one thing well: display the next word at the right moment.

This is the Garmin analogue of [RSVP Nano](https://github.com/ionutdecebal/rsvpnano) (an open-source ESP32 RSVP reading device), with the storage/conversion topology deliberately inverted: where RSVP Nano converts and stores books on-device, a Garmin watch can do neither, so the companion app parses and stores while the watch streams.

## Why this exists

Honest founding motivation: **builder's itch.** The author saw RSVP Nano, owns a Garmin Fenix 8, and wants the Garmin version to exist. This is a personal, open-source project first; a product for others second. Success is a working, polished, publishable reader — not a revenue line.

That said, the niche is real and barely served: as of June 2026, the Connect IQ Store has **one paid RSVP reader** — which the author tried and found unsatisfying — and one page-based eBook app, while book-reading on Garmin has been requested in forums for years. A paid competitor validates demand; its shortcomings define the differentiation: **free, open-source, and book-first** — an EPUB-to-wrist pipeline rather than a standalone watch gadget (see Risks for the follow-up: capture what it gets wrong before building).

## Users

- **User #1 (guaranteed):** the author — Fenix 8 on wrist, Android in pocket, a library of DRM-free EPUBs to read.
- **Adopters (hypothesis):** RSVP/speed-reading enthusiasts who own Garmins; Connect IQ tinkerers; readers wanting to clear a backlog without pulling out their phone.
- **Contributors (open-source audience):** CIQ developers and mobile devs — served by clean architecture, a documented streaming protocol, and a permissive license.

## Product scope

### MVP target

| Dimension | Decision |
|---|---|
| Watch | Garmin **Fenix 8** (454×454 AMOLED, touch + buttons, CIQ API 6.0); other CIQ devices later |
| Companion | **Flutter** (Dart) — Android is the first target; the shared codebase keeps iOS in reach. Bridges the native CIQ Mobile SDK via the `watch_connectivity_garmin` plugin or a thin platform-channel layer ([comms research](../../research/technical-connect-iq-phone-watch-communication-research-2026-06-06.md)) |
| Formats | **EPUB** first-class; `.txt` / `.md` support nearly free; Kindle formats out of scope (DRM) — Calibre-convert path instead |
| Architecture | Companion parses → produces word-ready stream (RSVP Nano `.rsvp`-style intermediate, timing metadata baked in phone-side) → watch **pre-loads chapter-sized chunks into storage** (768 KB heap makes this comfortable) so BLE is never on playback's critical path → position syncs back as an **absolute word index** |

### MVP features

The reading core, complete enough that finishing a real book on the wrist is pleasant:

1. **RSVP playback with ORP/pivot letter** — Spritz-style anchor letter, fixed focal point, stable rendering.
2. **Variable timing** — longer dwell on long words and punctuation/sentence boundaries; baked into the word-stream format from day one (flat WPM is what makes RSVP feel robotic).
3. **On-watch controls** — play/pause and WPM up/down on buttons/touch.
4. **Per-book resume** — reopen exactly where you left off; position syncs watch ↔ phone.
5. **Quick rewind** — "go back a few words" recovery for RSVP's classic failure mode: one glance away and you're lost. Easy to overlook, but essential at book length. (RSVP Nano's proven pattern: sentence-granular rewind plus "pause coasts to sentence end" — see the [reader teardown](../../research/technical-rsvpnano-reader-teardown-research-2026-06-06.md).)
6. **Bare-bones library on phone** — import EPUB/.txt/.md, list books, show progress, send to watch. No covers, no metadata polish.

**Fast-follow (v1.x):** chapter/paragraph navigation on the watch.
**Later:** full library management (covers, metadata), typography options, reading stats.
**Not in scope:** Kindle/DRM formats, iOS companion (port territory), read-it-later integrations (roadmap note).

## Success criteria

Right-sized for a personal open-source project:

1. **The demo moment works end-to-end:** import a real EPUB on the phone, open it on the Fenix 8, and read — uninterrupted playback at the reader's chosen WPM, no manual chunk-wrangling.
2. **The author finishes one real book** entirely on the watch. Frictionless is proven by use, not claimed.
3. **Published:** on the Connect IQ Store and as a public GitHub repo with a permissive license (MIT, matching RSVP Nano), a README that explains the architecture, and a documented phone↔watch streaming protocol — the things that turn "my project" into "a project others can adopt."
4. **Resume never lies:** position sync survives disconnects, app restarts, and watch reboots. A book reader that loses your place has failed its one job.

## Risks & open questions

Updated 2026-06-06 after the technical research pass (see [Technical research inputs](#technical-research-inputs-2026-06-06) below); two of the original risks are resolved, one is reframed, and a new top risk emerged.

- **~~Watch-app memory budget on Fenix 8~~ — RESOLVED.** Verified at **786,432 bytes (768 KB)** for a watch-app; the scary 128 KB figure was the *data-field* limit. A full chapter of word-stream (~25–40 KB) fits many times over. ([Fenix 8 constraints research](../../research/technical-fenix-8-watch-app-constraints-research-2026-06-06.md))
- **~~BLE streaming throughput~~ — REFRAMED: reliability, not bandwidth.** At 700 WPM the stream needs only ~120–190 B/s — trivial. But the CIQ channel is slow (1–2 s round trips) with documented Android Mobile SDK reliability bugs (subsequent sends silently failing, MTU truncation). Mitigation already identified: pre-load chapter chunks into watch storage so BLE is never mid-playback, and design the protocol to assume failure (idempotent, absolute-offset requests). Needs an early on-hardware multi-send test. ([Comms research](../../research/technical-connect-iq-phone-watch-communication-research-2026-06-06.md))
- **NEW — AMOLED screen-on during hands-off reading is now the #1 technical risk.** A normal watch-app cannot keep the display lit: burn-in protection caps forced backlight (~1 min) and idle apps get terminated. Documented mitigation — run playback inside an `ActivityRecording` session — is Medium confidence and **must be validated on real hardware before architecture hardens**. ([Fenix 8 constraints research](../../research/technical-fenix-8-watch-app-constraints-research-2026-06-06.md))
- **Monkey C is new to the author — de-risked but real.** Known mitigations: enable Strict typing from commit 1, watch for reference-cycle leaks (refcounting GC), keep `onUpdate` trivial (watchdog), copy `matco/badminton` for tested CI. ([Monkey C research](../../research/technical-monkey-c-development-landscape-research-2026-06-06.md))
- **Companion pivoted Kotlin → Flutter (2026-06-06)** — cross-platform upside, but the CIQ Mobile SDK bridge plugin (`watch_connectivity_garmin`) is thin (v0.1.x); plan to fork it or write a custom platform-channel bridge if it falls short.
- **Differentiation hygiene** — a paid RSVP reader already exists on the CIQ Store; before building, capture concretely what it gets wrong (import friction? no companion? pacing?) so this project's claims are checkable against it.

## Technical research inputs (2026-06-06)

> **For the PM and Architect:** five decision-ready research reports back this brief's claims and pre-answer most architecture questions. Treat them as required inputs to the PRD and architecture phases — they live in [`_bmad-output/planning-artifacts/research/`](../../research/).

| Report | What it settles |
|---|---|
| [Connect IQ phone↔watch communication](../../research/technical-connect-iq-phone-watch-communication-research-2026-06-06.md) | Streaming is feasible; bandwidth trivial, reliability is the design driver. Chapter pre-load + pull-based buffering pattern; Flutter bridge options; known Mobile SDK bugs to defend against |
| [Fenix 8 watch-app constraints](../../research/technical-fenix-8-watch-app-constraints-research-2026-06-06.md) | 768 KB heap (verified); Storage API limits (32 KB/value, ~100 KB total); 50 ms timer floor vs ~86 ms/word at 700 WPM; input mapping; AMOLED screen-on problem + `ActivityRecording` mitigation |
| [Monkey C development landscape](../../research/technical-monkey-c-development-landscape-research-2026-06-06.md) | SDK/tooling state, Strict-typing recommendation, top newcomer pitfalls, testing/CI recipe, exemplar repos to copy |
| [EPUB parsing in Flutter/Dart](../../research/technical-epub-parsing-flutter-dart-research-2026-06-06.md) | Parse pipeline: `epub_pro` for structure + DIY text extraction; hand-rolled Unicode tokenization; binary-packed chunk format (~9 bytes/word); isolates + drift/flat-file storage |
| [RSVP Nano reader teardown](../../research/technical-rsvpnano-reader-teardown-research-2026-06-06.md) | What the reference project already solved: `ReadingLoop`/`BookWordSource` architecture seam, ORP geometry (35% anchor, length-tiered pivot), sentence-rewind & pause UX, position-persistence discipline — plus where to diverge (timing baked phone-side, coarser chunks, button-first controls) |

<!-- Brief by Mary (Business Analyst), technical research addendum 2026-06-06. Source: rsvp-garmin-idea-brief.md -->

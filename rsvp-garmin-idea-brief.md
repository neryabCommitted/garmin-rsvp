# Project Idea: RSVP Speed Reader for Garmin (with Companion App)

> Seed brief for the BMAD Analyst (Mary). This is a raw idea, not a finished brief — intended as the starting point for brainstorming, market analysis, and requirements elicitation.

## The core idea
A Rapid Serial Visual Presentation (RSVP) reading app for Garmin smartwatches, paired with a phone companion app. RSVP flashes one word at a time in a fixed position, letting the reader consume text at high speed without eye movement (the Spritz approach). The watch is the reader; the phone does the heavy lifting (importing, parsing, and storing text, then streaming it to the watch).

## Why a watch
- A watch screen only ever needs to show one word, so RSVP is an unusually good fit for a tiny display.
- Glanceable, hands-free, on-wrist reading — articles, book chapters, saved long-form text — without pulling out a phone.
- Underserved niche: speed-reading on wearables is largely unexplored compared to phone RSVP apps.

## Target user (hypothesis — to be validated)
People who already use RSVP/speed-reading apps, Garmin power users who like Connect IQ apps, commuters, and readers who want to clear a backlog of saved articles. Worth testing whether the audience is "productivity/quantified-self" types or "casual readers."

## How it would work (rough architecture, not final)
- **Watch app** — built on Garmin's Connect IQ SDK (Monkey C). Renders one word at a time, runs the timing loop, handles play/pause and speed controls, and tracks reading position. Holds only a small buffer of words at a time.
- **Companion app** — phone app (Android and/or iOS) using the Connect IQ Mobile SDK. Handles all the heavy work: importing text (pasted text, .txt, EPUB, web articles / read-it-later sources), cleaning it into a word list, managing the library, and streaming chunks to the watch over Bluetooth. Syncs reading progress back from the watch.

## The key constraint that shapes everything
Connect IQ apps are tightly memory-limited (older devices around 64KB app memory; newer ones more, but still small). A whole book cannot live in watch RAM. So the design is forced into: **companion parses and stores → streams chunks → watch buffers a few hundred words and requests more as it nears the end → position syncs back.** This constraint should drive a lot of the requirements and architecture decisions.

## RSVP-specific features worth considering
- **ORP / pivot letter** — the highlighted anchor letter slightly left of center (Spritz-style) that reduces eye drift and improves comprehension at speed.
- **Variable timing** — longer dwell on long words and on punctuation/sentence boundaries, rather than a flat words-per-minute.
- **Speed control** — adjustable WPM, with quick speed up/down and play/pause on physical buttons or touch (device-dependent).
- **Resume / bookmarking** — pick up where you left off, per document.
- **Library management** on the phone side.

## Open questions for the analyst to explore
- **Target device(s):** which Garmin models? Memory, screen size/shape, touch vs. button input, and always-on redraw limits vary a lot and constrain features.
- **Platform:** Android, iOS, or both for the companion app?
- **Text sources:** how far to go — paste-only at first, or .txt / EPUB / web-article / read-it-later (Pocket-style) integrations?
- **Distribution & monetization:** Connect IQ Store is free/paid/one-time; is there a model here, or is this a personal/portfolio project?
- **Competitive landscape:** existing Connect IQ reading or RSVP apps, and phone-based RSVP apps, to find the gap.
- **MVP scope:** likely the smallest valuable version is "paste/import text on phone → stream to watch → RSVP playback with speed control and resume." Worth confirming.

## Reference / prior art: RSVP Nano
**Repo:** https://github.com/ionutdecebal/rsvpnano (open source, MIT)

Not a Garmin project — it's a standalone ESP32-S3 RSVP reading *device* (Waveshare ESP32-S3-Touch-LCD-3.49, C++/PlatformIO firmware). Included as the closest prior art because it solves the same core problems on constrained embedded hardware and several of its design decisions transfer directly.

Worth studying for these patterns:
- **One-word RSVP with stable anchor-letter rendering** — its "anchor guides" are the same idea as the ORP/pivot letter noted above. Confirms anchor stability is a real implementation concern, not just a nicety.
- **`.rsvp` intermediate file format** — plain text with simple directives (`@rsvp`, `@title`, `@author`, `@source`, `@chapter`, `@para`); the firmware splits text into words. This is the key transferable idea: heavy source formats are pre-converted into a lightweight, word-ready stream that the constrained reader can consume cheaply. Maps almost exactly onto the "companion pre-processes → device just reads" split in this brief, where the companion would produce something like `.rsvp` and stream it.
- **Conversion pipeline** — imports `.epub`, `.txt`, `.md`, `.html` and converts to the `.rsvp` cache. Done three ways: on-device, via a desktop tool, and via a browser-based "Library Workspace." Useful prior art for our companion-app import/parse step and the supported-format question.
- **Reader features** — adjustable typography, tunable pacing, chapter/paragraph-aware navigation, and "phantom words." Good checklist of features that proved worth having.

**Key difference to flag for the analyst:** RSVP Nano stores the whole library locally on an SD card and converts books on the device itself. A Garmin watch can't do either (tiny memory, no SD, conversion too heavy) — which is exactly why our architecture pushes parsing/storage to the companion and streams chunks. So RSVP Nano is a strong reference for the *reader UX and the file/format model*, but the *storage and conversion topology* is deliberately inverted in our case.

## Personal context
This is an idea from a developer with a strong AI/voice/IoT and full-stack background; comfortable with mobile (Android/Kotlin or iOS/Swift) and embedded constraints. Connect IQ / Monkey C would be the new piece to learn.

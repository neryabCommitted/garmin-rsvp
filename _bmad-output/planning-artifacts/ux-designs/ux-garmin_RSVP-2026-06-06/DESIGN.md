---
name: PaceTurner
description: RSVP speed-reading for the wrist. The watch is a dark page with one luminous word; the phone is a quiet librarian. Material 3 with dynamic color on Flutter; from-scratch dark identity on Garmin AMOLED.
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
colors:
  # Watch palette — AMOLED-native. Mostly-black is a burn-in requirement, not just taste.
  void: '#000000'
  ink: '#EAE6DF'
  ink-dim: '#8A867F'
  ink-faint: '#45423E'
  pivot: '#FF5349'
  # Phone palette — Material 3 with dynamic color (Material You); `seed` is the
  # fallback scheme seed where dynamic color is unavailable. Full M3 semantic
  # roles (incl. error) are fair game on the phone; the one-red rule is watch-only.
  seed: '#FF5349'
typography:
  word-display:
    fontFamily: 'Atkinson Hyperlegible'
    fontSize: 48px
    fontWeight: '400'
    letterSpacing: 0em
  chapter-title:
    fontFamily: 'Atkinson Hyperlegible'
    fontSize: 28px
    fontWeight: '700'
  watch-meta:
    fontFamily: 'Atkinson Hyperlegible'
    fontSize: 22px
    fontWeight: '400'
  context-body:
    fontFamily: 'Atkinson Hyperlegible'
    fontSize: 26px
    fontWeight: '400'
    lineHeight: '1.45'
  phone-title:
    note: 'Material 3 — Title Large'
  phone-body:
    note: 'Material 3 — Body Large'
  phone-meta:
    note: 'Material 3 — Body Small'
rounded:
  sm: 8px
  md: 12px
  lg: 16px
  full: 9999px
spacing:
  unit: 4px
  watch-edge: 28px
  watch-safe-square: 320px
  phone-margin: 16px
components:
  word-display:
    background: '{colors.void}'
    ink: '{colors.ink}'
    pivot: '{colors.pivot}'
    anchor: '35% of display width'
  guide-marks:
    color: '{colors.ink-faint}'
    tick-color: '{colors.pivot}'
  phantom-words:
    color: '{colors.ink-faint}'
  progress-readout:
    color: '{colors.ink-dim}'
    typography: '{typography.watch-meta}'
  chapter-card:
    background: '{colors.void}'
    title: '{typography.chapter-title}'
    meta: '{colors.ink-dim}'
  status-view:
    background: '{colors.void}'
    ink: '{colors.ink-dim}'
  library-row:
    note: 'Material 3 ListTile with cover thumbnail; progress as a thin LinearProgressIndicator in the M3 primary'
  book-detail-header:
    note: 'Material 3 — cover art (when the EPUB carries one), title/author, progress % + time remaining; chapter list below'
  transfer-bar:
    note: 'Material 3 LinearProgressIndicator + Body Small label; never a modal'
---

## Brand & Style

PaceTurner puts a book on your wrist without pretending the wrist is a phone. The entire visual identity flows from one image: **a dark page with a single luminous word on it.** Everything else — progress, chrome, settings, the phone app — exists to protect that image and then get out of the way.

The watch identity is built from scratch for AMOLED: true black canvas, warm off-white ink, and exactly one chromatic color — the pivot red that marks the optimal recognition point of each word. `[ASSUMPTION]` The mostly-black, one-accent discipline is also load-bearing engineering: the Fenix 8's burn-in protection budget and battery both reward dark pixels, and the research mandates no static bright elements.

The phone app is deliberately the supporting act — a quiet librarian. It inherits Material 3 wholesale: dynamic color on, system light/dark followed, full semantic palette allowed. The austerity is a *watch* discipline, not a house rule (Nerya, 2026-06-06) — on the phone, PaceTurner is a normal, friendly Material citizen, and the pivot red survives only as the fallback seed and the active-book marker.

Posture: hobby project, publish-quality finish. Open-source contributors should be able to read this file and extend the product without inventing taste.

## Colors

The watch palette is four values and a rule. The rule: **if it isn't the current word, it doesn't get to be bright.**

- **Void (`#000000`)** — the canvas, both surfaces of the watch experience. True black, not near-black: AMOLED black pixels are off pixels, which serves burn-in protection, battery, and the "dark page" image at once.
- **Ink (`#EAE6DF`)** — the current word, and nothing else at full brightness. Warm off-white rather than pure white; softer at 86ms-per-word flash rates and at night. `[ASSUMPTION]` Exact value untested on the 454×454 panel — device-tune.
- **Ink Dim (`#8A867F`)** — paused-state chrome: progress readout, WPM readout, status text. Visible when you look for it, invisible at reading speed.
- **Ink Faint (`#45423E`)** — phantom context words flanking the focal word, and the guide marks. Peripheral by design.
- **Pivot (`#FF5349`)** — the single chromatic color. Marks the pivot letter and the anchor ticks. Never used for chrome, decoration, errors, or emphasis anywhere else on the watch. `[ASSUMPTION]` Softened from RSVPnano's pure red toward orange-red for legibility at 48px on black; toggleable per the precedent's focus-highlight setting.
- **Seed (`#FF5349`)** — the phone's fallback scheme seed. Dynamic color (Material You) leads when the device offers it; the full M3 semantic palette — error, tertiary, the lot — is welcome on the phone. The one-red rule stops at the wrist.

Avoid on the watch: status colors (no green success, no amber warning — status is text in `ink-dim`), gradients, and any second accent. One red, used for one job.

## Typography

**Atkinson Hyperlegible** is the watch voice — chosen for maximal per-glyph distinguishability, which is exactly the failure mode RSVP stresses (a word seen once, for 85 milliseconds, must not be misread). `[ASSUMPTION]` Shipped as a custom Connect IQ font resource; if custom fonts prove infeasible or too heavy, fall back to Garmin's largest native system font and re-tune sizes.

- **`word-display` (48px / 400)** — the focal word. Sized so ~13 characters (the perceptual span behind the ORP tiers) fit inside the round display's safe width at the 35% anchor. `[ASSUMPTION]` 48px is a calculated starting point, not a validated one — gate on hardware. Regular weight, not bold: bold closes counters at flash speed.
- **`context-body` (26px / 1.45)** — the paused context view. Comfortable multi-line reading at wrist distance.
- **`chapter-title` (28px / 700)** — chapter-transition cards. The one place bold is allowed.
- **`watch-meta` (22px)** — progress %, time remaining, WPM readout. Glanceable, never competing.
- **Phone roles** — Material 3 conventions as-is (Title Large / Body Large / Body Small). `[ASSUMPTION]` No serif moments, no display font on the phone; the companion has no hero surfaces.

OpenDyslexic as an optional alternate face is acknowledged from the precedent but out of MVP scope — the token structure (one `fontFamily` swap) keeps the door open.

## Layout & Spacing

The watch is a 454×454 **round** display. Two layout regimes:

- **Playback regime** — one word on the anchor line at 35% of display width, vertically centered. Guide marks above and below. Phantom words flank on the same baseline, clipped by the circle without apology. Nothing else on screen while words are flowing. Long words margin-clamp at `watch-edge` (28px) and show whole — the pivot may drift off-anchor rather than ever truncating a word.
- **Card regime** (paused context, chapter cards, status views, menus) — content lives inside the `watch-safe-square` (~320px centered); the circle's corners stay empty. Text blocks center-aligned on cards, left-aligned in the scrolling context view.

Burn-in rule that shapes all watch layout: **no element may occupy fixed pixels indefinitely.** The word display applies a slow per-session jitter (±2px random walk) to the entire playback composition. `[ASSUMPTION]` Jitter applied per-session/per-pause rather than per-word, so the anchor feels stable while reading.

Phone: Material 3 defaults, single column, `phone-margin` 16dp, no tablet layout in v1.

## Elevation & Depth

None on the watch. The page is flat; hierarchy is brightness (`ink` → `ink-dim` → `ink-faint`), never shadow or layering. The phone inherits Material 3 elevation as-is and adds nothing.

## Shapes

Watch surfaces are full-bleed on the round display — no cards-with-corners floating on the watch. Where a boundary is needed (paused context view scroll region) the circle itself is the boundary. Phone uses `{rounded.md}` (12px) for cards and M3 defaults elsewhere. `{rounded.full}` only for the phone's progress pill on library rows, if used at all.

## Components

→ Rendered reference: `mockups/key-playback.html` (word display, guide marks, phantom words, progress readout, 1:1). Spine wins on conflict.

- **Word display** — the product. One word, pivot letter in `{colors.pivot}`, the rest in `{colors.ink}`, positioned so the pivot's center sits on the anchor line at 35% of width. Background always `{colors.void}`.
- **Guide marks** — split horizontal hairlines above and below the word in `{colors.ink-faint}`, with a gap at the anchor column and short anchor ticks in `{colors.pivot}`. Not a full crosshair — the precedent's split-guide pattern, kept because it aims the eye without caging the word.
- **Phantom words** — previous and next words flanking the focal word in `{colors.ink-faint}`, same baseline, same size. Cheap peripheral context. `[ASSUMPTION]` Kept from RSVPnano; toggleable.
- **Progress readout** — `{typography.watch-meta}` in `{colors.ink-dim}`: book %, time remaining, current WPM. **Appears only when paused.** While words flow, the screen owes the reader nothing but the word.
- **Chapter card** — chapter number + title (`{typography.chapter-title}`) on `{colors.void}`, with progress beneath in `{colors.ink-dim}`. Doubles as the prefetch breath between chapters.
- **Status views** — WaitingForPhone, Buffering, BookChanged, StorageFull, Finished. One sentence in `{colors.ink-dim}`, centered in the safe square. No icons, no spinners except a minimal indeterminate dot cycle for Buffering. `[ASSUMPTION]`
- **Library row (phone)** — M3 ListTile: cover thumbnail, title, author, thin progress bar, "last read" meta. Tap opens book detail; overflow for quick actions.
- **Book detail (phone)** — cover art when the EPUB carries one, metadata, progress, chapter list. "Send to watch" as the prominent M3 filled button; Restart and Remove behind lower-emphasis actions.
- **Transfer bar (phone)** — M3 linear progress + one-line label ("Sending to watch — chapter 4 of 31"). Inline, never modal; BLE is slow and the user should be able to walk away.

## Do's and Don'ts

| Do | Don't |
|---|---|
| True black canvas; brightness = hierarchy | Near-black grays, shadows, or layered surfaces on the watch |
| One chromatic color (pivot red), one job | Green/amber status colors, second accents, decorative red |
| Show progress and WPM only on pause | Persistent chrome while words are flowing |
| Jitter the playback composition; keep all watch elements off fixed pixels | Static bright elements anywhere on the AMOLED |
| Whole words, margin-clamped, pivot drifts if it must | Truncating or hyphenating a word to keep the anchor perfect |
| Material 3 defaults + dynamic color on the phone | Custom Flutter chrome, hero animations, or exporting the watch's austerity to the phone |

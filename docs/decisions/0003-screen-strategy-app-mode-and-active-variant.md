# 0003 — Screen-on strategy: app-mode ships first; "PaceTurner Active" is a second listing after publish

Date: 2026-07-17 · Status: accepted · Deciders: Nerya

## Context

Story 3.7 originally shipped gate V1's mechanism: a generic `ActivityRecording`
session (Fit permission) enters the During-Activity display profile so the
watch stays lit-dim for a whole hands-off session. On-device it surfaced two
costs the gate never measured:

- The **Fit permission alone** (independent of any running session) moves a
  CIQ app out of the Fenix 8 **apps area into the activities list**.
- The **running session** engages the during-activity **touch lock**
  (swipe-down to unlock).

Follow-up probes on the real Fenix 8 (2026-07-16/17, Nerya) — a control gate
V1 never ran — showed a session-less plain app reads fine in the dim state:
with **general-use AOD on and the watch on-wrist**, the display dims at ~8 s
and **never goes OFF while words keep flowing**; with AOD off it reaches OFF
after some minutes and Story 3.7's auto-pause froze playback exactly at the
current word (resume-never-lies held). Market check: **Readinity – RSVP
Reader** (the only RSVP app on the CIQ store) declares **zero permissions**
and advertises an "Always-On Display mode with dimmed word" — the same
app-mode path; **WristTale** (page e-book reader) ships the Fit/session path.
Both roads exist in the wild; no third mechanism exists — SDK docs, the
developer forum, and our own probes all confirm plain CIQ apps have no
keep-awake and the backlight API is firmware-capped (~1 min) on AMOLED.

A single listing cannot offer both: **permissions are per-manifest and the
store has no install-time variants** — a runtime toggle would carry the Fit
permission (and the activities placement) for every user regardless of mode.

## Decision

1. **PaceTurner ships app-mode**: no Fit permission, no activity session.
   The watch's own display settings govern the screen; the display policy is
   HIGH/LOW ⇒ words flow (dim is a designed-for reading state), OFF/unknown ⇒
   instant auto-pause + force-save, wake finds Paused. The paused-frame hint
   line instructs **Display > Always On** (armed by an observed OFF).
2. **The `DisplayStrategy` seam stays** (AR11/AC3): the shipped strategy is
   the inert base class behind `Display.createStrategy()`; all lifecycle call
   sites (play sites, App exit) remain wired as no-ops.
3. **After the initial store publish (Epic 5), a second listing "PaceTurner
   Active" is published** from the same codebase: a jungle build flag adds the
   Fit permission and swaps `ActivitySessionStrategy` (git-preserved at
   `81978d6`, spike-robustness hardened) into the factory — for readers who
   want session-grade screen-on (works off-wrist, scoped During-Activity AOD
   setting) and accept the activities placement + touch lock.

## Consequences

- Users choose by picking a listing (the only real install-time choice the
  store allows); within app-mode, the user's own AOD setting is the dial.
- Story 3.9 / Gate V4 measures battery **with the app-mode path**; the ~60-min
  on-wrist run doubles as the app-mode endurance proof (the 61-min session-path
  proof stands separately in gates.md §V1).
- Epic 5 gains a deliverable: the Active variant build flag + second listing
  (publish AFTER the primary listing is live and stable).
- gates.md §V1 carries an amendment recording the no-session control probes.

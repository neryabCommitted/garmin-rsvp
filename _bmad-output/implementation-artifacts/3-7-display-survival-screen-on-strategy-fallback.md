---
baseline_commit: b2ba097443e0464fe566d287ab6a83e32d4e139b
---

# Story 3.7: Display survival — screen-on strategy & fallback

Status: review

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a reader,
I want the screen to stay readable for a full session,
so that hands-off reading actually works on the wrist (FR4, gate V1).

## Acceptance Criteria

**AC1 — `ActivitySessionStrategy` keeps the display lit for the session.**
**Given** the gate-V1 result (**passed-dim**, 2026-06-11 — the primary path IS viable)
**When** playback starts
**Then** `ActivitySessionStrategy` (behind the `DisplayStrategy` seam) opens a generic `ActivityRecording` session so the watch enters the During-Activity display profile, and — with the user's **During Activity → Always On** watch setting enabled — the display stays **lit (HIGH ~15 s, then LOW/dim, never OFF) and legible** for the whole reading session, hands-off.
> Gate-V1 reality check (gates.md §V1): full-brightness-for-60-min is **not achievable** on this hardware — no keep-awake API exists for CIQ watch-apps. "Lit for the session" == the V1-validated dim-AON-via-activity-session form: HIGH→LOW at ~15 s, LOW continuously thereafter, one button/gesture restores HIGH per timeout window. **Reading continues through LOW** — dim-and-legible is the sanctioned FR4 fallback form and the product's normal reading state.

**AC2 — Auto-pause on an unreadable display; wake finds Paused, never mid-stream.**
**Given** the dim/AON fallback (the session failed to open, OR the display reaches `DISPLAY_MODE_OFF` because the user's During-Activity AOD setting is off)
**When** the display becomes **unreadable** — `OFF` in any circumstance, or `LOW` while **no** session is active
**Then** playback auto-pauses **instantly** (mode-independent freeze — coast must not flow words onto a dark screen) with a force-save, and a subsequent touch/button wake finds the app **Paused** at the frozen word — playback never resumes by itself and words never flow on a screen the user can't read (UX-DR12, EXPERIENCE.md:111).
> The epics' AC ("when the display dims → auto-pauses") was authored **before** V1 ran. V1's passed-dim verdict makes session-LOW the legible normal reading state, so "dims" must be read as "becomes unreadable": `OFF` always pauses; `LOW` pauses only when the session is not active (fallback mode — that LOW state's legibility is unvalidated and it is en route to OFF). Session-LOW keeps flowing. This is the policy matrix Task 2 pins in host tests.

**AC3 — The seam: swapping the strategy touches only `display/`.**
**Given** the `DisplayStrategy` seam
**When** the strategy is swapped (a future gate outcome or alternative screen-on mechanism)
**Then** only the `watch/source/display/` module changes — construction goes through a factory inside `display/`, `PlaybackView`/`PaceTurnerApp` hold only the base-class type, and the rest of the reader is untouched (AR11: "gate-V1 failure swaps a module, not the architecture").

## Tasks / Subtasks

- [x] **Task 1 — Re-add the `Fit` permission to the manifest (AC1).** (AC: 1)
  - [x] `watch/manifest.xml`: add `<iq:uses-permission id="Fit"/>` beside the existing `Communications` permission. Required by `Toybox.ActivityRecording`; the Story-1.3 spike added it and the Story-1.4 commit (`e25aa33`) **removed it** along with the GateV1 spike files — the current manifest has only `Communications`. This is a REAL manifest change (the "no manifest change" streak of 3.2–3.6 ends here); do NOT touch `minApiLevel` (stays 5.2.0 — decision 0001; every API used here is ≤5.0.0).

- [x] **Task 2 — `display/DisplayStrategy.mc`: the seam + the pure display policy (AC2, AC3).** NEW directory `watch/source/display/` (auto-included by `base.sourcePath = source;source-test`, recursive — the `sync/` precedent from 3.6; verify both builds pick it up). (AC: 2, 3)
  - [x] `module Display` holding BOTH halves, mirroring `module Sync` (pure policy + adapter in one module — SyncManager.mc:6-13):
    - **Pure policy (host-tested, Lang-only, no Toybox.System/ActivityRecording):**
      - `function shouldPauseForMode(mode as Number, sessionActive as Boolean) as Boolean` — the AC2 matrix: `DISPLAY_MODE_OFF` (2) ⇒ true always; `DISPLAY_MODE_LOW_POWER` (1) ⇒ `!sessionActive`; `DISPLAY_MODE_HIGH_POWER` (0) ⇒ false; any unknown/other mode value ⇒ **true** (degrade safe: an unrecognized mode is treated as unreadable — bounds-check-and-degrade, NFR8/AR24). Pass mode as a plain `Number` so the function stays Lang-only; the caller feeds it `System.getDisplayMode()`.
      - `function isWakeGrace(lastWakeMs as Number?, now as Number, graceMs as Number) as Boolean` — true iff `lastWakeMs != null && now >= lastWakeMs && now - lastWakeMs < graceMs` (a `now < lastWakeMs` wraparound ⇒ false, grace over — mirror `GateV2.armWindowOpen`'s window idiom). Used by Task 4's wake-tap guard.
      - `const WAKE_GRACE_MS = 400;` (tune on device — Task 8).
    - **Base seam class `class DisplayStrategy`** — all no-op/false defaults so a null-object fallback is the base itself: `onPlaybackStart() as Void {}` (idempotent), `shutdown() as Void {}`, `isSessionActive() as Boolean { return false; }`, `sawOffDuringSession() as Boolean { return false; }`, `onDisplayModeChanged(mode as Number) as Void {}`.
    - **Factory `function createStrategy() as DisplayStrategy { return new ActivitySessionStrategy(); }`** — the ONE construction site (AC3: a swap edits this line only; callers never name the concrete class).
  - [x] NEW `watch/source-test/DisplayPolicyTest.mc` (`(:test)`, conditional-assert style — NO `Test.assert*`, one `(:test) function name(logger as Test.Logger) as Boolean` per case, see SyncManagerTest.mc): the full `shouldPauseForMode` matrix (OFF+session ⇒ pause; OFF+no-session ⇒ pause; LOW+session ⇒ **no** pause; LOW+no-session ⇒ pause; HIGH either ⇒ no pause; unknown mode e.g. `99`/`-1` ⇒ pause) + `isWakeGrace` (inside window ⇒ true; at/after window ⇒ false; null ⇒ false; wraparound `now < lastWake` ⇒ false).

- [x] **Task 3 — `display/ActivitySessionStrategy.mc`: the session adapter, spike-robustness hardened (AC1, AC2).** `class ActivitySessionStrategy extends DisplayStrategy`, imports `Toybox.ActivityRecording`, `Toybox.Activity`, `Toybox.Lang`, `Toybox.System`. This class is the graduation of the disposable Gate-V1 spike — every item in the deferred-work "spike-robustness bundle" (deferred-work.md:43) that applies here MUST be closed, not copied: (AC: 1, 2)
  - [x] `onPlaybackStart()` — **idempotent**: if `_session != null && isSessionActive()` return (structurally prevents the rapid-cycle firmware-freeze hazard, robustness #7 — no session churn on every pause/resume because Task 4 opens once and Task 5 closes once, but the guard makes over-calling harmless). Else: `createSession({:name => "PaceTurner", :sport => Activity.SPORT_GENERIC, :subSport => Activity.SUB_SPORT_GENERIC})` wrapped in try/catch (`Lang.InvalidOptionsException` or any throw ⇒ `_session = null`, one `System.println` line, **fallback mode** — robustness #2/#5); then **check `session.start()`'s Boolean** — `false` ⇒ stop+discard+null the session, log once, fallback mode (a silently-fake-active session is the one failure that invalidates the whole premise undetected — robustness #1). Exact API shapes verified against SDK 9.1.0 `api.mir` in Story 1.3 (1-3 story Dev Notes §Exact API shapes); use `Activity.SPORT_*` (3.2.0+), never the deprecated `ActivityRecording.SPORT_*`.
  - [x] `isSessionActive()` — `_session != null && _session.isRecording()` (gate everything on the live session state, not a stale flag — robustness #4).
  - [x] `shutdown()` — guarded: if `_session != null` then `stop()`, `discard()`, `_session = null` inside try/catch (a throwing stop must not crash app exit). **Always `discard()`, never `save()`** — a reading session must not pollute Garmin Connect with fake generic activities (Story-1.3 decision, carried forward; flagged for Nerya below).
  - [x] `onDisplayModeChanged(mode)` — bookkeeping only (the VIEW owns the engine reaction, Task 4): if `mode == DISPLAY_MODE_OFF && isSessionActive()` set `_sawOffDuringSession = true` (the evidence that the user's During-Activity AOD setting is off — feeds Task 6's hint). Keep this handler O(1), no Storage writes, no allocation (a system callback must never be able to crash or stall — robustness #3; the Gate-V3 watchdog memo applies to every system callback).
  - [x] `sawOffDuringSession()` — return the flag. No unbounded state anywhere in the class (robustness #6): fields are `_session`, one Boolean, nothing grows.
  - [x] Do NOT touch `Attention.backlight` — sustained backlight is hard-stopped by firmware (`BacklightOnTooLongException`, ~1-min class) and is explicitly not a pass path (gates.md §V1 Notes).

- [x] **Task 4 — Wire the strategy into `PlaybackView` (AC1, AC2).** The view owns engine/source/settings/timer/sync; it now owns the display strategy too, via the base type only. (AC: 1, 2)
  - [x] `initialize()`: `_display = Display.createStrategy();` (typed `as Display.DisplayStrategy` — AC3). Add `private var _lastWakeMs as Number?` (null) for the wake-grace guard.
  - [x] **Session opens at the play sites** — call `_display.onPlaybackStart()` immediately after each existing `_engine.play(...)` + `armTimer()` pair: the `onShow` STATE_IDLE auto-play branch (PlaybackView.mc:162), the `pauseOrResume()` resume branch (:229), and `resumeFromCard()` (:415). Idempotence in the strategy makes repeats free. The session then stays open across pauses/cards (**no** stop-on-pause — session churn is the rapid-cycle hazard, and the During-Activity profile keeping the paused frame glanceably dim-lit is desired); it closes only at App exit (Task 5).
  - [x] **`onDisplayModeChanged(mode as Number)` public handler** (the App routes to it, Task 5): first `_display.onDisplayModeChanged(mode)` (bookkeeping), then:
    - Compute `unreadable = Display.shouldPauseForMode(mode, _display.isSessionActive())`.
    - If `unreadable` and `_chapterCard`: `_timer.stop()` — cancel a pending Auto-card breath so it cannot resume the stream onto a black screen; the card holds like a Wait card until START (a one-off Auto→Wait demotion for that card; do NOT re-arm on wake — "never mid-stream" wins over the ~2 s breath).
    - Else if `unreadable` and (`_engine.isPlaying() || _engine.isRamping()`): `_engine.pauseAtCurrent()` + `commitPosition(true)` + `recomputeJitter()` + `WatchUi.requestUpdate()` — **`pauseAtCurrent()`, NOT `requestPause()`**: coast mode would keep flowing words to the sentence end on an unreadable screen, violating AC2's core sentence. `pauseAtCurrent` is instant and mode-independent and already handles RAMP (Story 3.5). The pending one-shot tick then fires once into `onTimerTick`'s paused branch (harmless — commit dedupes via `_lastWrittenIndex`, jitter refreshes).
    - If NOT `unreadable` (a wake: OFF→LOW/HIGH transition): set `_lastWakeMs = System.getTimer()`, `WatchUi.requestUpdate()` (repaint the paused frame) — **never** call `play()`/`resumeFromCard()` here. Wake finds Paused; the reader resumes deliberately with START (AC2).
  - [x] **Wake-tap guard**: at the top of `pauseOrResume()` and `rewindOne()` add `if (Display.isWakeGrace(_lastWakeMs, System.getTimer(), Display.WAKE_GRACE_MS)) { return; }` — if the firmware delivers the waking tap/press through to the delegate as an input event, it must not toggle playback or move position within the grace window. (`stepWpm`/`openContextView` are harmless while paused — WPM readout is play-gated, context is the paused affordance — leave them unguarded.) Whether the waking press actually reaches the delegate is a hardware-only answer — Task 8 verifies; the guard is cheap insurance either way, and if hardware proves the event is always consumed by the firmware, document that on the guard rather than removing it.
  - [x] Do NOT touch: the `onShow` STATE_IDLE guard, `onHide` (already force-saves; the session does NOT close here — a pushed context view fires `onHide` and must not drop the display profile mid-reading), the commitPosition contract sites, or the chapter-card lifecycle beyond the unreadable-cancel above.

- [x] **Task 5 — Route the AppBase callbacks in `PaceTurnerApp` (AC1, AC2).** (AC: 1, 2)
  - [x] Add `function onDisplayModeChanged() as Void` override (AppBase, API 5.0.0 — the callback lives on the App, not the View; Story-1.3 precedent): `if (_playbackView != null) { (_playbackView as PlaybackView).onDisplayModeChanged(System.getDisplayMode()); }`. Wrap the body in try/catch + one println (a display-mode transition must never crash the app — the exact crash class robustness #3 warns about). Verify the exact override signature against the local SDK 9.1.0 `api.mir` (Story 1.3 implemented it — `git show 837e1bd` has the working spike code to crib).
  - [x] In `onStop(state)`, after the existing GateV2 evidence write and `commitOnStop()` call: `if (_playbackView != null) { (_playbackView as PlaybackView).shutdownDisplay(); }` — add the thin `function shutdownDisplay() as Void { _display.shutdown(); }` wrapper to `PlaybackView` (the `commitOnStop()` pattern). Order: position save first, session teardown second (position is the sacred state). Leave the GateV2 spike write and `onStart` phone-message registration intact (git-preserved reference).

- [x] **Task 6 — The During-Activity-AOD user instruction (AC1 product implication).** gates.md §V1 carries this to Epic 3 verbatim: "the app must instruct users to enable **During Activity → Always On**". Minimal quiet-librarian form: (AC: 1)
  - [x] In `drawPausedReadout` (or a sibling paused-frame draw), when `_display.sawOffDuringSession()` is true, draw ONE extra Ink-Dim line (`COLOR_INK_DIM`, `FONT_SYSTEM_XTINY`, riding `_jitterX/_jitterY` like everything else) in the upper third (clear of word, guides, and the lower-third readout): `"Display > During Activity > Always On"` — factual, no exclamation (UX-DR23). Paused-frame only (never while words flow — UX-DR8's "the screen owes the reader nothing but the word" still governs; the hint IS paused chrome). Session-local state, not persisted.
  - [x] The trigger is precise by construction: `_sawOffDuringSession` arms only when the display hit OFF **while a session was recording** — exactly the signature of the AOD setting being off (with it on, V1 proved the mode never reaches OFF in 61 min). No settings read, no heuristics.

- [x] **Task 7 — Build + host tests (AC1–AC3).** (AC: 1, 2, 3)
  - [x] TDD: write `DisplayPolicyTest.mc` first, confirm red (undefined `Display` symbols), then implement. Strict L3 **release** build clean/warning-free + **unit-test** build green, on-host SDK 9.1.0 AND the exact CI image (`ghcr.io/matco/connectiq-tester`, SDK 8.4.0, fenix847mm — `rm watch/bin/app.prg` first, stale-binary trap). All 81 prior tests stay green; target 81 + the new DisplayPolicy cases. The CI image has found SDK-8.4.0-only landmines before (1.2's `convertEncodedString`) — do not skip it.
  - [x] Verify the new `display/` directory is compiled into both builds (the `sync/` precedent — `base.sourcePath` is recursive, but confirm, don't assume).
  - [x] Grep-check AC3: no file outside `watch/source/display/` names `ActivitySessionStrategy` or imports `Toybox.ActivityRecording` (`grep -rn "ActivitySessionStrategy\|ActivityRecording" watch/source --include=*.mc` hits only `display/`).

- [ ] **Task 8 — On-device hardware checks (AC1, AC2) — human-in-the-loop.** Sideload per docs/setup.md (MTP, `gio copy`). Results to stdout/app log where possible (machine-readable, repo memory). The simulator lies about display modes, watchdogs, and AOD (AR15) — none of this is sim-verifiable:
  - [ ] **(a) Primary path (AOD setting ON):** Display → During Activity → Always On enabled. Launch, let auto-play run hands-off ≥5 min: HIGH→LOW at ~15 s, words KEEP FLOWING through LOW, display never OFF, one button press restores HIGH and playback is unaffected (still flowing). (The 60-min endurance figure is V1's already-proven result; this checks the integration, not the physics. The 60-min + battery measurement is Story 3.9 / Gate V4.)
  - [ ] **(b) Dim legibility spot-check (carried from V1):** the flowing word in LOW, at arm's length, outdoors/bright light if available — gates.md carried "dedicated outdoor/direct-sun judgment not performed" into Epic 3; record the judgment.
  - [ ] **(c) Fallback path (AOD setting OFF):** with During Activity → Always On disabled, play hands-off past the timeout: screen goes dark/OFF → relaunch-or-wake must find **Paused at-or-before the last word visible before dark** (resume-never-lies still holds through the auto-pause path), and the AOD hint line shows on the paused frame. Words must never have been flowing while the screen was dark (listen/watch the moment it dims: freeze must be instant, not coast).
  - [ ] **(d) Wake semantics:** from the auto-paused dark screen, wake by touch AND by button: app shows the Paused still-frame (word + readout + hint), does NOT auto-resume, and the waking tap/press itself does not trigger pause-toggle or rewind (the wake-grace guard; record whether the waking event even reaches the app — adjust `WAKE_GRACE_MS` or document accordingly).
  - [ ] **(e) Session hygiene:** BACK-exit the app; confirm no activity appears in Garmin Connect / watch history (discard works). Relaunch: no crash, resume lands Paused per 3.6.
  - [ ] **(f) No-regression:** 3.2–3.6 flows (play/pause/WPM/rewind/context/chapter cards/Finished/relaunch-resume) unchanged with the session active.
  - [ ] Record all results in the story + sprint note (machine-readable).

- [x] **Task 9 — APP-MODE AMENDMENT (2026-07-17, Nerya-approved — ADR 0003).** Supersedes the session mechanism in AC1/AC2 after on-device probes (2026-07-16/17) and market evidence; AC3's seam is what made it a one-module change:
  - [x] Probe evidence recorded: Fit permission alone ⇒ activities-list placement; running session ⇒ touch lock; session-less app + general-use AOD + on-wrist ⇒ dim @~8 s, never OFF, words keep flowing; AOD off ⇒ OFF after minutes, auto-pause froze at the current word (safety net hardware-proven). Readinity–RSVP Reader (store) ships zero-permission app-mode; WristTale ships Fit/session. No third mechanism exists (SDK docs + dev forum + probes concur).
  - [x] `watch/manifest.xml`: `Fit` permission removed (back to `Communications` only).
  - [x] `display/ActivitySessionStrategy.mc` DELETED (git-preserved at `81978d6`; returns in the "PaceTurner Active" second listing after publish — ADR 0003).
  - [x] `display/DisplayStrategy.mc`: policy amended — `shouldPauseForMode(mode)` (session param gone): HIGH/LOW ⇒ flow (dim is a designed-for reading state), OFF/unknown ⇒ pause; factory ships the base class; all seam lifecycle call sites stay wired (no-ops) for the Active variant.
  - [x] `PlaybackView`: hint arming moved into the view (`_sawDisplayOff`, set on any observed OFF — with general-use AOD on + on-wrist, OFF never arrives); hint copy → `"Display > Always On"`; wake-grace guard + auto-pause handler unchanged.
  - [x] `PaceTurnerApp`: unchanged wiring (route + `shutdownDisplay()` kept, app-mode no-ops).
  - [x] `DisplayPolicyTest.mc`: matrix re-pinned to the amended policy (LOW must NOT pause). 85/85 @ Strict L3 in the CI image; both builds warning-free on host 9.1.0 + image 8.4.0 (release 44,348 B). AC3 grep: no code references outside `display/` (comments only).
  - [x] Documented: ADR `docs/decisions/0003-screen-strategy-app-mode-and-active-variant.md` (incl. the post-publish "PaceTurner Active" second-listing plan) + gates.md §V1 amendment.
  - [ ] Final on-device pass on the app-mode build (supersedes Task 8's session checks): apps-area placement + touch normal; AOD-off dark ⇒ Paused-at-word + hint line visible on the paused frame; wake semantics (no auto-resume, wake-tap grace); 3.2–3.6 no-regression.

## Dev Notes

### Scope boundary (read first)
This story delivers the **screen-on mechanism + the unreadable-display safety net** for the Epic-3 reader over the canned source. **In scope:** the `display/` module (seam + `ActivitySessionStrategy` + pure policy), the `Fit` manifest permission, session lifecycle wiring (open at play, close at App exit), auto-pause-on-unreadable with force-save, wake-finds-Paused semantics, the wake-tap grace guard, and the During-Activity-AOD hint line. **Out of scope:** Gate V4 battery measurement (Story 3.9 — this story is its prerequisite: V4 runs "with the screen-on path active"), the settings menu (3.8 — the strategy is not user-configurable), any status-view triggers (`WaitingForPhone`/`Buffering` — Epic 4), saving real activities to Garmin Connect (sessions are always discarded; see Questions), and any `Attention.backlight` usage (firmware-capped, not a pass path). No Storage schema change, no protocol change, no engine (`ReaderEngine`) change — the engine already has every primitive this story needs (`pauseAtCurrent`, `isPlaying`/`isRamping`/`isPaused`).

### The V1→AC2 reconciliation (the key decision — read before implementing)
The epics' AC2 text ("when the display dims, playback auto-pauses") predates the Gate-V1 run. V1's verdict (gates.md §V1, **passed-dim**): with a session open + the During-Activity AOD watch setting on, the display goes HIGH→LOW at ~15 s and then stays LOW-and-legible indefinitely — **dim IS the normal reading state**, sanctioned by FR4's fallback clause ("a dim always-on display restored by one button press") and by the UX ("UX designs for dim legibility"). Auto-pausing on LOW-during-session would pause every session 15 seconds in — an absurdity the epics never intended. The operative UX rule is EXPERIENCE.md:111/154 and UX-DR12: *"words never flow on a screen the user can't read"*, and the fallback governs *"if the activity-session screen-on path fails"*. Hence the policy matrix (pin in host tests):

| Display mode | Session active | Behavior |
|---|---|---|
| HIGH (0) | any | words flow |
| LOW (1) | yes | **words flow** — the V1-validated legible dim reading state |
| LOW (1) | no | auto-pause — fallback mode; this LOW's legibility is unvalidated and it is en route to OFF |
| OFF (2) | any | auto-pause — unreadable, full stop; during a session it also proves the AOD setting is off (arm the hint) |
| unknown | any | auto-pause — degrade safe (NFR8) |

Wake (any transition out of unreadable): repaint, stay Paused, stamp `_lastWakeMs`. Resume is always a deliberate START.

### The ownership model
Mirrors 3.6 exactly. `PlaybackView` already owns engine/source/settings/timer/`SyncManager` and is the only place that coordinates playback transitions — so it owns the `DisplayStrategy` too (held as the **base type**, constructed via `Display.createStrategy()` — AC3). The App routes its two AppBase-only concerns to the view it already holds: `onDisplayModeChanged` → `_playbackView.onDisplayModeChanged(System.getDisplayMode())` (the callback exists only on `Application.AppBase`, API 5.0.0 — Story-1.3 precedent, working code in `git show 837e1bd`), and `onStop` → `shutdownDisplay()` (the `commitOnStop()` pattern, position save FIRST). The strategy never references the view or the engine (no cycle, AR15); the view reads strategy state (`isSessionActive`, `sawOffDuringSession`) and the pure policy decides — engine coordination stays 100% in the view.

### Session lifecycle: open once at play, close once at App exit
- **Open** at the three `_engine.play()` sites (onShow IDLE auto-play, pauseOrResume resume, resumeFromCard), idempotently. NOT in `initialize()`/`onShow` unconditionally — a restored-Paused launch shouldn't burn activity-grade battery before the reader chooses to read.
- **Never close on pause/card/onHide.** Stopping per-pause would rapid-cycle sessions (the Story-1.3 forum-documented firmware-freeze hazard, deferred robustness #7 — solved here *structurally*, no debounce needed) and `onHide` fires on every context-view push (closing there would drop the During-Activity profile mid-reading). A paused frame under the session profile stays glanceably dim-lit — desired.
- **Close** (stop+discard+null, guarded) only in `App.onStop`. An abrupt carousel-kill skips `onStop` — the firmware reaps the orphaned session; nothing recoverable is lost (position was force-saved on the pause/hide path per 3.6).
- **Always `discard()`, never `save()`** — no fake "Generic" activities in Garmin Connect (Story-1.3 decision, carried).

### The spike-robustness bundle is this story's acceptance debt
deferred-work.md:43 enumerates 8 patterns from the disposable Gate-V1 spike that "must NOT carry into Epic 3 `ActivitySessionStrategy.mc`". Their dispositions here: (1) `session.start()` Boolean **checked** → false = fallback mode (Task 3); (2) `createSession` **wrapped** (InvalidOptionsException → fallback); (3) no Storage writes in system callbacks (the mode-change handlers are O(1) bookkeeping; position saves ride the existing guarded SyncManager); (4) everything gated on `isSessionActive()` (live `_session.isRecording()`, not a flag); (5) broad catch in the App's routing callback; (6) no unbounded state (two fields); (7) rapid-cycle prevented structurally (open-once/close-once + idempotent start); (8) `getTimer()` wraparound handled in `isWakeGrace` (wraparound ⇒ grace over, mirroring `Sync.shouldCommit`). A "fallback mode" outcome (no session) is NOT an error state — the app reads on with the stricter pause policy; one println each, no retry loop, no user-facing error (quiet librarian; the screen behavior itself communicates).

### Files being modified — current behavior to preserve (READ THESE before editing)
- `watch/source/views/PlaybackView.mc` (774 lines) — owns engine/source/settings/timer/sync + the drift-free loop. The three play sites to hook: onShow IDLE branch (:161-163), pauseOrResume resume branch (:228-232), resumeFromCard (:413-418). `pauseAtCurrent()` + `commitPosition(true)` is the existing chapter-card freeze idiom (:378-382) — the auto-pause handler reuses it verbatim. `commitPosition` has the empty-book guard and SyncManager dedupes same-index writes (`_lastWrittenIndex`, 3.6 review patch) — the extra settling-tick commit after an auto-pause is free. Do not touch: onShow's STATE_IDLE guard, onHide's force-save+timer-stop, the card lifecycle (beyond the unreadable Auto-cancel), the commitPosition contract comment block (:179-188 — extend it with the new auto-pause site so the enumerated contract stays honest).
- `watch/source/PaceTurnerApp.mc` (227 lines) — holds `_playbackView` (3.6), `onStop` does GateV2 evidence write → `commitOnStop()`; append `shutdownDisplay()` third. `onStart` registers phone messages (GateV2 spike — leave intact). Add the `onDisplayModeChanged` override; keep it try/caught.
- `watch/manifest.xml` — currently `Communications` only. Add `Fit`. Nothing else.
- `watch/monkey.jungle` — NO change expected (`base.sourcePath = source;source-test` is recursive); verify only.
- NOT modified: `ReaderEngine.mc` (all primitives exist; keep it Lang-only — do not leak display concerns into it), `InputMap.mc`/`PlaybackDelegate.mc` (the wake-grace guard lives in the view's action API, keeping the delegate dumb per 3.3), `SyncManager.mc`, `Settings.mc` (no new setting).

### Architecture & pattern compliance
- **Pure/adapter split** (architecture.md:451; the `Sync`/`Settings` shape): `Display.shouldPauseForMode`/`isWakeGrace` are Lang-only host-tested policy; `ActivitySessionStrategy` is the thin ActivityRecording adapter. The policy function takes `sessionActive` as a parameter precisely so it never imports ActivityRecording.
- **Seam discipline** (AR11, architecture.md:207/369-370): `display/DisplayStrategy.mc` + `display/ActivitySessionStrategy.mc` are the architecture tree's named files. The factory keeps concrete-class knowledge inside `display/` (AC3's grep test).
- **Named-state posture** (AR24): fallback mode is a *behavior*, not an error dialog; the hint line is the only user-facing text and it's an instruction, not an alarm (UX-DR23).
- **Burn-in citizenship** (UX-DR4): the hint line rides the session jitter and is Ink-Dim paused-chrome; nothing new persists while words flow.
- **Logging budget** (AR25): one println per abnormal event (session-open failure, start()-false, mode-change route failure) — never per mode transition at reading cadence.
- **Memory hygiene** (AR15): strategy holds no view/engine refs; App→View ref already sanctioned (3.6).

### Testing standards
- Host tests: `matco/action-connectiq-tester` image (SDK 8.4.0, fenix847mm) at Strict L3 via Docker (`rm watch/bin/app.prg` first — stale-binary trap, repo memory). Conditional-assert style, no `Test.assert*`. Current suite: **81** green (3.6). Target: 81 + DisplayPolicy cases (matrix + wake-grace ≈ +6..8), all green.
- Pure-only host coverage: the policy matrix and grace window. The session lifecycle, real display-mode transitions, AOD behavior, and wake-event delivery are **hardware-only** (AR15: the simulator misreports this entire area) — Task 8 is the real gate, human-in-the-loop, results machine-readable.
- TDD: red (undefined `Display` symbols) → green; plus one seeded-mutation red-check (e.g. flip LOW+no-session to false ⇒ exactly the matrix test fails), the 3.6 pattern.

### Resolves / touches prior deferred work
- **Closes** the deferred-work.md:43 spike-robustness bundle (its binding site was "Epic 3 `ActivitySessionStrategy.mc`" — this story). Mark each item's disposition in the PR/story record.
- **Executes** the gates.md §V1 carries: the During-Activity-AOD user instruction (Task 6) and the outdoor dim-legibility spot-check (Task 8b).
- **Prerequisite for** Story 3.9 / Gate V4 ("the full reader with the screen-on path active"); the 3.6-deferred "sync flash write stutter" measurement also lands there.
- Does NOT touch deferred #118 (Finished days tail) or any Epic-4-armed items.

### Project Structure Notes
- NEW `watch/source/display/` — the architecture tree's placement (architecture.md:369-371); recursive sourcePath includes it (3.6's `sync/` precedent).
- Monkey C conventions: `PascalCase.mc`, one public class per file (`DisplayStrategy.mc` holds the module + base class + factory, `ActivitySessionStrategy.mc` the concrete class — the `Sync`-module precedent for module+class cohabitation), `UPPER_SNAKE` consts, `_camelCase` privates, tests in `source-test/` with `(:test)`.
- Manifest gains `Fit` — the only config change; `minApiLevel` 5.2.0 untouched (all APIs here ≤5.0.0: createSession/start/stop/discard 1.0.0, `Activity.SPORT_*` 3.2.0, `getDisplayMode`/`onDisplayModeChanged` 5.0.0).

### References
- [Source: _bmad-output/planning-artifacts/epics.md#Story 3.7] — story + ACs (lines 697–715); FR4 (28); AR11 seam (102); AR15 sim-lies/memory (106); AR24 named states (121); AR25 logging (122); AR27 gate V1 (130); UX-DR4 burn-in (145); UX-DR12 dim/AON fallback treatment (159); UX-DR23 microcopy (182); UX-DR25 screen survival (184); Epic 3 intro "hands-off display (gate-V1 path + dim-AON fallback)" (528).
- [Source: docs/gates.md#V1] — passed-dim verdict, measured timeline (dim at 00:14, never OFF in 61:00, one-button restore), fallback legibility ("indoor legible; outdoor carried to Epic 3"), backlight probe notes, product implication ("ActivitySessionStrategy = activity session + user-setting instruction; UX designs for dim legibility") (13, 18–62).
- [Source: _bmad-output/implementation-artifacts/1-3-gate-v1-hands-off-screen-on-feasibility-hardware.md#Dev Notes] — expected hardware reality (no keep-awake API, During-Activity AOD semantics, burn-in rules), **exact API shapes verified against SDK 9.1.0 api.mir** (createSession options dict, start() Boolean, stop/discard, getDisplayMode constants, onDisplayModeChanged on AppBase), run protocol; the spike implementation is in `git show 837e1bd`.
- [Source: _bmad-output/implementation-artifacts/deferred-work.md] — the spike-robustness bundle this story must close (line 43).
- [Source: _bmad-output/planning-artifacts/ux-designs/ux-garmin_RSVP-2026-06-06/EXPERIENCE.md] — activity session as the screen-on mechanism (26), dim/AON fallback state row (111), §Screen Survival (148–154), battery honesty (152).
- [Source: architecture.md] — DisplayStrategy seam + gate-V1 swap (207, 235, 369–371, 489); display lifecycle constraint (72); four-class separation (207); pure/adapter + boundaries (451); pattern enforcement (309–317).
- [Source: watch/source/views/PlaybackView.mc] — play sites (161–163, 228–232, 413–418), pauseAtCurrent freeze idiom (378–382), commitPosition contract (179–199), onHide (172–177), card lifecycle (362–418), jitter (764–773).
- [Source: watch/source/PaceTurnerApp.mc] — `_playbackView` + onStop ordering (75–92), getInitialView (94–106).
- [Source: watch/source/sync/SyncManager.mc] — the module shape (pure policy + adapter) `Display` mirrors (1–60).
- [Source: watch/source/engine/ReaderEngine.mc] — pauseAtCurrent (3.5), isPlaying/isRamping/isPaused; no engine change needed.
- [Source: watch/manifest.xml] — current permissions (Communications only; Fit was removed with the spike in `e25aa33`).
- [Source: docs/decisions/0001-watch-min-api-level.md] — minApiLevel 5.2.0 stands.
- [Source: _bmad-output/implementation-artifacts/3-6-local-persistence-resume-never-lies.md] — ownership model, App-routes-to-view pattern, TDD/mutation red-check discipline, on-device record format.

### Decisions confirmed (Nerya, 2026-07-15)
1. **Session discard vs save:** sessions are always `discard()`ed — no Garmin Connect record of reading time. Approved. ("Reading = a logged activity" remains a possible later product decision; not this story.)
2. **AOD hint copy/placement:** Task 6 renders `"Display > During Activity > Always On"` in Ink-Dim XTINY on the paused frame, armed only after an OFF-during-session was observed. Approved as specified; may still be reworded on-device if it reads badly on the round face.
3. **Wake-grace window:** 400 ms starting value approved; tune (or document-and-keep the inert guard) per Task 8(d)'s hardware finding on whether waking events reach the app at all.

## Dev Agent Record

### Agent Model Used

claude-fable-5 (Amelia, dev-story 2026-07-15)

### Debug Log References

- TDD red confirmed: `DisplayPolicyTest.mc` written first; on-host Strict-L3 unit-test compile failed with `Undefined symbol ':Display'` / `':shouldPauseForMode'` at every call site — exactly the story's predicted red.
- Green: on-host SDK 9.1.0 unit-test + release builds `BUILD SUCCESSFUL`, warning-free (`-w`) at `-l 3`.
- CI-image gate (ghcr.io/matco/connectiq-tester, SDK 8.4.0, fenix847mm; `rm bin/app.prg` first per stale-binary trap): **85/85 PASS** (81 prior + 4 new DisplayPolicy cases). No SDK-8.4.0 landmines.
- Seeded-mutation red-check (3.6 discipline): flipped the LOW+no-session policy row to `false` → exactly `displayShouldPauseMatrix` failed (84/85, all other tests green) → reverted → 85/85 green again on the restored tree.
- CI-image Strict-L3 **release** build: `BUILD SUCCESSFUL`, 45,084 B (temp openssl key form).
- AC3 grep: `grep -rn "ActivitySessionStrategy\|ActivityRecording" watch/source --include=*.mc` hits only `watch/source/display/` (zero hits outside).
- `display/` compiled into both builds without jungle changes (recursive `base.sourcePath` — the `sync/` precedent held; proven by in-image test execution + release link).

### Completion Notes List

- **Task 1:** `Fit` permission re-added to `watch/manifest.xml` (removed with the GateV1 spike in `e25aa33`); `minApiLevel` 5.2.0 untouched. The 3.2–3.6 "no manifest change" streak ends here, by design.
- **Task 2:** NEW `watch/source/display/DisplayStrategy.mc` — `module Display` mirroring the `Sync` module shape: pure Lang-only policy (`shouldPauseForMode` = the V1→AC2 matrix with unknown-mode⇒pause NFR8 degrade; `isWakeGrace` with null⇒false and getTimer-wraparound⇒grace-over, the `GateV2.armWindowOpen` idiom; `WAKE_GRACE_MS = 400`), base seam `class DisplayStrategy` (all no-op/false defaults — the null-object fallback IS the base), and `createStrategy()` — the single construction site (AC3).
- **Task 3:** NEW `watch/source/display/ActivitySessionStrategy.mc` — SPORT_GENERIC/SUB_SPORT_GENERIC session adapter (API shapes per SDK 9.1.0 api.mir, `Activity.SPORT_*` not the deprecated `ActivityRecording.SPORT_*`). All 8 deferred-work:43 robustness items closed: (1) `start()` Boolean checked → false = stop+discard+null+fallback; (2) `createSession` try/caught → fallback; (3) `onDisplayModeChanged` O(1) bookkeeping, no Storage/allocation; (4) `isSessionActive()` = live `_session.isRecording()`, never a flag; (5) broad catches (+ the App's routing catch); (6) two bounded fields only; (7) rapid-cycle prevented structurally — open-once-at-play / close-once-at-App-exit + idempotent `onPlaybackStart`; (8) wraparound handled in pure `isWakeGrace`. Always `discard()`, never `save()`. No `Attention.backlight`.
- **Task 4:** `PlaybackView` holds `_display as Display.DisplayStrategy` (base type, factory-built — AC3) + `_lastWakeMs`. `onPlaybackStart()` at the three play sites (onShow IDLE auto-play, pauseOrResume resume, resumeFromCard) — session survives pauses/cards/onHide, closes only at App exit. `onDisplayModeChanged(mode)`: strategy bookkeeping first, then unreadable+card ⇒ `_timer.stop()` (one-off Auto→Wait demotion, not re-armed on wake); unreadable+playing/ramping ⇒ `pauseAtCurrent()` (instant, NOT requestPause — coast must not flow words onto a dark screen) + force-save + jitter + repaint; readable (wake) ⇒ stamp `_lastWakeMs` + repaint, NEVER auto-resume. Wake-grace guard at the top of `pauseOrResume()`/`rewindOne()` only (`stepWpm`/`openContextView` harmless while paused, left unguarded). commitPosition contract comment extended with the new auto-pause site. onShow IDLE guard / onHide / card lifecycle untouched.
- **Task 5:** `PaceTurnerApp.onDisplayModeChanged()` override (AppBase, API 5.0.0 — Story-1.3 precedent, signature per api.mir) routes `System.getDisplayMode()` to the view, body try/caught + one println. `onStop`: `shutdownDisplay()` added AFTER the GateV2 evidence write and `commitOnStop()` — position save first, session teardown second. GateV2 spike write + onStart registration intact.
- **Task 6:** AOD hint line in `drawPausedReadout`: `"Display > During Activity > Always On"`, Ink-Dim XTINY at h/5 (upper third, clear of word/guides/lower-third readout), riding `_jitterX/_jitterY`, drawn only when `_display.sawOffDuringSession()` — armed precisely by OFF-while-recording (the AOD-off signature). Paused-frame-only, session-local, not persisted.
- **Task 7:** all gates green — see Debug Log. Host suite 81 → **85** (+4 DisplayPolicy: pause matrix, unknown-mode degrade, grace window, null/wraparound).
- **Task 8 (PENDING — human-in-the-loop):** on-device Fenix 8 checks (a)–(f) not run; the simulator lies about display modes/AOD/watchdogs (AR15). Sideload `watch/bin/PaceTurner.prg` per docs/setup.md. Includes the V1-carried outdoor dim-legibility spot-check, AOD-off fallback, wake semantics (tune or document `WAKE_GRACE_MS`), session hygiene (no Garmin Connect activity), and 3.2–3.6 no-regression.
- Fallback mode (session open fails / start() false) is a behavior, not an error state: stricter pause policy (LOW⇒pause), one println, no retry loop, no user-facing error (AR24/AR25, quiet librarian).
- No engine/Settings/InputMap/PlaybackDelegate/SyncManager/jungle changes; no Storage schema change; GateV2 spike preserved.
- **Amendment 2026-07-17 (Task 9, ADR 0003):** shipped strategy swapped to APP-MODE after Nerya's on-device findings — see Task 9, the Change Log, and `docs/decisions/0003`. The 07-15 session implementation is fully git-preserved at `81978d6` and is the planned "PaceTurner Active" second listing (post-publish, Epic 5).

### File List

- `watch/manifest.xml` — net unchanged after amendment (`Fit` added 07-15, removed 07-17; `Communications` only).
- `watch/source/display/DisplayStrategy.mc` — NEW: `module Display` (pure policy + base seam class + factory). Amended 07-17: app-mode policy (LOW ⇒ flow, no session param), factory ships the base.
- `watch/source/display/ActivitySessionStrategy.mc` — added 07-15, DELETED 07-17 (git-preserved at `81978d6`; returns as the "PaceTurner Active" listing — ADR 0003).
- `watch/source/views/PlaybackView.mc` — modified: strategy ownership, play-site lifecycle calls, `onDisplayModeChanged` engine reaction, wake-grace guards, `shutdownDisplay()`, AOD hint line (view-armed `_sawDisplayOff`, copy `"Display > Always On"`), contract-comment extension.
- `watch/source/PaceTurnerApp.mc` — modified: `onDisplayModeChanged` AppBase override routing to the view; `onStop` strategy teardown after position save.
- `watch/source-test/DisplayPolicyTest.mc` — NEW: 4 host tests (app-mode policy matrix, unknown-mode degrade, wake-grace window, null/wraparound).
- `docs/decisions/0003-screen-strategy-app-mode-and-active-variant.md` — NEW: the strategy decision + post-publish "PaceTurner Active" second-listing plan.
- `docs/gates.md` — modified: §V1 amendment (no-session control probes, shipped-strategy change).

## Change Log

- 2026-07-15 (dev-story, Amelia): Story 3.7 implemented — display survival via ActivityRecording session behind the `Display` seam (AC1/AC3), unreadable-display auto-pause with instant freeze + force-save + wake-finds-Paused (AC2), Fit manifest permission, AOD hint line, wake-tap grace guard. Closes the deferred-work:43 spike-robustness bundle. 85/85 host tests @ Strict L3 in the CI image (81→85), both builds warning-free on-host 9.1.0 and in-image 8.4.0 (release 45,084 B), seeded-mutation red-check passed. Task 8 on-device checks PENDING human.
- 2026-07-16/17 (on-device probe session, Nerya + Amelia): session build surfaced activities-list placement (← Fit permission) and during-activity touch lock (← running session); three probe builds isolated the mechanisms; app-mode dim reading validated on-wrist with general-use AOD; Readinity/WristTale market evidence gathered. Ramp-countdown WPM-scaling recorded in deferred-work.md.
- 2026-07-17 (amendment, Amelia — Nerya-approved): swapped to APP-MODE (ADR 0003): Fit removed, ActivitySessionStrategy deleted (git-preserved `81978d6`), policy LOW ⇒ flow, hint → `"Display > Always On"` (view-armed on observed OFF), seam + lifecycle wiring kept for the post-publish "PaceTurner Active" second listing. gates.md §V1 amended. 85/85 @ Strict L3 in CI image, both builds warning-free (release 44,348 B). Final app-mode on-device pass PENDING human.

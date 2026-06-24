---
baseline_commit: 74772bcbadf58ea762ae144e79965f3846c243ab
---
# Story 3.3: Playback controls & input mapping

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a reader,
I want buttons-first controls with a touch mirror,
so that I can pause, adjust speed, and rewind eyes-free mid-stride (FR8, FR9, FR10, FR12).

## Acceptance Criteria

**AC1 — Pause honors the coast/instant setting**
**Given** playback
**When** I press START (or tap, if touch on)
**Then** it pauses per the coast/instant setting read from the `SettingsModel.Settings` model (established in Story 3.1) — coast advances to the next sentence end then freezes; instant freezes on the current word.

**AC2 — UP/DOWN adjust WPM adaptively, mid-stream, with a transient readout**
**Given** playback
**When** I press UP/DOWN
**Then** WPM steps (adaptive: 10 below 100, 25 at/above) **without interrupting the stream** (the change takes effect on the next word — no re-fetch, no drift, no timer disruption), with a **transient** WPM readout flashed in Ink-Dim (`#8A867F`, `watch-meta` 22px) that disappears on its own — never persistent chrome.

**AC3 — Rewind one sentence (touch swipe or button path), auto-pausing**
**Given** playback
**When** I swipe right (touch on) **or** use the button-path rewind (START to pause, then UP while paused)
**Then** it pauses and rewinds one sentence (`ReaderEngine.rewind()`, which already auto-pauses and is stackable; clamp at word 0).

**AC4 — Complete, principled input map**
**Given** the input map
**When** any action is invoked
**Then** every action has a physical-button path; BACK exits to the watch face (position force-save is wired in Story 3.6 — see Dev Notes "Scope boundary: BACK & force-save"); LIGHT is unused (never consumed); and handlers use `onKey` + `onTap`/`onSwipe`, **never `onSelect`** (extend `WatchUi.InputDelegate`, not the `onSelect`/`onBack` semantics of `BehaviorDelegate`).

**AC5 — Fully button-operable with touch off**
**Given** the "Touch controls" setting Off (`Settings.touchControls == false`)
**When** I read
**Then** all core actions (pause, WPM ±, rewind, resume, exit) remain fully operable by physical buttons; `onTap`/`onSwipe` become no-ops (return `false`).

## Tasks / Subtasks

- [x] **Task 1 — Adaptive WPM step in the engine, host-tested (AC2)**
  - [x] Add two pure methods to `Reader.ReaderEngine` (`watch/source/engine/ReaderEngine.mc`): `stepWpmUp() as Void` and `stepWpmDown() as Void`. Each computes the adaptive step from the **current** WPM and applies it through the existing `clampWpm`/`setWpm` path. **The engine still imports only `Toybox.Lang`** (AC7 from 3.1 must be preserved — no `Toybox.System`/`WatchUi`). [Source: ReaderEngine.mc:3-8, 173-175, 289-293]
  - [x] Adaptive-step rule (pin it exactly; **step size keyed on the current WPM before stepping**): if `wpm < 100` the step is `10`, else `25`. So: up from 90 → 100; up from 100 → 125; down from 125 → 100; **down from 100 → 75** (current is `>= 100`, step 25); down from 90 → 80. Clamp to `[WPM_MIN=10, WPM_MAX=1000]`. [Source: EXPERIENCE.md:96, 126; epics.md#Story-3.3 line 613; Settings.mc:37-38]
  - [x] **Prefer a tiny pure helper** for the step magnitude so the rule is unit-pinned: `private function adaptiveStep() as Number { return _wpm < 100 ? 10 : 25; }` used by both step methods. (Keeping it private is fine — the host tests exercise it through `stepWpmUp/Down()` + `wpm()`.)
  - [x] Host tests in `watch/source-test/ReaderEngineTest.mc` (extend the existing file; **test count must RISE**, mirroring the 3.2 review's "not flat" note). Assert literal post-step `wpm()`: 90→100 (up), 100→125 (up), 100→75 (down), 125→100 (down), 250→275 / 250→225 (default ±), and the two clamp edges (down from 10 stays 10; up from 1000 stays 1000). Pattern: conditional + `logger.error(...)` + `return false` — **no `Test.assert*`** in this repo. [Source: ReaderEngineTest.mc:1-9, 65-71; SmokeTest.mc]

- [x] **Task 2 — Pure input-map module, host-tested (AC1–AC5)**
  - [x] Create `watch/source/input/InputMap.mc` — a `module InputMap` of **pure** functions that map a raw input + reader state to an **action constant**, so the (provisional) key/gesture map is isolated, unit-pinned, and cheap to re-map after the first hardware test. Create the `watch/source/input/` directory (architecture's canonical home; does not exist yet). [Source: architecture.md:379-382, 301]
  - [x] Action constants (typed `const`, no magic numbers): `ACTION_NONE = 0`, `ACTION_PAUSE_RESUME = 1`, `ACTION_WPM_UP = 2`, `ACTION_WPM_DOWN = 3`, `ACTION_REWIND = 4`, `ACTION_CONTEXT = 5` (reserved for Story 3.4 — returned but the delegate treats it as no-op here), `ACTION_EXIT = 6`.
  - [x] `actionForKey(key as Number, isPaused as Boolean) as Number`: `KEY_ENTER` → `ACTION_PAUSE_RESUME`; `KEY_UP` → `ACTION_REWIND` if `isPaused` else `ACTION_WPM_UP`; `KEY_DOWN` → `ACTION_CONTEXT` if `isPaused` else `ACTION_WPM_DOWN`; `KEY_ESC` → `ACTION_EXIT`; **`KEY_LIGHT` and `KEY_MENU` → `ACTION_NONE`** (LIGHT off-limits; the settings menu is Story 3.8). It may `import Toybox.WatchUi` to name the `KEY_*` constants — the matco tester runs the full SDK so host tests can pass `WatchUi.KEY_*` in (mirrors how `ReaderEngineTest` references `Protocol`/`StreamDecoder`). [Source: WatchUi.KeyEvent docs — KEY_ENTER/UP/DOWN/ESC/MENU(=7)/LIGHT; EXPERIENCE.md:119-146]
  - [x] `actionForTap(touchEnabled as Boolean) as Number`: `ACTION_PAUSE_RESUME` if `touchEnabled` else `ACTION_NONE`.
  - [x] `actionForSwipe(direction as Number, touchEnabled as Boolean, rewindDir as Number) as Number`: `ACTION_REWIND` if `touchEnabled && direction == rewindDir` else `ACTION_NONE`. `rewindDir` is `WatchUi.SWIPE_RIGHT` for `HAND_RIGHT`, `WatchUi.SWIPE_LEFT` for `HAND_LEFT` (handedness mirrors swipe directions — MVP). [Source: EXPERIENCE.md:127, 144]
  - [x] Host tests `watch/source-test/InputMapTest.mc` (mirror `OrpLayoutTest.mc`/`SmokeTest.mc` `(:test)` pattern): every key both paused and playing; LIGHT and MENU → NONE in both states; tap on/off; swipe-right with touch on/off and with the right- vs left-handed `rewindDir`; a non-rewind swipe direction → NONE. Assert literal action constants.

- [x] **Task 3 — PlaybackView control surface + transient WPM readout (AC1, AC2, AC3)**
  - [x] Add a small **action API** to `watch/source/views/PlaybackView.mc` (the view owns the engine/timer/jitter; the delegate calls these — input flows delegate → view → engine, never engine → view, preserving AR15):
    - `function pauseOrResume() as Void` — if `engine.isPlaying() || engine.isRamping()` → `engine.requestPause()` + `WatchUi.requestUpdate()` (coast keeps ticking to the sentence end via the existing loop; instant settles on the next tick). If `engine.isPaused()` → `engine.play(System.getTimer())` + `armTimer()` + `WatchUi.requestUpdate()` (re-arm: the timer self-stopped when paused). FINISHED stays terminal (no resume) — `play()` already no-ops it. [Source: ReaderEngine.mc:79-96, 101-114, 188-191]
    - `function stepWpm(up as Boolean) as Void` — `up ? engine.stepWpmUp() : engine.stepWpmDown()`, then arm/refresh the transient readout (below) + `WatchUi.requestUpdate()`. **No timer change** — `setWpm` takes effect next word by contract (AC2 "without interrupting the stream"). [Source: ReaderEngine.mc:168-175]
    - `function rewindOne() as Void` — `engine.rewind()` (auto-pauses, stackable, clamps at 0), then `recomputeJitter()` (new still frame) + `WatchUi.requestUpdate()`. [Source: ReaderEngine.mc:119-136]
    - `function touchEnabled() as Boolean` → `_settings.touchControls`; `function rewindSwipeDirection() as Number` → `WatchUi.SWIPE_RIGHT`/`SWIPE_LEFT` by `_settings.handedness`; `function isPausedState() as Boolean` → `engine.isPaused()`. (Encapsulate Settings in the view; keep the delegate thin.)
  - [x] **Transient WPM readout (AC2):** add `private var _wpmReadoutUntil as Number` (ms deadline) set in `stepWpm()` to `System.getTimer() + READOUT_MS` (`READOUT_MS ≈ 900`). In `onUpdate`, **only while not paused** and while `System.getTimer() < _wpmReadoutUntil`, draw `engine.wpm().toString()` (optionally `+ " wpm"`) in a new `COLOR_INK_DIM = 0x8A867F` const using a small native font (`watch-meta` 22px → `FONT_SYSTEM_SMALL`/`TINY`), positioned so it does **not** overlap the focal word (e.g. lower third of the safe square), carrying the existing `_jitterX/_jitterY` like the rest of the composition. It self-clears: the playback tick loop repaints every word, so the first repaint past the deadline drops it. [Source: DESIGN.md:108, 122; EXPERIENCE.md:126]
  - [x] **Burn-in / chrome reconciliation:** the readout is **transient and Ink-Dim (dim, not bright)** — it does NOT violate Story 3.2 AC5 ("no *persistent bright* chrome while words flow"). It is the one allowed playing-state overlay, per UX. Document this in a code comment so a future review doesn't flag it. [Source: 3-2 story AC5; EXPERIENCE.md:126; DESIGN.md:167]
  - [x] **Do not stop the timer manually** in these actions. Coast pause needs ticks to reach the sentence end; instant pause / rewind settle via the existing `onTimerTick` paused-branch (recompute jitter + `requestUpdate`, no re-arm). Resume re-arms. (A single stale paused tick after rewind harmlessly refreshes the burn-in jitter — acceptable.) [Source: PlaybackView.mc:99-121]

- [x] **Task 4 — PlaybackDelegate, the thin input adapter (AC1, AC3, AC4, AC5)**
  - [x] Create `watch/source/input/PlaybackDelegate.mc` — `class PlaybackDelegate extends WatchUi.InputDelegate` (**NOT `BehaviorDelegate`** — InputDelegate gives raw `onKey`/`onTap`/`onSwipe` with no `onSelect`/behavior remapping, satisfying AC4's "never `onSelect`"). Holds a reference to the `PlaybackView` it drives. [Source: WatchUi.InputDelegate docs; architecture.md:301]
  - [x] `onKey(evt as WatchUi.KeyEvent) as Boolean`: `var a = InputMap.actionForKey(evt.getKey(), _view.isPausedState());` then dispatch — `ACTION_PAUSE_RESUME` → `_view.pauseOrResume()`; `ACTION_WPM_UP` → `_view.stepWpm(true)`; `ACTION_WPM_DOWN` → `_view.stepWpm(false)`; `ACTION_REWIND` → `_view.rewindOne()`; **`ACTION_EXIT` → `return false`** (let the system exit to the watch face — BACK keeps its Garmin meaning, AC4); `ACTION_CONTEXT`/`ACTION_NONE` → `return false` (context view is Story 3.4; LIGHT/MENU unconsumed). Return `true` for the four consumed actions.
  - [x] `onTap(evt as WatchUi.ClickEvent) as Boolean`: `InputMap.actionForTap(_view.touchEnabled())` → `ACTION_PAUSE_RESUME` → `_view.pauseOrResume(); return true;` else `return false`.
  - [x] `onSwipe(evt as WatchUi.SwipeEvent) as Boolean`: `InputMap.actionForSwipe(evt.getDirection(), _view.touchEnabled(), _view.rewindSwipeDirection())` → `ACTION_REWIND` → `_view.rewindOne(); return true;` else `return false`.
  - [x] **Never** override/consume BACK to do anything but exit, never consume LIGHT, never implement `onSelect`. (AC4 principles are fixed; the concrete map is provisional — see Task 6 hardware verify.) [Source: EXPERIENCE.md:119, 142, 146; architecture.md:301]

- [x] **Task 5 — Wire the delegate into the app (AC4)**
  - [x] In `watch/source/PaceTurnerApp.mc`, change `getInitialView()` to construct the view once and return view + delegate:
    `var view = new PlaybackView(); return [view, new PlaybackDelegate(view)] as [WatchUi.Views, WatchUi.InputDelegates];`
    Keep the GateV2 spike code git-preserved (compiled, not entered), exactly as Story 3.2 left it. [Source: PaceTurnerApp.mc:80-88; 3-2 File List]
  - [x] No `manifest.xml` change — input handling needs no new permission; `Communications` stays for the preserved spike only. [Source: manifest.xml; 3-2 notes line 155]

- [x] **Task 6 — Verify (Strict L3 + host tests green + on-device input check)**
  - [x] Compile clean at **Strict (level 3)** — both the unit-test build (`tester.sh … -l 3 -t`) and the release build (`monkeyc -l 3 -r`). Strictness never lowered (a build needing it lowered is a defect). [Source: architecture.md:314; 3-2 Debug Log]
  - [x] Run host tests in the CI image: `docker run … ghcr.io/matco/connectiq-tester:latest -c 'tester.sh fenix847mm'` **after `rm -f watch/bin/app.prg`** (stale-binary trap). Existing 46 + new ReaderEngine WPM-step tests + new `InputMapTest` tests must all pass and the count must rise. [Source: watch-tests-local-via-ci-docker-image memo; 3-2 Task 6]
  - [x] **On-device input check (the input map is provisional until hardware — REQUIRED for this story). — ✅ DONE on real Fenix 8 (Nerya, 2026-06-23): 1✓ pause(coast)+resume, 2✓ live WPM + transient readout, 3✓ swipe-right rewinds EXCEPT a left-edge-origin swipe exits the app (firmware folds the bezel edge-swipe into BACK before onSwipe), 4✓ button-path rewind (START→UP), 5✓ BACK exits, 6✓ LIGHT untouched. See Completion Notes "On-device result".** Sideload to the real Fenix 8 (MTP / `gio copy` per the toolchain memo) and confirm: START pauses (coast → freezes at sentence end) and resumes with the ramp; UP/DOWN change WPM live with the transient readout and no stutter; **swipe-right rewinds** OR — if the device routes swipe-right to BACK/exit (see Dev Notes "CRITICAL — swipe-right may arrive as BACK") — confirm the button-path rewind (START→UP) and record the device's actual swipe behavior; BACK exits; LIGHT is untouched; with Touch controls Off, every action still works by buttons. Print a one-line `(:debug)`-guarded marker per input event for the log-based check — **never** a persistent or per-word `println` (logging budget). [Source: architecture.md:87, 301, 323; EXPERIENCE.md:146; watch-decode-watchdog/logging memos]

## Dev Notes

### What this story owns (scope boundary)
The **watch input map** and **playback controls**: a pure `input/InputMap.mc` (key/gesture → action), a thin `input/PlaybackDelegate.mc` (`WatchUi.InputDelegate`), a small **action API** + **transient WPM readout** added to the existing `PlaybackView`, and the adaptive **WPM-step** logic added to `ReaderEngine`. New: `input/InputMap.mc`, `input/PlaybackDelegate.mc`, `source-test/InputMapTest.mc`. Modify: `engine/ReaderEngine.mc` (+ `source-test/ReaderEngineTest.mc`), `views/PlaybackView.mc`, `PaceTurnerApp.mc`.

**OUT of scope (do not build here):**
- The **paused progress readout** (book %, time-remaining, current WPM) and the **context view** (DOWN/swipe-up → surrounding paragraph) — **Story 3.4**. `InputMap` returns `ACTION_CONTEXT` for DOWN-while-paused, but the delegate treats it as a no-op (`return false`) so 3.4 can wire the view.
- The **settings menu** (MENU → open settings) — **Story 3.8**. MENU maps to `ACTION_NONE` here.
- **Persistence / force-save** of position on BACK/pause/rewind (`SyncManager.commitPosition(force)`) — **Story 3.6**. See next note.
- Chapter card / Finished / status shells — **Story 3.5**; display survival — **Story 3.7**; `ChunkedWordSource`/transfer — **Epic 4**.
[Source: epics.md#Story-3.3 lines 599-625; architecture.md:374-382; EXPERIENCE.md:128, 131-138]

### Scope boundary: BACK & "position force-saved"
AC4 says "BACK exits (position force-saved)". The **force-save** half is a **Story 3.6** deliverable (`SyncManager.commitPosition(force:true)` on pause/exit/rewind/disconnect) and there is **no `SyncManager` yet**, and the current source is the canned dev stream — so **3.3 does NOT write any position to Storage**. In 3.3, BACK just **exits** (the delegate returns `false` for `KEY_ESC`; the system pops the initial view to the watch face — exactly the default Story 3.2 relied on). The engine already exposes the clean surface 3.6 will hook: `index()`, `lastTransition()`, `isPaused()` etc. **Do not fake a Storage write or build persistence here** — that would pre-empt 3.6 and is explicitly out of scope. [Source: ReaderEngine.mc:24-31, 181-198; epics.md#Story-3.6 lines 672-695; deferred-work.md "Forward to Epic 3"]

### CRITICAL — swipe-right may arrive as BACK on the Fenix 8 (the input map's #1 hardware risk)
Garmin's docs warn: *"Some devices interpret SWIPE_RIGHT SwipeEvents as KEY_ESC events."* (WatchUi.BehaviorDelegate.onBack). The UX map uses **swipe-right = pause + rewind** (the "I lost it" gesture, FR10), and **BACK = exit**. On a device that folds swipe-right into BACK, the swipe-rewind gesture can be **eaten as an exit** and never reach `onSwipe`. This is precisely why the input map is *provisional until the first hardware test* and why the **button path (START→UP) is the fixed guarantee**, not the swipe. Mitigations: (1) we extend **`InputDelegate`** (raw events, no behavior remap) rather than `BehaviorDelegate` — on touch devices `onSwipe(SWIPE_RIGHT)` should fire directly; (2) **Task 6 must record on the real Fenix 8 whether swipe-right arrives at `onSwipe` or as `onKey(KEY_ESC)`/exit**, and Nerya decides the final gesture from that evidence (he has gesture opinions queued for hardware). If swipe-right is unusable, the swipe-rewind can move to swipe-left/up behind `InputMap` with zero churn elsewhere. Do **not** consume `KEY_ESC` to "save" the gesture — BACK-is-exit is a fixed principle. [Source: WatchUi.BehaviorDelegate.onBack docs; EXPERIENCE.md:127, 142, 146; architecture.md:87, 301, 592]

### Connect IQ input API (verified against current Garmin docs)
- Extend **`WatchUi.InputDelegate`**. Override `onKey(keyEvent as WatchUi.KeyEvent) as Boolean`, `onTap(clickEvent as WatchUi.ClickEvent) as Boolean`, `onSwipe(swipeEvent as WatchUi.SwipeEvent) as Boolean`. **Return `true` to consume, `false` to let the system handle it** (this is how BACK exits — return `false` for `KEY_ESC`). [Source: developer.garmin.com Toybox.WatchUi.InputDelegate]
- `keyEvent.getKey()` → a `WatchUi.KEY_*` enum: `KEY_ENTER` (START/select), `KEY_UP`, `KEY_DOWN`, `KEY_ESC` (back), `KEY_MENU` (=7), `KEY_LIGHT`. `swipeEvent.getDirection()` → `WatchUi.SWIPE_UP/DOWN/LEFT/RIGHT` (`SWIPE_RIGHT=1`, `SWIPE_DOWN=2`). [Source: Toybox.WatchUi.KeyEvent / SwipeEvent]
- `BehaviorDelegate` extends `InputDelegate` and adds device-independent behaviors (`onNextPage`/`onPreviousPage`/`onSelect`/`onBack`); **`onSelect` is banned** here (it conflates START and tap; the principle is `onKey`+`onTap`). The existing `GateV2Delegate` uses `onSelect` — that is **spike code; do not copy its pattern** for the playback delegate. [Source: GateV2Delegate.mc:20-24; architecture.md:301]

### WPM step belongs in the engine (pure), the readout in the view
WPM lives in `ReaderEngine` (clamped `_wpm`, `setWpm` takes effect next word with no re-fetch/drift — `computeDuration()` reads `_wpm` only when the *next* word is selected). So the **adaptive step is pure engine logic** (host-testable, Task 1) and "without interrupting the stream" (AC2) is **already guaranteed by the engine** — the view must NOT touch the timer on a WPM change. The **transient readout** is a view concern (Task 3). [Source: ReaderEngine.mc:168-175, 226, 245-254]

### REUSE — do not reinvent
- **`Reader.ReaderEngine`** — drive via the existing surface; add only `stepWpmUp/Down`. `requestPause()` already implements coast/instant (AC1); `rewind()` already auto-pauses + is stackable + clamps at 0 (AC3); `play()` re-arms the 3-beat ramp on resume and no-ops on empty/FINISHED. Do not duplicate any of this in the view/delegate. [Source: ReaderEngine.mc:79-136, 173-203]
- **`SettingsModel.Settings`** — read `touchControls` (AC5 gate), `handedness` (swipe mirror), `pauseMode` (already consumed by the engine via the ctor — the view passes primitives, AC1 honored through the engine). Constants `HAND_RIGHT/HAND_LEFT`, `PAUSE_COAST/PAUSE_INSTANT`, `WPM_MIN/WPM_MAX`. [Source: Settings.mc:18-38, 50-58]
- **`PlaybackView`** ORP composition, `armTimer()`, `recomputeJitter()`, `onTimerTick` loop, `_jitterX/_jitterY`, color consts — reuse as-is; add the action API + readout. The engine/source/settings/timer are already owned by the view. [Source: PlaybackView.mc:54-294]
- **Test pattern** — copy `SmokeTest.mc` / `ReaderEngineTest.mc`: `import Toybox.Test; (:test) function x(logger as Test.Logger) as Boolean { if (a != b) { logger.error("..."); return false; } return true; }`. **No `Test.assert*`** anywhere in this repo. [Source: SmokeTest.mc; ReaderEngineTest.mc:1-9]

### Monkey C conventions (verified in-repo)
- Classes PascalCase, one public class per `PascalCase.mc`; methods/vars `camelCase`, private fields `_camelCase`, module constants `UPPER_SNAKE`. [Source: architecture.md:245-258; observed]
- **Strict typing (level 3) from commit 1** — every signature typed, `?` on nullables. Watch the poly-type traps the 3.1/3.2 devs hit (`Storage.ValueType`, `Array<Number>` vs `ByteArray`); cast at the seam, never lower strictness. The `getInitialView()` return type is `[WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates]` — the two-element form is already in the signature. [Source: architecture.md:314; PaceTurnerApp.mc:80; 3-2 Debug Log]
- Callbacks use `method(:symbol)`, not closures (timer is `method(:onTimerTick)`). [Source: PlaybackView.mc:120; 3-2 notes]
- **Refcount GC, no cycle collection (AR15)** — input flows **delegate → view → engine** only; the engine never references the view, and the view never references the delegate. The delegate holding the view is one-directional and fine (no cycle). [Source: architecture.md:106, 287; 3-2 notes line 131]
- `System.println` is **budgeted** (~10KB on-device log) — lifecycle/transitions only, **never per-word**; guard verbose input-event logs behind `(:debug)` (stripped from release). A per-input `println` at reading speed is the named anti-pattern's cousin. [Source: architecture.md:289, 323; 3-2 notes line 132]
- Error posture (NFR8/AR24): bounds-check-and-degrade, never crash; null/unexpected → no-op the action, keep reading. [Source: architecture.md:121]

### Edge cases to handle (bounds-check-and-degrade)
- **WPM step at the clamp edges** — down from 10 stays 10, up from 1000 stays 1000 (engine `clampWpm`). Tested in Task 1.
- **UP/DOWN during the start ramp** — treat as "not paused" → WPM step (engine recomputes ramp `beatMs` from the new WPM next beat). Harmless. [Source: ReaderEngine.mc:246-247]
- **UP/DOWN/START on a FINISHED book** — FINISHED is not "paused": UP/DOWN map to WPM (harmless no-visible-effect), START → `pauseOrResume` resume branch calls `play()` which **no-ops on FINISHED** (terminal until a rewind). Acceptable; document the minor harmless WPM-on-finished case. [Source: ReaderEngine.mc:79-83, 188-191]
- **Rewind while already paused** (stackable) — no timer running; `rewindOne()` just repaints. Engine clamps at word 0. [Source: ReaderEngine.mc:119-136]
- **Transient readout at very low WPM** — the readout self-clears on the next word repaint; at WPM near the floor (long inter-word interval) it can linger up to one word duration. Acceptable for MVP; do **not** add a second clear-timer unless on-device review demands it. [Source: AC2; PlaybackView.mc:99-113]

### Composition / colors (DESIGN authority)
- WPM readout: **Ink-Dim `#8A867F`**, `watch-meta` 22px, "Visible when you look for it, invisible at reading speed." It is explicitly named alongside the paused progress readout and status text as the Ink-Dim role. Add `COLOR_INK_DIM = 0x8A867F` by name (no inline hex at draw sites — the 3.2 rule). [Source: DESIGN.md:108, 122]
- The page stays flat: hierarchy is brightness (`ink → ink-dim → ink-faint`), never shadow/layering; one red for one job (do **not** use Pivot for the readout). [Source: DESIGN.md:113, 140]

### Build / harness facts (carried from Story 3.1/3.2)
- Manifest `minApiLevel = 5.2.0`, product `fenix847mm`; CI pins **SDK 8.4.0** (`matco/action-connectiq-tester`). The on-host SDK 9.1.0 sim can't run here (missing `libwebkit2gtk-4.0`) — run host tests via the container (`ghcr.io/matco/connectiq-tester`, `tester.sh fenix847mm`), the authoritative gate. **`rm -f watch/bin/app.prg` before every run** (stale-binary trap). [Source: 3-2 notes line 137; watch-tests-local-via-ci-docker-image memo; manifest.xml]
- Real-hardware check: sideload to the Fenix 8 (USB Mode → MTP, `gio copy` the `.prg`) — input behavior (and the swipe-right-as-BACK question) is the one thing host tests can't see. [Source: garmin-ciq-ubuntu-2404-appimage memo; 3-2 notes line 138]

## Project Structure & Conventions

### File locations (canonical tree — architecture.md lines 349-395)
- `watch/source/input/InputMap.mc` — pure key/gesture → action map (NEW; create `input/` dir). Host-testable seam (imports `Toybox.Lang` + `Toybox.WatchUi` only for `KEY_*`/`SWIPE_*` constants).
- `watch/source/input/PlaybackDelegate.mc` — `class PlaybackDelegate extends WatchUi.InputDelegate` (NEW). Architecture names this file at line 380 (`START=pause-coast, UP/DOWN=WPM, swipe-right=rewind, BACK=exit`).
- `watch/source-test/InputMapTest.mc` — host tests for the pure map (NEW).
- `watch/source/engine/ReaderEngine.mc` — add `stepWpmUp/Down` (MODIFY; still imports only `Toybox.Lang`).
- `watch/source-test/ReaderEngineTest.mc` — add WPM-step tests (MODIFY).
- `watch/source/views/PlaybackView.mc` — action API + transient readout (MODIFY).
- `watch/source/PaceTurnerApp.mc` — `getInitialView()` returns `[view, delegate]` (MODIFY; preserve spike).
- Reused unchanged: `engine/BookWordSource.mc`, `Settings.mc`, `source_data/{StreamDecoder,CannedWordSource}.mc`, `Protocol.mc`, `views/OrpLayout.mc`.

### Project Structure Notes
- `input/` does not exist yet — create it (architecture's canonical home for the delegates; line 379). Architecture also names a separate `PausedDelegate.mc` (line 382) for the paused state. **Decision for 3.3:** there is no separate *paused view* yet (PlaybackView renders the frozen still-frame itself), so a single **state-aware** `PlaybackDelegate` (it reads `engine.isPaused()` via the view and routes UP/DOWN/START accordingly) is the pragmatic shape now. **Story 3.4** introduces `PausedContextView` and may split out `PausedDelegate` then — `InputMap` already separates the paused mappings so the split is cheap. Flag for a reviewer if they prefer the `PausedDelegate` split landed here.
- `CannedWordSource` remains the Epic-3 dev stand-in; this story adds no new source. No `manifest.xml` change (no new permission).

### References
- [Source: _bmad-output/planning-artifacts/epics.md#Story-3.3 (lines 599-625)] — story statement + 5 ACs (FR8/FR9/FR10/FR12)
- [Source: _bmad-output/planning-artifacts/architecture.md (lines 87, 207, 301, 314, 323, 349-395 esp. 379-382, 592, AR15/AR24/AR25)] — input principles fixed/map provisional, file tree (input/ + PlaybackDelegate/PausedDelegate), Strict L3, logging budget, GC/error posture
- [Source: _bmad-output/planning-artifacts/ux-designs/ux-garmin_RSVP-2026-06-06/EXPERIENCE.md (lines 81-82, 96, 119-146)] — input map (START/UP/DOWN/swipe-right/MENU/BACK), adaptive WPM step, touch-off button path, handedness mirror, BACK sacred, map provisional
- [Source: _bmad-output/planning-artifacts/ux-designs/ux-garmin_RSVP-2026-06-06/DESIGN.md (lines 108, 113, 122, 140, 167)] — Ink-Dim WPM-readout role, watch-meta 22px, flat hierarchy / one-red, transient vs persistent chrome
- [Source: developer.garmin.com Toybox.WatchUi — InputDelegate / KeyEvent / SwipeEvent / BehaviorDelegate.onBack] — onKey/onTap/onSwipe signatures + return semantics, KEY_*/SWIPE_* enums, swipe-right-may-be-KEY_ESC warning
- [Source: watch/source/engine/ReaderEngine.mc:79-136, 168-203, 245-264, 289-293] — pause(coast/instant)/rewind/play/setWpm/clamp surface to reuse + add stepWpm to
- [Source: watch/source/Settings.mc:18-38, 50-58] — touchControls/handedness/pauseMode read surface + constants
- [Source: watch/source/views/PlaybackView.mc:54-156, 99-121, 283-294] — view owns engine/timer/jitter; add action API + readout; timer/jitter behavior
- [Source: watch/source/PaceTurnerApp.mc:80-88] — getInitialView signature already allows [Views, InputDelegates]
- [Source: watch/source/GateV2Delegate.mc:8-24] — spike delegate uses onSelect → do NOT copy (banned pattern)
- [Source: watch/source-test/{ReaderEngineTest,OrpLayoutTest,SmokeTest}.mc] — (:test) host pattern, no Test.assert*, CI-image run + stale-binary trap
- [Source: _bmad-output/implementation-artifacts/3-2-playbackview-orp-word-rendering.md (Dev Notes, Review Findings, File List)] — view ownership, AR15/logging/error conventions, build/harness facts, "test count must rise"
- [Source: _bmad-output/implementation-artifacts/deferred-work.md (lines 47-49 "Forward to Epic 3")] — reader pause/rewind consumer note, atEnd()/sentenceStartAtOrBefore anchors
- [Source: _bmad-output/planning-artifacts/prds/.../prd.md#FR8,FR9,FR10,FR12] — two-stage pause, WPM control, sentence rewind, buttons-first/touch-mirror

## Dev Agent Record

### Agent Model Used
Amelia (dev-story) — Claude Opus 4.8 (claude-opus-4-8[1m]).

### Debug Log References
- **Test gate (authoritative):** `docker run --rm -v $PWD/watch:/work -w /work ghcr.io/matco/connectiq-tester:latest fenix847mm` after `rm -f watch/bin/app.prg`. `Ran 55 tests … PASSED (passed=55, failed=0, errors=0)`. **Count rose 46 → 55 (+9: 4 engine WPM-step + 5 InputMap), not flat.** Re-run after adding the `(:debug)` input-trace overload — still 55/55.
- **Release gate:** in-container `monkeyc -f monkey.jungle -d fenix847mm -y <temp-key> -l 3 -w -r` (Strict L3, warnings-on) → `BUILD SUCCESSFUL`, exit 0, 34,780-byte `release.prg`. Confirms the `(:release)` no-op trace overload compiles and ships with no per-input `println`. Strictness never lowered.
- **Tester harness gotcha (caught + worked around):** the matco image ENTRYPOINT is `/bin/bash /connectiq/bin/tester.sh`, so a trailing `-c '…'` is swallowed as `tester.sh`'s `DEVICE_ID` arg and the container hangs compiling for device "-c" (0-byte output, killed after ~8 min). The unit-test gate is the bare positional form (`… fenix847mm`); the release build is run with `--entrypoint bash … -c '<monkeyc …>'` and its own temp cert (mirrors tester.sh's `openssl genrsa | pkcs8` cert step). Recorded so a future story does not repeat the hang.
- **Strict-L3 enum seam:** `KeyEvent.getKey()`/`SwipeEvent.getDirection()` (typed `WatchUi.Key`/`Swipe`, Number-backed enums) pass cleanly into `InputMap`'s `Number` params and compare `==` against `WatchUi.KEY_*`/`SWIPE_*` at level 3 — no cast needed. Tests pass the real `WatchUi.*` constants in (the matco tester runs the full SDK), so the map is pinned against the actual enum values, not a guess.

### Completion Notes List
- **All 5 ACs implemented in code; 55/55 host tests green @ Strict L3; both builds clean.** Engine stayed `Toybox.Lang`-only (AC7 from 3.1 preserved — `stepWpmUp/Down` + private `adaptiveStep()` are pure math through the existing `clampWpm`/`setWpm` path).
- **AC1 (pause):** delegate START/tap → `PlaybackView.pauseOrResume()` → `engine.requestPause()` (coast/instant already in the engine) / `engine.play()` + re-arm on resume. No manual timer stop — coast coasts on the live loop, instant/rewind settle on the existing `onTimerTick` paused branch.
- **AC2 (adaptive WPM, mid-stream, transient readout):** step keyed on current WPM before stepping (10 below 100, 25 at/above; the 100→75-down boundary is unit-pinned), routed through `setWpm` so it takes effect next word with no re-fetch/drift (proved by `engineStepWpmDoesNotInterruptStream`). Transient Ink-Dim (`COLOR_INK_DIM=0x8A867F`) readout in the lower third (`FONT_SYSTEM_TINY`, ~`watch-meta`), armed for `READOUT_MS=900`, self-clearing on the first repaint past the deadline — drawn only while NOT paused. It is the one allowed playing-state overlay (transient + dim), so it does NOT violate 3.2 AC5's "no persistent BRIGHT chrome" (documented at the draw site).
- **AC3 (rewind):** `PlaybackView.rewindOne()` → `engine.rewind()` (auto-pauses, stackable, clamps at 0) + `recomputeJitter()` for the new still frame. Reached by the button path (START→pause, UP-while-paused) AND swipe-right (touch on), both via the pure map.
- **AC4 (principled map):** `PlaybackDelegate extends WatchUi.InputDelegate` (NOT `BehaviorDelegate`) — raw `onKey`/`onTap`/`onSwipe`, **no `onSelect`**. BACK (`KEY_ESC`) → `return false` so the system exits to the watch face (no Storage write — force-save is Story 3.6); LIGHT/MENU → `ACTION_NONE`, never consumed. Every action has a button path.
- **AC5 (button-operable, touch off):** `actionForTap`/`actionForSwipe` gate on `Settings.touchControls`; with touch off they return `ACTION_NONE` (the delegate returns `false`), and pause/WPM±/rewind/resume/exit all remain on physical buttons.
- **⏳ PENDING HUMAN — on-device input check (Task 6, REQUIRED, not yet done):** host tests can't see real button/gesture routing. Nerya must sideload the debug `.prg` to the Fenix 8 (MTP / `gio copy`) and confirm: START pauses (coast→sentence-end) & resumes with ramp; UP/DOWN change WPM live with the transient readout, no stutter; **swipe-right rewinds OR is folded into BACK/exit** (the #1 risk — record which); button-path rewind (START→UP) works regardless; BACK exits; LIGHT untouched; with Touch controls Off everything still works by buttons. A `(:debug)`-guarded one-line marker (`input <kind> raw=<n> -> action=<n>`) prints per input event for the log-based check (stripped from release via the `(:release)` no-op overload). If swipe-right is unusable, the rewind gesture can move to swipe-left/up entirely behind `InputMap` with zero churn elsewhere.
- **✅ On-device result (Fenix 8 47 mm, sideloaded debug build, Nerya 2026-06-23) — all 6 checks PASS:** START pauses (coast → freezes at sentence end) and resumes with the 3-2-1 ramp; UP/DOWN change WPM live with the transient readout, no stutter; button-path rewind (START→UP) works and stacks; BACK exits; LIGHT untouched.
  - **Swipe-right RESOLVED (the story's #1 hardware risk):** swipe-right **rewinds** as designed — UNLESS the swipe *originates at the very left bezel edge*, in which case the firmware consumes it as a system BACK/exit before it ever reaches `onSwipe` (the documented "SWIPE_RIGHT may arrive as KEY_ESC" behavior, here scoped precisely to a **left-edge-origin** edge-swipe, not all swipe-rights). A swipe-right that begins anywhere off the left edge reaches `onSwipe` and rewinds. **Verdict: the swipe gesture is usable and KEPT as-is; the button path (START→UP) remains the fixed guarantee** for the edge-swipe overlap. No code change — `InputMap`/`PlaybackDelegate` are validated unchanged. (If Nerya later finds the edge-swipe-exit annoying in practice, the rewind gesture can move to swipe-left/up entirely behind `InputMap` with zero churn elsewhere; not needed now.)
- **Scope honored:** no `manifest.xml` / permission change; GateV2 spike preserved (compiled, not entered); `ACTION_CONTEXT` (DOWN-while-paused) returned but treated as no-op by the delegate so Story 3.4 can wire the context view; single state-aware `PlaybackDelegate` (no separate `PausedDelegate` yet — flagged for reviewer, the paused mappings are already isolated in `InputMap` so the 3.4 split is cheap).

### File List
**New:**
- `watch/source/input/InputMap.mc` — pure key/gesture → action map (action consts; `actionForKey`/`actionForTap`/`actionForSwipe`)
- `watch/source/input/PlaybackDelegate.mc` — `class PlaybackDelegate extends WatchUi.InputDelegate` (thin adapter; `(:debug)`/`(:release)` input-trace overloads)
- `watch/source-test/InputMapTest.mc` — 5 host tests for the pure map

**Modified:**
- `watch/source/engine/ReaderEngine.mc` — added `stepWpmUp`/`stepWpmDown` + private `adaptiveStep()` (still `Toybox.Lang`-only)
- `watch/source-test/ReaderEngineTest.mc` — added 4 adaptive-WPM-step tests + `engineAtWpm()` helper
- `watch/source/views/PlaybackView.mc` — action API (`pauseOrResume`/`stepWpm`/`rewindOne`/`touchEnabled`/`rewindSwipeDirection`/`isPausedState`) + transient Ink-Dim WPM readout (`COLOR_INK_DIM`, `READOUT_MS`, `_wpmReadoutUntil`, `drawWpmReadout`)
- `watch/source/PaceTurnerApp.mc` — `getInitialView()` constructs the view once and returns `[view, PlaybackDelegate(view)]` (spike preserved)

### Change Log
- 2026-06-23 — Story 3.3 implemented (dev-story): adaptive WPM step in the engine (pure, host-tested) + pure `InputMap` + thin `PlaybackDelegate` (`WatchUi.InputDelegate`, never `onSelect`; BACK=exit; LIGHT/MENU=NONE) + `PlaybackView` action API & transient Ink-Dim WPM readout + `getInitialView`→`[view, delegate]`. 5/5 ACs in code; 55/55 host tests green @ Strict L3 (count rose 46→55, +9), release build clean (34.8 KB).
- 2026-06-23 — On-device input check PASS on real Fenix 8 (sideload, Nerya): all 6 checks green; swipe-right RESOLVED — rewinds except a left-bezel-edge-origin swipe which the firmware folds into BACK/exit; gesture kept as-is, button path (START→UP) is the guarantee. No code change.

### Review Findings

Code review 2026-06-23 (3 layers — Blind Hunter / Edge Case Hunter / Acceptance Auditor). Acceptance Auditor: **5/5 ACs MET in code**, dev self-report accurate, all Dev-Note constraints honored (engine Lang-only, no `onSelect`, `InputDelegate` not `BehaviorDelegate`, BACK→false no-Storage, `COLOR_INK_DIM` by name, no `Test.assert*`, count rose 46→55, no manifest change). 1 patch, 3 deferred, 12 dismissed as noise/by-design.

- [x] [Review][Patch] Transient WPM readout never self-clears in FINISHED state [watch/source/views/PlaybackView.mc:253-259] — APPLIED 2026-06-23 (guard tightened to `!(isPlaying()||isRamping())`; 55/55 @ Strict L3) — `drawWpmReadout` guards only on `isPaused()`. In FINISHED, `isPaused()` is false so a UP/DOWN (→`ACTION_WPM_UP/DOWN`, since FINISHED is not "paused") arms the readout and draws it, but the timer is stopped (no repaint loop) so the "self-clears on the next word repaint" contract never fires — the Ink-Dim readout sticks on the terminal frame until the next unrelated input, becoming the persistent overlay it was designed never to be (brushes 3.2 AC5). Fix: gate the draw on playing/ramping — `if (!(_engine.isPlaying() || _engine.isRamping())) { return; }` (covers paused AND finished AND idle; still draws during the ramp, which is intended).
- [x] [Review][Defer] No button-path rewind from the FINISHED state [watch/source/input/InputMap.mc:actionForKey + PlaybackView] — deferred. The map keys only on `isPaused`, so at end-of-book UP→`ACTION_WPM_UP` (not REWIND); there is no button path back into the text from FINISHED. Finished-screen behavior is Story 3.5 scope (no Finished screen exists in 3.3 — the canned source just ends). Revisit when 3.5 lands.
- [x] [Review][Defer] View-side readout deadline has no `System.getTimer()` wraparound guard [watch/source/views/PlaybackView.mc:145,257] — deferred. `_wpmReadoutUntil = getTimer() + READOUT_MS` and `getTimer() >= _wpmReadoutUntil` can misbehave at the 32-bit ms wrap (~24.8 days uptime); the readout flashes nothing or sticks one wrap-period. Cosmetic, self-correcting on the next step; the engine guards wrap at its own seam, the view does not. Low priority.
- [x] [Review][Defer] `rewindOne` double-recomputes jitter when rewinding mid-play [watch/source/views/PlaybackView.mc:155-159] — deferred, acknowledged-harmless. Rewinding while playing calls `recomputeJitter()` once, then the pending one-shot tick fires into the paused branch and recomputes it again (≤1px shift on the settled still frame). Documented as acceptable in the code comment; on-device PASS did not flag it.

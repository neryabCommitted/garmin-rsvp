---
baseline_commit: ec3f42014081f2a077f9d73434a4c3e587fd40ce
---

# Story 3.8: Settings menu UI

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a reader,
I want a menu to edit the settings,
so that I can tune the reading experience to my eyes and hands (UX-DR17, UX-DR24).

## Acceptance Criteria

1. **Given** the Settings model (established in Story 3.1) and the MENU action
   **When** opened
   **Then** a Menu2 surface presents the model's values for editing: WPM, pause mode (coast/instant), chapter-card resume (Auto/Wait), touch controls (On/Off), font size (±2 steps), handedness, focus highlight, phantom words, anchor position.

2. **Given** a setting change in the menu
   **When** applied
   **Then** it updates the model, persists to the `"settings"` Storage key, takes effect immediately, and remains per-device, never synced.

3. **Given** a font-size change
   **When** applied
   **Then** only the active word-display size is heap-resident (load-on-demand); native-font fallback is the documented escape hatch if resource cost breaks NFR2.
   *Note: the shipped renderer uses native system fonts (the escape hatch, per UX-DR2 and the 3.2 font-swap deferral) — all sizes are firmware-resident, so AC3 is satisfied by the escape-hatch clause today. The load-on-demand obligation activates with the Atkinson BMFont swap story. Document this in code where `_fontIndex` is applied.*

4. **Given** handedness
   **When** set
   **Then** swipe directions mirror accordingly.
   *Note: mirroring itself already works — `PlaybackView.rewindSwipeDirection()` (PlaybackView.mc:457) reads `_settings.handedness` live. AC4 is met by exposing the setting + pinning the propagation path; do not reimplement mirroring.*

5. *(rider, deferred-work.md:133 — explicitly earmarked "Land with Story 3.8")* **Given** any WPM
   **When** the 3-beat start ramp runs
   **Then** each ramp beat's duration is clamped to a bounded range (~400–1000 ms) independent of WPM, so the countdown is neither ~9 s at 20 WPM nor ~360 ms at 500 WPM. Pure engine change, host-test pinned (non-divisor WPMs included). Normal word beats are untouched.

## Tasks / Subtasks

- [x] Task 1: Claim the MENU key in the input map (AC: 1)
  - [x] `input/InputMap.mc`: add `ACTION_MENU = 7`; `actionForKey`: `WatchUi.KEY_MENU` → `ACTION_MENU` in **both** states (playing = "pause + open settings" per UX-DR16; paused = open settings — the UX spine leaves paused-MENU unmapped, this is the resolved reading). `KEY_LIGHT` stays `ACTION_NONE` (off-limits, UX-DR15). Update the stale header comment ("the settings menu is Story 3.8").
  - [x] `watch/source-test/InputMapTest.mc`: the existing pins assert MENU→NONE in both states — **flip them** to pin MENU→ACTION_MENU both states; keep the LIGHT→NONE pins.
  - [x] `input/PlaybackDelegate.mc`: dispatch `ACTION_MENU` → `_view.openSettingsMenu()`, return `true` (consumed).
- [x] Task 2: `PlaybackView.openSettingsMenu()` (AC: 1, 2)
  - [x] Wake-grace guard first: `Display.isWakeGrace(_lastWakeMs, System.getTimer(), Display.WAKE_GRACE_MS)` → return. Same rationale as `openContextView` (review 2026-07-20, Nerya-approved): wake finds Paused, not a menu.
  - [x] No-op while `_chapterCard || _engine.isFinished()` (Story 3.5 Task-8 input discipline — card is a breath, FINISHED is terminal/UX-DR14).
  - [x] If playing/ramping: `_engine.pauseAtCurrent()` (instant, mode-independent — `requestPause` coast would flow words behind the pushed menu), then `commitPosition(true)` (3.6 transition force-save; same-index suppression makes a redundant call free).
  - [x] Push: `WatchUi.pushView(SettingsMenu.build(_settings, engineWpm), new SettingsMenuDelegate(_settings, self, menu), WatchUi.SLIDE_UP)` — exact wiring per Task 3; PlaybackView keeps NO reference to the pushed menu/delegate (AR15 no-cycle; `openContextView` PlaybackView.mc:425-448 is the template). *[AMENDED in dev: delegate takes `(_settings, self)` — no menu param; see Task 4 amendment.]*
- [x] Task 3: NEW `views/SettingsMenu.mc` — Menu2 surface + pure logic module (AC: 1, 2)
  - [x] Module `SettingsMenu` with two halves in one file (SyncManager.mc:6-13 / DisplayStrategy.mc precedent):
    **Pure half (Lang-only, host-tested):** label/value/cycle helpers — `labelForPauseMode(v)` ("Coast"/"Instant"), `labelForChapterResume(v)` ("Auto"/"Wait"), `labelForHandedness(v)` ("Right"/"Left"), `labelForFontSize(v)` (5 steps, e.g. "1 (largest)".."5 (smallest)"), `cycleEnum(v, lo, hi)` (wraps), `cycleFontSize(v, rampLength)` (wraps 0..rampLength-1, out-of-range input snaps into range), `cycleAnchorPct(v)` (30→35→…→60→30, step 5 — UX-DR5 user-tunable range is 30–60 even though the model clamps 0–100; out-of-range/non-multiple input snaps to 35 default). No Toybox.System/Storage imports in the pure half.
    **Thin half:** `build(settings, liveWpm)` returns a `WatchUi.Menu2` ({:title => "Settings"}) with items **in UX-DR17 order**: WPM (MenuItem, sub-label = live value), Pause mode (MenuItem, sub-label via labelFor), Chapter resume (MenuItem), Touch (ToggleMenuItem, checked = touchControls), Font size (MenuItem), Handedness (MenuItem), Focus highlight (ToggleMenuItem), Phantom words (ToggleMenuItem), Anchor (MenuItem, sub-label "NN%"). Item ids = Symbols (`:wpm`, `:pauseMode`, …) — no magic numbers/strings at dispatch sites.
  - [x] Copy: quiet-librarian (UX-DR23) — short, factual, no exclamation marks. Labels/sub-labels pinned by the pure label functions' host tests.
- [x] Task 4: NEW `input/SettingsMenuDelegate.mc` extends `WatchUi.Menu2InputDelegate` (AC: 2)
  - [x] `onSelect(item)`: switch on item id — enum/toggle items cycle-or-flip the field on `_settings`, call `_settings.save()` (menu is cold path — the deferred-work:129 flash-write hazard is the hot tick path, not here), update the item's sub-label/toggle state, notify the view (Task 5), `WatchUi.requestUpdate()`. WPM item → push the stepper (Task 6).
  - [x] `onBack()`: `WatchUi.popView(WatchUi.SLIDE_DOWN)` — BACK pops to the Paused frame, never exits the app from the menu (BACK-sacred, UX-DR15; PausedContextDelegate.mc:22-24 is the template). PlaybackView's existing `onShow` STATE_IDLE guard keeps the revealed frame Paused (PlaybackView.mc:206).
  - [x] Delegate holds refs to `_settings`, the PlaybackView, and the Menu2 (delegate→view is the established direction — PlaybackDelegate does the same; the view holds no ref back: no GC cycle, AR15). *[AMENDED in dev: the Menu2 ref is NOT held — `onSelect(item)` receives the touched item directly, so a stored menu ref is dead weight, and an unused member is a warning the warning-free gate (Enforcement #5) rejects. Deviation documented in SettingsMenuDelegate.mc header.]*
- [x] Task 5: Immediate-effect propagation in PlaybackView (AC: 2, 3, 4)
  - [x] Already-live fields need **nothing**: `touchControls` (:451), `handedness` (:457), `anchorPct` (:609), `phantomWords` (:884), `focusHighlight` (:905), `chapterResume` (:203, :530) are read from `_settings` per event/frame — menu mutates the same instance the view owns.
  - [x] Copied-at-construction fields need thin apply methods on PlaybackView: `applyWpm(v)` → `_engine.setWpm(v)` (engine clamps; takes effect next word, no drift — engine contract); `applyPauseMode(v)` → `_engine.setPauseMode(v)`; `applyFontSize()` → `_fontIndex = OrpLayout.clampFontIndex(_settings.fontSize, RAMP_LENGTH)` (the 3.1-deferred-#94 bound stays enforced at the view).
  - [x] [DECISION — veto-able at review] Reconcile the live-WPM divergence: in-flow UP/DOWN steps mutate only the engine today, so `Settings.wpm` (and the next relaunch) silently forgets stepped speed. Fix: `stepWpm()` additionally syncs `_settings.wpm = _engine.wpm()` (memory-only, sets a `_settingsDirty` flag); `onHide()` saves iff dirty (cold path, rides the existing force-save transition at PlaybackView.mc:223-228). Menu edits save immediately and clear the flag. The menu's WPM item seeds from `_engine.wpm()` (runtime source of truth), not the stale stored value.
- [x] Task 6: NEW WPM stepper editor — `views/WpmStepperView.mc` + `input/WpmStepperDelegate.mc` (AC: 1, 2)
  - [x] WPM (10–1000, adaptive step) cannot be a cycling MenuItem; every other item edits in ≤7 presses. A pushed **value editor** is not a "multi-level menu" (UX-DR16 bans nested menus; this is a single flat menu + an editor leaf — document this reading in the file header).
  - [x] View: Void background, candidate value in Ink large, title "WPM" in Ink-Dim `watch-meta`, inside the watch-safe-square (DESIGN.md card regime). Render-only; no timer.
  - [x] Delegate (`WatchUi.InputDelegate`, raw `onKey` — never `onSelect`, UX-DR15): UP/DOWN = ±adaptive step on the candidate; START = commit (`_settings.wpm = candidate; _settings.save(); view.applyWpm(candidate); menuItem.setSubLabel(...)`) + pop; BACK = cancel + pop (pop-not-exit). *[AMENDED — on-device Task 9, Nerya 2026-07-23: START=commit/BACK=cancel was confusing on the wrist — it wasn't obvious a separate START was needed, and changing the number then pressing BACK silently discarded it, out of step with every other item (which applies on change). Now **commit-on-exit**: BOTH START and BACK save the candidate (shared `commitAndPop()`), so "what you set is what sticks"; to undo, step back to the old value. BACK still only pops, never exits the app.]*
  - [x] Adaptive-step rule must have ONE encoding (review-feedback class: unpinned duplicate tables). Move it to the model: NEW pure `SettingsModel.adaptiveWpmStep(current, up) as Number` (10 below 100, 25 at/above, the 100→75 down-boundary, clamp WPM_MIN..WPM_MAX — exactly the current `ReaderEngine.adaptiveStep` behavior); `ReaderEngine.stepWpmUp/Down` delegate to it. Existing ReaderEngineTest adaptive pins must stay green unchanged — that is the proof the move is behavior-preserving.
- [x] Task 7: Ramp-beat clamp rider (AC: 5)
  - [x] `engine/ReaderEngine.mc`: clamp each ramp beat's duration to `[RAMP_BEAT_MIN_MS=400, RAMP_BEAT_MAX_MS=1000]` independent of WPM. Word beats (`60000/wpm + bonusMs`) untouched. Pure change, Lang-only intact.
  - [x] Host tests: wpm 20 → ramp beat 1000 (not 3000); wpm 500 → 400 (not 120); a non-divisor wpm (e.g. 137) inside the window passes through unclamped; ramp still 3 beats; accumulator re-anchor after ramp unchanged.
- [x] Task 8: Tests, gates, red-check (all ACs)
  - [x] NEW `source-test/SettingsMenuTest.mc`: pure-half pins — every labelFor* value, cycle wrap points (pauseMode INSTANT→COAST, fontSize rampLength-1→0 and out-of-range snap, anchor 60→30 and snap-to-35), `adaptiveWpmStep` boundary rows (99→+10, 100→+25, 100→down 75, clamps at 10/1000).
  - [x] Updated: InputMapTest (Task 1), ReaderEngineTest (Task 7; adaptive pins prove Task 6's move).
  - [x] TDD: red first (undefined symbols count), then green. Seeded-mutation red-check: flip one cycle bound (e.g. anchor wrap 60→**65**) → exactly the anchor pin fails; flip the ramp clamp min → exactly the wpm-20 ramp pin fails; revert, green.
  - [x] Gates: host compile SDK 9.1.0 `-l 3 -w` both builds; **execution in the CI image** (`docker context use desktop-linux`; `rm -f watch/bin/app.prg` first; `docker run --rm -v "$PWD/watch:/app" -w /app -e HOME=/root --entrypoint bash ghcr.io/matco/connectiq-tester:latest -c 'tester.sh fenix847mm'`). Expect 87 → ~95+. Release build `-r` warning-free; note the size (was 44,572 B).
- [x] Task 9: On-device Fenix 8 check (human, results machine-readable to stdout/log) — **PASS 2026-07-23 (Nerya), with one amendment**
  - [x] MENU while playing → pauses at current word + menu opens; MENU while paused → menu opens; MENU during chapter card / FINISHED → nothing. **All as designed.** (FINISHED-no-op questioned on device → CONFIRMED keep-disabled, Nerya 2026-07-23: FINISHED is terminal, UX-DR14; consistent with card/rewind no-op.)
  - [x] Each item takes effect immediately on pop-back: touch Off → tap dead but buttons work (native Menu2 stays touch-operable — intended, confirmed acceptable); handedness Left → mirrors; font size / anchor 60% / focus / phantom / pause-Instant / chapter-Wait — all visible & correct. **WPM editor commit was unclear on the wrist → fixed (see Task 6 amendment: commit-on-exit).**
  - [x] Persistence: set non-defaults → carousel force-quit → relaunch → menu shows the saved values, reading uses them (incl. stepped-in-flow WPM — Task 5 decision **stands**). **Works.**
  - [x] Regressions: BACK from menu → Paused frame (not exit); wake-press does NOT open the menu (grace); 3.2–3.7 spot checks. **None.**
  - [x] WPM commit-on-exit amendment re-tested on device (Nerya 2026-07-23): changing WPM then pressing BACK now saves; START also saves. **Works.**

## Dev Notes

### Developer context — read this first

- **The model already exists; do not touch its shape.** `watch/source/Settings.mc` (`SettingsModel.Settings`) has all 9 fields, validated `applyDict`/`toDict` (the test seam) and the ONLY Storage adapter `loadFrom()`/`save()` under `StorageKeys.SETTINGS` (Settings.mc:118-128). New settings fields are NOT needed; no schema-version bump (applyDict degrades missing/malformed to defaults by design). Field ranges: wpm 10–1000 clamp, pauseMode/handedness/chapterResume enum {0,1}, fontSize ≥0 (upper bound is the view's `OrpLayout.clampFontIndex` — deferred #94), anchorPct 0–100, three Booleans.
- **Settings are per-device, never synced, never cross the protocol** (UX-DR17, architecture "Process Patterns → Settings locality"). Nothing in this story touches Protocol/SyncManager's pos_* namespace.
- **MENU key is reserved and waiting**: InputMap.mc:35-36 maps KEY_MENU→NONE with the comment "the settings menu is Story 3.8"; PlaybackDelegate returns `false` for NONE so MENU currently bubbles to the system. InputMapTest pins that — flip the pins (Task 1).
- **Engine holds primitives, not the Settings object** (ReaderEngine.mc:60-63): wpm/pauseMode were copied at construction (PlaybackView.mc:153). Live mutators `setWpm`/`setPauseMode` exist (ReaderEngine.mc:212,216). `_fontIndex` is resolved once at init (PlaybackView.mc:168). Everything else is read live. Task 5 is the complete propagation map — trust it, don't rediscover.
- **Menu2 at minApiLevel 5.2.0 (ADR 0001) is safe**: Menu2/MenuItem/ToggleMenuItem/Menu2InputDelegate/setFocus are API 3.0.0; `:dividerType` 5.0.1, `:footer` 5.1.0 (Connect IQ API docs, checked 2026-07-20). The Strict-L3 compile against fenix847mm is the backstop. CI image is SDK 8.4.0 — it has caught SDK-only landmines before; never skip it.
- **What must NOT appear in this menu**: any display/AOD/screen-strategy item (ADR 0003 — strategy is not user-configurable; the watch's own "Display > Always On" governs), a font-family item (OpenDyslexic out of MVP, DESIGN.md), a guide-marks toggle (absent from UX-DR17's list and from the model — see open questions), anything phone-side (defaults/about/licenses live on the phone per EXPERIENCE.md IA).
- **Banned by UX-DR15/16**: remapping BACK, multi-level menus, double-tap semantics, touch-only actions, consuming LIGHT, `onSelect` on the playback surface (Menu2InputDelegate's own `onSelect` is fine — that ban was written for the playback delegate; PausedContextDelegate already extends Menu2InputDelegate).
- **Font-size semantics gap, resolved for this story**: UX says "±2 steps around 48px" `[ASSUMPTION]`; the shipped ramp is indices 0..4 over native fonts (0=LARGE default … 4=XTINY, PlaybackView `fontFor` :912-918, RAMP_LENGTH=5). Expose the 5 ramp steps as the ±2-step surface; re-center when the Atkinson BMFont story lands. AC3 is satisfied by the native-font escape-hatch clause (see AC3 note).

### Architecture compliance

- Strict L3, warnings-as-errors, both builds (Enforcement #5). PascalCase.mc one public class/module per file; `_camelCase` privates; UPPER_SNAKE consts; **no magic strings/keys at call sites** — Storage only via `StorageKeys`, item ids as Symbols.
- Pure/adapter split (SyncManager/Display precedent): SettingsMenu's pure half imports Lang only — that is what makes it host-testable in the CI image.
- Views/delegates stay thin shells; input flows delegate → view → engine only; the view never holds a ref to a pushed menu/delegate (AR15 no-cycle; anti-pattern: "a view holding a strong ref back to its delegate").
- No silent `catch {}`; bounds-check-and-degrade (NFR8) — unrecognized menu item id degrades to no-op.
- Logging: at most one `System.println` per abnormal event; never per-interaction chatter (AR25). `(:debug)`-gated traces if needed (PlaybackDelegate.traceInput pattern).
- NFR3: the settings dict is one small flat value under one key — no new keys, no cap risk.
- New files need **no jungle change**: `base.sourcePath = source;source-test` is recursive (proven in 3.6/3.7).

### Previous story intelligence (3.7 + review)

- Wake-grace discipline: every user-visible action entry point gets the `isWakeGrace` guard; the window opens only on the unreadable→readable edge (`_lastModeUnreadable`). `openSettingsMenu` joins `pauseOrResume`/`rewindOne`/`openContextView`.
- Review-feedback recurring classes to pre-empt: (a) edge-vs-level arming bugs; (b) blind play-sites ignoring current state; (c) **unpinned duplicate encodings of one table** — hence Task 6's adaptiveWpmStep move; (d) `getTimer()` wraparound in elapsed math (none new here — the stepper has no timer); (e) mark contract changes inline in this file if anything is amended mid-story.
- Two-daemon docker trap: the `default` context's image spuriously fails Settings.mc:115 — use `desktop-linux`. Stale `app.prg` trap: delete before tester runs. Root-owned `.mir` cache after daemon switch → clear in-container.
- Test style: top-level `(:test)` functions `(logger as Test.Logger) as Boolean`, conditional + `logger.error` + return false — **no `Test.assert*`** (DisplayPolicyTest/SyncManagerTest are templates).
- On-device observations are ground truth — probe, don't assert (Task 9 is human-in-the-loop; print machine-readable results).

### Git intelligence

- HEAD `ec3f420` (3.7 review): 87/87 @ Strict L3, release 44,572 B warning-free. `3d3a87f` (ADR 0003) deleted ActivitySessionStrategy (preserved at `81978d6` for the Epic-5 "PaceTurner Active" variant) and dropped the Fit permission — manifest is `Communications` only; nothing in 3.8 touches the manifest.

### Latest tech information

- Connect IQ API docs (2026-07-20): Menu2 constructor options — `:title` (3.0.0), `:icon` (3.4.0, subscreen devices), `:theme` (4.1.8), `:dividerType` (5.0.1), `:footer` (5.1.0). `ToggleMenuItem` flips state before `onSelect` fires — read `item.isEnabled()` in the handler rather than tracking it yourself. `Menu2.getItem(index)`/`MenuItem.setSubLabel` available since 3.0.0; call `WatchUi.requestUpdate()` after sub-label changes.

### Out of scope

- Guide-marks toggle (UX-DR24 says individually toggleable; UX-DR17's list and the model omit it — flagged to Nerya, default OUT; would need a model field).
- AOD hint on the FINISHED frame (deferred-work:138 — 3.8/3.9 UX call; leaving to 3.9's on-wrist evaluation with `_sawDisplayOff` disarm, :137).
- Display/screen-strategy setting (ADR 0003), font-family setting, settings sync (never), phone-side settings surface.
- Settings menu reachable from anywhere but PlaybackView (there is no other surface in Epic 3; the library/status views get triggers in Epic 4).

### Project Structure Notes

- NEW: `watch/source/views/SettingsMenu.mc` (architecture tree names exactly this file), `watch/source/views/WpmStepperView.mc`, `watch/source/input/SettingsMenuDelegate.mc`, `watch/source/input/WpmStepperDelegate.mc`, `watch/source-test/SettingsMenuTest.mc`.
- UPDATE: `watch/source/input/InputMap.mc`, `watch/source/input/PlaybackDelegate.mc`, `watch/source/views/PlaybackView.mc`, `watch/source/Settings.mc` (add `adaptiveWpmStep` pure fn only — no field/shape change), `watch/source/engine/ReaderEngine.mc` (delegate step rule; ramp clamp), `watch/source-test/InputMapTest.mc`, `watch/source-test/ReaderEngineTest.mc`.
- Variance note: architecture's tree has no stepper-view file — WpmStepperView/Delegate are additive under the same views/input pattern (GateV2View/PausedContextView precedent). No manifest, jungle, resource, or Storage-schema change.

### References

- ACs + story statement: _bmad-output/planning-artifacts/epics.md §Story 3.8 (lines ~717-739); UX-DR17 (line 170), UX-DR15/16 (165-166), UX-DR24 (183), UX-DR5/8/9, UX-DR23 (voice).
- EXPERIENCE.md §Interaction Primitives ("MENU | Pause + open settings"; banned list), §Information Architecture (settings-menu row; phone settings split).
- DESIGN.md §Colors (Void/Ink/Ink-Dim; "if it isn't the current word, it doesn't get to be bright"), §Layout (watch-safe-square), §Typography.
- architecture.md: "Frontend Architecture" (SettingsMenu Menu2 + Settings model), "Naming Patterns" (StorageKeys), "Process Patterns" (settings locality; input principles; font loading), "Enforcement Guidelines".
- docs/decisions/0001 (minApiLevel 5.2.0), 0003 (app-mode; no display setting).
- deferred-work.md:133 (ramp clamp — this story), :94 (fontSize bound at view), :129 (flash-write hot-path hazard — informs save placement), :137-138 (3.9 items, do not collide).
- Prior art: PlaybackView.mc:425-448 (push/pop pattern), :450-461 (thin reads for delegate), :148-185 (init/propagation sites); PausedContextDelegate.mc (Menu2InputDelegate + pop); Settings.mc (model + adapter); SyncManager.mc:6-13 (pure/adapter cohabitation).

## Dev Agent Record

### Agent Model Used

Claude Fable 5 (claude-fable-5) — dev-story workflow, 2026-07-20/21.

### Implementation Plan

- TDD: all failing pins written first (InputMapTest MENU flips, SettingsMenuTest, ReaderEngineTest ramp-clamp + drift-free update); RED confirmed via host compile (undefined symbols: ACTION_MENU, SettingsMenu.*, adaptiveWpmStep, RAMP_BEAT_*); then Tasks 1→7 implemented in story order; GREEN in the CI image.
- SettingsMenu.mc follows the SyncManager pure/adapter cohabitation: pure half is Lang-only (labels + cycle rules + shared sub-label formatters `wpmSubLabel`/`anchorSubLabel` — one encoding of each string); thin half is the Menu2 factory with Symbol ids.
- Step-rule single encoding: `SettingsModel.adaptiveWpmStep(current, up)` returns the stepped-and-clamped NEW wpm; `ReaderEngine.stepWpmUp/Down` delegate to it (private `adaptiveStep()` deleted). The untouched Story-3.3 adaptive pins passing unchanged is the behavior-preservation proof.
- Ramp clamp: `computeDuration()` RAMP branch clamps `beatMs()` to `[RAMP_BEAT_MIN_MS=400, RAMP_BEAT_MAX_MS=1000]`; word beats untouched. `engineDriftFreeAccumulator` updated (ramp beat at wpm 250 is now clamp(240)=400).

### Debug Log References

- RED compile (host SDK 9.1.0, Strict L3): undefined-symbol errors exactly at the new-test call sites — InputMapTest.mc:64/67 (ACTION_MENU), ReaderEngineTest.mc:325/334/345 (RAMP_BEAT_*), SettingsMenuTest.mc (SettingsMenu.*, adaptiveWpmStep).
- GREEN: `Ran 96 tests PASSED (passed=96, failed=0, errors=0)` in ghcr.io/matco/connectiq-tester (fenix847mm, desktop-linux context, app.prg removed first). 87 → 96 (+6 SettingsMenuTest, +3 ramp-clamp).
- Seeded-mutation red-check: (1) anchor wrap 60→65 ⇒ exactly `settingsMenuCycleAnchorPct` FAIL (95/96). (2) `RAMP_BEAT_MAX_MS` 1000→900 ⇒ first run PASSED 96/96 — caught a VACUOUS PIN (tests compared against the constant, so the mutation moved both sides); tests hardened to literal pins (+ an explicit `[400,1000]` constants pin), re-run ⇒ exactly `engineRampBeatClampedLowWpm` FAIL (95/96). Both mutations reverted; final run 96/96 green.
- Gates: host SDK 9.1.0 `-l 3 -w` unit-test and release builds both BUILD SUCCESSFUL, warning-free. Release size 47,964 B (was 44,572 B). Signed `watch/bin/PaceTurner.prg` built for the Task 9 sideload.

### Completion Notes List

- AC1: MENU claimed in both states (InputMap ACTION_MENU=7; pins flipped); PlaybackDelegate dispatches to `PlaybackView.openSettingsMenu()` (wake-grace guarded, card/FINISHED no-op, pauseAtCurrent+force-save from playing/ramping); Menu2 presents all 9 model values in UX-DR17 order, Symbol ids, sub-labels via the pure label fns.
- AC2: every edit mutates the live Settings instance, `save()`s to the "settings" key (cold path only), takes effect immediately — live-read fields propagate for free; copied fields via `applyWpm`/`applyPauseMode`/`applyFontSize`. Nothing touches the protocol.
- AC3: satisfied by the native-font escape-hatch clause; documented in code at `PlaybackView.applyFontSize()` (where `_fontIndex` is applied) per the AC3 note.
- AC4: exposed handedness in the menu; mirroring path pinned (`rewindSwipeDirection()` reads `_settings.handedness` live — untouched).
- AC5: ramp-beat clamp landed (wpm 20 ⇒ 1000 ms, wpm 500 ⇒ 400 ms, wpm 137 ⇒ 437 ms pass-through pinned; ramp still 3 beats; accumulator re-anchor pinned).
- Task 5 DECISION implemented (veto-able at review): `stepWpm()` syncs `_settings.wpm = _engine.wpm()` memory-only + `_settingsDirty`; `onHide()` saves iff dirty; `applyWpm` clears the flag; menu/stepper seed from `engineWpm()`.
- DEVIATION: SettingsMenuDelegate holds no Menu2 ref (see Task 4 amendment) — `onSelect(item)` is sufficient; unused member = warning = gate failure.
- Test-quality find (worth review attention): the mutation red-check exposed constant-relative assertions as vacuous; ramp pins now assert literals.
- Task 9 (human, on-device Fenix 8) PENDING — signed PaceTurner.prg ready to sideload; results wanted machine-readable per the task.

### File List

- NEW watch/source/views/SettingsMenu.mc
- NEW watch/source/views/WpmStepperView.mc
- NEW watch/source/input/SettingsMenuDelegate.mc
- NEW watch/source/input/WpmStepperDelegate.mc
- NEW watch/source-test/SettingsMenuTest.mc
- MODIFIED watch/source/input/InputMap.mc
- MODIFIED watch/source/input/PlaybackDelegate.mc
- MODIFIED watch/source/views/PlaybackView.mc
- MODIFIED watch/source/Settings.mc
- MODIFIED watch/source/engine/ReaderEngine.mc
- MODIFIED watch/source-test/InputMapTest.mc
- MODIFIED watch/source-test/ReaderEngineTest.mc
- MODIFIED _bmad-output/implementation-artifacts/3-8-settings-menu-ui.md
- MODIFIED _bmad-output/implementation-artifacts/sprint-status.yaml

### Change Log

- 2026-07-21: Story 3.8 implemented (Tasks 1–8): settings Menu2 + delegate, WPM stepper editor, adaptiveWpmStep moved to SettingsModel (one encoding), ramp-beat clamp 400–1000 ms, in-flow WPM dirty-flag persistence, MENU key claimed. 96/96 host tests @ Strict L3 in CI image (87→96), seeded-mutation red-check exact (after hardening a vacuous constant-relative pin), both builds warning-free, release 47,964 B. Status → review; Task 9 on-device check pending.
- 2026-07-23: On-device Task 9 PASS (Fenix 8, Nerya). One amendment from the wrist: WPM editor now **commits on exit** (both START and BACK save; was START=commit/BACK=cancel, which was unclear and discarded on BACK) — `WpmStepperDelegate.commitAndPop()`. FINISHED-no-op confirmed keep-disabled; touch-on-native-menu confirmed intended; Task 5 in-flow-WPM-persistence decision stands. Amendment re-tested on device (BACK saves, START saves). Change is UI-delegate-only (no host-tested path); re-ran full suite on the correct desktop-linux image: 96/96 @ Strict L3, both builds warning-free, release 47,964 B. Task 9 complete → ready for code-review.

### Review Findings

Code review 2026-07-23 (3 layers — Blind Hunter, Edge Case Hunter, Acceptance Auditor). All 5 ACs assessed **MET** (AC3/AC4 per their notes). 13 raw findings → 2 decision-needed (both resolved: 1 → patch, 1 → defer), 4 patch, 1 defer, 6 dismissed. No high/medium correctness defects; all patches are low (durability/comment/efficiency).

- [x] [Review][Patch] Flush dirty settings at App exit — `PlaybackView.stepWpm()` mirrors the stepped speed into `_settings.wpm` memory-only + `_settingsDirty`, and ONLY the view's `onHide()` flushes it (PlaybackView.mc:240-243). Position has three backstops (per-transition force-save, ~15 s tick debounce, `App.onStop → commitOnStop`), but `commitOnStop()` saves position ONLY (PlaybackView.mc:272-274, PaceTurnerApp.mc:89-91), so a kill that reaches `onStop` but skips `onHide` reverts the stepped WPM. Fix: flush the view's dirty settings from `App.onStop` (cold path, once per session — no flash-wear concern, symmetric with position). [watch/source/PaceTurnerApp.mc:89] — resolved from Decision 1 (Nerya, add-flush). Sources: blind+edge.
- [x] [Review][Patch] Stale header in WpmStepperView — comment says "candidate is uncommitted until START (BACK cancels — nothing touched)", contradicting the commit-on-exit amendment (both exits save). [watch/source/views/WpmStepperView.mc:16]
- [x] [Review][Patch] Misleading onBack comment — claims "the revealed PlaybackView's onShow STATE_IDLE guard keeps it Paused", but the `onShow` STATE_IDLE branch auto-plays (PlaybackView.mc:215-223). Behavior is benign (IDLE only on a fresh-install first-launch whose auto-play was deferred by an unreadable screen — closing the menu resumes that intended demo; restored positions are PAUSED, not IDLE), but the comment asserts the opposite. Fix the comment (Task 4 line 59 repeats the same wrong claim). [watch/source/input/SettingsMenuDelegate.mc:84]
- [x] [Review][Patch] `_settingsDirty` left stale after a non-WPM menu edit — `SettingsMenuDelegate.onSelect` calls `_settings.save()` (which serializes `wpm` too), so an outstanding in-flow step is now persisted, but the flag stays true (only `applyWpm`/`onHide` clear it) → `onHide` does a second, redundant flash write. Clear the flag on the menu-save path. [watch/source/input/SettingsMenuDelegate.mc:77]
- [x] [Review][Defer] WPM stepper commit-on-exit guaranteed only on the button path [watch/source/input/WpmStepperDelegate.mc:55] — deferred (Decision 2, on-device probe): button commit path confirmed on-device (Task 9); touch-back-swipe delivery on the raw-InputDelegate stepper needs a Fenix-8 probe before deciding on a guard. A stray `KEY_MENU` inside the editor (onKey returns false → firmware nav) rides the same probe.

Dismissed (6): MENU→onKey delivery device-dependence (on-device confirmed both states, Task 9); `applyPauseMode` "immediate effect" on the current pause (pauseMode governs the *next* pause by definition; `setPauseMode` is live — correct); `cycleAnchorPct` off-grid → 35 and `cycleFontSize(-1)` skip-largest (both documented bounds-check-and-degrade, latent — the model emits no such values — and pinned as intended); `labelForFontSize` hardcoded to 5 vs `rampLength` (semantic labels; RAMP_LENGTH is fixed until the Atkinson BMFont swap story, which re-centers the whole ramp); font-size "±2 steps" surfaced as 5 named steps (the resolved Dev-Notes reading, compliant).

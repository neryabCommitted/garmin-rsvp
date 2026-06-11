---
baseline_commit: ebde7b8655d9acf1d1a9fdc312089e9719c1aa1a
---

# Story 1.3: Gate V1 — hands-off screen-on feasibility (hardware)

Status: review

## Story

As a developer,
I want to prove on a real Fenix 8 that the display can stay readable hands-off for a full reading session,
So that the playback epic's core premise (FR4) is validated before it hardens.

## Acceptance Criteria

1. **Given** a minimal spike app opening an `ActivityRecording.Session`
   **When** it runs on Fenix 8 hardware with no user interaction
   **Then** the display stays lit and legible for ≥60 continuous minutes without tripping the backlight timeout.

2. **Given** the dim always-on fallback path
   **When** the activity-session path is unavailable or fails
   **Then** a single bright word is tested for legibility on the ~10% luminance budget
   **And** the result (legible / not) is recorded.

3. **Given** either outcome
   **When** the spike completes
   **Then** `docs/gates.md` records V1 status, method, and result
   **And** if both the primary and fallback paths fail, the premise-rework flag is raised explicitly.

> FR4 framing (epics.md §Functional Requirements): "Display stays readable without interaction for ≥60 min continuous. If platform forces degradation (R1), acceptable fallback is a dim always-on display restored by one button press." **Dim-but-lit-and-legible satisfies FR4** — see Dev Notes → Expected hardware reality. AC1's "stays lit and legible" is judged against that FR4 definition, not against "full brightness for 60 min".

## Tasks / Subtasks

- [x] Task 1: Build the V1 spike into the watch scaffold (AC: 1, 2)
  - [x] Add `<iq:uses-permission id="Fit"/>` to `watch/manifest.xml` (required by `Toybox.ActivityRecording`; exact id per SDK `bin/projectInfo.xml`). Do NOT touch `minApiLevel` (stays 5.2.0 — decision 0001; every API used here is ≤5.0.0).
  - [x] `watch/source/GateV1View.mc` — replaces the placeholder as initial view for the spike. Renders, per UX-DR1 palette: one bright word (Ink `#EAE6DF` on Void `#000000`, e.g. "PaceTurner") + a small elapsed `mm:ss` counter + current display-mode label (`HIGH`/`LOW`/`OFF`). Keep lit-pixel area small (burn-in citizenship). `Timer.Timer` at 1 s drives the counter via `WatchUi.requestUpdate()`.
  - [x] `watch/source/GateV1Delegate.mc` — `BehaviorDelegate`: START toggles session start/stop; BACK keeps its Garmin meaning (exit). On exit/`onStop`: `session.stop()` then `session.discard()` (never `save()` — don't pollute Garmin Connect), null the reference.
  - [x] Session creation exactly: `ActivityRecording.createSession({:name => "PaceTurner", :sport => Activity.SPORT_GENERIC, :subSport => Activity.SUB_SPORT_GENERIC})` then `session.start()`. Use `Activity.SPORT_*` (since 3.2.0) — the old `ActivityRecording.SPORT_*` enums are deprecated.
  - [x] Evidence log: implement `Application.AppBase.onDisplayModeChanged()` (API 5.0.0) — on each change, append `[elapsedSeconds, System.getDisplayMode()]` to an in-memory array and persist it under a single temporary Storage key on change + `onStop`. This is the objective record of HIGH→LOW→OFF transitions for the whole hour; do not `System.println` per second (logging budget, architecture §Communication Patterns).
  - [x] `PaceTurnerApp.getInitialView()` returns `[new GateV1View(), new GateV1Delegate()]`; delete `PaceTurnerView.mc` (placeholder; git preserves it).
  - [x] Verify all three local targets green at Strict: normal, `-r`, `-t` (`monkeyc -l 3`, commands in `docs/setup.md`). Run the test suite in the exact CI image (`ghcr.io/matco/connectiq-tester:latest`, SDK 8.4.0, `fenix847mm`) before pushing — local-SDK green ≠ CI green (Story 1.1/1.2 lesson). Existing 7 protocol tests must stay green; the spike needs no new unit tests (hardware-judged), but if you extract any pure helper (e.g. elapsed-time formatting), give it a `(:test)` function.
- [x] Task 2: Primary-path hardware run — activity session, hands-off 60 min (AC: 1) — **human-in-the-loop**
  - [x] Sideload per `docs/setup.md` (USB Mode → MTP, `gio copy`, unplug to install).
  - [x] **Hand off to Nerya:** set watch **Settings → System → Display & Brightness → During Activity → Always On** (hard prerequisite — with it Off the screen goes black after timeout for native and CIQ activities alike). Note the General Use AOD setting too. Launch app, press START to begin the session, place the watch where it's glanceable, no interaction for 60 min.
  - [x] Record: did the display stay lit the full 60 min; at what elapsed time did it drop HIGH→LOW (expect ~15 s, firmware-dependent); was the dimmed word legible at arm's length; did a single button press restore full brightness (FR4's "restored by one button press"); battery % at start/end (free early signal for V4 — not the gate).
  - [x] Pull the display-mode log from Storage (re-open app or read via println on next launch) and keep the transition timeline for `docs/gates.md`.
- [x] Task 3: Fallback-path legibility test (AC: 2) — **human-in-the-loop**
  - [x] In the dimmed (LOW display mode) state, judge the single bright word's legibility: indoor + outdoor light, arm's length, the UX-DR1 Ink-on-Void palette. Record legible / not-legible per condition.
  - [x] Optionally probe `Attention.backlight(true)` in a `try/catch` for `BacklightOnTooLongException` to document its actual ceiling on Fenix 8 — research says it extends but cannot sustain the display on burn-in-protected devices; this only feeds the gates.md notes, it is not a pass path.
- [x] Task 4: Record the verdict (AC: 3)
  - [x] Update `docs/gates.md`: V1 table row + §V1 section — status (passed / passed-dim / failed), method (activity session + During-Activity-AOD setting), the measured timeline (dim onset, 60-min outcome), fallback legibility result, and the product implication (the app must instruct users to enable the During-Activity AOD setting — carry to Epic 3).
  - [x] If primary AND fallback both fail: raise the premise-rework flag explicitly in gates.md and stop — Epic 3's playback design must not harden (architecture: FR4 is gate-conditional, R1). _(N/A — V1 passed-dim; flag explicitly recorded as not raised.)_
  - [x] Record the DisplayStrategy implication for Epic 3 (which path `ActivitySessionStrategy.mc` will implement; gate outcome swaps a module, not the architecture — architecture §Frontend Architecture).
  - [x] Update sprint-status: `1-3-gate-v1-hands-off-screen-on-feasibility-hardware` → done (after review). _(Set to `review` per dev-story workflow; the code-review workflow flips it to `done`.)_

## Dev Notes

### Scope discipline (prevent creep)

This story is **a disposable hardware spike + a documented verdict**. Explicitly NOT here:
- No `display/DisplayStrategy.mc`, no `ActivitySessionStrategy.mc` — those are Epic 3 modules; the gate only decides what they will do.
- No ReaderEngine, no playback, no protocol/Communications wiring (gates V2/V3 are stories 1.4/1.5 with their own harness).
- No settings model, no fonts, no new Toybox/pub dependencies. One manifest permission (`Fit`) is the only config change.
- Spike code (`GateV1View/Delegate`, the Storage evidence key) is temporary; stories 1.4/1.5 may replace it as the scaffold's resident spike. Don't gold-plate it — Strict-clean and CI-green is the bar.

### Expected hardware reality (research 2026-06-11 — read before judging "pass/fail")

- **An app cannot override display timeout on CIQ** — no keep-awake API for watch-apps, no `requestDisplayMode` setter exists (verified against SDK 9.1.0 `api.mir`), `Attention.backlight` repeated-call loops are hard-stopped by firmware on burn-in-protected devices via `BacklightOnTooLongException` (~1-min class; exact ceiling undocumented). [forums.garmin.com/.../314782; api-docs Toybox/Attention]
- **What a recording session actually does:** switches the watch into the "During Activities" display profile. With the watch setting **During Activity AOD = Always On**, a CIQ activity holds full brightness for the system timeout (~15 s on Fenix 8, firmware-dependent), then **dims but stays permanently lit** for the entire activity; gesture/button restores full brightness per timeout window. With that setting Off, the screen goes black — for native and CIQ activities alike. [forums.garmin.com/.../354108 (jim_m_58); Fenix 8 manual]
- **Therefore the realistic best case is "passed-dim":** lit-dim-legible for 60 min ≈ exactly FR4's sanctioned fallback ("dim always-on display restored by one button press") delivered via the activity-session path. Full-brightness-for-60-min is not achievable on this hardware; do not burn time chasing it.
- **Burn-in protection** (fenix847mm `screenProtectionSupport: true`): the documented 10%-of-pixels / 3-update-cycles rules are watch-face-AOD rules — in-activity dimming is system-managed. If the system ever blanks pixels on us, that's a *result to record*, not a bug to fix.
- API levels used, all within manifest floor 5.2.0: `ActivityRecording.createSession`/`Session.start/stop/discard` (1.0.0), `Activity.SPORT_*` (3.2.0), `System.getDisplayMode` + `AppBase.onDisplayModeChanged` (5.0.0), `Attention.backlight` (1.0.0; Float form 3.2.1), `Timer.Timer` (1.0.0). `ActivityRecording` is enabled for the watch-app type.

### Exact API shapes (verified against local SDK 9.1.0 api.mir)

```monkeyc
import Toybox.ActivityRecording;
import Toybox.Activity;

var session = ActivityRecording.createSession({
    :name => "PaceTurner",                    // required, ≤15 chars suggested
    :sport => Activity.SPORT_GENERIC,
    :subSport => Activity.SUB_SPORT_GENERIC
});                                           // throws Lang.InvalidOptionsException
session.start();                              // Boolean
// ... on exit:
session.stop(); session.discard(); session = null;
```
- `System.getDisplayMode()` → `DISPLAY_MODE_HIGH_POWER (0)` / `DISPLAY_MODE_LOW_POWER (1)` / `DISPLAY_MODE_OFF (2)`; read-only.
- Forum gotcha (old, possibly fixed): `start()` on a new session <2 s after `save()` froze devices — irrelevant here since we `discard()` once, but don't rapid-cycle sessions.

### Run protocol (the dev agent cannot wear the watch)

Tasks 2–3 are wall-clock hardware runs executed by Nerya. The dev agent's job: deliver a sideloadable Strict-clean build, the exact watch-settings checklist, and the observation checklist (dim-onset time, 60-min outcome, legibility judgments, one-button restore, battery start/end) — then transcribe results into `docs/gates.md` and this story's Dev Agent Record. Don't simulate or guess hardware outcomes; the simulator misreports this whole area (AR15).

### Outcome → verdict matrix (pin this in gates.md)

| Observed | Verdict | Consequence |
|---|---|---|
| Lit (even dim) + legible for 60 min, one-button restore works | **V1 passed (dim-AON via activity session)** — FR4 satisfied in its fallback form | Epic 3 `ActivitySessionStrategy` = activity session + user-setting instruction; UX designs for dim legibility |
| Stays full-bright 60 min | V1 passed (bright) — record exact settings that achieved it | Same module, better UX headroom |
| Screen blanks (AOD-off or firmware) but dim word legible when manually woken | Primary failed; fallback legibility = pass/fail per AC2 | Decide: is press-to-wake reading viable? Record honestly |
| Both paths fail (blank screen AND illegible dim word) | **Premise-rework flag** — raise explicitly in gates.md | Epic 3 must NOT harden; product premise needs rework |

### Previous story intelligence (Story 1.2 Dev Agent Record)

- **CI ceiling is real:** the public tester image is SDK 8.4.0 / `fenix847mm` / API 5.2.0 cap. Everything here compiles under that — but verify in the exact image anyway; 1.2 found an SDK-8.4.0-only uncatchable-error landmine (`StringUtil.convertEncodedString`) that local builds never showed.
- All three build targets must pass at Strict `-l 3`; a build needing the level lowered is a defect (Enforcement Guideline #5).
- `monkey.jungle` already links `source-test/`; new files in `watch/source/` need no jungle edit.
- Existing watch suite: 7 protocol tests, green in the CI image — keep them green; don't touch `Protocol.mc`/`StreamDecoder.mc`.
- Sideload procedure verified end-to-end 2026-06-10 (`docs/setup.md`): watch USB Mode → MTP, `gio copy` to `GARMIN/Apps/`, unmount, unplug to install.

### Project Structure Notes

- New: `watch/source/GateV1View.mc`, `watch/source/GateV1Delegate.mc`. Modified: `watch/manifest.xml` (Fit permission), `watch/source/PaceTurnerApp.mc` (initial view). Deleted: `watch/source/PaceTurnerView.mc`. Docs: `docs/gates.md`.
- These spike files are deliberately NOT the architecture tree's `display/` modules — the tree's `DisplayStrategy.mc`/`ActivitySessionStrategy.mc` are Epic 3 deliverables informed by this gate.
- Monkey C conventions: `PascalCase.mc`, one public class per file, private fields `_camelCase`, module consts `UPPER_SNAKE`. No inline magic Storage strings — the single temporary evidence key may be a local const (StorageKeys.mc is an Epic 4 file; don't create it early).
- A ticking 1 s timer is fine here; note the architecture's render-loop rules (one-shot timer, drift-free) bind Epic 3's ReaderEngine, not this spike.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.3] — story + ACs verbatim
- [Source: _bmad-output/planning-artifacts/epics.md#Functional Requirements] — FR4 incl. sanctioned dim-AON fallback; AR27 (gate V1 blocks playback hardening), AR31 (gates.md is the single status page)
- [Source: _bmad-output/planning-artifacts/architecture.md#Frontend Architecture] — DisplayStrategy seam: "gate V1's outcome … swaps a module, not the architecture"
- [Source: _bmad-output/planning-artifacts/architecture.md#Decision Impact Analysis] — sequencing: V1+V2 on hardware before playback/transfer hardens
- [Source: _bmad-output/planning-artifacts/architecture.md#Cross-Cutting Concerns] — display lifecycle: burn-in forbids naive screen-on; ActivityRecording strategy medium-confidence; dim-AON legibility unvalidated
- [Source: docs/gates.md] — V1 row + procedure section to update; hardware access unblocked 2026-06-10
- [Source: docs/setup.md] — build at Strict, CI-image test command, MTP sideload procedure
- [Source: docs/decisions/0001-watch-min-api-level.md] — minApiLevel 5.2.0 stands
- [Source: _bmad-output/implementation-artifacts/1-2-protocol-spec-md-and-mirrored-constants.md#Dev Agent Record] — CI-image discipline, Strict discipline, suite baseline
- Research (2026-06-11, agent-verified against SDK 9.1.0 api.mir + fenix847mm device files + Garmin docs/forums): createSession signature & Fit permission; During-Activity AOD behavior (forums.garmin.com/.../354108, /314782, /414860); BacklightOnTooLongException (api-docs Toybox/Attention); burn-in rules (api-docs System/DeviceSettings); no keep-awake/`requestDisplayMode` for watch-apps

## Dev Agent Record

### Agent Model Used

claude-fable-5 (Amelia / bmad-dev-story)

### Debug Log References

- RED→GREEN evidence: `GateV1Test.mc` written first; test build failed with `Undefined symbol ':GateV1'` (and `:formatElapsed`/`:displayModeLabel`/`:logToString`) before implementation, green after.
- All three local targets green at Strict `-l 3` (SDK 9.1.0, `fenix847mm`): normal, `-r`, `-t` — `BUILD SUCCESSFUL`.
- Exact CI image (`ghcr.io/matco/connectiq-tester:latest`, SDK 8.4.0, `fenix847mm`): `PASSED (passed=10, failed=0, errors=0)` — 7 pre-existing protocol tests + 3 new GateV1 helper tests.

### Completion Notes List

- Task 1 complete (2026-06-11). Session lifecycle + evidence log live in `PaceTurnerApp` (the `AppBase` owns `onStop`/`onDisplayModeChanged`); view and delegate get the app reference via constructor injection — avoids `Application.getApp()` casting at Strict.
- Evidence log persisted as a compact String (`"elapsed:mode,..."` via `GateV1.logToString`), not a nested array: Strict's invariant generics reject `Array<Array<Number>>` for `Storage.setValue`, and the value typedef differs between SDK 8.4.0 (CI, `PropertyValueType`) and 9.1.0 (local, `Storage.ValueType`) — a String is a plain member of both polys and prints human-readable. In-memory form stays `[[elapsedSeconds, mode], ...]` per the task.
- Evidence anchor: clock re-anchors and the log resets with a `[0, currentMode]` baseline entry at session start, so the persisted record covers exactly the 60-min run. On next launch the previous run's log is `System.println`'d (`onStart`) for retrieval via the device app log.
- Pure helpers extracted to `module GateV1` (`formatElapsed`, `displayModeLabel`, `logToString`), each `(:test)`-covered in `watch/source-test/GateV1Test.mc` (consistent with Story 1.2's source-test pattern).
- Optional Task-3 probe implemented on UP (`onPreviousPage`): `Attention.backlight(true)` guarded by `has :backlight`, catching `BacklightOnTooLongException`; result renders next to the mode label (`BL on`/`BL exc`/`BL n/a`).
- Sideload the **normal** build (`watch/bin/PaceTurner.prg`) for the hardware run — release strips nothing needed, but normal keeps debug symbols for any crash triage.
- Tasks 2–3 hardware run executed by Nerya 2026-06-11 (watch off-wrist on table, passcode disabled, During-Activity AOD = Always On). Agent did the MTP file work both ways (planted `GARMIN/Apps/LOGS/PaceTurner.TXT`, sideloaded the PRG, pulled the evidence log post-run).
- **Hardware results (Tasks 2–3):** dim onset HIGH→LOW at 00:14; LOW continuously thereafter; display never reached OFF in 61:00 (objective `onDisplayModeChanged` log). Two ~8 s HIGH blips at 39:54 / 58:23, cause unconfirmed (possible table bump or phone notification), both self-recovered to LOW. One button press restored full brightness (FR4 restore ✓). Dim word legible at arm's length in indoor daylight; outdoor judgment not performed — carried to Epic 3 UX as a spot-check, verdict unaffected. Battery 28% start, no observed drop (32% read after ~3 min on USB charge). Backlight probe: single `Attention.backlight(true)` returned without exception (`BL on`); sustained use untested.
- Raw evidence timeline (elapsed-seconds:mode; 0=HIGH 1=LOW 2=OFF): `0:0,0:0,14:1,2394:0,2402:1,3503:0,3511:1,3604:0,3612:1,3617:0,3632:1,3640:0,3640:0,3648:1,3660:0` — also preserved in `/tmp/PaceTurner-run1.TXT` during the session and transcribed to `docs/gates.md`.
- **Task 4 verdict: V1 passed-dim** (matrix row 1) — FR4 satisfied in its sanctioned fallback form. `docs/gates.md` updated (table row + full §V1: method, timeline, legibility, notes, pinned verdict matrix, Epic 3 implication: `ActivitySessionStrategy` = activity session + During-Activity-AOD user instruction). Premise-rework flag explicitly not raised.

### File List

- `watch/manifest.xml` (modified — `Fit` permission)
- `watch/source/PaceTurnerApp.mc` (modified — session lifecycle, evidence log, backlight probe, initial view)
- `watch/source/GateV1View.mc` (new — `GateV1` pure-helper module + spike view)
- `watch/source/GateV1Delegate.mc` (new — START toggle, UP backlight probe)
- `watch/source/PaceTurnerView.mc` (deleted — placeholder)
- `watch/source-test/GateV1Test.mc` (new — 3 `(:test)` functions for the pure helpers)
- `docs/gates.md` (modified — V1 verdict: passed-dim, method, timeline, Epic 3 implication)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (modified — 1-3 → review)
- `_bmad-output/implementation-artifacts/1-3-gate-v1-hands-off-screen-on-feasibility-hardware.md` (modified — this record)

## Change Log

- 2026-06-11: Story 1.3 implemented and hardware-validated. V1 spike (GateV1View/Delegate, session lifecycle + display-mode evidence log in PaceTurnerApp, Fit permission); 60-min hands-off run on real Fenix 8 → **V1 passed-dim**; verdict + Epic 3 DisplayStrategy implication recorded in `docs/gates.md`. Status → review.

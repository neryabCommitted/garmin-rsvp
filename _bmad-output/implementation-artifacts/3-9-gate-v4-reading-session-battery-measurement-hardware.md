---
baseline_commit: 09f90e1cb234e755500292b84c5172c2f7764b7b
---

# Story 3.9: Gate V4 — reading-session battery measurement (hardware)

Status: in-progress

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer,
I want the battery cost of a real 60-minute reading session measured on the Fenix 8,
so that "guilt-free daily use" is validated against the ≤10%/hour target (PRD §3 counter-metric, R4, AR30).

## Acceptance Criteria

**AC1 — Session measured & recorded.**
**Given** the full reader with the screen-on path active (app-mode, ADR 0003)
**When** a 60-minute continuous reading session runs on real Fenix 8 hardware (screen on, sync connected, on-wrist, off charger)
**Then** battery drain over the session is measured and recorded in `docs/gates.md` §V4 (table row + section: Method / Measured / Verdict).

**AC2 — Threshold / low-battery flag.**
**Given** the measurement
**When** the drain exceeds the ≤10%/hour target **or** the session silently trips the watch into low-battery behavior (power-save / low-battery warning / forced dim or shutdown)
**Then** the result is flagged in `docs/gates.md` for revisiting the threshold or the screen-on strategy (per the PRD `[ASSUMPTION]`, R4), rather than silently passed.

> This is a **hardware measurement gate**, not a feature story. The code deliverable is thin, honest instrumentation + a way to sustain a 60-min continuous session over Epic-3's canned content; the primary deliverable is the **measured result recorded in `docs/gates.md`**. Follow the house style of V1–V3 (Method / Measured / Verdict matrix / Product implication). [Source: docs/gates.md §V1–V3]

## Tasks / Subtasks

- [x] **Task 1 — Battery-sampling instrumentation** (AC: 1, 2)
  - [x] Add a coarse battery sampler that reads `System.getSystemStats()` → `.battery` (Float %) and `.charging` (Boolean). **NOT on the hot render tick** — use its own low-frequency `Timer.Timer` (e.g. one sample / 60 s) or sample inside a guarded, rate-limited branch. The per-word `onTimerTick` render loop and its logging budget stay untouched (deferred-work #129: no new synchronous work on the hot path). [Source: watch/source/views/PlaybackView.mc:582 `onTimerTick`; deferred-work.md#L129] → `BatteryGate.Sampler` owns its **own** `Timer.Timer` on a 60 s repeating cadence; the per-word loop is not touched.
  - [x] Record per session: `startBattery`, `startCharging`, a series of `(elapsedMs, battery, charging)` samples, `endBattery`, `endCharging`, `sampleCount`. Keep it compact — Storage is 32 KB/value (NFR3); a ring or coarse cadence keeps the string small. → Sampler keeps a rolling summary (start/last/min pct, charging-seen, sampleCount, startMs) rather than a per-sample array — same evidence, O(1) memory, tiny string.
  - [x] Reuse the established **persist-then-println evidence pattern**: write a compact machine-readable evidence string to a single Storage key on exit; print it via `System.println` on the *next* launch (`onStart`). Do NOT invent a richer logger. [Source: watch/source/PaceTurnerApp.mc:17 `EVIDENCE_KEY`, :64 (onStart println), :79 (onStop persist)] → new temporary `BATTERY_KEY = "gateV4Battery"` alongside the GateV2 key; persisted in `onStop`, printed in `onStart`.
  - [x] Emit a machine-readable one-line summary to stdout/logs — start%, end%, elapsed, absolute drain, **extrapolated %/hour**, `charging`-seen flag, min-battery-seen. Nerya must not transcribe watch screens. [Source: memory hardware-run-results-machine-readable] → `BatteryGate.evidenceString` — one comma-separated line with every field.

- [x] **Task 2 — Sustain a 60-min continuous session over the canned source** (AC: 1)
  - [x] The Epic-3 reader plays a **228-word** canned stream (`CannedWordSource`, WORD_COUNT=228 ≈ 46 s at 300 WPM) — far short of 60 min, and it auto-stops at FINISHED. Provide a **gate-scoped auto-replay**: on `TRANSITION_FINISHED`, `seekTo(0)` + `play()` to start a fresh lap, so the render loop + display + BLE-connected radio run continuously for the full hour. [Source: watch/source/source_data/CannedWordSource.mc:23 WORD_COUNT; watch/source/views/PlaybackView.mc:596 finished branch] → auto-replay in `onTimerTick` after `maybeEnterChapterCard`, on `_engine.isFinished()`.
  - [x] **Memory-safe by construction:** loop the small 228-word source — do NOT embed an ~18k-word fixture (NFR2 600 KB heap; `CannedWordSource` fully buffers the stream). Looping keeps heap flat and each lap re-exercises ramp + chapter cards + Finished honestly. → loops the existing buffered source; no new fixture; `_cardedIndex` naturally re-fires cards each lap.
  - [x] Gate the auto-replay behind a **single compile-time flag** (e.g. a `const GATE_V4 = false` in one place, flipped to `true` only for the sideloaded gate build) so the shipped release build is untouched. Document the flag location in Completion Notes. → **`BatteryGate.ENABLED` (`watch/source/gate/BatteryGate.mc:24`)** — the single flip.
  - [x] The battery sampler (Task 1) may ride the same flag, or ship as harmless always-on instrumentation at the dev's discretion — but the **release build must not regress** (warning-free, no new hot-path work). → sampler rides the SAME flag (`_batterySampler` is null in release; its timer never arms). Release build warning-free at Strict L3.

- [x] **Task 3 — Low-battery / charging integrity guards** (AC: 2)
  - [x] A run with `charging == true` at any sample is **INVALID** (a USB/charger reading pollutes the measurement — this is exactly why V1's post-run 32% reading was unusable). Surface the charging flag prominently in the evidence string and flag the run invalid if seen. [Source: docs/gates.md §V1 Notes] → any charging sample sets `_chargingSeen`; `evidenceString` prefixes the whole line with `INVALID-CHARGING`.
  - [x] Track and report **minimum battery observed**; note if the device is near the low-battery region so AC2's "silently trips low-battery behavior" can be judged against the recorded timeline. → `min:` field in the evidence string (running minimum across all samples).

- [ ] **Task 4 — On-device measurement run (HUMAN, Nerya)** (AC: 1, 2)
  - [ ] Follow the **On-Device Procedure** below on the real Fenix 8. Capture the printed evidence string (next-launch println) verbatim. **[BLOCKED ON HUMAN — dev cannot run hardware. Gate build (`BatteryGate.ENABLED = true`) is built and signed at `watch/bin/PaceTurner.prg`, ready to sideload; committed source keeps the flag false.]**

- [ ] **Task 5 — Record the result & verdict in `docs/gates.md` §V4** (AC: 1, 2) **[BLOCKED — needs the Task 4 measured result]**
  - [ ] Fill the V4 table row (`Status`, `Result`) and the §V4 section (Method / Measured / Verdict matrix / Product implication), matching the V1–V3 format. [Source: docs/gates.md §V4 (currently "not started")]
  - [ ] Apply the **Verdict matrix** below; if AC2 trips, record the flag and the recommended next step (revisit threshold or strategy) — do not launder a fail into a pass.
  - [ ] Close/annotate the carry-in deferred items evaluated during the run (Task 6).

- [ ] **Task 6 — Opportunistic carry-in observations during the same run** (AC: 1) **[BLOCKED — observed during the Task 4 run]**
  - [ ] **deferred-work #139** — FR4 app-mode endurance duration is unmeasured. This 60-min on-wrist run **is** the app-mode endurance proof; record the observed hands-off duration and whether the display stayed dim-lit (never OFF) throughout. [Source: deferred-work.md#L139]
  - [ ] **deferred-work #137** — `_sawDisplayOff` false-arms off-wrist and never disarms. Observe on-wrist whether the "Display > Always On" hint appears spuriously during a legitimate dim reading session. [Source: deferred-work.md#L137]
  - [ ] **deferred-work #129** — synchronous flash-write stutter on the hot tick path (~15 s cadence). Watch for a periodic visible catch-up burst / stutter during the hour; note if observed (sim cannot reproduce it). [Source: deferred-work.md#L129]

## Dev Notes

### What this story is (and is not)

A **battery-measurement gate** (AR30 / R4 / PRD §3). The value is the *measured number* and the *verdict recorded in `docs/gates.md`* — not a shipped feature. Keep the code minimal and honest. The prior gate stories (1.3 V1, 1.4 V2, 1.5 V3) are the structural precedent: a thin harness + a real hardware run + a Method/Measured/Verdict record in `docs/gates.md`. [Source: docs/gates.md; _bmad-output/implementation-artifacts/1-5-gate-v3-*.md]

### The measured path is APP-MODE (ADR 0003)

The shipped screen-on strategy is **app-mode** — no `ActivityRecording` session, no Fit permission; the watch's own display settings govern the screen and words keep flowing through dim (hardware-validated 2026-07-16/17). V4 measures **this** path. The Fit/session "PaceTurner Active" variant is git-preserved (`81978d6`) and out of scope here. [Source: docs/gates.md §V1 Amendment 2026-07-17; watch/source/views/PlaybackView.mc:33–45; ADR 0003 docs/decisions/0003-screen-strategy-app-mode-and-active-variant.md]

**Battery-cost contributors this run measures (app-mode):**
- **Display** — AMOLED dim-AON (general-use Always-On), the dominant draw. Requires the watch setting **System → Display & Brightness → Always On** enabled, or the display goes OFF and the app auto-pauses (3.7 policy) — which would invalidate a continuous-session measurement. Same hard prerequisite as V1. [Source: docs/gates.md §V1 Method]
- **Render-loop CPU** — the per-word timer loop redrawing the ORP word continuously (this is why Task 2 must keep the loop *running*, not sitting on a Finished still-frame).
- **BLE radio connected** — phone paired via Garmin Connect Mobile, idle-connected (no active transfer). Epic-4 transfer draw is heavier and **out of scope** for V4; note this explicitly so the number isn't over-claimed. [Source: docs/gates.md §V2/V3]

### Instrumentation seam (reuse, don't reinvent)

`PaceTurnerApp` already owns the exact pattern to reuse: one temporary Storage key, persisted in `onStop`, printed on the next `onStart`. Add the battery evidence alongside (or replacing, for the gate build) the GateV2 evidence string. `PlaybackView` is held by the app (`_playbackView`) and owns the timer + lifecycle, so the sampler and the auto-replay live naturally there. [Source: watch/source/PaceTurnerApp.mc:17,37,64,79,89–90; watch/source/views/PlaybackView.mc:156 initialize, :199 onShow, :232 onHide, :582 onTimerTick]

- Sample cadence: a **separate coarse `Timer.Timer`** (~60 s) is cleanest — it is decoupled from the drift-sensitive per-word loop and cannot perturb pacing. Do not fold sampling into `onTimerTick` (deferred-work #129: keep the hot path clean).
- `System.getSystemStats()` returns `System.Stats`; read `.battery` (Float, 0.0–100.0) and `.charging` (Boolean). Bounds-check and degrade — never crash the reader for a stats read (NFR8, AR24). [Source: Garmin Connect IQ API — Toybox.System.getSystemStats() / System.Stats; verified 2026-07-23 via developer.garmin.com]
- Compact evidence string, ≤32 KB/value (NFR3). Coarse cadence keeps it tiny (~60 samples/hour).

### CannedWordSource loop seam (Task 2)

`CannedWordSource` decodes 228 records once at startup and serves them; `ReaderEngine.seekTo(0)` (Story 3.6) lands PAUSED at word 0 with no transition, and `play()` re-arms the ramp. Auto-replay = on the FINISHED branch, `seekTo(0)` then `play()` + re-arm the timer. Guard it behind the gate flag so normal FINISHED behaviour (Finished screen, BACK exits, UX-DR14) is unchanged in the release build. [Source: watch/source/source_data/CannedWordSource.mc:49; watch/source/engine/ReaderEngine.mc seekTo; watch/source/views/PlaybackView.mc:596]

### Representative run parameters

- **WPM:** default **300** (mid-range, PRD FR3 default). Record the exact WPM used — battery ∝ redraw rate, so the WPM is part of the result, not a free variable. [Source: PRD §3 / FR3]
- **Duration:** ≥60 min continuous, on-wrist, off charger, screen-on (dim-AON).
- **Sync:** phone paired + Garmin Connect Mobile foreground/connected, BLE idle-connected, no active transfer.

### Verdict matrix (apply in Task 5, house style)

| Observed | Verdict | Consequence |
|---|---|---|
| Drain ≤ 10%/hour, no low-battery trip, charging never seen | **V4 passed** — ≤10%/hour target met on the app-mode path; guilt-free daily use validated | Threshold assumption confirmed; FR4 app-mode endurance (deferred #139) also proven |
| Drain > 10%/hour, no low-battery trip | **V4 measured-over-target** — flag per AC2 | Revisit the ≤10%/hour assumption OR the screen-on strategy (dim vs session vs cadence); record recommendation |
| Session silently trips low-battery behavior (power-save / forced dim / shutdown) | **V4 flagged** — safety-net concern | Investigate low-battery interaction before store listing; record |
| `charging == true` seen mid-run | **V4 invalid** — re-run off charger | Not a result; discard and repeat |

### Non-negotiable constraints (do not regress)

- Release build stays warning-free at Strict L3; both host and image test suites stay green. No new work on the per-word hot path. [Source: sprint-status.yaml 3-8 note — 96/96 @ Strict L3, release 48,028 B]
- Position durability (Story 3.6) untouched — the sampler/loop must not touch `pos_<bookId>` or the commit sites. [Source: watch/source/views/PlaybackView.mc:268 commitPosition]
- No manifest/permission change (app-mode = zero permissions for this path). [Source: ADR 0003]

### On-Device Procedure (Task 4 — Nerya, real Fenix 8)

1. **Prep:** charge to a known high level (e.g. 90–100%), then **unplug**. Enable **System → Display & Brightness → Always On**. Confirm phone paired + Garmin Connect Mobile connected (BLE up). Sideload the **gate build** (GATE_V4 flag on).
2. **Start:** open the active book, let it play at **300 WPM**, note the wall-clock start time. Put the watch on-wrist (or on a table with wrist-gesture off — but on-wrist is the honest posture and also tests deferred #137).
3. **Run:** leave it playing, hands-off, for **≥60 minutes**. The gate build auto-replays the canned book each lap so playback never stops.
4. **Observe during the run** (Task 6): does the display ever go OFF? Any spurious "Display > Always On" hint (#137)? Any periodic stutter / catch-up burst (#129)?
5. **Stop:** at ≥60 min, note wall-clock + on-watch battery %. Exit the app (BACK) so `onStop` persists the evidence.
6. **Export:** relaunch the app — the previous run's evidence string prints to the log (`System.println`). Capture it verbatim. Confirm `charging` was never true.
7. Hand the evidence string + your observations back; results get recorded in `docs/gates.md` §V4 (Task 5).

### Project Structure Notes

- New/modified watch code lives under `watch/source/` (views/PlaybackView.mc, PaceTurnerApp.mc, possibly source_data/CannedWordSource.mc for the loop seam). No new folder. [Source: architecture.md §Frontend Architecture, line 199; watch source tree]
- `docs/gates.md` is the single gate status page — update §V4 there, not elsewhere. [Source: architecture.md line 479; docs/gates.md]
- Host tests (`watch/source-test/`) for any pure logic added (e.g. drain / %-per-hour computation should be a pure, host-testable helper — mirror the SyncManager pure/adapter split). Hardware measurement itself is not unit-testable. [Source: architecture.md line 264; watch/source/sync/SyncManager.mc pure/adapter pattern]

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story-3.9] — AC1/AC2 verbatim, AR30, "Measure gate V4 during a real reading session"
- [Source: _bmad-output/planning-artifacts/prds/prd-garmin_RSVP-2026-06-06/prd.md:35] — §3 counter-metric: 60-min continuous, primary screen-on mode, ≤10%/hour, "never silently trip low-battery," `[ASSUMPTION]` revisit after first hardware measurement
- [Source: _bmad-output/planning-artifacts/prds/prd-garmin_RSVP-2026-06-06/prd.md:115] — R4 (MEDIUM): Gate V4 measures a 1-hour session vs ≤10%/hour
- [Source: docs/gates.md §V1 (passed-dim, battery NOT measured — "the real measurement is gate V4"), §V1 Amendment 2026-07-17 (app-mode; "Gate V4 measures battery on the app-mode path; its ~60-min on-wrist run doubles as the app-mode endurance proof"), §V4 (not started)]
- [Source: docs/decisions/0003-screen-strategy-app-mode-and-active-variant.md] — shipped strategy = app-mode
- [Source: watch/source/PaceTurnerApp.mc] — EVIDENCE_KEY persist-then-println pattern to reuse
- [Source: watch/source/views/PlaybackView.mc] — timer loop (:582), lifecycle (:156/:199/:232), commit sites (:268), FINISHED branch (:596), display-mode routing (:289)
- [Source: watch/source/source_data/CannedWordSource.mc] — 228-word fixture, decode-once, loop seam
- [Source: _bmad-output/implementation-artifacts/deferred-work.md#L129,#L137,#L139] — carry-in observations for this run
- [Source: memory hardware-run-results-machine-readable] — print results to stdout/logs, do not transcribe screens
- Garmin Connect IQ API — `Toybox.System.getSystemStats()` returns `System.Stats` (`.battery` Float, `.charging` Boolean); verified 2026-07-23 via developer.garmin.com

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Amelia / dev-story), 2026-07-23.

### Debug Log References

- Release build (Strict L3, `-w -r`): `BUILD SUCCESSFUL`, warning-free. Size **49,180 B** (was 48,028 B at 3.8) — the inert gate module compiles in but never runs in release (`ENABLED = false`).
- Unit-test build (Strict L3, `-w -t`): `BUILD SUCCESSFUL`, warning-free.
- Host tests, CI image (`ghcr.io/matco/connectiq-tester:latest`, `fenix847mm`, `desktop-linux` context, `app.prg`/`app-test.prg` removed first): `Ran 100 tests … PASSED (passed=100, failed=0, errors=0)`. **96 → 100** (+4 `BatteryGateTest`).
  - First run errored on `errors=1`: the epsilon helper `batteryDrainPerHourClose` was mis-annotated `(:test)`, so the tester invoked it as a zero-context test and errored on arity. Removed the annotation (it is a plain helper) → clean.
- **Mutation red-check (non-vacuous, exact):** seeded two bugs in the pure functions in one build — (A) removed the `elapsedMs <= 0` guard in `drainPerHour`, (B) dropped the `INVALID-CHARGING` prefix in `evidenceString`. Result: `batteryDrainPerHourDegrades` ERROR (div-by-zero, mutation A) + `batteryEvidenceStringChargingIsFlaggedInvalid` FAIL (mutation B); the other two battery tests stayed PASS. Each mutation caught by exactly its intended test. Reverted; restored tree byte-identical to the green tree; re-built signed release clean.
- **Gate build for Task 4:** the sideload binary at `watch/bin/PaceTurner.prg` is built with `BatteryGate.ENABLED = true` (signed, `fenix847mm`). The committed source keeps `ENABLED = false` — the flag is flipped only for the local gate build, never committed true.

### Completion Notes List

Tasks 1–3 (the thin, honest instrumentation) are complete, TDD'd, and validated. Tasks 4–6 are **blocked on the human hardware run** — this is a hardware-measurement gate; the primary deliverable (the measured %/hour in `docs/gates.md` §V4) cannot exist until Nerya runs the 60-min session on the real Fenix 8.

- **The single compile-time flag: `BatteryGate.ENABLED` (`watch/source/gate/BatteryGate.mc:24`).** false in every committed/release build; flip to `true` for the sideloaded gate build, then revert before merge. It gates BOTH the sampler (App never constructs it — `_batterySampler` stays null, its 60 s timer never arms) AND the `PlaybackView.onTimerTick` auto-replay branch. Release behaviour is therefore untouched: Finished screen still holds, BACK still exits, no new hot-path work.
- **Pure/adapter split (mirrors `Sync`).** `BatteryGate` = pure `drainPerHour` (extrapolate absolute drain → %/hour; degrades to 0.0 on a zero/negative window; a battery *gain* reports a negative rate, never clamped — the sign is charger-contamination evidence) + pure `evidenceString` (one machine-readable comma-separated line, `INVALID-CHARGING` prefix when charging seen) + the `Sampler` adapter class (System/Timer, device-only, host-untestable like the SyncManager adapter). The pure half is host-tested (`BatteryGateTest`, 4 tests); the adapter is proven by the Task 4 run.
- **Off the hot path (deferred #129).** The sampler runs on its OWN `Timer.Timer` at 60 s — never folded into the drift-sensitive per-word `onTimerTick`. ~60 samples/hour keeps the persisted string tiny (NFR3).
- **Persist-then-println (reused, not reinvented).** New temporary `BATTERY_KEY = "gateV4Battery"` in `PaceTurnerApp`, alongside the GateV2 key; persisted in `onStop` (WPM read from the live engine there — battery ∝ redraw rate, so WPM is part of the result), printed in `onStart`. All Storage I/O guarded (NFR8); a throwing `getSystemStats()` degrades with one println, never crashes the reader.
- **Charging integrity (Task 3):** any charging sample sets `_chargingSeen` → the run is prefixed `INVALID-CHARGING`. The ≤10%/hour verdict itself stays a human call in `docs/gates.md` §V4 (Task 5) — the evidence string reports facts only; it does not launder a fail into a pass.
- **Position durability (Story 3.6) untouched:** the sampler/auto-replay never call `commitPosition` differently; `seekTo(0)` on replay emits no transition. The debounced ~15 s position write stays live during the run, which is exactly what deferred #129 wants to observe on-device.
- **No manifest/permission change** (app-mode = zero permissions, ADR 0003).

**Next steps (human):** flip nothing — the gate build is already at `watch/bin/PaceTurner.prg`. Sideload it, run the **On-Device Procedure** (Task 4), capture the next-launch `GateV4 battery: …` println verbatim, hand it back with the Task 6 observations. Then dev records §V4 (Task 5).

**Preliminary on-device attempt (2026-07-24, Fenix 8, Nerya) — INCONCLUSIVE, carried forward.** Gate build sideloaded by dev (Amelia) over MTP; Nerya ran a valid off-charger session and reconnected the watch; dev read the evidence from the device log `GARMIN/Apps/LOGS/PaceTurner.TXT`:

```
GateV4 start:99.0%,end:99.0%,drain:0.0%,rate:0.0%/h,min:99.0%,elapsedMs:2194494,samples:37,wpm:300,charging:false
```

- **Valid** (`charging:false`, off charger) and the app sustained a continuous hands-off session for **36.6 min** (37 samples, 60 s cadence) with no crash — instrumentation + auto-replay + persist-then-println all proven end-to-end on real hardware.
- **Inconclusive, NOT a pass:** the run started at the 100% flat-top (99%), so in 36.6 min no 1% battery quantum crossed → 0% drain → `rate:0.0%/h` is a flat-top artifact carrying no signal about the steady-state rate. Recorded as **preliminary — inconclusive** in `docs/gates.md` §V4 (a 5th verdict-matrix row); explicitly not laundered into a pass.
- **Re-run needed** from mid-curve (~90%), on-wrist, 300 WPM, ≥60 min. Tasks 4–6 stay open; per Nerya this is a **carry-forward, not an epic-retro blocker**. Task 6 observations (#139/#137/#129) were not usable on a 0-drain run and roll into the re-run.

### File List

- **NEW** `watch/source/gate/BatteryGate.mc` — the gate flag + pure `drainPerHour`/`evidenceString` + the `Sampler` adapter.
- **NEW** `watch/source-test/BatteryGateTest.mc` — 4 host tests for the pure half (+ one epsilon helper).
- **MOD** `watch/source/PaceTurnerApp.mc` — `BATTERY_KEY`, `_batterySampler` (null in release), sampler start + previous-evidence println in `onStart`, sampler stop + evidence persist in `onStop`.
- **MOD** `watch/source/views/PlaybackView.mc` — gate-scoped auto-replay branch in `onTimerTick`.

## Change Log

- 2026-07-23 (dev-story, Amelia): Story 3.9 Tasks 1–3 — Gate V4 battery instrumentation. New `BatteryGate` module (single compile-time `ENABLED` flag; pure `drainPerHour`/`evidenceString`; device-only `Sampler` on its own 60 s timer), persist-then-println battery evidence wired into `PaceTurnerApp` (new `gateV4Battery` key), gate-scoped auto-replay in `PlaybackView.onTimerTick`. 96 → 100 host tests @ Strict L3 (CI image), both builds warning-free (release 49,180 B), mutation red-check exact. Tasks 4–6 blocked on the human hardware run; signed gate build (`ENABLED = true`) ready at `watch/bin/PaceTurner.prg`.

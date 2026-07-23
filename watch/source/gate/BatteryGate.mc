import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;

// Gate V4 battery-measurement instrumentation (Story 3.9, AR30/R4/PRD §3). A
// battery-measurement GATE, not a shipped feature: the value is the measured
// %/hour recorded in docs/gates.md §V4. Kept thin and honest, mirroring the
// Sync module's pure/adapter split (architecture.md:451):
//
//   1. Pure free functions — drainPerHour / evidenceString — host-testable
//      (BatteryGateTest), Lang-only arithmetic + string, no System/Timer.
//   2. The Sampler class — the thin System.getSystemStats()/Timer adapter that
//      samples battery on its OWN coarse ~60 s timer, decoupled from the
//      drift-sensitive per-word render loop (deferred-work #129: no new work on
//      the hot path). Device-only; proven by the on-device gate run (Task 4).
//
// EVERYTHING here is gated behind the single compile-time flag ENABLED. Shipped
// release builds set it false: the Sampler is never constructed (App gates the
// `new`), its timer never arms, and the PlaybackView auto-replay branch is never
// taken — so the release build's behaviour is untouched (warning-free, no new
// hot-path work). Flip ENABLED to true ONLY for the sideloaded gate build.
module BatteryGate {

    // ── the single compile-time gate flag (Task 2/Task 1) ───────────────────
    // false in every committed/release build. Set true ONLY in the sideloaded
    // gate build, then revert before merge. One place, one flip.
    const ENABLED = false;

    // Coarse battery-sample cadence. Its OWN Timer.Timer (Sampler), NOT the
    // per-word onTimerTick loop — a slow flash/stats read here can never perturb
    // pacing (deferred-work #129). ~60 samples over the 60-min gate run keeps the
    // persisted evidence string tiny (≤32 KB/value, NFR3).
    const SAMPLE_INTERVAL_MS = 60000;

    // Sentinels: below any real battery percentage (0.0–100.0), so the first
    // valid sample always overwrites _startPct/_lastPct, and 101.0 is above any
    // real percentage, so the first sample always becomes the running minimum.
    const PCT_UNSET = -1.0;
    const PCT_MAX_SENTINEL = 101.0;

    // ── pure measurement policy (host-tested, no System/Timer) ───────────────

    // Extrapolate an absolute drain (startPct - endPct) over `elapsedMs` to a
    // %/hour rate — the quantity the ≤10%/hour target (PRD §3) compares on, so a
    // run stopped a little over/under 60 min is still judged on the right axis.
    // A zero/negative window (no basis, or a getTimer() wraparound that reached
    // here) degrades to 0.0 — never a divide-by-zero. A battery GAIN (charger
    // contamination) yields a NEGATIVE rate, reported honestly, not clamped:
    // the sign is itself evidence the run is polluted (Task 3).
    function drainPerHour(startPct as Float, endPct as Float, elapsedMs as Number) as Float {
        if (elapsedMs <= 0) {
            return 0.0;
        }
        var drain = startPct - endPct; // positive = discharge
        return drain * 3600000.0 / elapsedMs;
    }

    // The compact, machine-readable evidence line persisted at exit and printed
    // on the next launch (persist-then-println, PaceTurnerApp). A single String,
    // not nested arrays — Storage value-type polys differ across SDK 8.4.0/9.1.0
    // (the GateV2 evidence lesson). Nerya reads this off the app log verbatim and
    // records it in docs/gates.md §V4 — no watch-screen transcription (memory
    // hardware-run-results-machine-readable). If `chargingSeen`, the whole line
    // is prefixed INVALID-CHARGING so the one hard auto-invalidation (Task 3) is
    // impossible to miss; the ≤10%/hour verdict itself stays a human call in
    // gates.md (Task 5) — this string only reports facts.
    function evidenceString(startPct as Float, endPct as Float, minPct as Float,
            elapsedMs as Number, sampleCount as Number, chargingSeen as Boolean,
            wpm as Number) as String {
        var rate = drainPerHour(startPct, endPct, elapsedMs);
        var prefix = chargingSeen ? "INVALID-CHARGING " : "";
        return "GateV4 " + prefix
            + "start:" + startPct.format("%.1f") + "%"
            + ",end:" + endPct.format("%.1f") + "%"
            + ",drain:" + (startPct - endPct).format("%.1f") + "%"
            + ",rate:" + rate.format("%.1f") + "%/h"
            + ",min:" + minPct.format("%.1f") + "%"
            + ",elapsedMs:" + elapsedMs.toString()
            + ",samples:" + sampleCount.toString()
            + ",wpm:" + wpm.toString()
            + ",charging:" + (chargingSeen ? "true" : "false");
    }

    // ── the System.getSystemStats()/Timer adapter (device-only) ──────────────

    class Sampler {

        private var _timer as Timer.Timer?;
        private var _startPct as Float;   // first valid sample (PCT_UNSET until then)
        private var _lastPct as Float;    // most recent valid sample
        private var _minPct as Float;     // lowest sample observed (PCT_MAX_SENTINEL until then)
        private var _chargingSeen as Boolean;
        private var _sampleCount as Number;
        private var _startMs as Number;   // System.getTimer() at start (ms since boot)

        function initialize() {
            _timer = null;
            _startPct = PCT_UNSET;
            _lastPct = PCT_UNSET;
            _minPct = PCT_MAX_SENTINEL;
            _chargingSeen = false;
            _sampleCount = 0;
            _startMs = 0;
        }

        // Begin sampling: stamp the start clock, take the baseline sample, then
        // arm the coarse REPEATING timer. Idempotent-safe: a second start() just
        // resets the window (the gate app starts once, at App.onStart).
        function start() as Void {
            _startMs = System.getTimer();
            sampleOnce(); // baseline — the first valid reading becomes _startPct
            if (_timer == null) {
                _timer = new Timer.Timer();
            }
            (_timer as Timer.Timer).start(method(:onSample), SAMPLE_INTERVAL_MS, true);
        }

        function stop() as Void {
            if (_timer != null) {
                (_timer as Timer.Timer).stop();
            }
        }

        // Timer callback — one coarse sample. Public so `method(:onSample)` can
        // bind to it (the Timer needs a symbol reference).
        function onSample() as Void {
            sampleOnce();
        }

        // Read battery + charging once, accumulate. Guarded: a device that throws
        // on a stats read must never crash the reader (NFR8/AR24) — one println,
        // no growing log (AR25). Stats.battery/.charging are non-null per the SDK
        // (api.mir), so no null-guard is needed beyond the broad catch.
        private function sampleOnce() as Void {
            try {
                var stats = System.getSystemStats();
                var pct = stats.battery; // Float 0.0–100.0
                _lastPct = pct;
                if (_startPct < 0.0) {
                    _startPct = pct; // first valid sample = baseline
                }
                if (pct < _minPct) {
                    _minPct = pct;
                }
                if (stats.charging) {
                    _chargingSeen = true; // one hard auto-invalidation (Task 3)
                }
                _sampleCount += 1;
            } catch (e) {
                System.println("GateV4: stats read failed");
            }
        }

        // Build the evidence line for persistence (persist-then-println). `wpm`
        // is the run parameter (battery ∝ redraw rate — part of the result, not a
        // free variable), read from the live engine at exit. Guards a getTimer()
        // wraparound over the run window (negative elapsed → 0, degrades cleanly
        // in drainPerHour).
        function evidence(wpm as Number) as String {
            var elapsed = System.getTimer() - _startMs;
            if (elapsed < 0) {
                elapsed = 0;
            }
            return evidenceString(
                _startPct, _lastPct, _minPct, elapsed, _sampleCount, _chargingSeen, wpm);
        }
    }
}

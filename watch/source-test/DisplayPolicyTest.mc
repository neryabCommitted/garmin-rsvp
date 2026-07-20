import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Host tests for the PURE half of the Display module (Story 3.7, AC2/AC3) —
// the unreadable-display pause policy and the wake-tap grace window. Real
// display-mode transitions, AOD behavior, and wake-event delivery are
// hardware-only (AR15) and covered by the on-device checks (Task 8). No
// Test.assert* API — conditionals + logger.error(...) + return false
// (mirrors SyncManagerTest).

// ── AC2: shouldPauseForMode — the app-mode policy matrix (ADR 0003) ─────────
// Mode values mirror System.DISPLAY_MODE_*: HIGH_POWER=0, LOW_POWER=1, OFF=2
// (verified against SDK 9.1.0 api.mir). The policy takes the mode as a plain
// Number so it stays Lang-only. Amended 2026-07-17: the session dimension is
// gone with the activity session — dim (LOW) is a designed-for reading state
// in both display profiles (gate-V1 session-dim + the 2026-07-16 on-wrist
// general-AOD probe), so LOW never pauses.

(:test)
function displayShouldPauseMatrix(logger as Test.Logger) as Boolean {
    // OFF (2) ⇒ pause always — unreadable, full stop.
    if (!Display.shouldPauseForMode(2)) { logger.error("OFF must pause"); return false; }
    // LOW (1) ⇒ words KEEP FLOWING — the validated legible dim reading state
    // (gates.md §V1 + app-mode probe). Flipping this row would pause every
    // reading session seconds after the dim timeout.
    if (Display.shouldPauseForMode(1)) { logger.error("LOW must NOT pause (designed-for dim reading state)"); return false; }
    // HIGH (0) ⇒ words flow.
    if (Display.shouldPauseForMode(0)) { logger.error("HIGH must not pause"); return false; }
    return true;
}

(:test)
function displayShouldPauseUnknownModeDegradesSafe(logger as Test.Logger) as Boolean {
    // Any unrecognized mode value ⇒ pause — an unknown display state is treated
    // as unreadable (bounds-check-and-degrade, NFR8/AR24).
    if (!Display.shouldPauseForMode(99)) { logger.error("unknown mode 99 must pause"); return false; }
    if (!Display.shouldPauseForMode(-1)) { logger.error("unknown mode -1 must pause"); return false; }
    if (!Display.shouldPauseForMode(3)) { logger.error("unknown mode 3 must pause"); return false; }
    return true;
}

// ── isWakeGrace — the wake-tap guard window ─────────────────────────────────

(:test)
function displayWakeGraceWindow(logger as Test.Logger) as Boolean {
    // Inside the window ⇒ true (the waking tap must not toggle playback).
    if (!Display.isWakeGrace(1000, 1001, Display.WAKE_GRACE_MS)) { logger.error("just inside window refused"); return false; }
    if (!Display.isWakeGrace(1000, 1000 + Display.WAKE_GRACE_MS - 1, Display.WAKE_GRACE_MS)) { logger.error("last ms of window refused"); return false; }
    // The instant of the wake itself is inside the window.
    if (!Display.isWakeGrace(1000, 1000, Display.WAKE_GRACE_MS)) { logger.error("now == lastWake refused"); return false; }
    // At/after the window ⇒ false (grace over — strict <, not <=).
    if (Display.isWakeGrace(1000, 1000 + Display.WAKE_GRACE_MS, Display.WAKE_GRACE_MS)) { logger.error("at window edge granted"); return false; }
    if (Display.isWakeGrace(1000, 1000 + Display.WAKE_GRACE_MS + 1, Display.WAKE_GRACE_MS)) { logger.error("past window granted"); return false; }
    return true;
}

(:test)
function displayWakeGraceNullAndWraparound(logger as Test.Logger) as Boolean {
    // Never woken (null) ⇒ false — no phantom grace on a fresh view.
    if (Display.isWakeGrace(null, 5000, Display.WAKE_GRACE_MS)) { logger.error("null lastWake granted"); return false; }
    // getTimer() wraparound (now < lastWake) ⇒ false — grace over, mirror the
    // GateV2.armWindowOpen / Sync.shouldCommit window idiom.
    if (Display.isWakeGrace(1000, 999, Display.WAKE_GRACE_MS)) { logger.error("wraparound granted"); return false; }
    // Subtraction overflow (review 2026-07-20): a ≥2^31 ms gap where now is
    // still numerically ≥ last makes `now - last` wrap negative — that must
    // read grace-over, never phantom grace. (-2e9 stamped post-wrap, now 2e9:
    // true gap 4e9 ms overflows to a negative Number.)
    if (Display.isWakeGrace(-2000000000, 2000000000, Display.WAKE_GRACE_MS)) { logger.error("overflowed elapsed granted phantom grace"); return false; }
    return true;
}

(:test)
function displayWakeTransitionEdgeOnly(logger as Test.Logger) as Boolean {
    // Only the unreadable→readable EDGE opens the grace window (review
    // 2026-07-20): a readable→readable transition (the ~8 s HIGH→LOW dim, or
    // the LOW→HIGH brighten a button press itself causes) must NOT stamp —
    // it would swallow a deliberate pause-while-dim.
    if (!Display.isWakeTransition(true, false)) { logger.error("unreadable->readable must stamp (the wake)"); return false; }
    if (Display.isWakeTransition(false, false)) { logger.error("readable->readable must NOT stamp (dim/brighten)"); return false; }
    if (Display.isWakeTransition(false, true)) { logger.error("readable->unreadable must NOT stamp (going dark)"); return false; }
    if (Display.isWakeTransition(true, true)) { logger.error("unreadable->unreadable must NOT stamp"); return false; }
    return true;
}

// ── the literal↔constant pin (review 2026-07-20) ────────────────────────────
// shouldPauseForMode hardcodes 0/1 to stay Lang-only; the view compares
// System.DISPLAY_MODE_OFF. Two encodings of one table — this sim-run test is
// the single pin that keeps them from drifting apart silently.

(:test)
function displayModeConstantsMatchPolicyTable(logger as Test.Logger) as Boolean {
    if (!Display.shouldPauseForMode(System.DISPLAY_MODE_OFF as Number)) { logger.error("System OFF constant not treated as pause"); return false; }
    if (Display.shouldPauseForMode(System.DISPLAY_MODE_HIGH_POWER as Number)) { logger.error("System HIGH_POWER constant treated as pause"); return false; }
    if (Display.shouldPauseForMode(System.DISPLAY_MODE_LOW_POWER as Number)) { logger.error("System LOW_POWER constant treated as pause"); return false; }
    return true;
}

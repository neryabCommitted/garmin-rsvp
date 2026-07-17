import Toybox.Lang;
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
    return true;
}

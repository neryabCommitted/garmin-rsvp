import Toybox.Lang;
import Toybox.Test;

// Host tests for the PURE half of the Display module (Story 3.7, AC2/AC3) —
// the unreadable-display pause policy and the wake-tap grace window. The
// ActivitySessionStrategy adapter (ActivityRecording lifecycle) needs a device
// context and is covered by the on-device checks (Task 8), exactly as the
// SyncManager Storage adapter is. No Test.assert* API — conditionals +
// logger.error(...) + return false (mirrors SyncManagerTest).

// ── AC2: shouldPauseForMode — the V1→AC2 policy matrix ──────────────────────
// Mode values mirror System.DISPLAY_MODE_*: HIGH_POWER=0, LOW_POWER=1, OFF=2
// (verified against SDK 9.1.0 api.mir). The policy takes the mode as a plain
// Number so it stays Lang-only.

(:test)
function displayShouldPauseMatrix(logger as Test.Logger) as Boolean {
    // OFF (2) ⇒ pause always — unreadable, full stop, session or not.
    if (!Display.shouldPauseForMode(2, true)) { logger.error("OFF+session must pause"); return false; }
    if (!Display.shouldPauseForMode(2, false)) { logger.error("OFF+no-session must pause"); return false; }
    // LOW (1) + session ⇒ words KEEP FLOWING — the V1-validated legible dim
    // reading state (gates.md §V1 passed-dim). This is the row that encodes
    // the V1→AC2 reconciliation; flipping it would pause every session ~15 s in.
    if (Display.shouldPauseForMode(1, true)) { logger.error("LOW+session must NOT pause (V1 dim reading state)"); return false; }
    // LOW (1) + no session ⇒ pause — fallback mode, legibility unvalidated,
    // en route to OFF.
    if (!Display.shouldPauseForMode(1, false)) { logger.error("LOW+no-session must pause (fallback)"); return false; }
    // HIGH (0) ⇒ words flow, session or not.
    if (Display.shouldPauseForMode(0, true)) { logger.error("HIGH+session must not pause"); return false; }
    if (Display.shouldPauseForMode(0, false)) { logger.error("HIGH+no-session must not pause"); return false; }
    return true;
}

(:test)
function displayShouldPauseUnknownModeDegradesSafe(logger as Test.Logger) as Boolean {
    // Any unrecognized mode value ⇒ pause — an unknown display state is treated
    // as unreadable (bounds-check-and-degrade, NFR8/AR24), session or not.
    if (!Display.shouldPauseForMode(99, true)) { logger.error("unknown mode 99+session must pause"); return false; }
    if (!Display.shouldPauseForMode(99, false)) { logger.error("unknown mode 99 must pause"); return false; }
    if (!Display.shouldPauseForMode(-1, true)) { logger.error("unknown mode -1+session must pause"); return false; }
    if (!Display.shouldPauseForMode(3, false)) { logger.error("unknown mode 3 must pause"); return false; }
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

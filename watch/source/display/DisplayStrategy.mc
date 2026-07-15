import Toybox.Lang;

// Display survival — screen-on strategy seam + the pure unreadable-display
// policy (Story 3.7, FR4/gate-V1). Two halves, deliberately separated (the
// Sync/Settings pure-adapter pattern, architecture.md:451):
//
//   1. Pure free functions — shouldPauseForMode / isWakeGrace — the
//      host-testable display POLICY. Lang-only: the display mode arrives as a
//      plain Number (the caller feeds it System.getDisplayMode()) so this
//      half never imports Toybox.System or Toybox.ActivityRecording.
//   2. The DisplayStrategy base class + createStrategy() factory — the AR11
//      seam. Construction goes through the factory, callers hold only the
//      base type, so swapping the screen-on mechanism (a future gate outcome)
//      edits ONE line inside display/ and nothing outside it (AC3: "gate-V1
//      failure swaps a module, not the architecture").
//
// The base class is all no-op/false defaults, so a null-object fallback is
// the base itself — a strategy that keeps no session and never claims one.
module Display {

    // Wake-tap grace window (ms): a touch/button that WAKES the display from
    // the auto-paused dark screen may also be delivered to the input delegate;
    // within this window it must not toggle playback or move position.
    // Starting value approved 2026-07-15; tune on device (Task 8d).
    const WAKE_GRACE_MS = 400;

    // ── pure display policy (host-tested, never touches Toybox.System) ──────

    // The AC2 policy matrix — "words never flow on a screen the user can't
    // read" (UX-DR12), reconciled with the gate-V1 passed-dim verdict:
    //   HIGH (0)          ⇒ flow (readable)
    //   LOW  (1) +session ⇒ flow — the V1-validated legible dim reading state
    //   LOW  (1) no sess. ⇒ pause — fallback mode, legibility unvalidated,
    //                       en route to OFF
    //   OFF  (2)          ⇒ pause always — unreadable, full stop
    //   anything else     ⇒ pause — an unrecognized mode is treated as
    //                       unreadable (bounds-check-and-degrade, NFR8/AR24)
    // Mode values mirror System.DISPLAY_MODE_* (HIGH_POWER=0, LOW_POWER=1,
    // OFF=2 — verified against SDK 9.1.0 api.mir).
    function shouldPauseForMode(mode as Number, sessionActive as Boolean) as Boolean {
        if (mode == 0) {
            return false;
        }
        if (mode == 1) {
            return !sessionActive;
        }
        return true;
    }

    // True iff `now` is inside the wake-tap grace window opened at lastWakeMs.
    // null ⇒ never woken ⇒ false. A getTimer() wraparound (now < lastWakeMs)
    // ⇒ false — grace over (mirrors the GateV2.armWindowOpen window idiom).
    function isWakeGrace(lastWakeMs as Number?, now as Number, graceMs as Number) as Boolean {
        if (lastWakeMs == null) {
            return false;
        }
        var last = lastWakeMs as Number;
        if (now < last) {
            return false;
        }
        return now - last < graceMs;
    }

    // ── the strategy seam (AC3) ──────────────────────────────────────────────

    // Base screen-on strategy: every method a safe no-op/false default. The
    // view drives it purely through this surface and never names a concrete
    // class; the strategy never references the view or the engine (AR15).
    class DisplayStrategy {
        // Playback (re)started — acquire the screen-on mechanism. Idempotent.
        function onPlaybackStart() as Void {
        }

        // App is exiting — release the mechanism. Safe to over-call.
        function shutdown() as Void {
        }

        // Is the screen-on mechanism currently holding the display profile?
        // Feeds the LOW-row of shouldPauseForMode.
        function isSessionActive() as Boolean {
            return false;
        }

        // Did the display reach OFF while the mechanism was active? (The
        // evidence that the user's During-Activity AOD setting is off — arms
        // the Task-6 hint line.)
        function sawOffDuringSession() as Boolean {
            return false;
        }

        // Display-mode transition bookkeeping only — the VIEW owns the engine
        // reaction. Must stay O(1), no Storage, no allocation (system-callback
        // discipline, robustness #3).
        function onDisplayModeChanged(mode as Number) as Void {
        }
    }

    // The ONE construction site (AC3): a strategy swap edits this line only.
    function createStrategy() as DisplayStrategy {
        return new ActivitySessionStrategy();
    }
}

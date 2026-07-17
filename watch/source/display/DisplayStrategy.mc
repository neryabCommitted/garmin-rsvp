import Toybox.Lang;

// Display survival — screen-on strategy seam + the pure unreadable-display
// policy (Story 3.7, FR4/gate-V1; amended 2026-07-17). Two halves, deliberately
// separated (the Sync/Settings pure-adapter pattern, architecture.md:451):
//
//   1. Pure free functions — shouldPauseForMode / isWakeGrace — the
//      host-testable display POLICY. Lang-only: the display mode arrives as a
//      plain Number (the caller feeds it System.getDisplayMode()) so this
//      half never imports Toybox.System.
//   2. The DisplayStrategy base class + createStrategy() factory — the AR11
//      seam. Construction goes through the factory, callers hold only the
//      base type, so swapping the screen-on mechanism edits ONE line inside
//      display/ and nothing outside it (AC3: "a gate outcome swaps a module,
//      not the architecture").
//
// STRATEGY DECISION (Nerya, 2026-07-17 — ADR 0003): the shipped strategy IS
// the base class — app-mode. PaceTurner declares no Fit permission, opens no
// ActivityRecording session, and designs for the watch's own general-use
// display behavior instead: HIGH after interaction, dim (LOW) after the
// user's timeout, words KEEP FLOWING through dim, and a true OFF auto-pauses.
// Hardware-validated on the real Fenix 8 (on-device probes 2026-07-16/17):
// with general-use AOD on and the watch on-wrist the display dims at ~8 s and
// never goes OFF while words flow; with AOD off it reaches OFF after some
// minutes and the auto-pause caught it exactly at the frozen word. The
// activity-session strategy (gate V1's original mechanism) is git-preserved
// at commit 81978d6 (display/ActivitySessionStrategy.mc) and returns as the
// separate "PaceTurner Active" store listing after the initial publish —
// the Fit permission moves a CIQ app into the Fenix 8 ACTIVITIES list and
// brings the during-activity touch lock, so the two mechanisms cannot share
// one listing (permissions are per-manifest; ADR 0003).
module Display {

    // Wake-tap grace window (ms): a touch/button that WAKES the display from
    // the auto-paused dark screen may also be delivered to the input delegate;
    // within this window it must not toggle playback or move position.
    // Starting value approved 2026-07-15; tune on device (Task 8d).
    const WAKE_GRACE_MS = 400;

    // ── pure display policy (host-tested, never touches Toybox.System) ──────

    // The AC2 policy matrix — "words never flow on a screen the user can't
    // read" (UX-DR12), amended 2026-07-17 after the app-mode probes:
    //   HIGH (0)      ⇒ flow (readable)
    //   LOW  (1)      ⇒ flow — dim is a DESIGNED-FOR reading state (gate-V1
    //                   session-dim + the 2026-07-16 on-wrist general-AOD
    //                   probe both validated dim legibility; UX designs for it)
    //   OFF  (2)      ⇒ pause always — unreadable, full stop
    //   anything else ⇒ pause — an unrecognized mode is treated as
    //                   unreadable (bounds-check-and-degrade, NFR8/AR24)
    // Mode values mirror System.DISPLAY_MODE_* (HIGH_POWER=0, LOW_POWER=1,
    // OFF=2 — verified against SDK 9.1.0 api.mir). The former sessionActive
    // parameter is gone with the session: LOW is legible in both the
    // during-activity and general-use profiles, so the row no longer branches.
    function shouldPauseForMode(mode as Number) as Boolean {
        if (mode == 0 || mode == 1) {
            return false;
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

    // Base screen-on strategy AND the shipped app-mode strategy: acquire
    // nothing, hold nothing — the watch's own display settings govern the
    // screen, the policy above governs playback. Every method is a safe no-op
    // default, so the future ActivitySessionStrategy ("PaceTurner Active"
    // listing, ADR 0003) overrides exactly what it needs and nothing else.
    // The strategy never references the view or the engine (AR15).
    class DisplayStrategy {
        // Playback (re)started — acquire the screen-on mechanism (app-mode:
        // nothing to acquire). Idempotent.
        function onPlaybackStart() as Void {
        }

        // App is exiting — release the mechanism. Safe to over-call.
        function shutdown() as Void {
        }

        // Is a screen-holding session active? App-mode: never. (The Active
        // variant gates its lifecycle on the live recording state here.)
        function isSessionActive() as Boolean {
            return false;
        }

        // Display-mode transition bookkeeping only — the VIEW owns the engine
        // reaction and the AOD-hint evidence. Must stay O(1), no Storage, no
        // allocation (system-callback discipline, robustness #3).
        function onDisplayModeChanged(mode as Number) as Void {
        }
    }

    // The ONE construction site (AC3): a strategy swap edits this line only.
    // App-mode ships the base itself (ADR 0003); the Active listing swaps in
    // its session strategy here.
    function createStrategy() as DisplayStrategy {
        return new DisplayStrategy();
    }
}

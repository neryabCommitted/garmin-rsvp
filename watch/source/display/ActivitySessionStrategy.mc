import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Lang;
import Toybox.System;

// The gate-V1-validated screen-on mechanism (Story 3.7, AC1): a generic
// ActivityRecording session puts the watch in the During-Activity display
// profile, and — with the user's During Activity → Always On setting enabled —
// the display stays lit (HIGH ~15 s, then LOW/dim, never OFF) and legible for
// the whole reading session (gates.md §V1, passed-dim).
//
// This class is the graduation of the disposable Gate-V1 spike; every item in
// the deferred-work spike-robustness bundle (deferred-work.md:43) is closed
// here, not copied: start() Boolean checked (#1), createSession wrapped (#2),
// O(1) no-Storage system callback (#3), everything gated on the live
// isRecording() state (#4), broad catches (#5), two bounded fields (#6),
// rapid-cycle prevented structurally — open once at play, close once at App
// exit, idempotent onPlaybackStart (#7); getTimer() wraparound lives in the
// pure Display.isWakeGrace (#8).
//
// A failed open is FALLBACK MODE, not an error state: the app reads on under
// the stricter pause policy (Display.shouldPauseForMode with sessionActive
// false) — one println, no retry loop, no user-facing error (quiet librarian;
// the screen behavior itself communicates). Sessions are always discard()ed,
// never save()d — a reading session must not pollute Garmin Connect with fake
// generic activities (Story-1.3 decision, confirmed 2026-07-15).
//
// Deliberately absent: Attention.backlight — sustained backlight is hard-
// stopped by firmware (BacklightOnTooLongException, ~1-min class) and is
// explicitly not a pass path (gates.md §V1 Notes).
class ActivitySessionStrategy extends Display.DisplayStrategy {

    private var _session as ActivityRecording.Session?;
    private var _sawOffDuringSession as Boolean;

    function initialize() {
        DisplayStrategy.initialize();
        _session = null;
        _sawOffDuringSession = false;
    }

    // Open the session, idempotently: an already-recording session is kept
    // (over-calling from every play site is free — robustness #7's structural
    // guard). Any failure ⇒ _session = null ⇒ fallback mode.
    function onPlaybackStart() as Void {
        if (_session != null && isSessionActive()) {
            return;
        }
        var session = null;
        try {
            // Activity.SPORT_* (3.2.0+), never the deprecated
            // ActivityRecording.SPORT_* (API shapes: SDK 9.1.0 api.mir, 1-3).
            session = ActivityRecording.createSession({
                :name => "PaceTurner",
                :sport => Activity.SPORT_GENERIC,
                :subSport => Activity.SUB_SPORT_GENERIC
            });
        } catch (e) {
            System.println("Display: createSession failed — fallback mode");
            _session = null;
            return;
        }
        // start() returning false leaves a silently-fake-active session — the
        // one failure that invalidates the whole premise undetected
        // (robustness #1). Verify, and discard the dead session on false.
        var started = false;
        try {
            started = session.start();
        } catch (e) {
            started = false;
        }
        if (!started) {
            System.println("Display: session.start() false — fallback mode");
            try {
                session.stop();
                session.discard();
            } catch (e) {
            }
            _session = null;
            return;
        }
        _session = session;
    }

    // Live session state, never a stale flag (robustness #4).
    function isSessionActive() as Boolean {
        return _session != null && (_session as ActivityRecording.Session).isRecording();
    }

    // Release at App exit — stop+discard+null, guarded (a throwing stop must
    // not crash app exit). Always discard(), never save().
    function shutdown() as Void {
        var session = _session;
        if (session == null) {
            return;
        }
        try {
            session.stop();
            session.discard();
        } catch (e) {
            System.println("Display: session shutdown failed");
        }
        _session = null;
    }

    // Bookkeeping only — the VIEW owns the engine reaction. OFF while the
    // session records is exactly the signature of the user's During-Activity
    // AOD setting being off (with it on, V1 proved the mode never reaches OFF
    // in 61 min) — arm the Task-6 hint. O(1), no Storage, no allocation
    // (system-callback discipline, robustness #3).
    function onDisplayModeChanged(mode as Number) as Void {
        if (mode == System.DISPLAY_MODE_OFF && isSessionActive()) {
            _sawOffDuringSession = true;
        }
    }

    function sawOffDuringSession() as Boolean {
        return _sawOffDuringSession;
    }
}

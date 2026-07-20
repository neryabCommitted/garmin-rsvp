import Toybox.Lang;
import Toybox.WatchUi;

// Pure key/gesture -> action map for playback (Story 3.3, AC1–AC5, FR8–FR12).
//
// Why a module of pure functions: the watch input map is PROVISIONAL until the
// first hardware test (the #1 risk is that some Fenix 8 devices fold
// SWIPE_RIGHT into KEY_ESC — see the story's "swipe-right may arrive as BACK"
// note). Isolating the raw-input -> action mapping here makes it unit-pinned and
// cheap to re-map after that test, with zero churn in the delegate or view. The
// delegate (PlaybackDelegate) is a thin adapter that just dispatches these
// actions to the view; the view drives the engine. Input flows
// delegate -> view -> engine only (AR15, no cycle).
//
// The map's PRINCIPLES are fixed (AC4): every action has a physical-button path;
// BACK exits (returned as ACTION_EXIT, the delegate lets the system handle it);
// LIGHT is never consumed; MENU opens the settings menu (Story 3.8) in BOTH
// states. The concrete key/gesture choices are provisional. Imports
// Toybox.WatchUi only to name the KEY_*/SWIPE_* enum constants — it touches no
// UI and reads no Storage, so the matco host tester exercises it directly
// (mirrors how ReaderEngineTest references Protocol/StreamDecoder).
module InputMap {

    // Action constants (typed, no magic numbers at call sites).
    const ACTION_NONE = 0;          // unconsumed — let the system handle it
    const ACTION_PAUSE_RESUME = 1;  // START / tap
    const ACTION_WPM_UP = 2;        // UP while playing
    const ACTION_WPM_DOWN = 3;      // DOWN while playing
    const ACTION_REWIND = 4;        // UP while paused / rewind swipe
    const ACTION_CONTEXT = 5;       // DOWN while paused — reserved for Story 3.4
    const ACTION_EXIT = 6;          // BACK -> exit to watch face
    const ACTION_MENU = 7;          // MENU -> settings menu (Story 3.8)

    // Map a raw key + the reader's paused state to an action. UP/DOWN are
    // state-aware: while playing they adjust WPM; while paused UP rewinds and
    // DOWN opens the (3.4) context view. MENU maps to ACTION_MENU in BOTH
    // states (Story 3.8: while playing it means "pause + open settings",
    // UX-DR16; while paused it just opens settings — the resolved reading of
    // the UX spine, which leaves paused-MENU unmapped). KEY_LIGHT stays NONE —
    // LIGHT is off-limits, never consumed (UX-DR15). Anything unrecognised
    // degrades to NONE (bounds-check-and-degrade, AR24).
    function actionForKey(key as Number, isPaused as Boolean) as Number {
        if (key == WatchUi.KEY_ENTER) {
            return ACTION_PAUSE_RESUME;
        }
        if (key == WatchUi.KEY_UP) {
            return isPaused ? ACTION_REWIND : ACTION_WPM_UP;
        }
        if (key == WatchUi.KEY_DOWN) {
            return isPaused ? ACTION_CONTEXT : ACTION_WPM_DOWN;
        }
        if (key == WatchUi.KEY_ESC) {
            return ACTION_EXIT;
        }
        if (key == WatchUi.KEY_MENU) {
            return ACTION_MENU;
        }
        return ACTION_NONE;
    }

    // Tap mirrors START (pause/resume) only when touch controls are on (AC5: with
    // touch off, tap is a no-op so the watch is fully button-operable).
    function actionForTap(touchEnabled as Boolean) as Number {
        return touchEnabled ? ACTION_PAUSE_RESUME : ACTION_NONE;
    }

    // The rewind gesture (FR10 "I lost it") fires only when touch is on AND the
    // swipe matches the handedness-mirrored rewind direction. `rewindDir` is
    // WatchUi.SWIPE_RIGHT for a right-handed reader, SWIPE_LEFT for a left-handed
    // one (the view derives it from Settings.handedness). Additionally (Story 3.4),
    // a swipe UP while PAUSED (touch on) opens the context view — the touch mirror
    // of DOWN-while-paused (which actionForKey maps to ACTION_CONTEXT). Any other
    // direction, or touch off, is a no-op. NOTE: this only fires if the event
    // actually reaches onSwipe — on a device that routes SWIPE_RIGHT to KEY_ESC the
    // button path (START->UP) is the rewind guarantee, decided on hardware (Task 6).
    // rewindDir is never SWIPE_UP, so the rewind and context cases never collide.
    function actionForSwipe(direction as Number, touchEnabled as Boolean,
                            rewindDir as Number, isPaused as Boolean) as Number {
        if (touchEnabled && direction == rewindDir) {
            return ACTION_REWIND;
        }
        if (touchEnabled && isPaused && direction == WatchUi.SWIPE_UP) {
            return ACTION_CONTEXT;
        }
        return ACTION_NONE;
    }
}

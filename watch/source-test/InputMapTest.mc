import Toybox.Lang;
import Toybox.Test;
import Toybox.WatchUi;

// Host-side tests for the pure input map (Story 3.3, AC1–AC5). Run under
// matco/action-connectiq-tester (SDK 8.4.0, fenix847mm) at Strict level 3. The
// matco tester runs the full SDK, so the tests pass real WatchUi.KEY_*/SWIPE_*
// enum constants in (mirrors how ReaderEngineTest passes Protocol/StreamDecoder).
// No Test.assert* API in this repo — assert via conditionals + logger.error +
// return false (mirrors SmokeTest/ReaderEngineTest/OrpLayoutTest).

// ── AC2/AC3/AC4: state-aware key map (UP/DOWN flip on pause) ──────────────────

(:test)
function inputKeyMapPlaying(logger as Test.Logger) as Boolean {
    var playing = false; // isPaused == false
    if (InputMap.actionForKey(WatchUi.KEY_ENTER, playing) != InputMap.ACTION_PAUSE_RESUME) {
        logger.error("ENTER playing -> PAUSE_RESUME"); return false;
    }
    if (InputMap.actionForKey(WatchUi.KEY_UP, playing) != InputMap.ACTION_WPM_UP) {
        logger.error("UP playing -> WPM_UP"); return false;
    }
    if (InputMap.actionForKey(WatchUi.KEY_DOWN, playing) != InputMap.ACTION_WPM_DOWN) {
        logger.error("DOWN playing -> WPM_DOWN"); return false;
    }
    if (InputMap.actionForKey(WatchUi.KEY_ESC, playing) != InputMap.ACTION_EXIT) {
        logger.error("ESC playing -> EXIT"); return false;
    }
    return true;
}

(:test)
function inputKeyMapPaused(logger as Test.Logger) as Boolean {
    var paused = true;
    // ENTER always pauses/resumes; ESC always exits — state-independent (AC4).
    if (InputMap.actionForKey(WatchUi.KEY_ENTER, paused) != InputMap.ACTION_PAUSE_RESUME) {
        logger.error("ENTER paused -> PAUSE_RESUME"); return false;
    }
    if (InputMap.actionForKey(WatchUi.KEY_ESC, paused) != InputMap.ACTION_EXIT) {
        logger.error("ESC paused -> EXIT"); return false;
    }
    // While paused UP rewinds (button-path rewind, the fixed guarantee) and DOWN
    // opens the context view (reserved for Story 3.4).
    if (InputMap.actionForKey(WatchUi.KEY_UP, paused) != InputMap.ACTION_REWIND) {
        logger.error("UP paused -> REWIND"); return false;
    }
    if (InputMap.actionForKey(WatchUi.KEY_DOWN, paused) != InputMap.ACTION_CONTEXT) {
        logger.error("DOWN paused -> CONTEXT"); return false;
    }
    return true;
}

(:test)
function inputLightNeverConsumedMenuClaimed(logger as Test.Logger) as Boolean {
    // AC4 (3.3): LIGHT is off-limits (never consumed) — NONE in BOTH states.
    // Story 3.8 AC1: MENU is claimed in BOTH states (playing = pause + open
    // settings per UX-DR16; paused = open settings).
    if (InputMap.actionForKey(WatchUi.KEY_LIGHT, false) != InputMap.ACTION_NONE) {
        logger.error("LIGHT playing -> NONE"); return false;
    }
    if (InputMap.actionForKey(WatchUi.KEY_LIGHT, true) != InputMap.ACTION_NONE) {
        logger.error("LIGHT paused -> NONE"); return false;
    }
    if (InputMap.actionForKey(WatchUi.KEY_MENU, false) != InputMap.ACTION_MENU) {
        logger.error("MENU playing -> MENU"); return false;
    }
    if (InputMap.actionForKey(WatchUi.KEY_MENU, true) != InputMap.ACTION_MENU) {
        logger.error("MENU paused -> MENU"); return false;
    }
    return true;
}

// ── AC1/AC5: tap mirrors START only when touch is on ──────────────────────────

(:test)
function inputTapMap(logger as Test.Logger) as Boolean {
    if (InputMap.actionForTap(true) != InputMap.ACTION_PAUSE_RESUME) {
        logger.error("tap, touch on -> PAUSE_RESUME"); return false;
    }
    // AC5: touch off -> no-op (return NONE so the watch stays fully button-driven).
    if (InputMap.actionForTap(false) != InputMap.ACTION_NONE) {
        logger.error("tap, touch off -> NONE"); return false;
    }
    return true;
}

// ── AC3/AC5: rewind swipe respects touch + handedness mirror ──────────────────

(:test)
function inputSwipeMap(logger as Test.Logger) as Boolean {
    // Right-handed: rewindDir == SWIPE_RIGHT. Swipe right with touch on -> REWIND.
    // Rewind is state-independent, so isPaused does not change these cases.
    if (InputMap.actionForSwipe(WatchUi.SWIPE_RIGHT, true, WatchUi.SWIPE_RIGHT, false) != InputMap.ACTION_REWIND) {
        logger.error("swipe-right, touch on, right-handed -> REWIND"); return false;
    }
    // AC5: touch off -> no-op even on the matching direction.
    if (InputMap.actionForSwipe(WatchUi.SWIPE_RIGHT, false, WatchUi.SWIPE_RIGHT, false) != InputMap.ACTION_NONE) {
        logger.error("swipe-right, touch off -> NONE"); return false;
    }
    // Left-handed mirror: rewindDir == SWIPE_LEFT. A right swipe no longer rewinds;
    // the matching left swipe does.
    if (InputMap.actionForSwipe(WatchUi.SWIPE_RIGHT, true, WatchUi.SWIPE_LEFT, false) != InputMap.ACTION_NONE) {
        logger.error("swipe-right, left-handed -> NONE"); return false;
    }
    if (InputMap.actionForSwipe(WatchUi.SWIPE_LEFT, true, WatchUi.SWIPE_LEFT, false) != InputMap.ACTION_REWIND) {
        logger.error("swipe-left, touch on, left-handed -> REWIND"); return false;
    }
    // A non-rewind direction while NOT paused is never a rewind (e.g. swipe up).
    if (InputMap.actionForSwipe(WatchUi.SWIPE_UP, true, WatchUi.SWIPE_RIGHT, false) != InputMap.ACTION_NONE) {
        logger.error("swipe-up, playing -> NONE"); return false;
    }
    return true;
}

// ── AC2: swipe-up while paused (touch on) opens the context view ──────────────

(:test)
function inputSwipeContextMap(logger as Test.Logger) as Boolean {
    // Swipe up + paused + touch on -> CONTEXT (the gesture mirror of DOWN-paused).
    if (InputMap.actionForSwipe(WatchUi.SWIPE_UP, true, WatchUi.SWIPE_RIGHT, true) != InputMap.ACTION_CONTEXT) {
        logger.error("swipe-up, paused, touch on -> CONTEXT"); return false;
    }
    // Swipe up while PLAYING -> NONE (context is paused-only).
    if (InputMap.actionForSwipe(WatchUi.SWIPE_UP, true, WatchUi.SWIPE_RIGHT, false) != InputMap.ACTION_NONE) {
        logger.error("swipe-up, playing -> NONE"); return false;
    }
    // Swipe up + paused but touch OFF -> NONE (AC5: fully button-driven; swipe no-op).
    if (InputMap.actionForSwipe(WatchUi.SWIPE_UP, false, WatchUi.SWIPE_RIGHT, true) != InputMap.ACTION_NONE) {
        logger.error("swipe-up, paused, touch off -> NONE"); return false;
    }
    // A non-up swipe while paused is unchanged: down is not context, and a matching
    // rewind direction still rewinds.
    if (InputMap.actionForSwipe(WatchUi.SWIPE_DOWN, true, WatchUi.SWIPE_RIGHT, true) != InputMap.ACTION_NONE) {
        logger.error("swipe-down, paused -> NONE"); return false;
    }
    if (InputMap.actionForSwipe(WatchUi.SWIPE_RIGHT, true, WatchUi.SWIPE_RIGHT, true) != InputMap.ACTION_REWIND) {
        logger.error("swipe-right, paused, right-handed -> REWIND"); return false;
    }
    return true;
}

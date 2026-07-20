import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// The thin input adapter for playback (Story 3.3, AC1/AC3/AC4/AC5). It extends
// WatchUi.InputDelegate — NOT BehaviorDelegate — on purpose: InputDelegate gives
// the RAW onKey/onTap/onSwipe events with NO onSelect/onBack behavior remapping,
// which is exactly AC4's "handlers use onKey + onTap/onSwipe, never onSelect".
// (The GateV2 spike's GateV2Delegate uses onSelect — that is spike code; its
// pattern is deliberately NOT copied here.)
//
// All policy lives in the pure InputMap (testable, re-mappable after hardware);
// all behaviour lives in the PlaybackView action API. This class only translates
// an action constant into a view call and reports consume/pass-through via the
// Boolean return. Input flows delegate -> view -> engine; the delegate holds the
// view one-directionally (no cycle, AR15).
//
// Return semantics (Garmin): return true to CONSUME the event, false to let the
// system handle it. ACTION_EXIT returns false so BACK keeps its Garmin meaning
// and the system pops to the watch face — BACK-is-exit is a fixed principle, and
// the Story 3.6 position force-save will hook the engine's transition surface
// later, NOT here (3.3 writes no Storage). ACTION_CONTEXT (Story 3.4) opens the
// pushed context view via the view; ACTION_NONE stays unconsumed (LIGHT/MENU).
class PlaybackDelegate extends WatchUi.InputDelegate {

    private var _view as PlaybackView;

    function initialize(view as PlaybackView) {
        InputDelegate.initialize();
        _view = view;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var action = InputMap.actionForKey(evt.getKey(), _view.isPausedState());
        traceInput("key", evt.getKey(), action);
        if (action == InputMap.ACTION_PAUSE_RESUME) {
            _view.pauseOrResume();
            return true;
        }
        if (action == InputMap.ACTION_WPM_UP) {
            _view.stepWpm(true);
            return true;
        }
        if (action == InputMap.ACTION_WPM_DOWN) {
            _view.stepWpm(false);
            return true;
        }
        if (action == InputMap.ACTION_REWIND) {
            _view.rewindOne();
            return true;
        }
        if (action == InputMap.ACTION_CONTEXT) {
            // DOWN while paused (Story 3.4) — push the context view. The view guards
            // on isPaused/currentRecord, so a stale event degrades to a no-op.
            _view.openContextView();
            return true;
        }
        if (action == InputMap.ACTION_MENU) {
            // MENU (Story 3.8) — pause if playing, then push the settings menu.
            // The view owns the pause/guard logic (wake-grace, card, FINISHED).
            _view.openSettingsMenu();
            return true;
        }
        // ACTION_EXIT (BACK -> let the system exit), ACTION_NONE (LIGHT): do not
        // consume.
        return false;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var action = InputMap.actionForTap(_view.touchEnabled());
        traceInput("tap", 0, action);
        if (action == InputMap.ACTION_PAUSE_RESUME) {
            _view.pauseOrResume();
            return true;
        }
        return false;
    }

    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        var action = InputMap.actionForSwipe(
            evt.getDirection(), _view.touchEnabled(), _view.rewindSwipeDirection(),
            _view.isPausedState());
        traceInput("swipe", evt.getDirection(), action);
        if (action == InputMap.ACTION_REWIND) {
            _view.rewindOne();
            return true;
        }
        if (action == InputMap.ACTION_CONTEXT) {
            // Swipe-up while paused (touch on) — the gesture mirror of DOWN-while-paused.
            _view.openContextView();
            return true;
        }
        return false;
    }

    // One-line marker per input event for the on-device log check (Task 6) — the
    // input map is provisional until hardware confirms whether swipe-right arrives
    // here at onSwipe or is folded into KEY_ESC. (:debug)-only: the (:release)
    // overload below is a no-op, so NO per-input println ships (logging budget,
    // AR25 — input is rare, but this is still stripped from release). The raw value
    // is the key/direction enum; action is the resolved InputMap.ACTION_*.
    (:debug)
    private function traceInput(kind as String, raw as Number, action as Number) as Void {
        System.println(Lang.format("input $1$ raw=$2$ -> action=$3$", [kind, raw, action]));
    }

    (:release)
    private function traceInput(kind as String, raw as Number, action as Number) as Void {
    }
}

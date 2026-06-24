import Toybox.Lang;
import Toybox.WatchUi;

// Input delegate for the pushed context-on-pause CustomMenu (Story 3.4, AC2/AC3).
// It extends WatchUi.Menu2InputDelegate because the context view is a CustomMenu: the
// menu handles SCROLLING natively (fluid touch/momentum AND UP/DOWN buttons — FR12
// "buttons are the guarantee", AC5 "touch-off still works"), so this delegate only
// needs to own BACK and (the unused) SELECT. No scroll plumbing here — that was the
// whole point of moving to CustomMenu.
//
// It holds NO reference to the view (the menu manages its own scroll/focus) — fully
// acyclic (AR15).
class PausedContextDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    // AC3: BACK pops the context menu and returns to the paused PlaybackView beneath —
    // it does NOT exit the app. (PlaybackView.onShow's STATE_IDLE guard keeps it
    // PAUSED on reveal.) popView is explicit so the intent is unambiguous.
    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    // The reading screen has nothing to select — START/tap on the focused line is a
    // deliberate no-op (the readout/resume controls live on the paused PlaybackView,
    // reached via BACK).
    function onSelect(item as WatchUi.MenuItem) as Void {
    }
}

import Toybox.Lang;
import Toybox.WatchUi;

// Gate V1 spike delegate (Story 1.3): START toggles the recording session;
// BACK keeps its Garmin meaning (exit — session cleanup runs in
// AppBase.onStop). UP runs the optional backlight-ceiling probe whose result
// only feeds the gates.md notes. Temporary spike code.
class GateV1Delegate extends WatchUi.BehaviorDelegate {

    private var _app as PaceTurnerApp;

    function initialize(app as PaceTurnerApp) {
        BehaviorDelegate.initialize();
        _app = app;
    }

    // START button / screen tap.
    function onSelect() as Boolean {
        _app.toggleSession();
        WatchUi.requestUpdate();
        return true;
    }

    // UP button — optional Attention.backlight ceiling probe (Task 3).
    function onPreviousPage() as Boolean {
        _app.probeBacklight();
        WatchUi.requestUpdate();
        return true;
    }
}

import Toybox.Lang;
import Toybox.WatchUi;

// Gate V2 spike delegate (Story 1.4): START/tap zeroes the counters so Run A
// (base64 String) and Run B (List<int>) are measured separately on one
// sideload; BACK keeps its Garmin meaning (exit — evidence persists in
// AppBase.onStop). Temporary spike code.
class GateV2Delegate extends WatchUi.BehaviorDelegate {

    private var _app as PaceTurnerApp;

    function initialize(app as PaceTurnerApp) {
        BehaviorDelegate.initialize();
        _app = app;
    }

    // START button / screen tap — reset counters between runs.
    function onSelect() as Boolean {
        _app.resetCounters();
        WatchUi.requestUpdate();
        return true;
    }
}

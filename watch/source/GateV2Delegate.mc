import Toybox.Lang;
import Toybox.WatchUi;

// Gate V2 spike delegate (Story 1.4): START/tap arms then performs the
// counter reset so Run A (base64 String) and Run B (List<int>) are measured
// separately on one sideload; BACK keeps its Garmin meaning (exit — evidence
// persists in AppBase.onStop). Temporary spike code.
class GateV2Delegate extends WatchUi.BehaviorDelegate {

    private var _app as PaceTurnerApp;

    function initialize(app as PaceTurnerApp) {
        BehaviorDelegate.initialize();
        _app = app;
    }

    // START button / screen tap — two-press reset: the first press arms
    // ("reset? press again" on the view), a second within the window resets.
    // One accidental press destroyed Run B's live ledger; never again.
    function onSelect() as Boolean {
        _app.requestReset();
        WatchUi.requestUpdate();
        return true;
    }
}

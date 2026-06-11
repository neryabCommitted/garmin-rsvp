import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Pure helpers for the Gate V1 spike, unit-tested in
// watch/source-test/GateV1Test.mc.
module GateV1 {

    // mm:ss with minutes counting past 59:59 — a 60-min run reads "60:00".
    function formatElapsed(seconds as Number) as String {
        return (seconds / 60).format("%02d") + ":" + (seconds % 60).format("%02d");
    }

    function displayModeLabel(mode as Number) as String {
        if (mode == System.DISPLAY_MODE_HIGH_POWER) { return "HIGH"; }
        if (mode == System.DISPLAY_MODE_LOW_POWER) { return "LOW"; }
        if (mode == System.DISPLAY_MODE_OFF) { return "OFF"; }
        return "?";
    }

    // Evidence-log wire form: "elapsed:mode" pairs, comma-joined. Persisted as
    // a String because Storage's value typedef differs between SDK 8.4.0 (CI)
    // and 9.1.0 (local), and nested arrays fail Strict's invariant generics.
    function logToString(log as Array<Array<Number> >) as String {
        var s = "";
        for (var i = 0; i < log.size(); i++) {
            var entry = log[i];
            if (i > 0) { s += ","; }
            s += entry[0].toString() + ":" + entry[1].toString();
        }
        return s;
    }
}

// Gate V1 spike view (Story 1.3): one bright word (UX-DR1 Ink on Void), a
// small session-elapsed counter, and the live display-mode label. Lit-pixel
// area stays small (burn-in citizenship). Temporary spike code — Epic 3's
// display/ modules supersede it.
class GateV1View extends WatchUi.View {

    private const COLOR_INK = 0xEAE6DF;  // UX-DR1 Ink
    private const COLOR_VOID = 0x000000; // UX-DR1 Void

    private var _app as PaceTurnerApp;
    private var _timer as Timer.Timer;

    function initialize(app as PaceTurnerApp) {
        View.initialize();
        _app = app;
        _timer = new Timer.Timer();
    }

    function onShow() as Void {
        _timer.start(method(:onTick), 1000, true);
    }

    function onHide() as Void {
        _timer.stop();
    }

    function onTick() as Void {
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(COLOR_INK, COLOR_VOID);
        dc.clear();

        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;

        dc.drawText(cx, cy, Graphics.FONT_MEDIUM, "PaceTurner",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var elapsed = _app.isSessionActive() ? _app.elapsedSeconds() : 0;
        var line = GateV1.formatElapsed(elapsed) + "  "
            + GateV1.displayModeLabel(System.getDisplayMode() as Number);
        var probe = _app.backlightProbeResult();
        if (probe != null) {
            line += "  " + probe;
        }
        dc.drawText(cx, cy + dc.getFontHeight(Graphics.FONT_MEDIUM),
            Graphics.FONT_XTINY, line, Graphics.TEXT_JUSTIFY_CENTER);
    }
}

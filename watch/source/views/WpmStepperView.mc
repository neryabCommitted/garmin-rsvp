import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// The WPM value editor (Story 3.8, AC1/AC2 — Task 6). WPM spans 10..1000 with
// an adaptive step: it cannot be a cycling MenuItem like every other setting
// (a full wrap would take dozens of presses; everything else edits in <= 7).
// So the menu's WPM row pushes THIS editor leaf. It is NOT a "multi-level
// menu": UX-DR16's ban targets nested menu trees; a single flat menu plus one
// value editor is the resolved reading (documented here per the story).
//
// Render-only and timer-less: it draws the CANDIDATE value large in Ink over
// Void with a small "WPM" title in Ink-Dim (watch-meta), inside the
// watch-safe-square (DESIGN.md card regime — centered content, guide-margin
// insets). All input/commit logic lives in WpmStepperDelegate; the candidate
// is uncommitted until START (BACK cancels — nothing touched).
class WpmStepperView extends WatchUi.View {

    // DESIGN palette (DESIGN.md Colors) — same roles as PlaybackView.
    private const COLOR_VOID = 0x000000;   // true-black AMOLED canvas
    private const COLOR_INK = 0xEAE6DF;    // the candidate value (focal)
    private const COLOR_INK_DIM = 0x8A867F; // "WPM" title (watch-meta)

    private var _candidate as Number;

    function initialize(initial as Number) {
        View.initialize();
        _candidate = initial;
    }

    function candidate() as Number {
        return _candidate;
    }

    function setCandidate(v as Number) as Void {
        _candidate = v;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_TRANSPARENT, COLOR_VOID);
        dc.clear();
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var valueFont = Graphics.FONT_SYSTEM_NUMBER_MEDIUM;
        var titleFont = Graphics.FONT_SYSTEM_TINY; // watch-meta

        // Title above the value, clear of it by half the value's height.
        dc.setColor(COLOR_INK_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - dc.getFontHeight(valueFont) / 2 - dc.getFontHeight(titleFont) / 2,
            titleFont, "WPM",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // The candidate, large, centered where the round face is widest.
        dc.setColor(COLOR_INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, valueFont, _candidate.toString(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

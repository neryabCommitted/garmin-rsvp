import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Placeholder view — proves the scaffold builds and runs. The real RSVP
// playback surface arrives in Epic 3 (PlaybackView).
class PaceTurnerView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(
            dc.getWidth() / 2,
            dc.getHeight() / 2,
            Graphics.FONT_MEDIUM,
            "PaceTurner",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }
}

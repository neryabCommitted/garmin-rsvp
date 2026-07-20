import Toybox.Lang;
import Toybox.WatchUi;

// Input delegate for the WPM stepper editor (Story 3.8, Task 6). A raw
// WatchUi.InputDelegate driving onKey — never onSelect (UX-DR15): the editor
// is button-operated like the playback surface it serves.
//
//   UP / DOWN — step the CANDIDATE by the adaptive rule. The rule has ONE
//     encoding: SettingsModel.adaptiveWpmStep (the engine's stepWpmUp/Down
//     delegate to the same function), so the editor and in-flow stepping can
//     never drift apart.
//   START — commit: persist, apply to the live engine (takes effect next
//     word), refresh the menu row's sub-label, pop back to the menu.
//   BACK — cancel: pop back to the menu, nothing touched (pop-not-exit;
//     BACK-sacred, UX-DR15).
//
// Holds refs one-way (delegate -> view/settings/menu-item, AR15 no-cycle).
class WpmStepperDelegate extends WatchUi.InputDelegate {

    private var _stepper as WpmStepperView;
    private var _settings as SettingsModel.Settings;
    private var _playback as PlaybackView;
    private var _menuItem as WatchUi.MenuItem;

    function initialize(stepper as WpmStepperView, settings as SettingsModel.Settings,
                        playback as PlaybackView, menuItem as WatchUi.MenuItem) {
        InputDelegate.initialize();
        _stepper = stepper;
        _settings = settings;
        _playback = playback;
        _menuItem = menuItem;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_UP) {
            _stepper.setCandidate(SettingsModel.adaptiveWpmStep(_stepper.candidate(), true));
            WatchUi.requestUpdate();
            return true;
        }
        if (key == WatchUi.KEY_DOWN) {
            _stepper.setCandidate(SettingsModel.adaptiveWpmStep(_stepper.candidate(), false));
            WatchUi.requestUpdate();
            return true;
        }
        if (key == WatchUi.KEY_ENTER) {
            // Commit: model -> Storage -> live engine -> menu row, then pop.
            var v = _stepper.candidate();
            _settings.wpm = v;
            _settings.save();
            _playback.applyWpm(v);
            _menuItem.setSubLabel(SettingsMenu.wpmSubLabel(v));
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return true;
        }
        if (key == WatchUi.KEY_ESC) {
            // Cancel: pop back to the menu, never exit the app from here.
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return true;
        }
        return false;
    }
}

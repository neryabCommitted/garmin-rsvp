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
//   START or BACK — commit-on-exit: persist the candidate, apply to the live
//     engine (takes effect next word), refresh the menu row's sub-label, and
//     pop back to the menu. Both exits save.
//
// AMENDED (on-device Task 9, Nerya 2026-07-23): the original spec had
// START=commit / BACK=cancel, but on the watch it was not obvious a separate
// START press was needed — changing the number and pressing BACK silently
// discarded it, out of step with every OTHER menu item, which applies the
// instant it changes. So the editor now commits on ANY exit ("what you set is
// what sticks"); to undo, step back to the old value. BACK still only pops to
// the menu, never exits the app (BACK-sacred, UX-DR15).
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
        // Commit-on-exit: both START and BACK save the candidate, then pop back
        // to the menu (never exit the app — BACK-sacred, UX-DR15). See header.
        if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_ESC) {
            commitAndPop();
            return true;
        }
        return false;
    }

    // Persist the candidate: model -> Storage -> live engine -> menu row, then
    // pop. applyWpm clears the in-flow dirty flag (the committed value is the
    // saved value). One save per exit, regardless of how many steps were taken.
    private function commitAndPop() as Void {
        var v = _stepper.candidate();
        _settings.wpm = v;
        _settings.save();
        _playback.applyWpm(v);
        _menuItem.setSubLabel(SettingsMenu.wpmSubLabel(v));
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

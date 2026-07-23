import Toybox.Lang;
import Toybox.WatchUi;

// Input delegate for the pushed settings Menu2 (Story 3.8, AC2). Extends
// Menu2InputDelegate — the onSelect ban (UX-DR15) was written for the PLAYBACK
// delegate; menus select things (PausedContextDelegate is the precedent).
//
// Every edit follows the same shape: mutate the LIVE SettingsModel.Settings
// (the same instance PlaybackView owns), persist via save() (the menu is a
// cold path — the deferred-work:129 flash-write hazard is the hot tick path),
// refresh the item's sub-label, notify the view where a field was copied at
// construction (applyWpm/applyPauseMode/applyFontSize — everything else is
// read live per event/frame, so the mutation alone is the propagation), and
// repaint. Changes take effect immediately (AC2).
//
// Reference direction: delegate -> {settings, view} — the established one-way
// flow (PlaybackDelegate does the same); the view holds no reference back to
// this delegate or the menu (no GC cycle, AR15). Deviation from the story's
// "holds refs to … the Menu2": onSelect receives the touched item directly,
// so a stored menu ref is dead weight — and an unused member is a warning the
// warning-free gate (Enforcement #5) rejects.
class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _settings as SettingsModel.Settings;
    private var _view as PlaybackView;

    function initialize(settings as SettingsModel.Settings, view as PlaybackView) {
        Menu2InputDelegate.initialize();
        _settings = settings;
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :wpm) {
            // WPM (10..1000, adaptive step) cannot be a cycling item — push the
            // value-editor leaf instead (Task 6). It commits/cancels and pops;
            // the item's sub-label is updated by the stepper delegate on commit.
            var stepper = new WpmStepperView(_view.engineWpm());
            WatchUi.pushView(stepper,
                new WpmStepperDelegate(stepper, _settings, _view, item),
                WatchUi.SLIDE_UP);
            return;
        }
        if (id == :pauseMode) {
            _settings.pauseMode = SettingsMenu.cycleEnum(_settings.pauseMode,
                SettingsModel.PAUSE_COAST, SettingsModel.PAUSE_INSTANT);
            _view.applyPauseMode(_settings.pauseMode);
            item.setSubLabel(SettingsMenu.labelForPauseMode(_settings.pauseMode));
        } else if (id == :chapterResume) {
            _settings.chapterResume = SettingsMenu.cycleEnum(_settings.chapterResume,
                SettingsModel.CHAPTER_RESUME_AUTO, SettingsModel.CHAPTER_RESUME_WAIT);
            item.setSubLabel(SettingsMenu.labelForChapterResume(_settings.chapterResume));
        } else if (id == :touchControls) {
            // ToggleMenuItem flips its state BEFORE onSelect fires — read it,
            // don't track it (Connect IQ contract, checked 2026-07-20).
            _settings.touchControls = (item as WatchUi.ToggleMenuItem).isEnabled();
        } else if (id == :fontSize) {
            _settings.fontSize = SettingsMenu.cycleFontSize(_settings.fontSize,
                _view.fontRampLength());
            _view.applyFontSize();
            item.setSubLabel(SettingsMenu.labelForFontSize(_settings.fontSize));
        } else if (id == :handedness) {
            _settings.handedness = SettingsMenu.cycleEnum(_settings.handedness,
                SettingsModel.HAND_RIGHT, SettingsModel.HAND_LEFT);
            item.setSubLabel(SettingsMenu.labelForHandedness(_settings.handedness));
        } else if (id == :focusHighlight) {
            _settings.focusHighlight = (item as WatchUi.ToggleMenuItem).isEnabled();
        } else if (id == :phantomWords) {
            _settings.phantomWords = (item as WatchUi.ToggleMenuItem).isEnabled();
        } else if (id == :anchorPct) {
            _settings.anchorPct = SettingsMenu.cycleAnchorPct(_settings.anchorPct);
            item.setSubLabel(SettingsMenu.anchorSubLabel(_settings.anchorPct));
        } else {
            return; // unrecognized id degrades to a no-op (NFR8) — nothing to save
        }
        _settings.save(); // cold path: one flat dict under the "settings" key
        // The save above serialized the FULL dict, so any in-flow WPM step the
        // view mirrored into _settings.wpm is now durable — clear its dirty flag
        // to avoid a redundant re-save when onHide fires on menu dismiss.
        _view.markSettingsPersisted();
        WatchUi.requestUpdate();
    }

    // BACK pops to the Paused frame beneath — never exits the app from the menu
    // (BACK-sacred, UX-DR15; PausedContextDelegate is the template). The
    // revealed PlaybackView fires onShow: a PAUSED/PLAYING engine is left as-is;
    // only a never-played IDLE engine (fresh-install first-launch demo whose
    // auto-play an unreadable screen deferred) resumes that intended demo — a
    // restored position is PAUSED, not IDLE, so it never auto-plays here.
    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

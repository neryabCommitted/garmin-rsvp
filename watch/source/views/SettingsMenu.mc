import Toybox.Lang;
import Toybox.WatchUi;

// The settings menu surface (Story 3.8, AC1/AC2 — UX-DR17). Two halves in one
// file (the SyncManager/DisplayStrategy pure/adapter precedent):
//
//   1. Pure label/cycle helpers — Lang-only, host-tested (SettingsMenuTest).
//      They own the menu's copy (quiet-librarian, UX-DR23: short, factual, no
//      exclamation marks) and the enum/step cycling rules, so every value the
//      menu can show or produce is pinned without a UI.
//   2. build() — the thin WatchUi.Menu2 factory. Items appear in UX-DR17 order
//      with Symbol ids (no magic numbers/strings at dispatch sites); the
//      SettingsMenuDelegate switches on those ids.
//
// This is a single FLAT menu: the WPM stepper it can push is a value EDITOR
// leaf, not a submenu — UX-DR16's "no multi-level menus" ban targets nested
// menu trees, and a flat menu + one editor leaf is the resolved reading (see
// WpmStepperView). Settings are per-device, never synced (UX-DR17): everything
// here mutates the local SettingsModel.Settings and the "settings" Storage key
// only — nothing crosses the protocol.
module SettingsMenu {

    // ── pure half (Lang-only — no Toybox.System/Storage use) ─────────────────

    function labelForPauseMode(v as Number) as String {
        return v == SettingsModel.PAUSE_INSTANT ? "Instant" : "Coast";
    }

    function labelForChapterResume(v as Number) as String {
        return v == SettingsModel.CHAPTER_RESUME_WAIT ? "Wait" : "Auto";
    }

    function labelForHandedness(v as Number) as String {
        return v == SettingsModel.HAND_LEFT ? "Left" : "Right";
    }

    // The 5 font-ramp steps, 1-based for the reader, ends named so the
    // direction is obvious without a live preview (index 0 = largest native
    // face — PlaybackView's ramp; ±2 steps around the default, see AC3 note).
    function labelForFontSize(v as Number) as String {
        if (v <= 0) { return "1 (largest)"; }
        if (v == 1) { return "2"; }
        if (v == 2) { return "3"; }
        if (v == 3) { return "4"; }
        return "5 (smallest)";
    }

    // Advance a contiguous [lo, hi] enum by one, wrapping hi -> lo. An
    // out-of-range input (a malformed persisted value) snaps to lo
    // (bounds-check-and-degrade, NFR8).
    function cycleEnum(v as Number, lo as Number, hi as Number) as Number {
        if (v < lo || v >= hi) {
            return lo;
        }
        return v + 1;
    }

    // Advance the font-size index by one, wrapping rampLength-1 -> 0. The model
    // persists any fontSize >= 0 (the ramp bound lives at the view, 3.1
    // deferred #94) — snap out-of-range input into the ramp before cycling.
    function cycleFontSize(v as Number, rampLength as Number) as Number {
        if (rampLength <= 0) {
            return 0;
        }
        var cur = v;
        if (cur < 0) { cur = 0; }
        if (cur > rampLength - 1) { cur = rampLength - 1; }
        return cur >= rampLength - 1 ? 0 : cur + 1;
    }

    // Advance the ORP anchor by 5, over the user-tunable 30..60 range (UX-DR5),
    // wrapping 60 -> 30. The model clamps 0..100 — anything off the tunable
    // grid (out-of-range or a non-multiple of 5) snaps to the 35 default.
    function cycleAnchorPct(v as Number) as Number {
        if (v < 30 || v > 60 || v % 5 != 0) {
            return SettingsModel.DEFAULT_ANCHOR_PCT;
        }
        return v >= 60 ? 30 : v + 5;
    }

    // ── thin half: the Menu2 factory ─────────────────────────────────────────

    // Build the settings Menu2 over the LIVE model. Items in UX-DR17 order; ids
    // are Symbols the delegate dispatches on. The WPM sub-label seeds from
    // `liveWpm` — the engine's runtime value, not the possibly-stale stored one
    // (in-flow UP/DOWN steps mutate the engine first; see PlaybackView.stepWpm).
    function build(settings as SettingsModel.Settings, liveWpm as Number) as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({:title => "Settings"});
        menu.addItem(new WatchUi.MenuItem("WPM", wpmSubLabel(liveWpm), :wpm, null));
        menu.addItem(new WatchUi.MenuItem("Pause", labelForPauseMode(settings.pauseMode), :pauseMode, null));
        menu.addItem(new WatchUi.MenuItem("Chapter resume", labelForChapterResume(settings.chapterResume), :chapterResume, null));
        menu.addItem(new WatchUi.ToggleMenuItem("Touch", null, :touchControls, settings.touchControls, null));
        menu.addItem(new WatchUi.MenuItem("Font size", labelForFontSize(settings.fontSize), :fontSize, null));
        menu.addItem(new WatchUi.MenuItem("Handedness", labelForHandedness(settings.handedness), :handedness, null));
        menu.addItem(new WatchUi.ToggleMenuItem("Focus highlight", null, :focusHighlight, settings.focusHighlight, null));
        menu.addItem(new WatchUi.ToggleMenuItem("Phantom words", null, :phantomWords, settings.phantomWords, null));
        menu.addItem(new WatchUi.MenuItem("Anchor", anchorSubLabel(settings.anchorPct), :anchorPct, null));
        return menu;
    }

    // Sub-label formatters shared by build() and the delegates' post-edit
    // updates — one encoding of each string (the review-feedback class:
    // unpinned duplicate tables).
    function wpmSubLabel(wpm as Number) as String {
        return wpm.toString() + " wpm";
    }

    function anchorSubLabel(pct as Number) as String {
        return pct.toString() + "%";
    }
}

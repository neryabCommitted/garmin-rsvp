import Toybox.Lang;
import Toybox.Test;

// Host-side pins for the settings-menu PURE half (Story 3.8, AC1/AC2) plus the
// SettingsModel.adaptiveWpmStep table the WPM stepper shares with the engine
// (Task 6 — ONE encoding of the step rule). Runs under the matco CI image at
// Strict L3. No Test.assert* in this repo — conditional + logger.error + return
// false (DisplayPolicyTest/SyncManagerTest are the templates).

// ── label functions: every value pinned (copy is quiet-librarian, UX-DR23) ────

(:test)
function settingsMenuLabels(logger as Test.Logger) as Boolean {
    if (!SettingsMenu.labelForPauseMode(SettingsModel.PAUSE_COAST).equals("Coast")) {
        logger.error("pauseMode COAST label"); return false;
    }
    if (!SettingsMenu.labelForPauseMode(SettingsModel.PAUSE_INSTANT).equals("Instant")) {
        logger.error("pauseMode INSTANT label"); return false;
    }
    if (!SettingsMenu.labelForChapterResume(SettingsModel.CHAPTER_RESUME_AUTO).equals("Auto")) {
        logger.error("chapterResume AUTO label"); return false;
    }
    if (!SettingsMenu.labelForChapterResume(SettingsModel.CHAPTER_RESUME_WAIT).equals("Wait")) {
        logger.error("chapterResume WAIT label"); return false;
    }
    if (!SettingsMenu.labelForHandedness(SettingsModel.HAND_RIGHT).equals("Right")) {
        logger.error("handedness RIGHT label"); return false;
    }
    if (!SettingsMenu.labelForHandedness(SettingsModel.HAND_LEFT).equals("Left")) {
        logger.error("handedness LEFT label"); return false;
    }
    return true;
}

(:test)
function settingsMenuFontSizeLabels(logger as Test.Logger) as Boolean {
    // 5 ramp steps (PlaybackView RAMP_LENGTH): 1-based for the reader, with the
    // ends named so the direction is obvious without a live preview.
    if (!SettingsMenu.labelForFontSize(0).equals("1 (largest)")) {
        logger.error("fontSize 0 label"); return false;
    }
    if (!SettingsMenu.labelForFontSize(1).equals("2")) {
        logger.error("fontSize 1 label"); return false;
    }
    if (!SettingsMenu.labelForFontSize(2).equals("3")) {
        logger.error("fontSize 2 label"); return false;
    }
    if (!SettingsMenu.labelForFontSize(3).equals("4")) {
        logger.error("fontSize 3 label"); return false;
    }
    if (!SettingsMenu.labelForFontSize(4).equals("5 (smallest)")) {
        logger.error("fontSize 4 label"); return false;
    }
    return true;
}

// ── cycle helpers: wrap points + out-of-range snap (NFR8 degrade) ─────────────

(:test)
function settingsMenuCycleEnum(logger as Test.Logger) as Boolean {
    // Two-value enum: advances, then wraps hi -> lo (INSTANT -> COAST).
    if (SettingsMenu.cycleEnum(SettingsModel.PAUSE_COAST, SettingsModel.PAUSE_COAST,
            SettingsModel.PAUSE_INSTANT) != SettingsModel.PAUSE_INSTANT) {
        logger.error("cycleEnum COAST -> INSTANT"); return false;
    }
    if (SettingsMenu.cycleEnum(SettingsModel.PAUSE_INSTANT, SettingsModel.PAUSE_COAST,
            SettingsModel.PAUSE_INSTANT) != SettingsModel.PAUSE_COAST) {
        logger.error("cycleEnum INSTANT -> COAST (wrap)"); return false;
    }
    // Out-of-range input snaps to lo (bounds-check-and-degrade).
    if (SettingsMenu.cycleEnum(7, 0, 1) != 0) {
        logger.error("cycleEnum out-of-range -> lo"); return false;
    }
    if (SettingsMenu.cycleEnum(-1, 0, 1) != 0) {
        logger.error("cycleEnum negative -> lo"); return false;
    }
    return true;
}

(:test)
function settingsMenuCycleFontSize(logger as Test.Logger) as Boolean {
    // Wraps 0..rampLength-1; the top step wraps back to 0.
    if (SettingsMenu.cycleFontSize(0, 5) != 1) { logger.error("fontSize 0 -> 1"); return false; }
    if (SettingsMenu.cycleFontSize(3, 5) != 4) { logger.error("fontSize 3 -> 4"); return false; }
    if (SettingsMenu.cycleFontSize(4, 5) != 0) { logger.error("fontSize 4 -> 0 (wrap)"); return false; }
    // Out-of-range persisted input snaps into range before cycling (the model
    // stores any fontSize >= 0; the view clamps — the cycle must too).
    if (SettingsMenu.cycleFontSize(99, 5) != 0) { logger.error("fontSize 99 -> 0 (snap hi + wrap)"); return false; }
    if (SettingsMenu.cycleFontSize(-1, 5) != 1) { logger.error("fontSize -1 -> 1 (snap lo + advance)"); return false; }
    return true;
}

(:test)
function settingsMenuCycleAnchorPct(logger as Test.Logger) as Boolean {
    // UX-DR5 user-tunable range: 30..60, step 5, wraps 60 -> 30. The model
    // clamps 0..100 — anything outside the tunable grid snaps to the 35 default.
    if (SettingsMenu.cycleAnchorPct(30) != 35) { logger.error("anchor 30 -> 35"); return false; }
    if (SettingsMenu.cycleAnchorPct(35) != 40) { logger.error("anchor 35 -> 40"); return false; }
    if (SettingsMenu.cycleAnchorPct(55) != 60) { logger.error("anchor 55 -> 60"); return false; }
    if (SettingsMenu.cycleAnchorPct(60) != 30) { logger.error("anchor 60 -> 30 (wrap)"); return false; }
    if (SettingsMenu.cycleAnchorPct(33) != 35) { logger.error("anchor 33 (non-multiple) -> 35"); return false; }
    if (SettingsMenu.cycleAnchorPct(0) != 35) { logger.error("anchor 0 (below range) -> 35"); return false; }
    if (SettingsMenu.cycleAnchorPct(100) != 35) { logger.error("anchor 100 (above range) -> 35"); return false; }
    return true;
}

// ── adaptiveWpmStep: the ONE step-rule encoding (engine + stepper share it) ───

(:test)
function settingsAdaptiveWpmStepTable(logger as Test.Logger) as Boolean {
    // Step keyed on the CURRENT wpm before stepping: 10 below 100, 25 at/above
    // (exactly the Story 3.3 ReaderEngine.adaptiveStep behavior, moved here).
    if (SettingsModel.adaptiveWpmStep(99, true) != 109) { logger.error("99 up -> 109 (step 10)"); return false; }
    if (SettingsModel.adaptiveWpmStep(100, true) != 125) { logger.error("100 up -> 125 (step 25)"); return false; }
    if (SettingsModel.adaptiveWpmStep(100, false) != 75) { logger.error("100 down -> 75 (boundary: step 25)"); return false; }
    if (SettingsModel.adaptiveWpmStep(99, false) != 89) { logger.error("99 down -> 89 (step 10)"); return false; }
    if (SettingsModel.adaptiveWpmStep(250, true) != 275) { logger.error("250 up -> 275"); return false; }
    // Clamps at the WPM range edges (down from MIN stays, up near/at MAX caps).
    if (SettingsModel.adaptiveWpmStep(SettingsModel.WPM_MIN, false) != SettingsModel.WPM_MIN) {
        logger.error("down from WPM_MIN clamps"); return false;
    }
    if (SettingsModel.adaptiveWpmStep(SettingsModel.WPM_MAX, true) != SettingsModel.WPM_MAX) {
        logger.error("up from WPM_MAX clamps"); return false;
    }
    if (SettingsModel.adaptiveWpmStep(995, true) != SettingsModel.WPM_MAX) {
        logger.error("995 up clamps to WPM_MAX"); return false;
    }
    return true;
}

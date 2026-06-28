import Toybox.Lang;
import Toybox.Application.Storage;

// Per-device reading settings (FR15, AR16). Two halves, deliberately separated:
//
//   1. Pure defaults + (de)serialisation — `initialize()`, `applyDict`, `toDict`.
//      The constructor yields every default with ZERO Storage access (AC1): the
//      defaults are a property of the model, not of persisted state.
//   2. A thin persistence adapter — `loadFrom()` / `save()` — that routes the
//      pure dict through Application.Storage under the single StorageKeys.SETTINGS
//      key. This is the ONLY place this class touches Storage.
//
// Settings are per-device and NEVER cross the protocol (AR16) — only position
// syncs. Story 3.3 reads this model for input mapping; Story 3.8 edits it via a
// menu. This story (3.1) owns the model + defaults only — no menu, no input.
module SettingsModel {

    // ── pauseMode (AC1) — typed enum-style constants, no magic numbers ──
    const PAUSE_COAST = 0;   // default: on pause, coast to the next sentence end
    const PAUSE_INSTANT = 1; // stop immediately

    // ── handedness (AC1) ──
    const HAND_RIGHT = 0;    // default
    const HAND_LEFT = 1;

    // ── chapterResume (Story 3.5, AC1) — what a chapter card does after it shows.
    // Auto: card breathes ~2 s then flow resumes; Wait: card holds until START.
    // Read by PlaybackView's chapter-card mode here; the menu UI is Story 3.8.
    const CHAPTER_RESUME_AUTO = 0;   // default
    const CHAPTER_RESUME_WAIT = 1;

    // ── per-device defaults (AC1) ──
    const DEFAULT_WPM = 250;
    const DEFAULT_PAUSE_MODE = PAUSE_COAST;
    const DEFAULT_TOUCH_CONTROLS = true;
    const DEFAULT_FONT_SIZE = 0;          // index into the device font ramp (Story 3.2)
    const DEFAULT_HANDEDNESS = HAND_RIGHT;
    const DEFAULT_FOCUS_HIGHLIGHT = true;
    const DEFAULT_PHANTOM_WORDS = true;
    const DEFAULT_ANCHOR_PCT = 35;        // ORP anchor, percent from the left edge
    const DEFAULT_CHAPTER_RESUME = CHAPTER_RESUME_AUTO;

    // WPM clamp range (addendum #2 — resolved value, supersedes stale epics FR3).
    const WPM_MIN = 10;
    const WPM_MAX = 1000;

    // Dict keys for the persistence adapter (private to this module's seam).
    const KEY_WPM = "wpm";
    const KEY_PAUSE_MODE = "pauseMode";
    const KEY_TOUCH_CONTROLS = "touchControls";
    const KEY_FONT_SIZE = "fontSize";
    const KEY_HANDEDNESS = "handedness";
    const KEY_FOCUS_HIGHLIGHT = "focusHighlight";
    const KEY_PHANTOM_WORDS = "phantomWords";
    const KEY_ANCHOR_PCT = "anchorPct";
    const KEY_CHAPTER_RESUME = "chapterResume";

    class Settings {
        public var wpm as Number;
        public var pauseMode as Number;
        public var touchControls as Boolean;
        public var fontSize as Number;
        public var handedness as Number;
        public var focusHighlight as Boolean;
        public var phantomWords as Boolean;
        public var anchorPct as Number;
        public var chapterResume as Number;

        // Pure default construction — NO Storage access (AC1). Persisted values
        // are layered on afterwards via loadFrom(), never in the default path.
        function initialize() {
            wpm = DEFAULT_WPM;
            pauseMode = DEFAULT_PAUSE_MODE;
            touchControls = DEFAULT_TOUCH_CONTROLS;
            fontSize = DEFAULT_FONT_SIZE;
            handedness = DEFAULT_HANDEDNESS;
            focusHighlight = DEFAULT_FOCUS_HIGHLIGHT;
            phantomWords = DEFAULT_PHANTOM_WORDS;
            anchorPct = DEFAULT_ANCHOR_PCT;
            chapterResume = DEFAULT_CHAPTER_RESUME;
        }

        // Apply a persisted dict over the current values. Pure and Storage-free
        // (the test seam): each field is type- and range-checked; anything
        // missing or malformed leaves the current (default) value untouched —
        // bounds-check-and-degrade, never crash (NFR8/AR24). A null dict (no
        // saved settings yet) is a no-op, preserving defaults.
        function applyDict(d as Dictionary?) as Void {
            if (d == null) {
                return;
            }
            wpm = clampWpm(readNumber(d, KEY_WPM, wpm));
            pauseMode = readEnum(d, KEY_PAUSE_MODE, pauseMode, PAUSE_COAST, PAUSE_INSTANT);
            handedness = readEnum(d, KEY_HANDEDNESS, handedness, HAND_RIGHT, HAND_LEFT);
            chapterResume = readEnum(d, KEY_CHAPTER_RESUME, chapterResume, CHAPTER_RESUME_AUTO, CHAPTER_RESUME_WAIT);
            fontSize = readNonNegative(d, KEY_FONT_SIZE, fontSize);
            anchorPct = readPercent(d, KEY_ANCHOR_PCT, anchorPct);
            touchControls = readBoolean(d, KEY_TOUCH_CONTROLS, touchControls);
            focusHighlight = readBoolean(d, KEY_FOCUS_HIGHLIGHT, focusHighlight);
            phantomWords = readBoolean(d, KEY_PHANTOM_WORDS, phantomWords);
        }

        // Pure serialisation of the current values (the test seam).
        function toDict() as Dictionary {
            return {
                KEY_WPM => wpm,
                KEY_PAUSE_MODE => pauseMode,
                KEY_TOUCH_CONTROLS => touchControls,
                KEY_FONT_SIZE => fontSize,
                KEY_HANDEDNESS => handedness,
                KEY_FOCUS_HIGHLIGHT => focusHighlight,
                KEY_PHANTOM_WORDS => phantomWords,
                KEY_ANCHOR_PCT => anchorPct,
                KEY_CHAPTER_RESUME => chapterResume
            };
        }

        // ── thin persistence adapter (the ONLY Storage access) ──

        // Overlay any persisted settings onto the defaults. Safe to call on a
        // fresh install: getValue returns null and applyDict keeps the defaults.
        function loadFrom() as Void {
            applyDict(Storage.getValue(StorageKeys.SETTINGS) as Dictionary?);
        }

        function save() as Void {
            Storage.setValue(StorageKeys.SETTINGS, toDict() as Storage.ValueType);
        }

        // ── private validation helpers ──

        private function clampWpm(value as Number) as Number {
            if (value < WPM_MIN) { return WPM_MIN; }
            if (value > WPM_MAX) { return WPM_MAX; }
            return value;
        }

        private function readNumber(d as Dictionary, key as String, fallback as Number) as Number {
            var v = d[key];
            if (v instanceof Lang.Number) { return v as Number; }
            return fallback;
        }

        private function readNonNegative(d as Dictionary, key as String, fallback as Number) as Number {
            var v = readNumber(d, key, fallback);
            return v < 0 ? fallback : v;
        }

        private function readPercent(d as Dictionary, key as String, fallback as Number) as Number {
            var v = readNumber(d, key, fallback);
            return (v < 0 || v > 100) ? fallback : v;
        }

        private function readEnum(d as Dictionary, key as String, fallback as Number, lo as Number, hi as Number) as Number {
            var v = readNumber(d, key, fallback);
            return (v < lo || v > hi) ? fallback : v;
        }

        private function readBoolean(d as Dictionary, key as String, fallback as Boolean) as Boolean {
            var v = d[key];
            if (v instanceof Lang.Boolean) { return v as Boolean; }
            return fallback;
        }
    }
}

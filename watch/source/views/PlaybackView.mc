import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// The watch RSVP render surface + the timer-driven render loop that drives the
// Story 3.1 ReaderEngine over the Epic-3 canned word source — the first pixels of
// Epic 3 (FR1, FR7). It OWNS the engine/source/settings/timer; it only READS
// engine state and never lets the engine reference it back (AR15, refcount GC, no
// cycle collection).
//
// Scope (Story 3.2): ORP word composition, split guides, phantoms, long-word
// margin-clamp, burn-in jitter, and the per-word timer loop with auto-play on show.
// OUT: the input map / playback controls (Story 3.3), the paused progress readout
// + context view (Story 3.4) — this view draws NO persistent bright chrome while
// words flow ("the screen owes the reader nothing but the word").
class PlaybackView extends WatchUi.View {

    // ── DESIGN palette (DESIGN.md Colors 102-113) — one place, by name, no inline
    // hex at draw sites. "One red, one job": PIVOT is the pivot letter + anchor
    // ticks only, never chrome.
    private const COLOR_VOID = 0x000000;       // true-black AMOLED canvas
    private const COLOR_INK = 0xEAE6DF;         // focal word
    private const COLOR_INK_FAINT = 0x45423E;   // guides + phantoms
    private const COLOR_PIVOT = 0xFF5349;       // pivot letter + anchor ticks

    // ── composition geometry (DESIGN / mockups/key-playback.html, a 454-px
    // starting point — recalibrated against dc.getWidth()/measured widths, never
    // hardcoding 454). The anchor column comes from dc.getWidth(); these offsets
    // are absolute px tuned for the 454-px fenix847mm target.
    private const WATCH_EDGE = 28;        // guide-hairline span inset / normal margin
    // The focal word may use a smaller inset than the guides: at the vertical center
    // of a ROUND display the full diameter is available, so a wide word can fill more
    // width (and thus take a larger, more legible native font) without clipping on
    // the corners. Fit-to-width and the focal word's margin-clamp both use this.
    private const FOCAL_EDGE = 8;         // AC4 focal-word fit/clamp inset
    private const HAIRLINE_OFFSET = 44;   // guide hairline distance above/below center
    private const GAP_HALF = 16;          // half-width of the anchor-column gap
    private const TICK_LEN = 10;          // anchor-tick length
    private const PHANTOM_GAP = 18;       // gap between focal word and a phantom

    // ── word-display font ramp (font seam, Task 5 — resolved in ONE place via
    // fontFor()). Native font ramp = the documented escape hatch (DESIGN typography;
    // architecture.md:305): index 0 is the largest native text face (the default
    // reading size); higher indices step DOWN. The Atkinson Hyperlegible BMFont is a
    // localized later swap behind THIS seam, its own follow-up story — not here.
    private const RAMP_LENGTH = 5;

    // ── timer ──
    private const TIMER_FLOOR_MS = 50;    // platform timer floor (AR13)

    private var _settings as SettingsModel.Settings;
    private var _source as CannedWordSource;
    private var _engine as Reader.ReaderEngine;
    private var _timer as Timer.Timer;
    private var _fontIndex as Number;

    // Per-session burn-in jitter applied to the WHOLE composition (AC5). Bounded
    // random walk in [-2, +2] px; recomputed per session/per-pause, NEVER per word
    // (the anchor must feel stable while reading).
    private var _jitterX as Number;
    private var _jitterY as Number;

    function initialize() {
        View.initialize();
        _settings = new SettingsModel.Settings();
        _settings.loadFrom(); // overlay persisted values; defaults on fresh install
        _source = new CannedWordSource(); // decodes the dev stream once, at startup
        _engine = new Reader.ReaderEngine(_source, _settings.wpm, _settings.pauseMode);
        // Resolve the unbounded persisted fontSize against the ramp (3.1 deferred #1).
        _fontIndex = OrpLayout.clampFontIndex(_settings.fontSize, RAMP_LENGTH);
        _timer = new Timer.Timer();
        _jitterX = 0;
        _jitterY = 0;
    }

    // Auto-play on show so playback is demonstrable without input (Story 3.3 owns
    // controls). One machine-readable readiness marker to the app log — NEVER a
    // per-word println (the 700-WPM logging anti-pattern, AR25).
    function onShow() as Void {
        recomputeJitter();
        _engine.play(System.getTimer()); // re-arms the 3-beat ramp; no-op if empty
        System.println(Lang.format("PlaybackView ready: words=$1$ wpm=$2$ fontIdx=$3$",
            [_source.wordCount(), _engine.wpm(), _fontIndex]));
        armTimer();
    }

    function onHide() as Void {
        _timer.stop();
    }

    // Timer fire: drive time forward, repaint the now-selected word, then re-arm to
    // the NEXT word's duration (NOT a fixed coarse tick — a fixed tick at high WPM
    // hits the engine's 4-word catch-up cap every tick and defeats drift-free
    // accumulation; resolves Story 3.1 deferred #4, architecture AR13). The engine
    // imports no System; the view supplies `now` via System.getTimer().
    function onTimerTick() as Void {
        _engine.onTick(System.getTimer());
        WatchUi.requestUpdate();
        if (_engine.isPlaying() || _engine.isRamping()) {
            armTimer();
        } else {
            // Paused / finished: stop ticking (no runaway timer, no per-tick work
            // while frozen) and refresh the burn-in jitter for the still frame.
            recomputeJitter();
        }
    }

    private function armTimer() as Void {
        var interval = _engine.currentDuration();
        if (interval < TIMER_FLOOR_MS) {
            interval = TIMER_FLOOR_MS;
        }
        _timer.start(method(:onTimerTick), interval, false); // one-shot, re-armed
    }

    // Draw ONLY the already-selected word — no advancement here (all advancement is
    // in onTimerTick; architecture.md:287). Cheap: clear + one word + guides +
    // phantoms, so the firmware onUpdate watchdog is never at risk.
    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_TRANSPARENT, COLOR_VOID);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var anchorCol = OrpLayout.anchorX(w, _settings.anchorPct) + _jitterX;
        var cy = h / 2 + _jitterY;

        // Start ramp: the engine owns the 3-2-1 count/timing (Story 3.1); this view
        // owns the pixels. Countdown centered on the anchor in Ink — no word, no
        // phantoms (AC5 support).
        if (_engine.isRamping()) {
            drawGuides(dc, anchorCol, cy, w);
            dc.setColor(COLOR_INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(anchorCol, cy, fontFor(_fontIndex), _engine.rampRemaining().toString(),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var rec = _engine.currentRecord();
        if (rec == null) {
            // Unbuffered / empty book — draw nothing for the word, keep the frame
            // (bounds-check-and-degrade, NFR8/AR24).
            drawGuides(dc, anchorCol, cy, w);
            return;
        }

        drawGuides(dc, anchorCol, cy, w);
        drawWord(dc, rec, anchorCol, cy, w);
    }

    // Split guide marks (AC2): split hairlines above/below in Ink-Faint with a gap
    // at the anchor column, and short anchor ticks in Pivot. The GEOMETRY (gap +
    // ticks), not color alone, points at the pivot — color-blind safe (UX-DR24).
    private function drawGuides(dc as Graphics.Dc, anchorCol as Number, cy as Number, w as Number) as Void {
        var left = WATCH_EDGE + _jitterX;
        var right = w - WATCH_EDGE + _jitterX;
        var topY = cy - HAIRLINE_OFFSET;
        var botY = cy + HAIRLINE_OFFSET;

        dc.setColor(COLOR_INK_FAINT, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        // Hairlines, split by a gap centered on the anchor column.
        dc.drawLine(left, topY, anchorCol - GAP_HALF, topY);
        dc.drawLine(anchorCol + GAP_HALF, topY, right, topY);
        dc.drawLine(left, botY, anchorCol - GAP_HALF, botY);
        dc.drawLine(anchorCol + GAP_HALF, botY, right, botY);

        // Anchor ticks: short vertical ticks in Pivot pointing inward at the pivot.
        dc.setColor(COLOR_PIVOT, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(anchorCol, topY, anchorCol, topY + TICK_LEN);          // down from top hairline
        dc.drawLine(anchorCol, botY - TICK_LEN, anchorCol, botY);          // up from bottom hairline
    }

    // Compose the focal word with the pivot's CENTER on the anchor column (AC1), so
    // the anchor does not move between words. Phantoms flank it (AC3). A word wider
    // than usable width is shown WHOLE, clamped at the margin with the pivot allowed
    // to drift off-anchor — never truncated/hyphenated (AC4).
    private function drawWord(dc as Graphics.Dc, rec as StreamDecoder.WordRecord,
                              anchorCol as Number, cy as Number, w as Number) as Void {
        var usable = w - 2 * FOCAL_EDGE;
        // Long-word fit-to-width (AC4 / DESIGN.md:131 "show whole"): a word wider
        // than the available width at the base font would run off the round display.
        // Step DOWN the font ramp to the LARGEST size whose whole-word width still
        // fits the focal budget (best-effort: the smallest ramp font if nothing fits)
        // — show whole at the most legible size that fits, never truncate/hyphenate.
        // The Atkinson BMFont swap re-tunes this behind the same seam (Font decision).
        // Normal words fit at the base font and keep it.
        var font = fontFor(fitFontIndex(dc, rec.word, usable));
        var parts = OrpLayout.splitAtPivot(rec.word, rec.orpPivot);
        var before = parts[0];
        var pivot = parts[1];
        var after = parts[2];

        var beforeW = dc.getTextWidthInPixels(before, font);
        var pivotW = dc.getTextWidthInPixels(pivot, font);
        var afterW = dc.getTextWidthInPixels(after, font);

        // Pivot centered on the anchor -> the whole word's three segment origins.
        var pivotLeftX = anchorCol - pivotW / 2;
        var beforeLeftX = pivotLeftX - beforeW;
        var afterLeftX = pivotLeftX + pivotW;

        // Bidirectional margin-clamp (AC4): anchoring the pivot at 35% can push a
        // long word past EITHER margin (the pivot is often near the word's start, so
        // the tail overruns the RIGHT edge). Shift the whole word so it sits inside
        // [marginLeft, marginRight]; the pivot drifts off-anchor. After fit-to-width
        // the word fits the focal budget, so it always fits between these margins and
        // at most one side overflows — never truncate, never hyphenate.
        var marginLeft = FOCAL_EDGE + _jitterX;
        var marginRight = w - FOCAL_EDGE + _jitterX;
        var shift = 0;
        if (beforeLeftX < marginLeft) {
            shift = marginLeft - beforeLeftX;            // overran left -> shift right
        } else if (afterLeftX + afterW > marginRight) {
            shift = marginRight - (afterLeftX + afterW); // overran right -> shift left
        }
        beforeLeftX += shift;
        pivotLeftX += shift;
        afterLeftX += shift;

        // Phantoms (AC3): previous/next words flank the focal word at the same
        // baseline in Ink-Faint, with a gap; null neighbours simply draw nothing.
        // FLAG_CONTINUATION is reserved (MUST be 0 in v1) — no branch on it (AC4).
        if (_settings.phantomWords) {
            dc.setColor(COLOR_INK_FAINT, Graphics.COLOR_TRANSPARENT);
            var prev = _source.wordAt(_engine.index() - 1);
            if (prev != null) {
                dc.drawText(beforeLeftX - PHANTOM_GAP, cy, font, prev.word,
                    Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            }
            var next = _source.wordAt(_engine.index() + 1);
            if (next != null) {
                dc.drawText(afterLeftX + afterW + PHANTOM_GAP, cy, font, next.word,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            }
        }

        // Focal word. Pivot in Pivot iff focusHighlight; else Ink (the guide gap +
        // ticks still point at it — color-blind safe, AC2). before/after in Ink.
        dc.setColor(COLOR_INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(beforeLeftX, cy, font, before,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(afterLeftX, cy, font, after,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(_settings.focusHighlight ? COLOR_PIVOT : COLOR_INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(pivotLeftX, cy, font, pivot,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Font seam (Task 5): the word-display face resolved in ONE place. Native ramp
    // = the documented escape hatch; index 0 is the largest native text face.
    private function fontFor(index as Number) as Graphics.FontType {
        if (index <= 0) { return Graphics.FONT_SYSTEM_LARGE; }
        if (index == 1) { return Graphics.FONT_SYSTEM_MEDIUM; }
        if (index == 2) { return Graphics.FONT_SYSTEM_SMALL; }
        if (index == 3) { return Graphics.FONT_SYSTEM_TINY; }
        return Graphics.FONT_SYSTEM_XTINY;
    }

    // The largest ramp index at or below the base font whose WHOLE-word width fits
    // `usable` (AC4 fit-to-width). Returns the base index for normal words (they fit
    // immediately) and the smallest ramp font if even that overflows (best effort —
    // never truncate). A handful of measurements, only for the focal word.
    private function fitFontIndex(dc as Graphics.Dc, word as String, usable as Number) as Number {
        var idx = _fontIndex;
        while (idx < RAMP_LENGTH - 1) {
            if (!OrpLayout.needsMarginClamp(dc.getTextWidthInPixels(word, fontFor(idx)), usable)) {
                return idx;
            }
            idx += 1;
        }
        return idx;
    }

    // Bounded ±2px random walk for the whole composition (AC5 burn-in). Math.rand()
    // is non-negative; (rand % 3) - 1 yields a -1/0/+1 step, clamped to [-2, 2].
    private function recomputeJitter() as Void {
        _jitterX = clampJitter(_jitterX + (Math.rand() % 3) - 1);
        _jitterY = clampJitter(_jitterY + (Math.rand() % 3) - 1);
    }

    private function clampJitter(v as Number) as Number {
        if (v < -2) { return -2; }
        if (v > 2) { return 2; }
        return v;
    }
}

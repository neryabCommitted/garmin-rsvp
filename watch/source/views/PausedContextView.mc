import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// The context-on-pause scroll view (Story 3.4, AC2 — FR11). Pushed over the paused
// PlaybackView; shows the SURROUNDING PARAGRAPH as wrapped, left-aligned, scrollable
// text with the CURRENT word marked by BRIGHTNESS (Ink against the Ink-Dim body),
// never a second accent color (DESIGN: hierarchy is brightness, "one red, one job").
//
// Implemented as a WatchUi.CustomMenu (NOT a raw View): the native widget provides
// the FLUID kinetic/momentum scroll on touch AND native UP/DOWN button scroll — the
// community-confirmed way to get that feel (replicating CustomMenu's animated scroll
// by hand is "significant effort"; forums.garmin.com Menu2/CustomMenu threads). Each
// wrapped line is a CustomMenuItem (PausedContextLine) that paints its own words.
// Menu chrome is suppressed to honor "text on void, scrolled by the user": theme null
// (no selection theme), dividerType null (no top/bottom divider lines), background =
// void. The reading screen stays read-only — we never need per-item tap coordinates
// (the one CustomMenu limitation), so it is a clean fit.
//
// It holds only the (read-only) line items; it does NOT reference the engine or
// PlaybackView (no GC cycle, AR15). The position is a SNAPSHOT — paused, so the index
// will not change while open. BACK pops back to the paused PlaybackView (AC3, handled
// in PausedContextDelegate); the PlaybackView.onShow IDLE-guard keeps it PAUSED.
//
// No watchdog risk: the paragraph (tens of words) is wrapped ONCE here in initialize()
// — at construction, OUTSIDE any timer/BLE callback — and the items only blit their
// cached words on draw. Wrapping needs text measurement (getTextWidthInPixels), which
// needs a Dc before any item exists, so we measure against a one-shot offscreen
// BufferedBitmap Dc (Graphics.createBufferedBitmap(...).get().getDc()), degrading to
// one word per line if the buffer can't be allocated (NFR8/AR24, never crash).
class PausedContextView extends WatchUi.CustomMenu {

    // ── DESIGN palette (background; the per-line ink/ink-dim live in PausedContextLine,
    // by name, no inline hex at draw sites).
    private const COLOR_VOID = 0x000000;

    // context-body face (DESIGN 26px target). Native fallback behind the same font
    // seam as PlaybackView's word face — the Atkinson Hyperlegible BMFont swap is its
    // own later story; here we name a native face, no inline magic.
    private const CONTEXT_FONT = Graphics.FONT_SYSTEM_SMALL;

    // Left/right inset for the wrapped text inside the round face (the focused line
    // sits at the vertical center where full width is available; PausedContextLine
    // starts its text at this same inset so wrap width and draw width agree).
    private const MARGIN = 30;

    // Fallback line height when no measuring Dc is available (degrade path only).
    private const FALLBACK_LINE_H = 32;

    function initialize(source as BookWordSource, currentIndex as Number) {
        // Paragraph bounds (pure PausedLayout). The current word lies within
        // [pStart, pEnd]; a stream with no FLAG_PARAGRAPH_START degrades to the whole
        // book as one bounded paragraph.
        var pStart = PausedLayout.paragraphStartAtOrBefore(source, currentIndex);
        var pEnd = PausedLayout.paragraphEndAtOrAfter(source, currentIndex);

        var screenW = System.getDeviceSettings().screenWidth;
        var usable = screenW - 2 * MARGIN;
        if (usable < 1) { usable = screenW; }

        // One-shot offscreen Dc just for text measurement (community workaround for
        // "measure before a real Dc exists"). createBufferedBitmap exists at our min
        // API (5.2.0); guard the result and degrade if it can't be allocated.
        var mdc = measuringDc(screenW);
        var lineHeight = FALLBACK_LINE_H;
        if (mdc != null) {
            lineHeight = mdc.getFontHeight(CONTEXT_FONT);
        }

        // Wrap into lines: parallel arrays of word strings and their absolute indices,
        // plus the index of the line that holds currentIndex (for initial focus).
        var lineWords = [] as Array<Array<String>>;
        var lineIdx = [] as Array<Array<Number>>;
        var currentLine = wrap(source, pStart, pEnd, currentIndex, mdc, usable, lineWords, lineIdx);

        // Build the CustomMenu: suppress menu chrome so it reads as plain text on void.
        CustomMenu.initialize(lineHeight, COLOR_VOID, {
            :focus => currentLine,
            :theme => null,
            :dividerType => null
        });

        for (var li = 0; li < lineWords.size(); li++) {
            addItem(new PausedContextLine(li, lineWords[li], lineIdx[li], currentIndex,
                CONTEXT_FONT, MARGIN));
        }
    }

    // The one-shot measuring Dc, or null if a buffer can't be allocated (degrade).
    private function measuringDc(screenW as Number) as Graphics.Dc? {
        if (!(Graphics has :createBufferedBitmap)) {
            return null;
        }
        var ref = Graphics.createBufferedBitmap({:width => screenW, :height => 50});
        // .get() on the reference returns a broad resource union (BufferedBitmap /
        // BitmapResource / FontResource / Null); narrow to BufferedBitmap so getDc()
        // resolves at Strict L3 and a non-buffer/null result degrades to no-measure.
        var buf = ref.get();
        if (buf instanceof Graphics.BufferedBitmap) {
            return buf.getDc();
        }
        return null;
    }

    // Greedy word-wrap of [pStart, pEnd] into `lineWords`/`lineIdx` (filled in place).
    // Returns the line index containing `currentIndex` (0 if not found). Null records
    // are skipped (bounds-check-and-degrade). With no measuring Dc, each word becomes
    // its own line — bounded and scrollable, never a crash.
    private function wrap(source as BookWordSource, pStart as Number, pEnd as Number,
                          currentIndex as Number, mdc as Graphics.Dc?, usable as Number,
                          lineWords as Array<Array<String>>, lineIdx as Array<Array<Number>>) as Number {
        var spaceW = mdc != null ? mdc.getTextWidthInPixels(" ", CONTEXT_FONT) : 0;
        var curWords = [] as Array<String>;
        var curIdx = [] as Array<Number>;
        var curWidth = 0;
        var currentLine = 0;

        for (var k = pStart; k <= pEnd; k++) {
            var rec = source.wordAt(k);
            if (rec == null) {
                continue;
            }
            var word = rec.word;
            var wW = mdc != null ? mdc.getTextWidthInPixels(word, CONTEXT_FONT) : usable + 1;
            var addW = curWords.size() == 0 ? wW : spaceW + wW;
            // A word that would overrun the usable width starts a new line (unless the
            // line is empty — a single over-wide word is shown whole, never truncated).
            // With no Dc, wW forces one word per line.
            if (curWords.size() > 0 && curWidth + addW > usable) {
                lineWords.add(curWords);
                lineIdx.add(curIdx);
                curWords = [] as Array<String>;
                curIdx = [] as Array<Number>;
                curWidth = 0;
                addW = wW;
            }
            if (k == currentIndex) {
                currentLine = lineWords.size(); // the line this word lands on
            }
            curWords.add(word);
            curIdx.add(k);
            curWidth += addW;
        }
        if (curWords.size() > 0) {
            lineWords.add(curWords);
            lineIdx.add(curIdx);
        }
        // Clamp focus into range (openContextView guarantees >= 1 word, so >= 1 line).
        if (currentLine < 0) { currentLine = 0; }
        if (currentLine > lineWords.size() - 1) {
            currentLine = lineWords.size() > 0 ? lineWords.size() - 1 : 0;
        }
        return currentLine;
    }
}

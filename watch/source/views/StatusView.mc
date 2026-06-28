import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// One render-only shell for the four system states (Story 3.5, AC3 — FR6):
// WaitingForPhone, Buffering, BookChanged, StorageFull. Parameterized by a
// StatusLayout.STATE_* id (+ an optional title for BookChanged). It draws ONE
// plain-text sentence in Ink-Dim, centered in the safe square on Void — no icons,
// no spinners (DESIGN.md:155, anti-patterns 165). The only motion allowed is the
// Buffering dot cycle (AC3 "minimal indeterminate dot cycle").
//
// Render-only: NO delegate, NO controls. The triggers that route to these states
// — and BookChanged's one-tap acknowledge — are wired in Epic 4. In Epic 3 the
// shells have no trigger; they are eyeballed on device by temporarily pointing
// getInitialView here (never committed). The pure copy lives in StatusLayout so
// this view holds zero inline strings.
//
// All copy is decided by StatusLayout (host-tested); this class only lays out the
// pixels, so its correctness is the on-device visual check (Task 9), not a host
// test (it needs a Dc / WatchUi).
class StatusView extends WatchUi.View {

    private const COLOR_VOID = 0x000000;     // true-black AMOLED canvas
    private const COLOR_INK_DIM = 0x8A867F;  // status sentence (Ink-Dim, DESIGN 103)

    // Inset from each edge so the wrapped text stays inside the round face's safe
    // square (~320 px on the 454-px fenix847mm). Tuned on device.
    private const SAFE_INSET = 50;
    private const STATUS_FONT = Graphics.FONT_SYSTEM_SMALL;

    // Buffering dot-cycle cadence and the timer that drives it.
    private const BUFFER_TICK_MS = 400;

    private var _stateId as Number;
    private var _title as String?;
    private var _timer as Timer.Timer?;
    private var _dotCount as Number;

    function initialize(stateId as Number, title as String?) {
        View.initialize();
        _stateId = stateId;
        _title = title;
        _timer = null;
        _dotCount = 1;
    }

    // Buffering animates a dot cycle; the other three states are static (no timer,
    // no per-tick work). The timer is allocated lazily only for Buffering.
    function onShow() as Void {
        if (_stateId == StatusLayout.STATE_BUFFERING) {
            if (_timer == null) {
                _timer = new Timer.Timer();
            }
            _timer.start(method(:onBufferTick), BUFFER_TICK_MS, true); // repeating
        }
        WatchUi.requestUpdate();
    }

    function onHide() as Void {
        if (_timer != null) {
            _timer.stop();
        }
    }

    // Cycle the dot count 1 -> 2 -> 3 -> 1 and repaint (Buffering only).
    function onBufferTick() as Void {
        _dotCount = _dotCount % 3 + 1;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_TRANSPARENT, COLOR_VOID);
        dc.clear();

        var text = _stateId == StatusLayout.STATE_BUFFERING
            ? StatusLayout.bufferingText(_dotCount)
            : StatusLayout.statusSentence(_stateId, _title);

        var w = dc.getWidth();
        var h = dc.getHeight();
        var usable = w - 2 * SAFE_INSET;
        if (usable < 1) { usable = w; }

        dc.setColor(COLOR_INK_DIM, Graphics.COLOR_TRANSPARENT);
        drawCenteredWrapped(dc, text, w / 2, h / 2, usable);
    }

    // Greedy word-wrap of a single sentence into lines fitting `usable`, drawn
    // centered as a block on (cx, cy). A sentence is a handful of words — measuring
    // here in onUpdate is cheap (no watchdog risk). An over-wide single word is
    // shown whole on its own line (never truncated — NFR8/AR24).
    private function drawCenteredWrapped(dc as Graphics.Dc, text as String,
                                         cx as Number, cy as Number, usable as Number) as Void {
        var words = splitWords(text);
        var lineH = dc.getFontHeight(STATUS_FONT);
        var spaceW = dc.getTextWidthInPixels(" ", STATUS_FONT);

        var lines = [] as Array<String>;
        var cur = "";
        var curW = 0;
        for (var i = 0; i < words.size(); i++) {
            var word = words[i];
            var wW = dc.getTextWidthInPixels(word, STATUS_FONT);
            var addW = cur.equals("") ? wW : spaceW + wW;
            if (!cur.equals("") && curW + addW > usable) {
                lines.add(cur);
                cur = word;
                curW = wW;
            } else {
                cur = cur.equals("") ? word : cur + " " + word;
                curW += addW;
            }
        }
        if (!cur.equals("")) {
            lines.add(cur);
        }
        if (lines.size() == 0) {
            return;
        }

        // Center the block of lines vertically on cy.
        var startY = cy - (lines.size() - 1) * lineH / 2;
        for (var li = 0; li < lines.size(); li++) {
            dc.drawText(cx, startY + li * lineH, STATUS_FONT, lines[li],
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Split on ASCII spaces (the only separator in the status copy). Empty book of
    // words degrades to a single-element array, never a crash.
    private function splitWords(text as String) as Array<String> {
        var out = [] as Array<String>;
        var chars = text.toCharArray();
        var cur = "";
        for (var i = 0; i < chars.size(); i++) {
            if (chars[i] == ' ') {
                if (!cur.equals("")) {
                    out.add(cur);
                    cur = "";
                }
            } else {
                cur += chars[i].toString();
            }
        }
        if (!cur.equals("")) {
            out.add(cur);
        }
        return out;
    }
}

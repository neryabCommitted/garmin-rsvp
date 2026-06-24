import Toybox.Lang;
import Toybox.Test;

// Host-side tests for the pure paused/context helpers (Story 3.4, AC1/AC2). Run
// under matco/action-connectiq-tester (SDK 8.4.0, fenix847mm) at Strict level 3.
// No Test.assert* API in this repo — assert via conditionals + logger.error +
// return false (mirrors OrpLayoutTest/ReaderEngineTest/SmokeTest).
module PausedLayoutTestSupport {

    // A 10-word book with KNOWN paragraph boundaries and bonusMs, mirroring the
    // ReaderEngineTestSupport.sampleWords() shape (word 0 carries
    // FLAG_PARAGRAPH_START | FLAG_CHAPTER_START). Paragraph starts at 0, 3, 7 →
    // paragraphs [0..2], [3..6], [7..9]. Bonus sum over [3..6] = 70, over [0..9] = 350.
    function paraWords() as Array<StreamDecoder.WordRecord> {
        var para = Protocol.FLAG_PARAGRAPH_START | Protocol.FLAG_CHAPTER_START;
        var p = Protocol.FLAG_PARAGRAPH_START;
        var se = Protocol.FLAG_SENTENCE_END;
        return [
            new StreamDecoder.WordRecord("Alpha", para, 0, 0),
            new StreamDecoder.WordRecord("bravo", 0, 0, 10),
            new StreamDecoder.WordRecord("charlie", 0, 0, 20),
            new StreamDecoder.WordRecord("Delta", p, 0, 0),
            new StreamDecoder.WordRecord("echo", 0, 0, 30),
            new StreamDecoder.WordRecord("foxtrot", 0, 0, 0),
            new StreamDecoder.WordRecord("golf", 0, 0, 40),
            new StreamDecoder.WordRecord("Hotel", p, 0, 0),
            new StreamDecoder.WordRecord("india", 0, 0, 50),
            new StreamDecoder.WordRecord("juliet.", se, 0, 200)
        ] as Array<StreamDecoder.WordRecord>;
    }

    // A 5-word book with NO FLAG_PARAGRAPH_START anywhere — the degrade fixture:
    // the whole book is one (scrollable) paragraph (start 0, end count-1).
    function noParaWords() as Array<StreamDecoder.WordRecord> {
        return [
            new StreamDecoder.WordRecord("one", 0, 0, 0),
            new StreamDecoder.WordRecord("two", 0, 0, 5),
            new StreamDecoder.WordRecord("three", 0, 0, 5),
            new StreamDecoder.WordRecord("four", 0, 0, 5),
            new StreamDecoder.WordRecord("five.", Protocol.FLAG_SENTENCE_END, 0, 5)
        ] as Array<StreamDecoder.WordRecord>;
    }

    function paraSource() as FakeWordSource {
        return new FakeWordSource(paraWords());
    }

    function noParaSource() as FakeWordSource {
        return new FakeWordSource(noParaWords());
    }
}

// ── AC1: book percent ─────────────────────────────────────────────────────────

(:test)
function pausedBookPercent(logger as Test.Logger) as Boolean {
    if (PausedLayout.bookPercent(0, 10) != 0) { logger.error("bookPercent(0,10) != 0"); return false; }
    if (PausedLayout.bookPercent(5, 10) != 55) { logger.error("bookPercent(5,10) != 55"); return false; }
    // Last word reads 100% (denominator is wordCount-1).
    if (PausedLayout.bookPercent(9, 10) != 100) { logger.error("bookPercent(9,10) != 100"); return false; }
    // wordCount <= 1 edges: empty -> 0, single word -> 100, never div-by-zero.
    if (PausedLayout.bookPercent(0, 0) != 0) { logger.error("bookPercent(0,0) != 0"); return false; }
    if (PausedLayout.bookPercent(0, 1) != 100) { logger.error("bookPercent(0,1) != 100"); return false; }
    // Out-of-range index clamps to [0,100].
    if (PausedLayout.bookPercent(-3, 10) != 0) { logger.error("bookPercent(-3,10) != 0"); return false; }
    if (PausedLayout.bookPercent(99, 10) != 100) { logger.error("bookPercent(99,10) != 100"); return false; }
    return true;
}

// ── AC1: time-remaining math (integer truncation pinned) ──────────────────────

(:test)
function pausedTimeRemainingMs(logger as Test.Logger) as Boolean {
    // Clean divisor: 60000/250 = 240. 5*240 + 350 = 1550.
    if (PausedLayout.timeRemainingMs(5, 250, 350) != 1550) { logger.error("timeRemainingMs clean != 1550"); return false; }
    // Non-divisor WPM 350: 60000/350 = 171 (truncated). 10*171 + 100 = 1810.
    if (PausedLayout.timeRemainingMs(10, 350, 100) != 1810) { logger.error("timeRemainingMs trunc != 1810"); return false; }
    // WPM floor 10: 60000/10 = 6000ms beat. 2*6000 + 0 = 12000.
    if (PausedLayout.timeRemainingMs(2, 10, 0) != 12000) { logger.error("timeRemainingMs floor != 12000"); return false; }
    return true;
}

// ── AC1: human time-left formatting ───────────────────────────────────────────

(:test)
function pausedFormatRemaining(logger as Test.Logger) as Boolean {
    if (!PausedLayout.formatRemaining(0).equals("0:00")) { logger.error("format(0) != 0:00"); return false; }
    if (!PausedLayout.formatRemaining(-5000).equals("0:00")) { logger.error("format(neg) != 0:00"); return false; }
    // Sub-minute: 42000ms -> 0:42.
    if (!PausedLayout.formatRemaining(42000).equals("0:42")) { logger.error("format(42000) != 0:42"); return false; }
    // Minutes, seconds zero-padded: 65000ms = 1m5s -> 1:05.
    if (!PausedLayout.formatRemaining(65000).equals("1:05")) { logger.error("format(65000) != 1:05"); return false; }
    if (!PausedLayout.formatRemaining(725000).equals("12:05")) { logger.error("format(725000) != 12:05"); return false; }
    // >= 1h: 3725000ms = 1h2m5s -> 1:02:05 (minutes field zero-padded).
    if (!PausedLayout.formatRemaining(3725000).equals("1:02:05")) { logger.error("format(3725000) != 1:02:05"); return false; }
    return true;
}

// ── AC1: bonus sum over a range ───────────────────────────────────────────────

(:test)
function pausedSumBonusMs(logger as Test.Logger) as Boolean {
    var src = PausedLayoutTestSupport.paraSource();
    // [3..6] = 0 + 30 + 0 + 40 = 70.
    if (PausedLayout.sumBonusMs(src, 3, 6) != 70) { logger.error("sumBonusMs[3..6] != 70"); return false; }
    // Whole book [0..9] = 350.
    if (PausedLayout.sumBonusMs(src, 0, 9) != 350) { logger.error("sumBonusMs[0..9] != 350"); return false; }
    // Out-of-range tail skips null records (no crash, degrades).
    if (PausedLayout.sumBonusMs(src, 8, 99) != 250) { logger.error("sumBonusMs[8..99] degrade != 250"); return false; }
    return true;
}

// ── AC2: paragraph bounds (mid, boundary, degrade) ────────────────────────────

(:test)
function pausedParagraphStart(logger as Test.Logger) as Boolean {
    var src = PausedLayoutTestSupport.paraSource();
    // Mid-paragraph: index 5 sits in [3..6] -> start 3.
    if (PausedLayout.paragraphStartAtOrBefore(src, 5) != 3) { logger.error("paraStart(5) != 3"); return false; }
    // At a boundary: index 3 carries the flag -> it IS the start.
    if (PausedLayout.paragraphStartAtOrBefore(src, 3) != 3) { logger.error("paraStart(3) != 3"); return false; }
    if (PausedLayout.paragraphStartAtOrBefore(src, 7) != 7) { logger.error("paraStart(7) != 7"); return false; }
    // First paragraph: index 0/1/2 -> 0.
    if (PausedLayout.paragraphStartAtOrBefore(src, 0) != 0) { logger.error("paraStart(0) != 0"); return false; }
    if (PausedLayout.paragraphStartAtOrBefore(src, 2) != 0) { logger.error("paraStart(2) != 0"); return false; }
    return true;
}

(:test)
function pausedParagraphEnd(logger as Test.Logger) as Boolean {
    var src = PausedLayoutTestSupport.paraSource();
    // index 0 in [0..2] -> end 2 (next para start at 3).
    if (PausedLayout.paragraphEndAtOrAfter(src, 0) != 2) { logger.error("paraEnd(0) != 2"); return false; }
    // index 4 in [3..6] -> end 6 (next para start at 7).
    if (PausedLayout.paragraphEndAtOrAfter(src, 4) != 6) { logger.error("paraEnd(4) != 6"); return false; }
    // index 7 in the last paragraph -> last word 9 (no further para start).
    if (PausedLayout.paragraphEndAtOrAfter(src, 7) != 9) { logger.error("paraEnd(7) != 9"); return false; }
    if (PausedLayout.paragraphEndAtOrAfter(src, 9) != 9) { logger.error("paraEnd(9) != 9"); return false; }
    return true;
}

(:test)
function pausedParagraphDegradesWithoutFlags(logger as Test.Logger) as Boolean {
    // No FLAG_PARAGRAPH_START anywhere -> whole book is one paragraph: start 0, end count-1.
    var src = PausedLayoutTestSupport.noParaSource();
    if (PausedLayout.paragraphStartAtOrBefore(src, 3) != 0) { logger.error("degrade paraStart(3) != 0"); return false; }
    if (PausedLayout.paragraphEndAtOrAfter(src, 1) != 4) { logger.error("degrade paraEnd(1) != 4"); return false; }
    // Empty book -> 0 / 0, never a crash.
    var empty = new FakeWordSource([] as Array<StreamDecoder.WordRecord>);
    if (PausedLayout.paragraphStartAtOrBefore(empty, 0) != 0) { logger.error("empty paraStart != 0"); return false; }
    if (PausedLayout.paragraphEndAtOrAfter(empty, 0) != 0) { logger.error("empty paraEnd != 0"); return false; }
    return true;
}

import Toybox.Lang;

// Pure paused/context math + paragraph navigation (Story 3.4). The host-testable
// seam for the paused readout and the context view: imports ONLY Toybox.Lang —
// NO Toybox.WatchUi, NO Toybox.Graphics. The pixel work (and the dc-measured line
// wrapping) lives in the views; everything decidable from numbers/records lives
// here so it runs under the CI test harness (mirrors OrpLayout / ReaderEngine).
//
// Error posture (NFR8/AR24): bounds-check-and-degrade, never crash. Out-of-range
// indices, null records, and a stream with no FLAG_PARAGRAPH_START all degrade to
// a bounded, safe answer rather than throwing.
module PausedLayout {

    // Book progress as an integer 0–100 (FR13). `index` is the 0-based absolute
    // word index; using (wordCount - 1) as the denominator makes the LAST word read
    // 100% (atEnd is index >= count-1 — ReaderEngine.mc:284). A 0/1-word book never
    // divides by zero: empty → 0, single word → 100. Result clamped to [0,100].
    function bookPercent(index as Number, wordCount as Number) as Number {
        if (wordCount <= 1) {
            return wordCount <= 0 ? 0 : 100;
        }
        var pct = (index * 100) / (wordCount - 1);
        if (pct < 0) { return 0; }
        if (pct > 100) { return 100; }
        return pct;
    }

    // Reading time left in integer ms: wordsRemaining * (60000/wpm) + bonusRemaining.
    // The 60000/wpm beat mirrors the engine's beatMs() EXACTLY (SPEC §5.1, never
    // float); the bonus part is WPM-invariant. `wpm` is the live engine WPM (clamped
    // >= WPM_MIN by the engine, never zero — ReaderEngine.clampWpm). Pure number
    // math — host-tested with literals.
    function timeRemainingMs(wordsRemaining as Number, wpm as Number, bonusRemainingMs as Number) as Number {
        return wordsRemaining * (60000 / wpm) + bonusRemainingMs;
    }

    // Σ wordAt(k).bonusMs over [fromIndex, toIndexInclusive], skipping null records
    // (bounds-check-and-degrade). Runs ONCE per pause over the canned source — paused
    // is not the hot path. Forward note (Story 4.1): with the manifest, swap this for
    // manifest.totalBonusMs − cumulativeBonusUpTo(index) (O(1)).
    function sumBonusMs(source as BookWordSource, fromIndex as Number, toIndexInclusive as Number) as Number {
        var sum = 0;
        for (var k = fromIndex; k <= toIndexInclusive; k++) {
            var rec = source.wordAt(k);
            if (rec != null) {
                sum += rec.bonusMs;
            }
        }
        return sum;
    }

    // Human time-left. < 1 h → "M:SS" (e.g. "0:42", "12:05"); >= 1 h → "H:MM:SS"
    // (e.g. "1:02:05"). Negative/zero → "0:00". Integer division only; seconds (and
    // the minutes field in the hour form) zero-padded to two digits.
    function formatRemaining(ms as Number) as String {
        if (ms <= 0) {
            return "0:00";
        }
        var totalSec = ms / 1000;
        var hours = totalSec / 3600;
        var minutes = (totalSec % 3600) / 60;
        var seconds = totalSec % 60;
        if (hours >= 1) {
            return hours.toString() + ":" + twoDigit(minutes) + ":" + twoDigit(seconds);
        }
        return minutes.toString() + ":" + twoDigit(seconds);
    }

    // The nearest index <= `index` whose record carries FLAG_PARAGRAPH_START, else 0
    // (bounds-check-and-degrade). Mirrors the engine's sentenceStartAtOrBefore shape
    // but keyed on Protocol.FLAG_PARAGRAPH_START (0x02). A stream with no paragraph
    // flag degrades to 0 (whole book as one paragraph).
    function paragraphStartAtOrBefore(source as BookWordSource, index as Number) as Number {
        var count = source.wordCount();
        if (count <= 0) {
            return 0;
        }
        var i = index;
        if (i < 0) { return 0; }
        if (i > count - 1) { i = count - 1; }
        while (i > 0) {
            var rec = source.wordAt(i);
            if (rec != null && (rec.flags & Protocol.FLAG_PARAGRAPH_START) != 0) {
                return i;
            }
            i -= 1;
        }
        return 0; // reached the start (or no flag found) — word 0 is the paragraph start
    }

    // The index just BEFORE the next FLAG_PARAGRAPH_START after `index`, else the
    // last word (wordCount - 1) — the inclusive end of the current paragraph. A
    // stream with no further paragraph flag degrades to the last word.
    function paragraphEndAtOrAfter(source as BookWordSource, index as Number) as Number {
        var count = source.wordCount();
        if (count <= 0) {
            return 0;
        }
        var start = index < 0 ? 0 : index;
        for (var k = start + 1; k < count; k++) {
            var rec = source.wordAt(k);
            if (rec != null && (rec.flags & Protocol.FLAG_PARAGRAPH_START) != 0) {
                return k - 1; // just before the next paragraph start
            }
        }
        return count - 1;
    }

    // Zero-pad a 0–59 field to two digits ("5" -> "05"). Used for the seconds field
    // and the minutes field of the hour form.
    function twoDigit(n as Number) as String {
        return n < 10 ? "0" + n.toString() : n.toString();
    }
}

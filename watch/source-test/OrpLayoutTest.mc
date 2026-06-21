import Toybox.Lang;
import Toybox.Test;

// Host-side tests for the pure ORP layout helpers (Story 3.2, AC1/AC2/AC4). Run
// under matco/action-connectiq-tester (SDK 8.4.0, fenix847mm) at Strict level 3.
// No Test.assert* API is used in this codebase — assert via conditionals +
// logger.error(...) + return false (mirrors SmokeTest/ReaderEngineTest).
//
// The accented fixtures are the load-bearing cases: orpPivot is a UTF-8 BYTE
// index, so for "cafe"/"naive" byte index != char index and a naive String split
// would corrupt the word. (The committed dev stream carries these lowercase, at
// café idx 90 / naïve idx 140 — see companion fixture README.)
module OrpLayoutTestSupport {

    // True iff splitAtPivot(word, pivot) == [before, pivot_, after].
    function splitIs(word as String, pivot as Number,
                     before as String, pivot_ as String, after as String) as Boolean {
        var p = OrpLayout.splitAtPivot(word, pivot);
        return p[0].equals(before) && p[1].equals(pivot_) && p[2].equals(after);
    }
}

// ── AC1/AC4: UTF-8 byte-index pivot split ────────────────────────────────────

(:test)
function orpSplitAscii(logger as Test.Logger) as Boolean {
    // ASCII: byte index == char index. "reading" pivot byte 3 -> 'd'.
    if (!OrpLayoutTestSupport.splitIs("reading", 3, "rea", "d", "ing")) {
        logger.error("ascii split 'reading'@3 != [rea|d|ing]");
        return false;
    }
    return true;
}

(:test)
function orpSplitMultibyteAfter(logger as Test.Logger) as Boolean {
    // "café" = [63 61 66 C3 A9]. Pivot byte 1 -> 'a'. The AFTER segment "fé"
    // spans the multibyte é: byte-correct slicing is required to reconstruct it.
    if (!OrpLayoutTestSupport.splitIs("café", 1, "c", "a", "fé")) {
        logger.error("'café'@1 != [c|a|fé] — after-segment multibyte mis-sliced");
        return false;
    }
    return true;
}

(:test)
function orpSplitByteIndexNotCharIndex(logger as Test.Logger) as Boolean {
    // "naïve" = [6E 61 C3 AF 76 65]. Pivot byte 4 -> 'v'. The BEFORE segment
    // "naï" is 4 BYTES but only 3 CHARS — so byte index 4 != char index 3. This
    // is the explicit reason a ByteArray split (not a String split) is mandatory.
    if (!OrpLayoutTestSupport.splitIs("naïve", 4, "naï", "v", "e")) {
        logger.error("'naïve'@4 != [naï|v|e] — byte index treated as char index");
        return false;
    }
    return true;
}

(:test)
function orpSplitPivotIsMultibyte(logger as Test.Logger) as Boolean {
    // "café" pivot byte 3 -> the lead byte (C3) of 'é': the pivot glyph itself is
    // a 2-byte char. before="caf", pivot="é", after="".
    if (!OrpLayoutTestSupport.splitIs("café", 3, "caf", "é", "")) {
        logger.error("'café'@3 != [caf|é|] — multibyte pivot length wrong");
        return false;
    }
    return true;
}

(:test)
function orpSplitDegradesOnBadPivot(logger as Test.Logger) as Boolean {
    // Out-of-range pivot -> whole word as `before`, never a crash (NFR8/AR24).
    if (!OrpLayoutTestSupport.splitIs("abc", 9, "abc", "", "")) {
        logger.error("out-of-range pivot did not degrade to whole word");
        return false;
    }
    // Pivot landing on a continuation byte (byte 4 of "café" = A9) is not a lead
    // byte -> degrade rather than slice a malformed char.
    if (!OrpLayoutTestSupport.splitIs("café", 4, "café", "", "")) {
        logger.error("non-lead pivot byte did not degrade");
        return false;
    }
    return true;
}

// ── AC1: anchor column ───────────────────────────────────────────────────────

(:test)
function orpAnchorX(logger as Test.Logger) as Boolean {
    if (OrpLayout.anchorX(454, 35) != 158) { logger.error("anchorX(454,35) != 158"); return false; }
    if (OrpLayout.anchorX(454, 30) != 136) { logger.error("anchorX(454,30) != 136"); return false; }
    if (OrpLayout.anchorX(454, 60) != 272) { logger.error("anchorX(454,60) != 272"); return false; }
    return true;
}

// ── AC5 support / 3.1 deferred #1: font index clamp ──────────────────────────

(:test)
function orpClampFontIndex(logger as Test.Logger) as Boolean {
    if (OrpLayout.clampFontIndex(0, 3) != 0) { logger.error("clamp(0,3)"); return false; }
    if (OrpLayout.clampFontIndex(1, 3) != 1) { logger.error("clamp(1,3)"); return false; }
    if (OrpLayout.clampFontIndex(2, 3) != 2) { logger.error("clamp(2,3)"); return false; }
    // A corrupted persisted fontSize=99 (Settings never bounds it above) clamps
    // to the top of the ramp, not out of range.
    if (OrpLayout.clampFontIndex(99, 3) != 2) { logger.error("corrupted 99 not clamped to 2"); return false; }
    // Defensive lower/empty-ramp guards.
    if (OrpLayout.clampFontIndex(-1, 3) != 0) { logger.error("clamp(-1,3)"); return false; }
    if (OrpLayout.clampFontIndex(0, 0) != 0) { logger.error("clamp(0,0) empty ramp"); return false; }
    return true;
}

// ── AC4: long-word margin-clamp decision ─────────────────────────────────────

(:test)
function orpNeedsMarginClamp(logger as Test.Logger) as Boolean {
    // Boundary: a word exactly at the usable width is NOT clamped.
    if (OrpLayout.needsMarginClamp(200, 200)) { logger.error("clamp at exactly usable width"); return false; }
    if (OrpLayout.needsMarginClamp(199, 200)) { logger.error("clamp below usable width"); return false; }
    if (!OrpLayout.needsMarginClamp(201, 200)) { logger.error("no clamp above usable width"); return false; }
    return true;
}

import Toybox.Lang;
import Toybox.StringUtil;

// Pure ORP geometry/byte-split helpers (Story 3.2). The host-testable seam for
// PlaybackView: imports ONLY Toybox.Lang (+ Toybox.StringUtil for byte<->string
// work). NO Toybox.WatchUi, NO Toybox.Graphics — the actual pixel-pushing and the
// dc.getTextWidthInPixels measurement live in PlaybackView; everything decidable
// from numbers/strings lives here so it runs under the CI test harness (mirrors
// how Story 3.1 kept ReaderEngine free of any view import).
//
// Error posture (NFR8/AR24): bounds-check-and-degrade, never crash. A malformed
// orpPivot returns the whole word as `before` rather than throwing.
module OrpLayout {

    // UTF-8 lead-byte -> character byte-length (RFC 3629). The exact rule
    // StreamDecoder.isValidUtf8 uses (StreamDecoder.mc:100-110) — mirrored here
    // (not reinvented arbitrarily) because that function validates a whole array
    // and exposes no per-lead length. Returns 0 for a non-lead / invalid byte.
    function utf8CharLen(lead as Number) as Number {
        if (lead <= 0x7F) { return 1; }
        if (lead >= 0xC2 && lead <= 0xDF) { return 2; }
        if (lead >= 0xE0 && lead <= 0xEF) { return 3; }
        if (lead >= 0xF0 && lead <= 0xF4) { return 4; }
        return 0;
    }

    // Split a word into [before, pivot, after] where `pivot` is the SINGLE UTF-8
    // character whose lead byte is at BYTE index `orpPivot` (SPEC §5 — orpPivot is
    // a byte index into the UTF-8 word as precomputed by the phone; the watch never
    // recomputes pivots, architecture.md:277). For ASCII byte index == char index;
    // for accented words ("cafe", "naive") it does not, which is the whole reason
    // we slice a ByteArray rather than a String (Monkey C String has no byte slice).
    //
    // Bounds-check-and-degrade (NFR8/AR24): an out-of-range or non-lead orpPivot
    // returns the whole word as `before` with empty pivot/after — never a crash.
    function splitAtPivot(word as String, orpPivot as Number) as Array<String> {
        // Work in a real ByteArray (String.toUtf8Array returns Array<Number>, which
        // convertEncodedString won't take, and whose slice() isn't a ByteArray). The
        // String->ByteArray conversion mirrors StreamDecoder's slice-and-convert.
        var bytes = stringToBytes(word);
        var size = bytes.size();
        if (orpPivot < 0 || orpPivot >= size) {
            return [word, "", ""] as Array<String>;
        }
        var len = utf8CharLen(bytes[orpPivot] as Number);
        if (len <= 0 || orpPivot + len > size) {
            return [word, "", ""] as Array<String>; // not a lead byte / truncated
        }
        var before = bytesToString(bytes.slice(0, orpPivot));
        var pivot = bytesToString(bytes.slice(orpPivot, orpPivot + len));
        var after = bytesToString(bytes.slice(orpPivot + len, size));
        return [before, pivot, after] as Array<String>;
    }

    // The pivot glyph's CENTER column = displayWidth * anchorPct / 100 (integer).
    // The anchor is the layout origin so it does not move between words (AC1).
    // 454 * 35 / 100 = 158.
    function anchorX(displayWidth as Number, anchorPct as Number) as Number {
        return displayWidth * anchorPct / 100;
    }

    // Clamp a persisted Settings.fontSize into [0, rampLength-1]. Settings only
    // rejects fontSize < 0 (Settings.mc:132-135 readNonNegative); a corrupted
    // fontSize=99 reaches the renderer and MUST be clamped to the ramp length here.
    // [Resolves Story 3.1 Review "Deferred" #1.]
    function clampFontIndex(fontSize as Number, rampLength as Number) as Number {
        if (rampLength <= 0) { return 0; }
        if (fontSize < 0) { return 0; }
        if (fontSize > rampLength - 1) { return rampLength - 1; }
        return fontSize;
    }

    // Pure long-word decision (AC4): true when the measured whole-word width
    // exceeds the usable width. The MEASUREMENT (dc.getTextWidthInPixels) happens
    // in the view; given the widths, the decision is pure and tested here. A word
    // exactly at the usable width does NOT need clamping (strict greater-than).
    function needsMarginClamp(wordWidthPx as Number, usableWidthPx as Number) as Boolean {
        return wordWidthPx > usableWidthPx;
    }

    // Convert a String to its UTF-8 ByteArray. A valid String always converts; on
    // the (unexpected) failure path return an empty ByteArray, which splitAtPivot's
    // bounds check then degrades to [word, "", ""]. Words are never empty (wordLen
    // is 1-255, SPEC §5), so convertEncodedString never sees an empty input here.
    function stringToBytes(s as String) as ByteArray {
        var b = StringUtil.convertEncodedString(s, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            :encoding => StringUtil.CHAR_ENCODING_UTF8
        });
        if (b instanceof Lang.ByteArray) {
            return b as ByteArray;
        }
        return []b;
    }

    // Convert a UTF-8 ByteArray slice back to a String. Empty slice -> "" (avoids
    // handing convertEncodedString an empty buffer). The slices splitAtPivot
    // produces are always well-formed UTF-8 (split on char-lead boundaries), so
    // conversion is safe (cf. StreamDecoder's malformed-input caveat at :63-71).
    function bytesToString(bytes as ByteArray) as String {
        if (bytes.size() == 0) {
            return "";
        }
        var s = StringUtil.convertEncodedString(bytes, {
            :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            :toRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
            :encoding => StringUtil.CHAR_ENCODING_UTF8
        });
        if (s instanceof Lang.String) {
            return s as String;
        }
        return "";
    }
}

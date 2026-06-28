import Toybox.Lang;

// Pure chapter metadata + lookups (Story 3.5, AC1). Host-testable by design:
// imports ONLY Toybox.Lang — no WatchUi/Graphics/System (mirrors OrpLayout /
// PausedLayout / ReaderEngine). A small value class over two parallel arrays:
// chapter OFFSETS (the absolute word index of each chapter's first word, ascending
// with offsets[0] == 0) and TITLES. The chapter card reads number+title from it.
//
// Where it comes from: in Epic 3 CannedWordSource builds one from the committed
// fixture's `ch` array; in Epic 4 ChunkedWordSource builds the SAME shape from the
// live manifest (Protocol.KEY_CHAPTERS) — the view code never changes.
//
// Error posture (NFR8/AR24): bounds-check-and-degrade, never crash. An empty
// catalog, out-of-range word/chapter indices, and a negative word index all return
// bounded, safe answers rather than throwing.
class ChapterCatalog {
    private var _offsets as Array<Number>;
    private var _titles as Array<String>;

    // `offsets` and `titles` are parallel; the catalog uses the shorter length if
    // they ever disagree (degrade, never index past the end). The caller supplies
    // them ascending from 0 (the canned/manifest contract); no sorting is done.
    function initialize(offsets as Array<Number>, titles as Array<String>) {
        _offsets = offsets;
        _titles = titles;
    }

    // Number of chapters (the safe length of the two parallel arrays).
    function count() as Number {
        var o = _offsets.size();
        var t = _titles.size();
        return o < t ? o : t;
    }

    // 1-based chapter number containing `wordIndex`: the highest chapter whose
    // offset <= wordIndex. Clamps to 1 for a word before the first offset or a
    // negative index; an empty catalog also degrades to 1 (harmless — the card only
    // fires where chapter flags exist).
    function numberForWord(wordIndex as Number) as Number {
        var n = count();
        if (n <= 0) {
            return 1;
        }
        var found = 0; // chapter 1 by default (clamp-to-1 for words before offset 0)
        for (var i = 0; i < n; i++) {
            if (_offsets[i] <= wordIndex) {
                found = i;
            } else {
                break; // offsets ascending — no later chapter can match
            }
        }
        return found + 1;
    }

    // The title of the chapter containing `wordIndex`, or null if the catalog is
    // empty (degrade).
    function titleForWord(wordIndex as Number) as String? {
        if (count() <= 0) {
            return null;
        }
        return titleAt(numberForWord(wordIndex) - 1);
    }

    // The absolute word offset of the 0-based chapter, or -1 if out of range.
    function offsetAt(chapterIndex as Number) as Number {
        if (chapterIndex < 0 || chapterIndex >= count()) {
            return -1;
        }
        return _offsets[chapterIndex];
    }

    // The title of the 0-based chapter, or null if out of range.
    function titleAt(chapterIndex as Number) as String? {
        if (chapterIndex < 0 || chapterIndex >= count()) {
            return null;
        }
        return _titles[chapterIndex];
    }
}

import Toybox.Lang;
import Toybox.Test;

// Host-side tests for the pure ChapterCatalog (Story 3.5, AC1). Run under
// matco/action-connectiq-tester (SDK 8.4.0, fenix847mm) at Strict level 3. No
// Test.assert* API in this repo — assert via conditionals + logger.error +
// return false (mirrors PausedLayoutTest/ReaderEngineTest).
module ChapterCatalogTestSupport {

    // The dev book's 3 chapters, verbatim from dev_sample_book.manifest.json:
    // offsets [0, 81, 170], titles below. The same data CannedWordSource bundles.
    function devCatalog() as ChapterCatalog {
        return new ChapterCatalog(
            [0, 81, 170] as Array<Number>,
            [
                "I. The Harbor at Dusk",
                "II. A Café and a Question",
                "III. What the Tide Returned"
            ] as Array<String>);
    }

    function emptyCatalog() as ChapterCatalog {
        return new ChapterCatalog([] as Array<Number>, [] as Array<String>);
    }
}

// ── AC1: count + offset/title accessors (bounds-checked) ──────────────────────

(:test)
function chapterCatalogCountAndAccessors(logger as Test.Logger) as Boolean {
    var cat = ChapterCatalogTestSupport.devCatalog();
    if (cat.count() != 3) { logger.error("count != 3"); return false; }
    if (cat.offsetAt(0) != 0) { logger.error("offsetAt(0) != 0"); return false; }
    if (cat.offsetAt(1) != 81) { logger.error("offsetAt(1) != 81"); return false; }
    if (cat.offsetAt(2) != 170) { logger.error("offsetAt(2) != 170"); return false; }
    var t1 = cat.titleAt(1);
    if (t1 == null || !t1.equals("II. A Café and a Question")) { logger.error("titleAt(1) wrong"); return false; }
    // Out-of-range accessors degrade (offset -1, title null), never crash.
    if (cat.offsetAt(3) != -1) { logger.error("offsetAt(3) != -1"); return false; }
    if (cat.offsetAt(-1) != -1) { logger.error("offsetAt(-1) != -1"); return false; }
    if (cat.titleAt(3) != null) { logger.error("titleAt(3) != null"); return false; }
    if (cat.titleAt(-1) != null) { logger.error("titleAt(-1) != null"); return false; }
    return true;
}

// ── AC1: numberForWord at offsets, between offsets, before/after ──────────────

(:test)
function chapterCatalogNumberForWord(logger as Test.Logger) as Boolean {
    var cat = ChapterCatalogTestSupport.devCatalog();
    // Exactly at an offset -> that chapter.
    if (cat.numberForWord(0) != 1) { logger.error("numberForWord(0) != 1"); return false; }
    if (cat.numberForWord(81) != 2) { logger.error("numberForWord(81) != 2"); return false; }
    if (cat.numberForWord(170) != 3) { logger.error("numberForWord(170) != 3"); return false; }
    // Between offsets -> the chapter that started.
    if (cat.numberForWord(80) != 1) { logger.error("numberForWord(80) != 1"); return false; }
    if (cat.numberForWord(82) != 2) { logger.error("numberForWord(82) != 2"); return false; }
    if (cat.numberForWord(169) != 2) { logger.error("numberForWord(169) != 2"); return false; }
    // Past the last offset -> last chapter.
    if (cat.numberForWord(227) != 3) { logger.error("numberForWord(227) != 3"); return false; }
    if (cat.numberForWord(99999) != 3) { logger.error("numberForWord(huge) != 3"); return false; }
    // Negative / before the first offset -> clamps to chapter 1.
    if (cat.numberForWord(-5) != 1) { logger.error("numberForWord(-5) != 1"); return false; }
    return true;
}

// ── AC1: titleForWord + empty-catalog degrade ────────────────────────────────

(:test)
function chapterCatalogTitleForWordAndEmpty(logger as Test.Logger) as Boolean {
    var cat = ChapterCatalogTestSupport.devCatalog();
    var t0 = cat.titleForWord(0);
    if (t0 == null || !t0.equals("I. The Harbor at Dusk")) { logger.error("titleForWord(0) wrong"); return false; }
    var t100 = cat.titleForWord(100);
    if (t100 == null || !t100.equals("II. A Café and a Question")) { logger.error("titleForWord(100) wrong"); return false; }
    var t200 = cat.titleForWord(200);
    if (t200 == null || !t200.equals("III. What the Tide Returned")) { logger.error("titleForWord(200) wrong"); return false; }

    // Empty catalog degrades: count 0, numberForWord clamps to 1, titles null,
    // accessors out of range — never a crash.
    var empty = ChapterCatalogTestSupport.emptyCatalog();
    if (empty.count() != 0) { logger.error("empty count != 0"); return false; }
    if (empty.numberForWord(50) != 1) { logger.error("empty numberForWord != 1"); return false; }
    if (empty.titleForWord(50) != null) { logger.error("empty titleForWord != null"); return false; }
    if (empty.offsetAt(0) != -1) { logger.error("empty offsetAt != -1"); return false; }
    if (empty.titleAt(0) != null) { logger.error("empty titleAt != null"); return false; }
    return true;
}

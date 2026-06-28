import Toybox.Lang;
import Toybox.Test;

// Host-side tests for the pure StatusLayout copy + Finished formatting (Story 3.5,
// AC2/AC3). Run under matco/action-connectiq-tester (SDK 8.4.0, fenix847mm) at
// Strict level 3. No Test.assert* API — assert via conditionals + logger.error +
// return false (mirrors PausedLayoutTest/ChapterCatalogTest).

// ── AC3: exact status sentences (incl. BookChanged title interpolation) ───────

(:test)
function statusSentencesAreExactCopy(logger as Test.Logger) as Boolean {
    if (!StatusLayout.statusSentence(StatusLayout.STATE_WAITING_FOR_PHONE, null)
            .equals("Waiting for phone")) { logger.error("WaitingForPhone copy"); return false; }
    if (!StatusLayout.statusSentence(StatusLayout.STATE_BUFFERING, null)
            .equals("Loading…")) { logger.error("Buffering copy"); return false; }
    if (!StatusLayout.statusSentence(StatusLayout.STATE_STORAGE_FULL, null)
            .equals("Storage full — manage books on your phone")) { logger.error("StorageFull copy"); return false; }
    // BookChanged interpolates the title.
    if (!StatusLayout.statusSentence(StatusLayout.STATE_BOOK_CHANGED, "Moby-Dick")
            .equals("Book changed on phone — starting Moby-Dick")) { logger.error("BookChanged copy"); return false; }
    // Null title degrades to an empty interpolation, never a crash.
    if (!StatusLayout.statusSentence(StatusLayout.STATE_BOOK_CHANGED, null)
            .equals("Book changed on phone — starting ")) { logger.error("BookChanged null title"); return false; }
    // Unknown state degrades to "Loading…".
    if (!StatusLayout.statusSentence(99, null).equals("Loading…")) { logger.error("unknown state default"); return false; }
    return true;
}

// ── AC3: animated buffering dot cycle (clamped) ───────────────────────────────

(:test)
function statusBufferingTextCycle(logger as Test.Logger) as Boolean {
    if (!StatusLayout.bufferingText(0).equals("Loading")) { logger.error("dots 0"); return false; }
    if (!StatusLayout.bufferingText(1).equals("Loading.")) { logger.error("dots 1"); return false; }
    if (!StatusLayout.bufferingText(2).equals("Loading..")) { logger.error("dots 2"); return false; }
    if (!StatusLayout.bufferingText(3).equals("Loading...")) { logger.error("dots 3"); return false; }
    // Clamp out-of-range counts (no unbounded growth, no negative).
    if (!StatusLayout.bufferingText(5).equals("Loading...")) { logger.error("dots clamp hi"); return false; }
    if (!StatusLayout.bufferingText(-1).equals("Loading")) { logger.error("dots clamp lo"); return false; }
    return true;
}

// ── AC2: reading-time formatting across the minute/hour boundaries + zero ─────

(:test)
function statusFormatReadingTime(logger as Test.Logger) as Boolean {
    if (!StatusLayout.formatReadingTime(0).equals("0m")) { logger.error("0ms != 0m"); return false; }
    if (!StatusLayout.formatReadingTime(-1000).equals("0m")) { logger.error("neg != 0m"); return false; }
    // 41 min = 2,460,000 ms -> "41m".
    if (!StatusLayout.formatReadingTime(2460000).equals("41m")) { logger.error("2460000 != 41m"); return false; }
    // 59 min (just under an hour) -> "59m".
    if (!StatusLayout.formatReadingTime(3540000).equals("59m")) { logger.error("3540000 != 59m"); return false; }
    // Exactly 1 h -> "1h 0m" (minutes not zero-padded).
    if (!StatusLayout.formatReadingTime(3600000).equals("1h 0m")) { logger.error("3600000 != 1h 0m"); return false; }
    // 6h 41m = 24,060,000 ms -> "6h 41m".
    if (!StatusLayout.formatReadingTime(24060000).equals("6h 41m")) { logger.error("24060000 != 6h 41m"); return false; }
    return true;
}

// ── AC2: Finished sentence with and without day-tracking ──────────────────────

(:test)
function statusFormatFinished(logger as Test.Logger) as Boolean {
    // Epic 3: days == null -> no "across N days" tail.
    if (!StatusLayout.formatFinished(24060000, null).equals("Finished. 6h 41m.")) {
        logger.error("finished no-days"); return false;
    }
    // Epic 4 / Story 3.6: with a day count.
    if (!StatusLayout.formatFinished(24060000, 19).equals("Finished. 6h 41m across 19 days.")) {
        logger.error("finished with days"); return false;
    }
    // Sub-hour finish, no days.
    if (!StatusLayout.formatFinished(2460000, null).equals("Finished. 41m.")) {
        logger.error("finished sub-hour"); return false;
    }
    return true;
}

import Toybox.Lang;

// Pure status-screen copy + Finished stat formatting (Story 3.5, AC2/AC3).
// Host-testable by design: imports ONLY Toybox.Lang — no WatchUi/Graphics/System
// (mirrors OrpLayout / PausedLayout / ChapterCatalog). All the EXACT UX strings
// live here, in ONE place, so StatusView (and Epic 4's triggers) never inline copy.
//
// Copy is verbatim from EXPERIENCE.md:106–110 / DESIGN.md:155 — do NOT paraphrase.
module StatusLayout {

    // Typed system-state ids for the render-only StatusView shells (AC3).
    const STATE_WAITING_FOR_PHONE = 0;
    const STATE_BUFFERING = 1;
    const STATE_BOOK_CHANGED = 2;
    const STATE_STORAGE_FULL = 3;

    // The Buffering word, shared by the canonical sentence ("Loading…") and the
    // animated dot-cycle variant the view paints (bufferingText) — one literal.
    const LOADING_BASE = "Loading";

    // The exact one-line sentence for a system state. `title` is interpolated only
    // for BookChanged (the title of the book the phone switched to); it is ignored
    // by the others, and a null title degrades to an empty interpolation rather than
    // crashing (NFR8/AR24). An unknown stateId degrades to "Loading…".
    function statusSentence(stateId as Number, title as String?) as String {
        if (stateId == STATE_WAITING_FOR_PHONE) {
            return "Waiting for phone";
        }
        if (stateId == STATE_STORAGE_FULL) {
            return "Storage full — manage books on your phone";
        }
        if (stateId == STATE_BOOK_CHANGED) {
            var t = title == null ? "" : title;
            return "Book changed on phone — starting " + t;
        }
        return LOADING_BASE + "…"; // STATE_BUFFERING (and the safe default)
    }

    // The animated Buffering text: "Loading" + `dotCount` dots (the view cycles
    // 1 → 2 → 3). Clamped to [0, 3] so a runaway counter never grows unbounded.
    function bufferingText(dotCount as Number) as String {
        var n = dotCount;
        if (n < 0) { n = 0; }
        if (n > 3) { n = 3; }
        var s = LOADING_BASE;
        for (var i = 0; i < n; i++) {
            s += ".";
        }
        return s;
    }

    // Human reading-time: ">= 1 h" → "6h 41m"; "< 1 h" → "41m"; zero/negative → "0m".
    // Integer division only (no float, mirrors the engine's ms math). The minutes
    // field in the hour form is NOT zero-padded ("6h 5m", not "6h 05m") — it reads as
    // prose, not a clock (distinct from PausedLayout.formatRemaining's H:MM:SS).
    function formatReadingTime(ms as Number) as String {
        if (ms <= 0) {
            return "0m";
        }
        var totalMin = ms / 60000;
        var hours = totalMin / 60;
        var minutes = totalMin % 60;
        if (hours >= 1) {
            return hours.toString() + "h " + minutes.toString() + "m";
        }
        return minutes.toString() + "m";
    }

    // The Finished sentence (AC2). Epic 3 has no day-tracking, so `days` is null and
    // it renders "Finished. 6h 41m."; when persistence lands (Story 3.6) the caller
    // passes the day count for "Finished. 6h 41m across 19 days." (EXPERIENCE.md:110).
    function formatFinished(totalMs as Number, days as Number?) as String {
        var time = formatReadingTime(totalMs);
        if (days == null) {
            return "Finished. " + time + ".";
        }
        return "Finished. " + time + " across " + days.toString() + " days.";
    }
}

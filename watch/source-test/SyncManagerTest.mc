import Toybox.Lang;
import Toybox.Test;

// Host tests for the PURE half of the Sync module (Story 3.6, AC1/AC4) — the
// debounce/force gate and the position encode/decode with bounds-check-and-
// degrade. The SyncManager class itself (the Storage/Time adapter) needs a
// device context and is covered by the on-device check (Task 7), exactly as
// Settings' loadFrom/save adapter is. LWW/clock-skew cases are Epic-4
// additions to this same file. No Test.assert* API — conditionals +
// logger.error(...) + return false (mirrors ReaderEngineTest).

// ── AC1: shouldCommit — force always wins, ~15 s debounce while playing ──────

(:test)
function syncShouldCommitForceAndDebounce(logger as Test.Logger) as Boolean {
    // force ⇒ true, even deep inside the debounce window.
    if (!Sync.shouldCommit(1000, 1001, true)) { logger.error("force inside window refused"); return false; }
    // Never written (null lastWrite) ⇒ true — the first save must not wait 15 s.
    if (!Sync.shouldCommit(null, 0, false)) { logger.error("null lastWrite refused"); return false; }
    // Inside the window ⇒ false (this is the 700-WPM Storage-thrash guard).
    if (Sync.shouldCommit(1000, 1000 + Sync.DEBOUNCE_MS - 1, false)) { logger.error("inside window committed"); return false; }
    // Exactly at the window ⇒ true (>=, not >).
    if (!Sync.shouldCommit(1000, 1000 + Sync.DEBOUNCE_MS, false)) { logger.error("at window refused"); return false; }
    // Past the window ⇒ true.
    if (!Sync.shouldCommit(1000, 1000 + Sync.DEBOUNCE_MS + 1, false)) { logger.error("after window refused"); return false; }
    // getTimer() wraparound (now < lastWrite) ⇒ true — resync, mirrors the
    // engine's onTick wraparound guard.
    if (!Sync.shouldCommit(1000, 999, false)) { logger.error("wraparound refused"); return false; }
    return true;
}

// ── AC3: encodePosition/decodeIndex round-trip ───────────────────────────────

(:test)
function syncEncodeDecodeRoundTrip(logger as Test.Logger) as Boolean {
    var d = Sync.encodePosition(42, 1750000000);
    if (d["pos"] != 42) { logger.error("encode pos"); return false; }
    if (d["ts"] != 1750000000) { logger.error("encode ts (epoch seconds, Epic-4 LWW unit)"); return false; }
    if (Sync.decodeIndex(d, 228) != 42) { logger.error("round-trip mid-book"); return false; }
    // The two edges round-trip exactly: word 0 and the last word.
    if (Sync.decodeIndex(Sync.encodePosition(0, 1), 228) != 0) { logger.error("round-trip word 0"); return false; }
    if (Sync.decodeIndex(Sync.encodePosition(227, 1), 228) != 227) { logger.error("round-trip last word"); return false; }
    return true;
}

// ── AC2/AC4: decodeIndex degrade matrix — never past the end, never a crash ──

(:test)
function syncDecodeIndexDegradeMatrix(logger as Test.Logger) as Boolean {
    // Malformed ⇒ null ⇒ the caller starts at word 0 (bounds-check-and-degrade).
    if (Sync.decodeIndex(null, 228) != null) { logger.error("null value"); return false; }
    if (Sync.decodeIndex("junk", 228) != null) { logger.error("non-dict string"); return false; }
    if (Sync.decodeIndex(42, 228) != null) { logger.error("non-dict number"); return false; }
    if (Sync.decodeIndex({ "ts" => 1 }, 228) != null) { logger.error("missing pos"); return false; }
    if (Sync.decodeIndex({ "pos" => "seven" }, 228) != null) { logger.error("non-number pos"); return false; }
    if (Sync.decodeIndex({ "pos" => -1 }, 228) != null) { logger.error("negative pos"); return false; }
    // Too large ⇒ clamped DOWN to the last word (a re-baked-shorter book or a
    // corrupt large value restores at-or-before the end, never past it — AC2).
    if (Sync.decodeIndex({ "pos" => 5000 }, 228) != 227) { logger.error("oversized pos not clamped to count-1"); return false; }
    if (Sync.decodeIndex({ "pos" => 228 }, 228) != 227) { logger.error("pos == count not clamped"); return false; }
    // No readable book ⇒ null (empty/unloaded source cannot be restored into).
    if (Sync.decodeIndex({ "pos" => 3 }, 0) != null) { logger.error("wordCount 0"); return false; }
    if (Sync.decodeIndex({ "pos" => 3 }, -1) != null) { logger.error("negative wordCount"); return false; }
    return true;
}

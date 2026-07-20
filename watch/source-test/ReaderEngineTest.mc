import Toybox.Lang;
import Toybox.Test;

// Host-side tests for the pure reading engine + Settings model (Story 3.1,
// AC1–AC7). Run under matco/action-connectiq-tester (SDK 8.4.0, fenix847mm) at
// Strict level 3. Assertions are literal: a regression in the timing math,
// drift-free accumulator, pause/rewind logic, or defaults must fail THIS build.
// No Test.assert* API is used in this codebase — assert via conditionals +
// logger.error(...) + return false (mirrors SmokeTest/ProtocolTest).
module ReaderEngineTestSupport {

    // A 10-word, 3-sentence book with known sentence-end indices (2, 4, 9) and
    // bonusMs values, so pacing, coast pause, and stackable rewind are all
    // exercisable. Word 9 is both a sentence end AND the last word of the book.
    //   sentence 0: idx 0..2  (starts at 0)
    //   sentence 1: idx 3..4  (starts at 3)
    //   sentence 2: idx 5..9  (starts at 5)
    function sampleWords() as Array<StreamDecoder.WordRecord> {
        var se = Protocol.FLAG_SENTENCE_END;
        var para = Protocol.FLAG_PARAGRAPH_START | Protocol.FLAG_CHAPTER_START;
        return [
            new StreamDecoder.WordRecord("The", para, 0, 0),
            new StreamDecoder.WordRecord("quick", 0, 0, 0),
            new StreamDecoder.WordRecord("fox.", se, 0, 100),
            new StreamDecoder.WordRecord("It", 0, 0, 0),
            new StreamDecoder.WordRecord("ran.", se, 0, 50),
            new StreamDecoder.WordRecord("Then", 0, 0, 0),
            new StreamDecoder.WordRecord("it", 0, 0, 0),
            new StreamDecoder.WordRecord("slept", 0, 0, 0),
            new StreamDecoder.WordRecord("all", 0, 0, 0),
            new StreamDecoder.WordRecord("night.", se, 0, 200)
        ] as Array<StreamDecoder.WordRecord>;
    }

    function newEngine() as Reader.ReaderEngine {
        return new Reader.ReaderEngine(new FakeWordSource(sampleWords()), 250, SettingsModel.PAUSE_COAST);
    }

    // A fresh engine seeded at a specific starting WPM (for the adaptive-step
    // cases). Source is never driven, so it stays IDLE — stepWpmUp/Down are pure
    // math over the WPM field and do not require a playing engine.
    function engineAtWpm(wpm as Number) as Reader.ReaderEngine {
        return new Reader.ReaderEngine(new FakeWordSource(sampleWords()), wpm, SettingsModel.PAUSE_COAST);
    }

    // Advance the engine by exactly one beat/word, ticking precisely at its due
    // time (elapsed == currentDuration) so no catch-up cap is involved.
    function stepDue(engine as Reader.ReaderEngine) as Void {
        engine.onTick(engine.lastAdvance() + engine.currentDuration());
    }

    // play() then walk the 3-beat ramp to land PLAYING on word 0, then advance to
    // `target`.
    function driveToPlayingIndex(engine as Reader.ReaderEngine, target as Number) as Void {
        engine.play(0);
        for (var i = 0; i < Reader.RAMP_BEATS; i++) {
            stepDue(engine);
        }
        while (engine.index() < target && engine.isPlaying()) {
            stepDue(engine);
        }
    }

    // Fresh default engine driven to PLAYING on `target`.
    function driveToPlayingIndexNew(target as Number) as Reader.ReaderEngine {
        var engine = newEngine();
        driveToPlayingIndex(engine, target);
        return engine;
    }
}

// ── AC1: Settings model with pure, Storage-independent defaults ──────────────

(:test)
function settingsDefaultsAreStorageFree(logger as Test.Logger) as Boolean {
    // Enum-style constants must be the stable, typed values call sites depend on.
    if (SettingsModel.PAUSE_COAST != 0) { logger.error("PAUSE_COAST"); return false; }
    if (SettingsModel.PAUSE_INSTANT != 1) { logger.error("PAUSE_INSTANT"); return false; }
    if (SettingsModel.HAND_RIGHT != 0) { logger.error("HAND_RIGHT"); return false; }
    if (SettingsModel.HAND_LEFT != 1) { logger.error("HAND_LEFT"); return false; }

    // Defaults are produced by the constructor with ZERO Storage access.
    var s = new SettingsModel.Settings();
    if (s.wpm != 250) { logger.error("default wpm"); return false; }
    if (s.pauseMode != SettingsModel.PAUSE_COAST) { logger.error("default pauseMode"); return false; }
    if (!s.touchControls) { logger.error("default touchControls"); return false; }
    if (s.fontSize != 0) { logger.error("default fontSize"); return false; }
    if (s.handedness != SettingsModel.HAND_RIGHT) { logger.error("default handedness"); return false; }
    if (!s.focusHighlight) { logger.error("default focusHighlight"); return false; }
    if (!s.phantomWords) { logger.error("default phantomWords"); return false; }
    if (s.anchorPct != 35) { logger.error("default anchorPct"); return false; }

    // Story 3.5: chapterResume enum + default (Auto). Read by the chapter card.
    if (SettingsModel.CHAPTER_RESUME_AUTO != 0) { logger.error("CHAPTER_RESUME_AUTO"); return false; }
    if (SettingsModel.CHAPTER_RESUME_WAIT != 1) { logger.error("CHAPTER_RESUME_WAIT"); return false; }
    if (s.chapterResume != SettingsModel.CHAPTER_RESUME_AUTO) { logger.error("default chapterResume"); return false; }
    return true;
}

(:test)
function settingsApplyDictIsPureAndValidated(logger as Test.Logger) as Boolean {
    // null dict (fresh install) keeps every default.
    var s = new SettingsModel.Settings();
    s.applyDict(null);
    if (s.wpm != 250 || s.anchorPct != 35) { logger.error("null dict not a no-op"); return false; }

    // Valid values apply.
    s.applyDict({
        "wpm" => 600, "pauseMode" => 1, "touchControls" => false, "fontSize" => 2,
        "handedness" => 1, "focusHighlight" => false, "phantomWords" => false, "anchorPct" => 50,
        "chapterResume" => 1
    });
    if (s.wpm != 600) { logger.error("apply wpm"); return false; }
    if (s.pauseMode != SettingsModel.PAUSE_INSTANT) { logger.error("apply pauseMode"); return false; }
    if (s.touchControls) { logger.error("apply touchControls"); return false; }
    if (s.fontSize != 2) { logger.error("apply fontSize"); return false; }
    if (s.handedness != SettingsModel.HAND_LEFT) { logger.error("apply handedness"); return false; }
    if (s.focusHighlight) { logger.error("apply focusHighlight"); return false; }
    if (s.phantomWords) { logger.error("apply phantomWords"); return false; }
    if (s.anchorPct != 50) { logger.error("apply anchorPct"); return false; }
    if (s.chapterResume != SettingsModel.CHAPTER_RESUME_WAIT) { logger.error("apply chapterResume"); return false; }

    // Out-of-range / malformed values degrade to the current value (NFR8/AR24).
    var s2 = new SettingsModel.Settings();
    s2.applyDict({
        "wpm" => 99999, "pauseMode" => 7, "anchorPct" => -5, "fontSize" => -1, "handedness" => "left",
        "chapterResume" => 9
    });
    if (s2.wpm != SettingsModel.WPM_MAX) { logger.error("wpm not clamped"); return false; }
    if (s2.pauseMode != SettingsModel.PAUSE_COAST) { logger.error("bad pauseMode not degraded"); return false; }
    if (s2.anchorPct != 35) { logger.error("bad anchorPct not degraded"); return false; }
    if (s2.fontSize != 0) { logger.error("negative fontSize not degraded"); return false; }
    if (s2.handedness != SettingsModel.HAND_RIGHT) { logger.error("non-number handedness not degraded"); return false; }
    if (s2.chapterResume != SettingsModel.CHAPTER_RESUME_AUTO) { logger.error("bad chapterResume not degraded"); return false; }

    // toDict round-trips through applyDict.
    var s3 = new SettingsModel.Settings();
    s3.applyDict(s.toDict());
    if (s3.wpm != 600 || s3.anchorPct != 50 || s3.pauseMode != 1) { logger.error("toDict round-trip"); return false; }
    if (s3.chapterResume != SettingsModel.CHAPTER_RESUME_WAIT) { logger.error("toDict round-trip chapterResume"); return false; }
    return true;
}

// ── AC2: drift-free advance, baked timing, catch-up cap ──────────────────────

(:test)
function engineWordTimingMath(logger as Test.Logger) as Boolean {
    // 60000/250 = 240 ms per word; bonusMs is added as-is (SPEC §5.1).
    var engine = ReaderEngineTestSupport.driveToPlayingIndexNew(0); // word 0, bonus 0
    if (engine.index() != 0 || !engine.isPlaying()) { logger.error("not playing word 0"); return false; }
    if (engine.currentDuration() != 240) { logger.error("word0 duration != 240"); return false; }

    ReaderEngineTestSupport.stepDue(engine); // word 1, bonus 0
    if (engine.currentDuration() != 240) { logger.error("word1 duration != 240"); return false; }

    ReaderEngineTestSupport.stepDue(engine); // word 2, bonus 100 -> 340
    if (engine.index() != 2) { logger.error("not at word 2"); return false; }
    if (engine.currentDuration() != 340) { logger.error("word2 duration != 340 (60000/250 + 100)"); return false; }
    return true;
}

(:test)
function engineDriftFreeAccumulator(logger as Test.Logger) as Boolean {
    var engine = ReaderEngineTestSupport.newEngine();
    engine.play(0); // RAMP, beat = clamp(240) = RAMP_BEAT_MIN_MS = 400 (Story 3.8, AC5)
    // Tick 5 ms LATE. The engine must advance one beat but set lastAdvance via
    // += duration (400), NOT = now (405). That is the whole point of drift-free.
    engine.onTick(405);
    if (engine.lastAdvance() != 400) { logger.error("lastAdvance drifted to now (expected 400)"); return false; }
    if (engine.rampRemaining() != 2) { logger.error("ramp did not advance one beat"); return false; }
    return true;
}

(:test)
function engineCatchUpCapFourWords(logger as Test.Logger) as Boolean {
    var engine = ReaderEngineTestSupport.driveToPlayingIndexNew(0);
    var anchor = engine.lastAdvance();
    // One tick a long way into the future must advance at MOST 4 words, then
    // resync the accumulator so a stall does not burst through the text.
    engine.onTick(anchor + 100000);
    if (engine.index() != 4) { logger.error("catch-up not capped at 4 words"); return false; }
    if (engine.lastAdvance() != anchor + 100000) { logger.error("accumulator not resynced after cap"); return false; }
    // Normal pace resumes from here.
    ReaderEngineTestSupport.stepDue(engine);
    if (engine.index() != 5) { logger.error("normal pace did not resume after cap"); return false; }
    return true;
}

// ── AC3: WPM change takes effect next word, no re-fetch, no drift ────────────

(:test)
function engineWpmChangeTakesEffectNextWordNoRefetch(logger as Test.Logger) as Boolean {
    var source = new FakeWordSource(ReaderEngineTestSupport.sampleWords());
    var engine = new Reader.ReaderEngine(source, 250, SettingsModel.PAUSE_COAST);
    engine.play(0);
    for (var i = 0; i < Reader.RAMP_BEATS; i++) { ReaderEngineTestSupport.stepDue(engine); }
    if (engine.index() != 0 || engine.currentDuration() != 240) { logger.error("setup: word0 @ 240"); return false; }

    var callsBefore = source.wordAtCalls;
    engine.setWpm(500); // 60000/500 = 120
    // The CURRENT word keeps its already-computed duration (effect is next word).
    if (engine.currentDuration() != 240) { logger.error("wpm change altered current word duration"); return false; }
    // No content re-fetch: changing WPM is pure math, it must not read the source.
    if (source.wordAtCalls != callsBefore) { logger.error("setWpm re-fetched content"); return false; }

    ReaderEngineTestSupport.stepDue(engine); // word 1, bonus 0 -> 120 at new WPM
    if (engine.index() != 1) { logger.error("did not advance to word 1"); return false; }
    if (engine.currentDuration() != 120) { logger.error("new WPM not applied next word"); return false; }
    return true;
}

// ── AC2 (Story 3.3): adaptive WPM step, keyed on the current WPM ──────────────

(:test)
function engineAdaptiveStepUp(logger as Test.Logger) as Boolean {
    // Step keyed on the CURRENT wpm before stepping: 10 below 100, 25 at/above.
    var e90 = ReaderEngineTestSupport.engineAtWpm(90);
    e90.stepWpmUp();
    if (e90.wpm() != 100) { logger.error("up 90 -> 100 (step 10)"); return false; }

    var e100 = ReaderEngineTestSupport.engineAtWpm(100);
    e100.stepWpmUp();
    if (e100.wpm() != 125) { logger.error("up 100 -> 125 (step 25)"); return false; }

    var e250 = ReaderEngineTestSupport.engineAtWpm(250);
    e250.stepWpmUp();
    if (e250.wpm() != 275) { logger.error("up 250 -> 275 (step 25)"); return false; }
    return true;
}

(:test)
function engineAdaptiveStepDown(logger as Test.Logger) as Boolean {
    // The boundary case: down from 100 uses step 25 (current is >= 100) -> 75.
    var e100 = ReaderEngineTestSupport.engineAtWpm(100);
    e100.stepWpmDown();
    if (e100.wpm() != 75) { logger.error("down 100 -> 75 (step 25, keyed on current >= 100)"); return false; }

    var e125 = ReaderEngineTestSupport.engineAtWpm(125);
    e125.stepWpmDown();
    if (e125.wpm() != 100) { logger.error("down 125 -> 100 (step 25)"); return false; }

    var e90 = ReaderEngineTestSupport.engineAtWpm(90);
    e90.stepWpmDown();
    if (e90.wpm() != 80) { logger.error("down 90 -> 80 (step 10)"); return false; }

    var e250 = ReaderEngineTestSupport.engineAtWpm(250);
    e250.stepWpmDown();
    if (e250.wpm() != 225) { logger.error("down 250 -> 225 (step 25)"); return false; }
    return true;
}

(:test)
function engineAdaptiveStepClampsAtEdges(logger as Test.Logger) as Boolean {
    // The step routes through clampWpm: down from WPM_MIN stays, up from WPM_MAX
    // stays (bounds-check-and-degrade — no out-of-range WPM ever reaches timing).
    var lo = ReaderEngineTestSupport.engineAtWpm(SettingsModel.WPM_MIN); // 10
    lo.stepWpmDown();
    if (lo.wpm() != SettingsModel.WPM_MIN) { logger.error("down from WPM_MIN did not clamp"); return false; }

    var hi = ReaderEngineTestSupport.engineAtWpm(SettingsModel.WPM_MAX); // 1000
    hi.stepWpmUp();
    if (hi.wpm() != SettingsModel.WPM_MAX) { logger.error("up from WPM_MAX did not clamp"); return false; }
    return true;
}

(:test)
function engineStepWpmDoesNotInterruptStream(logger as Test.Logger) as Boolean {
    // AC2 "without interrupting the stream": stepping WPM mid-play must NOT alter
    // the CURRENT word's already-computed duration and must NOT re-fetch content —
    // the new pace lands on the next word (stepWpm* route through setWpm).
    var source = new FakeWordSource(ReaderEngineTestSupport.sampleWords());
    var engine = new Reader.ReaderEngine(source, 250, SettingsModel.PAUSE_COAST);
    engine.play(0);
    for (var i = 0; i < Reader.RAMP_BEATS; i++) { ReaderEngineTestSupport.stepDue(engine); }
    if (engine.index() != 0 || engine.currentDuration() != 240) { logger.error("setup: word0 @ 240"); return false; }

    var callsBefore = source.wordAtCalls;
    engine.stepWpmUp(); // 250 -> 275
    if (engine.wpm() != 275) { logger.error("stepWpmUp did not raise wpm"); return false; }
    if (engine.currentDuration() != 240) { logger.error("step altered current word duration"); return false; }
    if (source.wordAtCalls != callsBefore) { logger.error("stepWpmUp re-fetched content"); return false; }
    if (!engine.isPlaying()) { logger.error("stepWpmUp disturbed playing state"); return false; }

    ReaderEngineTestSupport.stepDue(engine); // word 1, bonus 0 -> 60000/275 = 218 at new WPM
    if (engine.index() != 1) { logger.error("did not advance to word 1"); return false; }
    if (engine.currentDuration() != 60000 / 275) { logger.error("new WPM not applied next word"); return false; }
    return true;
}

// ── AC4: 3-beat start ramp ───────────────────────────────────────────────────

(:test)
function engineStartRampThreeBeats(logger as Test.Logger) as Boolean {
    var engine = ReaderEngineTestSupport.newEngine();
    engine.play(0);
    if (!engine.isRamping() || engine.rampRemaining() != 3) { logger.error("play did not arm 3-beat ramp"); return false; }
    ReaderEngineTestSupport.stepDue(engine);
    if (engine.rampRemaining() != 2 || !engine.isRamping()) { logger.error("beat 1"); return false; }
    ReaderEngineTestSupport.stepDue(engine);
    if (engine.rampRemaining() != 1 || !engine.isRamping()) { logger.error("beat 2"); return false; }
    ReaderEngineTestSupport.stepDue(engine);
    if (!engine.isPlaying() || engine.index() != 0 || engine.rampRemaining() != 0) { logger.error("ramp -> word 0"); return false; }

    // Resume after a pause re-arms the ramp (AC4 — on every play/resume).
    var e2 = ReaderEngineTestSupport.newEngine();
    e2.setPauseMode(SettingsModel.PAUSE_INSTANT);
    ReaderEngineTestSupport.driveToPlayingIndex(e2, 1);
    e2.requestPause();
    if (!e2.isPaused()) { logger.error("instant pause"); return false; }
    e2.play(100);
    if (!e2.isRamping() || e2.rampRemaining() != 3) { logger.error("resume did not re-arm ramp"); return false; }
    return true;
}

// ── Story 3.8 AC5 (deferred-work:133 rider): ramp-beat duration clamp ─────────
// Each of the 3 ramp beats is clamped to [RAMP_BEAT_MIN_MS, RAMP_BEAT_MAX_MS]
// independent of WPM — the countdown is neither ~9 s at 20 WPM nor ~360 ms at
// 500 WPM. Normal word beats stay bare 60000/wpm + bonusMs, untouched.

(:test)
function engineRampBeatClampedLowWpm(logger as Test.Logger) as Boolean {
    // wpm 20: word beat = 3000 ms, but each ramp beat clamps DOWN to the max.
    var engine = ReaderEngineTestSupport.engineAtWpm(20);
    engine.play(0);
    // Pin the LITERAL window values, not the constants — comparing against
    // Reader.RAMP_BEAT_MAX_MS would move with a mutated constant and pin
    // nothing (caught by the Task-8 seeded-mutation red-check).
    if (Reader.RAMP_BEAT_MIN_MS != 400 || Reader.RAMP_BEAT_MAX_MS != 1000) {
        logger.error("ramp clamp window constants != [400, 1000]"); return false;
    }
    if (engine.currentDuration() != 1000) {
        logger.error("wpm 20 ramp beat != 1000 (clamp max)"); return false;
    }
    // Ramp is still exactly 3 beats, then the word beat is UNCLAMPED (3000 + bonus 0).
    for (var i = 0; i < Reader.RAMP_BEATS; i++) { ReaderEngineTestSupport.stepDue(engine); }
    if (!engine.isPlaying() || engine.index() != 0) { logger.error("ramp not 3 beats at wpm 20"); return false; }
    if (engine.currentDuration() != 3000) { logger.error("wpm 20 word beat clamped (must stay 3000)"); return false; }
    // Accumulator re-anchor across the ramp is unchanged: 3 clamped beats accrued
    // via += duration, so lastAdvance sits exactly at 3 * RAMP_BEAT_MAX_MS.
    if (engine.lastAdvance() != 3000) {
        logger.error("accumulator drifted across clamped ramp (expected 3 * 1000)"); return false;
    }
    return true;
}

(:test)
function engineRampBeatClampedHighWpm(logger as Test.Logger) as Boolean {
    // wpm 500: word beat = 120 ms, but each ramp beat clamps UP to the min.
    var engine = ReaderEngineTestSupport.engineAtWpm(500);
    engine.play(0);
    if (engine.currentDuration() != 400) {
        logger.error("wpm 500 ramp beat != 400 (clamp min)"); return false;
    }
    for (var i = 0; i < Reader.RAMP_BEATS; i++) { ReaderEngineTestSupport.stepDue(engine); }
    if (!engine.isPlaying() || engine.index() != 0) { logger.error("ramp not 3 beats at wpm 500"); return false; }
    if (engine.currentDuration() != 120) { logger.error("wpm 500 word beat clamped (must stay 120)"); return false; }
    return true;
}

(:test)
function engineRampBeatInsideWindowUnclamped(logger as Test.Logger) as Boolean {
    // A non-divisor wpm whose bare beat falls INSIDE the window passes through:
    // 60000 / 137 = 437 (integer ms), 400 <= 437 <= 1000.
    var engine = ReaderEngineTestSupport.engineAtWpm(137);
    engine.play(0);
    if (engine.currentDuration() != 60000 / 137) {
        logger.error("wpm 137 ramp beat must pass through unclamped"); return false;
    }
    return true;
}

// ── AC5: two-stage pause (coast / instant) ───────────────────────────────────

(:test)
function engineCoastPauseStopsAtSentenceEnd(logger as Test.Logger) as Boolean {
    var engine = ReaderEngineTestSupport.driveToPlayingIndexNew(1); // mid sentence 0
    engine.requestPause();
    // Coast: still playing, not yet at a sentence end.
    if (!engine.isPlaying()) { logger.error("coast paused immediately (should keep playing)"); return false; }
    ReaderEngineTestSupport.stepDue(engine); // -> word 2, which ends the sentence
    if (!engine.isPaused()) { logger.error("coast did not finalize at sentence end"); return false; }
    if (engine.index() != 2) { logger.error("coast stopped at wrong index"); return false; }
    if (engine.lastTransition() != Reader.TRANSITION_PAUSE) { logger.error("no PAUSE transition"); return false; }
    return true;
}

(:test)
function engineInstantPauseStopsImmediately(logger as Test.Logger) as Boolean {
    var engine = ReaderEngineTestSupport.driveToPlayingIndexNew(1);
    engine.setPauseMode(SettingsModel.PAUSE_INSTANT);
    engine.requestPause();
    if (!engine.isPaused()) { logger.error("instant did not pause"); return false; }
    if (engine.index() != 1) { logger.error("instant did not stop on current word"); return false; }
    return true;
}

(:test)
function engineAtEndFinalizesCoastPause(logger as Test.Logger) as Boolean {
    // Coast pause requested before the last word must finalize at the book end
    // (endsSentence || atEnd), NOT run off into FINISHED.
    var engine = ReaderEngineTestSupport.driveToPlayingIndexNew(8); // not a sentence end, not atEnd
    engine.requestPause();
    if (!engine.isPlaying()) { logger.error("coast paused early at word 8"); return false; }
    ReaderEngineTestSupport.stepDue(engine); // -> word 9 (last, sentence end)
    if (!engine.isPaused()) { logger.error("did not finalize coast pause at book end"); return false; }
    if (engine.index() != 9) { logger.error("coast pause stopped at wrong index"); return false; }
    if (engine.isFinished()) { logger.error("coast pause leaked into FINISHED"); return false; }
    return true;
}

// ── AC6: stackable sentence rewind with auto-pause ───────────────────────────

(:test)
function engineRewindStackableClampAutoPause(logger as Test.Logger) as Boolean {
    var engine = ReaderEngineTestSupport.driveToPlayingIndexNew(7); // sentence 2 (starts at 5)
    engine.rewind();
    if (engine.index() != 5) { logger.error("rewind 1 -> start of current sentence (5)"); return false; }
    if (!engine.isPaused()) { logger.error("rewind did not auto-pause"); return false; }
    if (engine.lastTransition() != Reader.TRANSITION_REWIND) { logger.error("no REWIND transition"); return false; }

    engine.rewind(); // already at a sentence start -> previous sentence (starts at 3)
    if (engine.index() != 3) { logger.error("rewind 2 -> previous sentence (3)"); return false; }

    engine.rewind(); // -> sentence 0 (starts at 0)
    if (engine.index() != 0) { logger.error("rewind 3 -> first sentence (0)"); return false; }

    engine.rewind(); // clamp at start, never below 0
    if (engine.index() != 0) { logger.error("rewind did not clamp at start"); return false; }
    return true;
}

// ── Robustness guards (code review 2026-06-21) ───────────────────────────────

(:test)
function engineEmptyBookDoesNotPlayOrFinish(logger as Test.Logger) as Boolean {
    // A 0-word source is not a readable book: play() must refuse to start rather
    // than ramp into a false FINISHED (atEnd() = `_index >= count - 1` is vacuously
    // true at count 0). No bogus TRANSITION_FINISHED for SyncManager to commit.
    var engine = new Reader.ReaderEngine(new FakeWordSource([] as Array<StreamDecoder.WordRecord>), 250, SettingsModel.PAUSE_COAST);
    engine.play(0);
    if (engine.isRamping() || engine.isPlaying()) { logger.error("empty book entered a playable state"); return false; }
    engine.onTick(100000);
    if (engine.isFinished()) { logger.error("empty book faked a FINISHED"); return false; }
    if (engine.state() != Reader.STATE_IDLE) { logger.error("empty book left IDLE"); return false; }
    if (engine.lastTransition() != Reader.TRANSITION_NONE) { logger.error("empty book emitted a transition"); return false; }
    return true;
}

(:test)
function engineRewindFromIdleIsNoOp(logger as Test.Logger) as Boolean {
    // A never-played engine has nothing to rewind: it must NOT flip IDLE to PAUSED
    // or emit a spurious TRANSITION_REWIND.
    var engine = ReaderEngineTestSupport.newEngine();
    engine.rewind();
    if (engine.state() != Reader.STATE_IDLE) { logger.error("rewind from IDLE changed state"); return false; }
    if (engine.index() != 0) { logger.error("rewind from IDLE moved index"); return false; }
    if (engine.lastTransition() != Reader.TRANSITION_NONE) { logger.error("rewind from IDLE emitted a transition"); return false; }
    return true;
}

// ── Natural finish (FINISHED transition for the finished-screen, Story 3.5) ──

(:test)
function engineNaturalFinish(logger as Test.Logger) as Boolean {
    var engine = ReaderEngineTestSupport.driveToPlayingIndexNew(9); // last word, playing
    if (!engine.isPlaying() || engine.index() != 9) { logger.error("setup at last word"); return false; }
    ReaderEngineTestSupport.stepDue(engine); // display last word elapses -> FINISHED
    if (!engine.isFinished()) { logger.error("did not finish at book end"); return false; }
    if (engine.lastTransition() != Reader.TRANSITION_FINISHED) { logger.error("no FINISHED transition"); return false; }
    return true;
}

// ── Story 3.6: seekTo() — the restore/reposition primitive ───────────────────

(:test)
function engineSeekToLandsPausedAndClamps(logger as Test.Logger) as Boolean {
    // From IDLE: lands PAUSED on the exact index with the word's duration ready
    // (word 2 has bonus 100 → 60000/250 + 100 = 340).
    var engine = ReaderEngineTestSupport.newEngine();
    engine.seekTo(2);
    if (!engine.isPaused()) { logger.error("seekTo did not land PAUSED"); return false; }
    if (engine.index() != 2) { logger.error("seekTo missed the index"); return false; }
    if (engine.currentDuration() != 340) { logger.error("seekTo did not recompute duration"); return false; }
    // Clamp below 0 → 0.
    engine.seekTo(-5);
    if (engine.index() != 0 || !engine.isPaused()) { logger.error("seekTo below 0 not clamped"); return false; }
    // Clamp above count-1 → count-1 (at-or-before the last word, never past).
    engine.seekTo(500);
    if (engine.index() != 9 || !engine.isPaused()) { logger.error("seekTo past end not clamped to last word"); return false; }
    return true;
}

(:test)
function engineSeekToFromPlayingAndFinished(logger as Test.Logger) as Boolean {
    // From PLAYING: freezes PAUSED at the target.
    var playing = ReaderEngineTestSupport.driveToPlayingIndexNew(4);
    playing.seekTo(2);
    if (!playing.isPaused() || playing.index() != 2) { logger.error("seekTo from PLAYING"); return false; }
    // From FINISHED: seek repositions out of the terminal state (restore-after-
    // finish relaunch lands sanely, never past the end).
    var finished = ReaderEngineTestSupport.driveToPlayingIndexNew(9);
    ReaderEngineTestSupport.stepDue(finished);
    if (!finished.isFinished()) { logger.error("setup: not finished"); return false; }
    finished.seekTo(3);
    if (!finished.isPaused() || finished.index() != 3) { logger.error("seekTo from FINISHED"); return false; }
    return true;
}

(:test)
function engineSeekToEmptyBookIsNoOp(logger as Test.Logger) as Boolean {
    // An empty book has no word to restore onto — stay IDLE at 0 (the engine's
    // empty-book posture, same as play()).
    var engine = new Reader.ReaderEngine(new FakeWordSource([] as Array<StreamDecoder.WordRecord>), 250, SettingsModel.PAUSE_COAST);
    engine.seekTo(3);
    if (engine.state() != Reader.STATE_IDLE) { logger.error("empty-book seekTo left IDLE"); return false; }
    if (engine.index() != 0) { logger.error("empty-book seekTo moved index"); return false; }
    return true;
}

(:test)
function engineSeekToEmitsNoTransition(logger as Test.Logger) as Boolean {
    // seekTo is a RESTORE, not a user transition — it must not trip a
    // commitPosition of its own (Story 3.6 restore-loop guard).
    var engine = ReaderEngineTestSupport.newEngine();
    engine.seekTo(5);
    if (engine.lastTransition() != Reader.TRANSITION_NONE) { logger.error("seekTo from IDLE emitted a transition"); return false; }
    // And it leaves an existing sticky transition untouched.
    var rewound = ReaderEngineTestSupport.driveToPlayingIndexNew(7);
    rewound.rewind(); // sticky TRANSITION_REWIND
    rewound.seekTo(2);
    if (rewound.lastTransition() != Reader.TRANSITION_REWIND) { logger.error("seekTo overwrote lastTransition"); return false; }
    return true;
}

(:test)
function engineSeekToThenPlayReRampsNoCatchUp(logger as Test.Logger) as Boolean {
    // After a restore, play(now) re-arms the 3-beat ramp AND re-anchors the
    // accumulator to `now` — a relaunch minutes later must not catch-up burst.
    var engine = ReaderEngineTestSupport.newEngine();
    engine.seekTo(5);
    var bigNow = 7777777;
    engine.play(bigNow);
    if (!engine.isRamping() || engine.rampRemaining() != 3) { logger.error("play after seekTo did not re-ramp"); return false; }
    if (engine.lastAdvance() != bigNow) { logger.error("accumulator not re-anchored (catch-up risk)"); return false; }
    ReaderEngineTestSupport.stepDue(engine);
    if (engine.rampRemaining() != 2) { logger.error("burst: advanced more than one beat"); return false; }
    if (engine.index() != 5) { logger.error("play after seekTo moved off the restored word"); return false; }
    return true;
}

// ── Story 3.5: pauseAtCurrent() — instant, mode-independent chapter-card freeze ─

(:test)
function enginePauseAtCurrentFreezesInstantlyEvenInCoast(logger as Test.Logger) as Boolean {
    // Default engine is PAUSE_COAST. word 6 is mid sentence 2 (starts at 5, ends 9):
    // requestPause() would coast to 9, but pauseAtCurrent() must freeze ON word 6 —
    // the chapter card needs the chapter's FIRST word, not the next sentence end.
    var engine = ReaderEngineTestSupport.driveToPlayingIndexNew(6);
    if (engine.pauseMode() != SettingsModel.PAUSE_COAST) { logger.error("setup: not coast"); return false; }
    engine.pauseAtCurrent();
    if (!engine.isPaused()) { logger.error("pauseAtCurrent did not pause"); return false; }
    if (engine.index() != 6) { logger.error("pauseAtCurrent overran the current word"); return false; }
    if (engine.lastTransition() != Reader.TRANSITION_PAUSE) { logger.error("no PAUSE transition"); return false; }
    return true;
}

(:test)
function enginePauseAtCurrentResumeReAnchorsNoCatchUp(logger as Test.Logger) as Boolean {
    // Resume from a card is plain play(now): it re-arms the 3-beat ramp AND re-anchors
    // the accumulator to `now`, so a long card gap does NOT burst through the text.
    var engine = ReaderEngineTestSupport.driveToPlayingIndexNew(6);
    engine.pauseAtCurrent();
    var bigNow = 5000000; // a far-future resume timestamp (the ~2 s card + clock)
    engine.play(bigNow);
    if (!engine.isRamping() || engine.rampRemaining() != 3) { logger.error("resume did not re-arm ramp"); return false; }
    if (engine.lastAdvance() != bigNow) { logger.error("accumulator not re-anchored to now (catch-up risk)"); return false; }
    // One due tick advances exactly one ramp beat (no burst), staying on word 6.
    ReaderEngineTestSupport.stepDue(engine);
    if (engine.rampRemaining() != 2) { logger.error("burst: advanced more than one beat"); return false; }
    if (engine.index() != 6) { logger.error("resume moved off the carded word"); return false; }
    return true;
}

(:test)
function enginePauseAtCurrentNoOpFromIdlePausedFinished(logger as Test.Logger) as Boolean {
    // IDLE: nothing playing -> no state change, no transition.
    var idle = ReaderEngineTestSupport.newEngine();
    idle.pauseAtCurrent();
    if (idle.state() != Reader.STATE_IDLE) { logger.error("pauseAtCurrent left IDLE"); return false; }
    if (idle.lastTransition() != Reader.TRANSITION_NONE) { logger.error("IDLE emitted a transition"); return false; }

    // PAUSED: already frozen -> no-op (index unchanged, still paused).
    var paused = ReaderEngineTestSupport.driveToPlayingIndexNew(3);
    paused.setPauseMode(SettingsModel.PAUSE_INSTANT);
    paused.requestPause();
    if (!paused.isPaused() || paused.index() != 3) { logger.error("setup: not paused at 3"); return false; }
    paused.pauseAtCurrent();
    if (!paused.isPaused() || paused.index() != 3) { logger.error("pauseAtCurrent disturbed PAUSED"); return false; }

    // FINISHED: terminal -> no-op (stays finished).
    var finished = ReaderEngineTestSupport.driveToPlayingIndexNew(9);
    ReaderEngineTestSupport.stepDue(finished); // -> FINISHED
    if (!finished.isFinished()) { logger.error("setup: not finished"); return false; }
    finished.pauseAtCurrent();
    if (!finished.isFinished()) { logger.error("pauseAtCurrent disturbed FINISHED"); return false; }
    return true;
}

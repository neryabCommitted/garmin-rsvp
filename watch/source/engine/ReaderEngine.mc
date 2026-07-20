import Toybox.Lang;

// Pure RSVP reading engine (FR2, FR3, FR8, FR10, FR13). Host-testable by design:
// imports ONLY Toybox.Lang — no Toybox.WatchUi, no Toybox.Communications, no
// Toybox.System (AC7). The clock is INJECTED: every time-dependent method takes a
// `now` (ms) so host tests drive time deterministically and so a real
// System.getTimer() wraparound can be guarded at the seam rather than read
// internally.
//
// What it owns (Story 3.1): the WPM field + `60000/wpm + bonusMs` integer-ms
// timing, the drift-free `lastAdvance += duration` accumulator with a ~4-word
// catch-up cap, the 3-beat start ramp, coast/instant pause keyed on
// FLAG_SENTENCE_END, stackable auto-pausing sentence rewind, and the 0-based
// absolute-index position. It renders no pixels and writes no Storage.
module Reader {

    // Engine lifecycle states.
    const STATE_IDLE = 0;     // constructed, not yet played
    const STATE_RAMP = 1;     // 3-beat start lead-in before the stream
    const STATE_PLAYING = 2;  // streaming words
    const STATE_PAUSED = 3;   // frozen on a word (coast/instant/rewind)
    const STATE_FINISHED = 4; // ran off the end of the book

    // Clean transition surface for Story 3.6's SyncManager.commitPosition(force)
    // to hook WITHOUT engine rework — the consumer reads lastTransition() after
    // driving the engine. CHUNK_BOUNDARY is reserved for Epic 4 (no chunks here).
    const TRANSITION_NONE = 0;
    const TRANSITION_PAUSE = 1;
    const TRANSITION_REWIND = 2;
    const TRANSITION_CHUNK_BOUNDARY = 3;
    const TRANSITION_FINISHED = 4;

    // Start ramp: 3 beats (3-2-1) before the first real word (AC4) — the
    // explicit fix for RSVPnano's cold start.
    const RAMP_BEATS = 3;

    // Ramp-beat duration clamp (Story 3.8, AC5 — deferred-work:133). The
    // countdown is a fixed READINESS cue, not content: at the WPM extremes a
    // bare 60000/wpm beat makes it ~9 s at 20 WPM or ~360 ms at 500 WPM. Each
    // ramp beat clamps to this window, independent of WPM; normal word beats
    // are untouched.
    const RAMP_BEAT_MIN_MS = 400;
    const RAMP_BEAT_MAX_MS = 1000;

    // Catch-up cap (~4 words) — absorb a single delayed tick without bursting
    // through the text at a multiple of WPM (AR13). Beats during the ramp also
    // count as steps.
    const CATCHUP_CAP = 4;

    class ReaderEngine {
        private var _source as BookWordSource;
        private var _wpm as Number;        // read live; takes effect next word (AC3)
        private var _pauseMode as Number;  // SettingsModel.PAUSE_COAST / PAUSE_INSTANT

        private var _index as Number;      // 0-based absolute word index (FR13)
        private var _state as Number;
        private var _lastAdvance as Number;     // drift-free accumulator (ms)
        private var _currentDuration as Number; // display ms of the current beat/word
        private var _rampRemaining as Number;   // 3..0 during the start ramp
        private var _pausePending as Boolean;    // coast pause awaiting a sentence end
        private var _lastTransition as Number;

        // Seed from the Settings model: the caller passes primitives so the engine
        // never touches Storage and holds no Settings instance. It does depend on
        // SettingsModel *constants* (WPM_MIN/WPM_MAX for the clamp, PAUSE_INSTANT
        // for the pause-mode check) — a benign compile-time dependency, not a
        // Storage one. WPM is clamped to the valid range.
        function initialize(source as BookWordSource, wpm as Number, pauseMode as Number) {
            _source = source;
            _wpm = clampWpm(wpm);
            _pauseMode = pauseMode;
            _index = 0;
            _state = STATE_IDLE;
            _lastAdvance = 0;
            _currentDuration = 0;
            _rampRemaining = 0;
            _pausePending = false;
            _lastTransition = TRANSITION_NONE;
            _source.prefetchAround(_index);
        }

        // ── playback control ──

        // Start or resume. Every play/resume re-arms the 3-beat ramp (AC4). `now`
        // anchors the drift-free accumulator. No-op while already running, and
        // FINISHED is terminal until a rewind repositions the index.
        function play(now as Number) as Void {
            if (_state == STATE_PLAYING || _state == STATE_RAMP || _state == STATE_FINISHED) {
                return;
            }
            // A 0-word source is not a readable book — refuse to start rather than
            // ramp straight into a false FINISHED (atEnd() is `_index >= count - 1`,
            // which is vacuously true when count == 0). The base BookWordSource and
            // an unbuffered ChunkedWordSource (Epic 4) can both report count 0; the
            // engine must NOT emit a bogus TRANSITION_FINISHED for an empty book.
            if (_source.wordCount() <= 0) {
                return;
            }
            _state = STATE_RAMP;
            _rampRemaining = RAMP_BEATS;
            _pausePending = false;
            _lastAdvance = now;
            _currentDuration = computeDuration();
        }

        // Two-stage pause (AC5). Instant (and a pause during the ramp) stops on the
        // current word immediately; coast advances to the next FLAG_SENTENCE_END (or
        // the last word of the book) then stops.
        function requestPause() as Void {
            if (_state != STATE_PLAYING && _state != STATE_RAMP) {
                return;
            }
            if (_pauseMode == SettingsModel.PAUSE_INSTANT || _state == STATE_RAMP) {
                finalizePause();
                return;
            }
            if (endsSentenceAt(_index) || atEnd()) {
                finalizePause();
            } else {
                _pausePending = true;
            }
        }

        // Instant, mode-INDEPENDENT freeze on the current word (Story 3.5, AC1). The
        // chapter card must stop ON the chapter's first word the instant it appears;
        // requestPause() in PAUSE_COAST would coast to the next sentence end and
        // overrun it. Reuses the existing instant-pause path (finalizePause)
        // unconditionally. No-op unless PLAYING or RAMP (IDLE/PAUSED/FINISHED stay
        // put). Resume is plain play(now), the only lever that re-anchors
        // _lastAdvance — so the ~2 s card does NOT trigger onTick's catch-up burst.
        // Engine stays Lang-only.
        function pauseAtCurrent() as Void {
            if (_state != STATE_PLAYING && _state != STATE_RAMP) {
                return;
            }
            finalizePause();
        }

        // Stackable sentence rewind with auto-pause (AC6). Moves to the start of the
        // current sentence; if already at a sentence start, steps back to the
        // previous sentence. Clamps at word 0. Always auto-pauses.
        function rewind() as Void {
            // A never-played engine has nothing to rewind — don't flip IDLE to
            // PAUSED or emit a spurious TRANSITION_REWIND. (Rewind from FINISHED is
            // intentional: FINISHED is terminal until a rewind repositions.)
            if (_state == STATE_IDLE) {
                return;
            }
            var target = sentenceStartAtOrBefore(_index);
            if (target >= _index && target > 0) {
                target = sentenceStartAtOrBefore(target - 1);
            }
            _index = target;
            _source.prefetchAround(_index);
            _state = STATE_PAUSED;
            _pausePending = false;
            _currentDuration = computeDuration();
            setTransition(TRANSITION_REWIND);
        }

        // Restore/reposition primitive (Story 3.6, AC2). Lands the engine PAUSED
        // on `index`, clamped to [0, wordCount - 1] — at-or-before the last word,
        // never past it. This is the general reposition rewind() is not: rewind
        // only lands on sentence starts. Landing PAUSED lets the view's existing
        // onShow STATE_IDLE guard keep a restored engine frozen (resume lands
        // Paused) with zero onShow change. Unlike rewind() it emits NO transition:
        // seek is a restore, not a user action — it must not trip a commit of its
        // own. Empty book → no-op, stay IDLE (nothing to restore onto). Resume is
        // plain play(now), which re-anchors the accumulator (no catch-up burst).
        function seekTo(index as Number) as Void {
            var count = _source.wordCount();
            if (count <= 0) {
                return;
            }
            var target = index;
            if (target < 0) { target = 0; }
            if (target > count - 1) { target = count - 1; }
            _index = target;
            _state = STATE_PAUSED;
            _pausePending = false;
            _source.prefetchAround(_index);
            _currentDuration = computeDuration();
        }

        // Drive time forward. Advances as many beats/words as are due, capped at
        // CATCHUP_CAP per call. NEVER assigns `lastAdvance = now` on the normal
        // path — only `+= duration` (drift-free, AR13). The two exceptions are a
        // getTimer() wraparound (negative elapsed → resync) and hitting the
        // catch-up cap (we are >cap words behind → resync so a long stall does not
        // burst through the text).
        function onTick(now as Number) as Void {
            if (_state != STATE_PLAYING && _state != STATE_RAMP) {
                return;
            }
            var steps = 0;
            while (steps < CATCHUP_CAP) {
                var elapsed = now - _lastAdvance;
                if (elapsed < 0) {
                    _lastAdvance = now; // System.getTimer() wraparound guard
                    return;
                }
                if (elapsed < _currentDuration) {
                    return; // current beat/word still on screen
                }
                _lastAdvance += _currentDuration; // drift-free accumulator
                stepOnce();
                steps += 1;
                if (_state != STATE_PLAYING && _state != STATE_RAMP) {
                    return; // paused (coast finalize) or finished mid-catch-up
                }
            }
            _lastAdvance = now; // hit the cap — resync to resume at normal pace
        }

        // ── live mutators ──

        // WPM takes effect on the NEXT word, with no content re-fetch and no drift
        // (AC3): the current beat/word keeps its already-computed duration; only the
        // next computeDuration() reads the new value.
        function setWpm(wpm as Number) as Void {
            _wpm = clampWpm(wpm);
        }

        function setPauseMode(pauseMode as Number) as Void {
            _pauseMode = pauseMode;
        }

        // Adaptive WPM step (AC2, Story 3.3). The step rule's ONE encoding is
        // SettingsModel.adaptiveWpmStep (moved there in Story 3.8 so the WPM
        // stepper editor shares it — behavior unchanged, the 3.3 test pins
        // prove it): 10 below 100 wpm, 25 at/above, clamped to
        // [WPM_MIN, WPM_MAX]. Routed through setWpm, so the change still takes
        // effect on the NEXT word with no re-fetch and no drift (AC2: the
        // stream is never interrupted). Engine stays Lang-only — no
        // System/WatchUi (SettingsModel constants/functions are the same
        // benign compile-time dependency initialize() already has).
        function stepWpmUp() as Void {
            setWpm(SettingsModel.adaptiveWpmStep(_wpm, true));
        }

        function stepWpmDown() as Void {
            setWpm(SettingsModel.adaptiveWpmStep(_wpm, false));
        }

        // ── position & transition surface (Task 7 — read by SyncManager later) ──

        function index() as Number { return _index; }
        function state() as Number { return _state; }
        function wpm() as Number { return _wpm; }
        function pauseMode() as Number { return _pauseMode; }
        function rampRemaining() as Number { return _rampRemaining; }
        function isRamping() as Boolean { return _state == STATE_RAMP; }
        function isPlaying() as Boolean { return _state == STATE_PLAYING; }
        function isPaused() as Boolean { return _state == STATE_PAUSED; }
        function isFinished() as Boolean { return _state == STATE_FINISHED; }
        function lastTransition() as Number { return _lastTransition; }

        // The timestamp the current beat/word began and its duration — the view
        // layer (Story 3.2) uses these to arm its next timer; tests use them to
        // prove the drift-free accumulator.
        function lastAdvance() as Number { return _lastAdvance; }
        function currentDuration() as Number { return _currentDuration; }

        // The record currently on screen, or null (book empty / index unbuffered).
        function currentRecord() as StreamDecoder.WordRecord? {
            return _source.wordAt(_index);
        }

        // ── internals ──

        // Advance exactly one beat or word. Recomputes the current duration so the
        // catch-up loop tests the next item against the correct duration.
        private function stepOnce() as Void {
            if (_state == STATE_RAMP) {
                _rampRemaining -= 1;
                if (_rampRemaining <= 0) {
                    _state = STATE_PLAYING; // first real word (_index) now on screen
                }
                _currentDuration = computeDuration();
                return;
            }
            // STATE_PLAYING: finished displaying _index.
            if (atEnd()) {
                _state = STATE_FINISHED;
                setTransition(TRANSITION_FINISHED);
                return;
            }
            _index += 1;
            _source.prefetchAround(_index);
            _currentDuration = computeDuration();
            if (_pausePending && (endsSentenceAt(_index) || atEnd())) {
                finalizePause();
            }
        }

        private function finalizePause() as Void {
            _state = STATE_PAUSED;
            _pausePending = false;
            setTransition(TRANSITION_PAUSE);
        }

        private function setTransition(kind as Number) as Void {
            _lastTransition = kind;
        }

        // displayMs = 60000/wpm + bonusMs (SPEC §5.1) — integer ms, never float.
        // bonusMs comes straight from the record; the engine recomputes no
        // linguistics. Ramp beats are 60000/wpm (no word yet) clamped to
        // [RAMP_BEAT_MIN_MS, RAMP_BEAT_MAX_MS] (Story 3.8, AC5 — the countdown
        // is a readiness cue, bounded independent of WPM).
        private function computeDuration() as Number {
            if (_state == STATE_RAMP) {
                var beat = beatMs();
                if (beat < RAMP_BEAT_MIN_MS) { return RAMP_BEAT_MIN_MS; }
                if (beat > RAMP_BEAT_MAX_MS) { return RAMP_BEAT_MAX_MS; }
                return beat;
            }
            var rec = _source.wordAt(_index);
            if (rec == null) {
                return beatMs(); // degrade: unbuffered/empty → a bare beat
            }
            return beatMs() + rec.bonusMs;
        }

        private function beatMs() as Number {
            return 60000 / _wpm; // _wpm clamped >= WPM_MIN, never zero
        }

        // atEnd = the index is the LAST word of the WHOLE book (wordCount is the
        // true book length, not the buffer) — the Story 2.1 carry-forward contract.
        private function atEnd() as Boolean {
            return _index >= _source.wordCount() - 1;
        }

        private function endsSentenceAt(index as Number) as Boolean {
            var rec = _source.wordAt(index);
            if (rec == null) {
                return false; // bounds-check-and-degrade (NFR8/AR24)
            }
            return (rec.flags & Protocol.FLAG_SENTENCE_END) != 0;
        }

        // The first word of the sentence containing `index`: the word just after
        // the nearest preceding FLAG_SENTENCE_END, or 0. Clamp-at-start, never
        // below 0. Mirrors RSVP Nano's sentenceStartAtOrBefore().
        private function sentenceStartAtOrBefore(index as Number) as Number {
            if (index <= 0) {
                return 0;
            }
            for (var k = index - 1; k >= 0; k--) {
                if (endsSentenceAt(k)) {
                    return k + 1;
                }
            }
            return 0;
        }

        private function clampWpm(wpm as Number) as Number {
            if (wpm < SettingsModel.WPM_MIN) { return SettingsModel.WPM_MIN; }
            if (wpm > SettingsModel.WPM_MAX) { return SettingsModel.WPM_MAX; }
            return wpm;
        }
    }
}

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// The watch RSVP render surface + the timer-driven render loop that drives the
// Story 3.1 ReaderEngine over the Epic-3 canned word source — the first pixels of
// Epic 3 (FR1, FR7). It OWNS the engine/source/settings/timer; it only READS
// engine state and never lets the engine reference it back (AR15, refcount GC, no
// cycle collection).
//
// Scope (Story 3.2): ORP word composition, split guides, phantoms, long-word
// margin-clamp, burn-in jitter, and the per-word timer loop with auto-play on show.
//
// Story 3.3 adds a small ACTION API (pauseOrResume / stepWpm / rewindOne, plus
// the Settings-reading helpers the delegate needs) and a TRANSIENT WPM readout.
// Input flows delegate -> view -> engine only; the view still never references
// the delegate, and the engine never references the view (AR15, no cycle). The
// readout is the ONE allowed playing-state overlay (per UX): it is Ink-Dim (dim,
// not bright) and self-clearing, so it does NOT violate Story 3.2 AC5's "no
// persistent BRIGHT chrome while words flow".
//
// Story 3.4 adds the PAUSED-only progress readout (drawPausedReadout — book %,
// time-left, WPM in Ink-Dim, drawn ONLY while engine.isPaused, never while words
// flow — UX-DR8) and openContextView() (pushes the scrollable PausedContextView).
// onShow's auto-play is now guarded to STATE_IDLE so a pop-back from the context
// view stays PAUSED (AC3) instead of resuming. While words flow the view still
// draws NO persistent bright chrome ("the screen owes the reader nothing but the
// word").
//
// Story 3.7 adds display survival (amended 2026-07-17 to APP-MODE, ADR 0003):
// the view owns a DisplayStrategy (base type only, built via
// Display.createStrategy() — AC3 seam). The shipped strategy is the inert
// app-mode base — no activity session, no Fit permission; the watch's own
// display settings govern the screen and words keep flowing through dim
// (hardware-validated 2026-07-16/17). The strategy lifecycle calls at the
// play sites and App exit are kept (no-ops today) so the "PaceTurner Active"
// session variant swaps in behind the factory untouched. The App routes
// onDisplayModeChanged here: an unreadable mode (Display.shouldPauseForMode —
// OFF or unknown) freezes playback instantly (pauseAtCurrent — coast must not
// flow words onto a dark screen) with a force-save; a wake repaints the Paused
// frame and NEVER auto-resumes, and the waking tap/press is swallowed by the
// wake-grace guard in the action API.
class PlaybackView extends WatchUi.View {

    // ── DESIGN palette (DESIGN.md Colors 102-113) — one place, by name, no inline
    // hex at draw sites. "One red, one job": PIVOT is the pivot letter + anchor
    // ticks only, never chrome.
    private const COLOR_VOID = 0x000000;       // true-black AMOLED canvas
    private const COLOR_INK = 0xEAE6DF;         // focal word
    private const COLOR_INK_FAINT = 0x45423E;   // guides + phantoms
    private const COLOR_INK_DIM = 0x8A867F;     // transient WPM readout (watch-meta)
    private const COLOR_PIVOT = 0xFF5349;       // pivot letter + anchor ticks

    // ── composition geometry (DESIGN / mockups/key-playback.html, a 454-px
    // starting point — recalibrated against dc.getWidth()/measured widths, never
    // hardcoding 454). The anchor column comes from dc.getWidth(); these offsets
    // are absolute px tuned for the 454-px fenix847mm target.
    private const WATCH_EDGE = 28;        // guide-hairline span inset / normal margin
    // The focal word may use a smaller inset than the guides: at the vertical center
    // of a ROUND display the full diameter is available, so a wide word can fill more
    // width (and thus take a larger, more legible native font) without clipping on
    // the corners. Fit-to-width and the focal word's margin-clamp both use this.
    private const FOCAL_EDGE = 8;         // AC4 focal-word fit/clamp inset
    private const HAIRLINE_OFFSET = 44;   // guide hairline distance above/below center
    private const GAP_HALF = 16;          // half-width of the anchor-column gap
    private const TICK_LEN = 10;          // anchor-tick length
    private const PHANTOM_GAP = 18;       // gap between focal word and a phantom

    // ── word-display font ramp (font seam, Task 5 — resolved in ONE place via
    // fontFor()). Native font ramp = the documented escape hatch (DESIGN typography;
    // architecture.md:305): index 0 is the largest native text face (the default
    // reading size); higher indices step DOWN. The Atkinson Hyperlegible BMFont is a
    // localized later swap behind THIS seam, its own follow-up story — not here.
    private const RAMP_LENGTH = 5;

    // ── timer ──
    private const TIMER_FLOOR_MS = 50;    // platform timer floor (AR13)

    // ── transient WPM readout (AC2) ──
    // Flashed for ~900 ms on a WPM step, then self-clears: the playback tick loop
    // repaints every word, so the first repaint past the deadline simply drops it.
    // "Visible when you look for it, invisible at reading speed" (DESIGN.md:122).
    private const READOUT_MS = 900;

    // ── chapter card (Story 3.5, AC1) ──
    // How long an Auto card breathes before flow resumes ("~2 s"; tune on device).
    // It doubles as the Epic-4 prefetch breath (the prefetch trigger is wired later).
    private const CHAPTER_CARD_MS = 2000;
    // Card-screen insets: the title sits at the vertical center where the full
    // diameter is available, so the guide margin is enough to keep it off the edge.
    private const CARD_EDGE = 28;

    private var _settings as SettingsModel.Settings;
    private var _source as CannedWordSource;
    private var _engine as Reader.ReaderEngine;
    private var _sync as Sync.SyncManager;
    private var _display as Display.DisplayStrategy;
    private var _timer as Timer.Timer;
    private var _fontIndex as Number;

    // System.getTimer() of the last unreadable→readable display transition
    // (null = never woken). Feeds the wake-tap grace guard (Story 3.7, AC2):
    // the press/tap that wakes the display must not toggle playback or move
    // position if the firmware also delivers it to the delegate.
    private var _lastWakeMs as Number?;

    // shouldPauseForMode verdict of the LAST observed display mode, so the
    // grace window opens ONLY on the unreadable→readable edge (a real wake,
    // Display.isWakeTransition). Without it, the routine HIGH→LOW dim and the
    // LOW→HIGH brighten a button press itself causes would each open a 400 ms
    // window that eats deliberate input (review 2026-07-20). Initialized
    // false: an app can only be launched/interacted with on a readable
    // display, and callbacks report transitions only.
    private var _lastModeUnreadable as Boolean;

    // The display reached OFF at least once this session (Story 3.7 app-mode,
    // Task 6): with general-use AOD on and the watch worn, OFF never arrives —
    // so an observed OFF is the evidence that the AOD setting is off (or the
    // watch was off-wrist) and the paused frame earns the one-line setting
    // hint. View-owned: the app-mode strategy keeps no session to scope it to.
    private var _sawDisplayOff as Boolean;

    // Per-session burn-in jitter applied to the WHOLE composition (AC5). Bounded
    // random walk in [-2, +2] px; recomputed per session/per-pause, NEVER per word
    // (the anchor must feel stable while reading).
    private var _jitterX as Number;
    private var _jitterY as Number;

    // ms deadline until which the transient WPM readout is drawn (0 = not showing).
    // Set in stepWpm(); compared against System.getTimer() in onUpdate.
    private var _wpmReadoutUntil as Number;

    // ── chapter-card mode state (Story 3.5) ──
    // _chapterCard: the card-draw mode is active (engine frozen on the chapter's
    // first word). _cardedIndex: the word index a card was last raised for, so the
    // just-resumed chapter-start word does not immediately re-card (the next
    // chapter's index is naturally distinct). _cardChapterNum/_cardChapterTitle:
    // the snapshot drawn on the card. The Auto deadline is owned by the one-shot
    // timer (onCardTimeout), so no separate _cardUntil field is needed.
    private var _chapterCard as Boolean;
    private var _cardedIndex as Number;
    private var _cardChapterNum as Number;
    private var _cardChapterTitle as String?;

    // Settings.wpm was synced from an in-flow UP/DOWN step but not yet
    // persisted (Story 3.8, Task 5 decision): stepWpm mutates the engine AND
    // mirrors the value into _settings memory-only, and onHide saves iff this
    // flag is set — the cold-path transition, never the hot tick path
    // (deferred-work:129 flash-write hazard). Menu/stepper edits save
    // immediately and clear it (applyWpm).
    private var _settingsDirty as Boolean;

    function initialize() {
        View.initialize();
        _settings = new SettingsModel.Settings();
        _settings.loadFrom(); // overlay persisted values; defaults on fresh install
        _source = new CannedWordSource(); // decodes the dev stream once, at startup
        _engine = new Reader.ReaderEngine(_source, _settings.wpm, _settings.pauseMode);
        // Story 3.6 (AC2): restore the saved position BEFORE the first onShow.
        // SyncManager is the single pos_* writer, keyed on the source's book
        // identity; a saved position seeks the engine to PAUSED at-or-before the
        // saved word (never past it — loadPosition clamps/degrades), and the
        // existing onShow STATE_IDLE guard then skips auto-play, so resume lands
        // Paused with zero onShow change. A fresh install restores null and
        // leaves the engine IDLE at 0 — the first-launch auto-play demo applies
        // only to that case. Order matters: _source → _engine → restore.
        _sync = new Sync.SyncManager(_source.bookId());
        var restored = _sync.loadPosition(_source.wordCount());
        if (restored != null) {
            _engine.seekTo(restored);
        }
        // Resolve the unbounded persisted fontSize against the ramp (3.1 deferred #1).
        _fontIndex = OrpLayout.clampFontIndex(_settings.fontSize, RAMP_LENGTH);
        // Story 3.7 (AC3): built via the factory, held as the BASE type — the
        // view never names a concrete strategy. App-mode ships the inert base
        // (ADR 0003); the lifecycle calls at the play sites stay wired so the
        // Active variant's session strategy swaps in behind the factory only.
        _display = Display.createStrategy();
        _lastWakeMs = null;
        _lastModeUnreadable = false;
        _sawDisplayOff = false;
        _timer = new Timer.Timer();
        _jitterX = 0;
        _jitterY = 0;
        _wpmReadoutUntil = 0;
        _chapterCard = false;
        _cardedIndex = -1; // no card raised yet (word 0 is chapter 1 but never cards)
        _cardChapterNum = 0;
        _cardChapterTitle = null;
        _settingsDirty = false;
    }

    // Auto-play on show so playback is demonstrable without input (Story 3.3 owns
    // controls). One machine-readable readiness marker to the app log — NEVER a
    // per-word println (the 700-WPM logging anti-pattern, AR25).
    function onShow() as Void {
        recomputeJitter();
        // Auto-play ONLY from a never-played engine (first-launch demo, 3.2/3.3).
        // When the Story 3.4 context view is popped, the revealed PlaybackView fires
        // onShow again — guarding on STATE_IDLE keeps it PAUSED (AC3) instead of
        // resuming. Becoming visible while live re-arms the loop; PAUSED/FINISHED
        // stay frozen with no timer. Pre-aligns with Story 3.6 "resume lands Paused".
        if (_chapterCard) {
            // Shown again while a chapter card is up (e.g. a system overlay/notification
            // covered then revealed us mid-breath). onHide stopped the timer and the
            // engine is PAUSED behind the card, so neither branch below would re-arm it
            // — an Auto card would silently become a Wait card. Re-arm the Auto breath;
            // a Wait card legitimately holds for START (Story 3.5, AC1).
            if (_settings.chapterResume == SettingsModel.CHAPTER_RESUME_AUTO) {
                armCardTimer();
            }
        } else if (_engine.state() == Reader.STATE_IDLE) {
            // Play-site display guard (review 2026-07-20): never auto-play
            // onto an unreadable screen — stay IDLE; a later deliberate START
            // (on a readable display) starts the demo instead.
            if (!displayUnreadableNow()) {
                _engine.play(System.getTimer()); // first-launch demo auto-play; no-op if empty
                armTimer();
                _display.onPlaybackStart(); // strategy lifecycle (3.7; app-mode no-op)
            }
        } else if (_engine.isPlaying() || _engine.isRamping()) {
            armTimer(); // became visible while live — keep the loop running
        }
        System.println(Lang.format("PlaybackView ready: words=$1$ wpm=$2$ fontIdx=$3$",
            [_source.wordCount(), _engine.wpm(), _fontIndex]));
        WatchUi.requestUpdate();
    }

    function onHide() as Void {
        // Becoming hidden (carousel navigation, a system overlay) is a catchable
        // transition — force-save before the timer stops (Story 3.6, AC1).
        commitPosition(true);
        // Persist an in-flow WPM step, if any (Story 3.8, Task 5 decision):
        // stepWpm syncs _settings.wpm memory-only; this cold-path save is what
        // keeps a stepped speed across relaunch without a hot-tick flash write.
        // Also fires when the settings menu is pushed over us — harmless.
        saveDirtySettings();
        _timer.stop();
    }

    // Flush a pending in-flow WPM step (Story 3.8, Task 5 + review 2026-07-23).
    // Called from onHide (the common carousel path) AND from App.onStop via the
    // cold-path exit hook, so a stepped speed survives a kill that reaches
    // onStop but skips onHide — symmetric with commitOnStop for position. Cold
    // path, once per transition/exit: no hot-tick flash-write hazard.
    function saveDirtySettings() as Void {
        if (_settingsDirty) {
            _settings.save();
            _settingsDirty = false;
        }
    }

    // ── position persistence routing (Story 3.6, AC1) ──
    // The ONE routing point for position writes in this view: every catchable
    // transition funnels here; Sync.SyncManager owns the debounce/force gate and
    // is the only Storage writer of the pos_* key. Call sites are the contract:
    // onTimerTick playing branch (debounced), onTimerTick paused/finished branch
    // (force — covers coast-finalize, instant-pause settle, and FINISHED),
    // rewindOne (force — rewind-while-paused arms no pending tick), the chapter-
    // card freeze (force — the Epic-4 chunk-boundary analog), onHide (force),
    // the unreadable-display auto-pause in onDisplayModeChanged (force — the
    // screen may stay dark indefinitely, Story 3.7), and the App's onStop via
    // commitOnStop (force). Chunk-boundary/disconnect proper are Epic-4
    // transitions — reserved, no BLE/chunks here.
    private function commitPosition(force as Boolean) as Void {
        // Empty-book guard (review 2026-07-14): a decode-degraded session
        // (wordCount 0 — CannedWordSource degrades instead of crashing) still
        // reports the real bookId, so an unguarded force-save on hide/exit
        // would write {"pos"=>0} over the good saved record — destroying the
        // one state this story declares sacred. No readable book ⇒ no writes.
        if (_source.wordCount() <= 0) {
            return;
        }
        _sync.commitPosition(_engine.index(), force, System.getTimer());
    }

    // Best-effort exit save — the App calls this from onStop (Story 3.6, Task 6).
    function commitOnStop() as Void {
        commitPosition(true);
    }

    // ── display survival (Story 3.7) ──
    // The App routes its AppBase-only onDisplayModeChanged callback here; the
    // view coordinates the engine reaction (the strategy only bookkeeps — it
    // never references engine or view, AR15).
    function onDisplayModeChanged(mode as Number) as Void {
        _display.onDisplayModeChanged(mode); // strategy bookkeeping (no-op in app-mode)
        if (mode == System.DISPLAY_MODE_OFF as Number) { // AOD-hint evidence (Task 6)
            _sawDisplayOff = true;
        }
        var unreadable = Display.shouldPauseForMode(mode);
        var wasUnreadable = _lastModeUnreadable;
        _lastModeUnreadable = unreadable;
        if (unreadable && _chapterCard) {
            // A pending Auto-card breath would resume the stream onto a black
            // screen — cancel it. The card holds like a Wait card until START
            // (a one-off Auto→Wait demotion for THIS card; deliberately not
            // re-armed on wake — "never mid-stream" wins over the ~2 s breath).
            _timer.stop();
        } else if (unreadable && (_engine.isPlaying() || _engine.isRamping())) {
            // Unreadable while words flow: freeze INSTANTLY at the current
            // word. pauseAtCurrent, NOT requestPause — coast mode would keep
            // flowing words to the sentence end on a screen the user can't
            // read (AC2). Already handles RAMP (Story 3.5). The pending
            // one-shot tick then fires once into onTimerTick's paused branch —
            // harmless (commit dedupes via _lastWrittenIndex, jitter refreshes).
            _engine.pauseAtCurrent();
            commitPosition(true); // the screen may stay dark indefinitely
            recomputeJitter();
            WatchUi.requestUpdate();
        } else if (!unreadable) {
            // Readable again: repaint the Paused still-frame. The grace window
            // opens ONLY on a true wake — the unreadable→readable EDGE
            // (Display.isWakeTransition) — never on dim/brighten transitions
            // between readable modes, which would eat deliberate input
            // (review 2026-07-20). NEVER play()/resumeFromCard() here — wake
            // finds Paused; resume is a deliberate START (AC2).
            if (Display.isWakeTransition(wasUnreadable, unreadable)) {
                _lastWakeMs = System.getTimer();
            }
            WatchUi.requestUpdate();
        }
    }

    // Current-mode readability probe for the play sites (review 2026-07-20):
    // starting playback must consult the display NOW — if a waking key event
    // is delivered BEFORE the OFF→HIGH mode callback (ordering is firmware-
    // owned), the transition-driven policy alone would let the wake resume
    // onto a still-OFF screen with no further transition left to re-pause it.
    // Fail-OPEN on a throwing read: blocking all resumes forever on a broken
    // mode API is worse than the pre-3.7 behavior it would regress to.
    private function displayUnreadableNow() as Boolean {
        try {
            return Display.shouldPauseForMode(System.getDisplayMode() as Number);
        } catch (e) {
            return false;
        }
    }

    // Session teardown — the App calls this from onStop AFTER commitOnStop
    // (position save first; position is the sacred state — Story 3.7, Task 5).
    function shutdownDisplay() as Void {
        _display.shutdown();
    }

    // ── playback control surface (Story 3.3) ──
    // The delegate calls these; the view drives the engine. None of them stops the
    // timer manually: coast pause needs ticks to reach the sentence end, and
    // instant pause / rewind settle on the existing onTimerTick paused-branch
    // (recompute jitter + requestUpdate, no re-arm). Resume re-arms (the timer
    // self-stopped on pause). [story Task 3]

    // START / tap. Coast pause keeps ticking to the sentence end via the existing
    // loop; instant pause settles on the next tick; both freeze in onTimerTick's
    // paused branch. Resume re-arms the ramp (engine.play) and the timer. FINISHED
    // is terminal — play() no-ops it, so there is no resume from the end.
    function pauseOrResume() as Void {
        // Wake-tap grace (Story 3.7, AC2): if the firmware delivers the
        // display-waking tap/press through to the delegate, it must not toggle
        // playback. Whether it ever reaches us is a hardware answer (Task 8d)
        // — the guard is cheap insurance either way.
        if (Display.isWakeGrace(_lastWakeMs, System.getTimer(), Display.WAKE_GRACE_MS)) {
            return;
        }
        // START during a chapter card (Auto or Wait) resumes the stream immediately —
        // the card-aware branch must come first, because the engine is PAUSED behind
        // the card and would otherwise be treated as a normal paused resume (Story 3.5).
        if (_chapterCard) {
            resumeFromCard();
            return;
        }
        if (_engine.isPlaying() || _engine.isRamping()) {
            _engine.requestPause();
            WatchUi.requestUpdate();
        } else if (_engine.isPaused()) {
            // Play-site display guard (review 2026-07-20): a resume must not
            // start words onto a screen that is unreadable RIGHT NOW — the
            // wake-grace guard above only helps when the mode callback beat
            // the key event to us; this holds when it didn't.
            if (displayUnreadableNow()) {
                return;
            }
            _engine.play(System.getTimer()); // re-arms the 3-beat ramp
            armTimer();                       // timer self-stopped while paused
            _display.onPlaybackStart();       // strategy lifecycle (3.7; app-mode no-op)
            WatchUi.requestUpdate();
        }
    }

    // UP/DOWN while playing. The WPM change takes effect on the NEXT word with no
    // re-fetch and no drift (engine contract, AC2 "without interrupting the
    // stream") — so NO timer change here. Arm the transient readout and repaint.
    function stepWpm(up as Boolean) as Void {
        // No WPM change while a card or the Finished screen is up — those modes are
        // not "playing", and the re-read-is-phone-side contract (UX-DR14) keeps the
        // end screen from being driven (Story 3.5, Task 8). The readout is also gated
        // on isPlaying||isRamping, so this is belt-and-braces.
        if (_chapterCard || _engine.isFinished()) {
            return;
        }
        if (up) {
            _engine.stepWpmUp();
        } else {
            _engine.stepWpmDown();
        }
        // Sync the model so the stepped speed survives (Story 3.8, Task 5
        // decision): before this, in-flow steps mutated only the engine and the
        // next relaunch silently forgot them. Memory-only here (hot-ish path) —
        // the dirty flag defers the Storage write to onHide (cold path).
        _settings.wpm = _engine.wpm();
        _settingsDirty = true;
        _wpmReadoutUntil = System.getTimer() + READOUT_MS;
        WatchUi.requestUpdate();
    }

    // Swipe-right (touch) or button-path rewind (START to pause, UP while paused).
    // engine.rewind() auto-pauses, is stackable, and clamps at word 0. Recompute
    // the jitter for the new still frame and repaint. (If we were playing, the
    // pending one-shot tick fires once more into the paused branch — a harmless
    // jitter refresh; if we were already paused there is no pending tick, so this
    // repaint is the one that lands.)
    function rewindOne() as Void {
        // Wake-tap grace (Story 3.7, AC2): the waking input must not move
        // position. (stepWpm stays unguarded — harmless while paused;
        // openContextView gained its own guard in the 2026-07-20 review.)
        if (Display.isWakeGrace(_lastWakeMs, System.getTimer(), Display.WAKE_GRACE_MS)) {
            return;
        }
        // No rewind out of a chapter card or the Finished screen (Story 3.5, Task 8).
        // FINISHED is terminal — re-read is a phone-side decision (UX-DR14), which is
        // the deliberate resolution of deferred-work #107, NOT a missing feature. A
        // card freezes on a chapter start; rewinding from it would defeat the breath.
        if (_chapterCard || _engine.isFinished()) {
            return;
        }
        _engine.rewind();
        // Force-save the rewound position (Story 3.6, AC1). Critical here:
        // rewind-while-already-paused arms NO pending tick, so onTimerTick's
        // paused branch never fires for it — without this explicit call a
        // paused-rewind would silently miss the force-save.
        commitPosition(true);
        recomputeJitter();
        WatchUi.requestUpdate();
    }

    // DOWN / swipe-up while paused (Story 3.4, AC2). Push the scrollable context view
    // (a CustomMenu — native fluid scroll) over this one, snapshotting the (frozen)
    // position. Guarded: context is a paused-only affordance, and a null current record
    // (empty/unbuffered book) has no paragraph to show — degrade to a no-op. The
    // PausedContextView wraps the paragraph at construction; PlaybackView keeps NO
    // reference to the pushed menu/delegate (no GC cycle, AR15), and the menu holds
    // only the read-only line items, never the engine or this view. BACK in the
    // delegate pops back to this still-frame (AC3).
    function openContextView() as Void {
        // Wake-tap grace (review 2026-07-20, Nerya-approved override of the
        // story's "openContextView stays unguarded" note): a waking DOWN /
        // swipe-up must not push the context view over the Paused frame —
        // wake finds Paused (AC2), not a scrolling context. Position-safe
        // either way; this is a UI-state guard.
        if (Display.isWakeGrace(_lastWakeMs, System.getTimer(), Display.WAKE_GRACE_MS)) {
            return;
        }
        // A chapter card pauses the engine behind it, so guard the card explicitly:
        // the card is not the context affordance (Story 3.5, Task 8). FINISHED is not
        // paused, so isPaused() already excludes it, but guard it for symmetry.
        if (_chapterCard || _engine.isFinished()) {
            return;
        }
        if (!_engine.isPaused()) {
            return;
        }
        if (_engine.currentRecord() == null) {
            return;
        }
        var ctx = new PausedContextView(_source, _engine.index());
        WatchUi.pushView(ctx, new PausedContextDelegate(), WatchUi.SLIDE_UP);
    }

    // MENU in either reader state (Story 3.8, AC1). While playing this means
    // "pause + open settings" (UX-DR16): freeze instantly at the current word
    // (pauseAtCurrent, mode-independent — a coast requestPause would flow words
    // behind the pushed menu) with the 3.6 transition force-save, then push the
    // Menu2. openContextView is the push/guard template; PlaybackView keeps NO
    // reference to the pushed menu/delegate (AR15 no-cycle).
    function openSettingsMenu() as Void {
        // Wake-tap grace (same rationale as openContextView, review 2026-07-20,
        // Nerya-approved): a waking MENU press must not push the menu over the
        // Paused frame — wake finds Paused, not a settings menu.
        if (Display.isWakeGrace(_lastWakeMs, System.getTimer(), Display.WAKE_GRACE_MS)) {
            return;
        }
        // Input discipline while a card or the Finished screen is up (Story 3.5
        // Task 8): the card is a breath, FINISHED is terminal (UX-DR14).
        if (_chapterCard || _engine.isFinished()) {
            return;
        }
        if (_engine.isPlaying() || _engine.isRamping()) {
            _engine.pauseAtCurrent();
            // Transition force-save (Story 3.6); a redundant call when the
            // index was already committed is free (same-index suppression).
            commitPosition(true);
        }
        WatchUi.pushView(SettingsMenu.build(_settings, _engine.wpm()),
            new SettingsMenuDelegate(_settings, self), WatchUi.SLIDE_UP);
    }

    // ── immediate-effect propagation for menu edits (Story 3.8, AC2/AC3/AC4) ──
    // Only the fields COPIED at construction need apply methods: wpm/pauseMode
    // live in the engine as primitives, fontSize is resolved once into
    // _fontIndex. Everything else (touchControls, handedness, anchorPct,
    // phantomWords, focusHighlight, chapterResume) is read from _settings per
    // event/frame — the menu mutates the same instance, so those propagate for
    // free (AC4 handedness mirroring included: rewindSwipeDirection reads live).

    // Menu/stepper WPM commit (already persisted by the caller) — takes effect
    // next word, no drift (engine contract). Clears the in-flow dirty flag: the
    // committed value IS the saved value now.
    function applyWpm(v as Number) as Void {
        _engine.setWpm(v);
        _settingsDirty = false;
    }

    // The settings menu persisted the full dict (Story 3.8 review): any in-flow
    // WPM step mirrored into _settings.wpm is now durable, so clear the dirty
    // flag — otherwise onHide (fired on menu dismiss) does a redundant re-save.
    function markSettingsPersisted() as Void {
        _settingsDirty = false;
    }

    function applyPauseMode(v as Number) as Void {
        _engine.setPauseMode(v);
    }

    // Re-resolve the persisted fontSize against the ramp (the 3.1-deferred-#94
    // bound stays enforced here at the view). AC3 note: the shipped renderer
    // uses NATIVE system fonts (the documented escape hatch, UX-DR2 / the 3.2
    // font-swap deferral) — every size is firmware-resident, so there is
    // nothing to load or unload per size. The load-on-demand obligation
    // ("only the active word-display size is heap-resident") activates when
    // the Atkinson BMFont swap story replaces fontFor()'s ramp with packaged
    // font resources — this seam is where that loading will live.
    function applyFontSize() as Void {
        _fontIndex = OrpLayout.clampFontIndex(_settings.fontSize, RAMP_LENGTH);
    }

    // ── thin Settings/engine reads for the delegate (keep the delegate dumb) ──

    // The font ramp's ONE length encoding (the menu's fontSize cycle needs it).
    function fontRampLength() as Number {
        return RAMP_LENGTH;
    }

    // Runtime WPM — the source of truth the menu/stepper seed from (the stored
    // Settings.wpm may trail an uncommitted in-flow step).
    function engineWpm() as Number {
        return _engine.wpm();
    }
    function touchEnabled() as Boolean {
        return _settings.touchControls;
    }

    // The handedness-mirrored rewind swipe direction (UX: swipe direction mirrors
    // the reading hand). Right-handed -> SWIPE_RIGHT, left-handed -> SWIPE_LEFT.
    function rewindSwipeDirection() as Number {
        return _settings.handedness == SettingsModel.HAND_LEFT
            ? WatchUi.SWIPE_LEFT
            : WatchUi.SWIPE_RIGHT;
    }

    function isPausedState() as Boolean {
        return _engine.isPaused();
    }

    // Timer fire: drive time forward, repaint the now-selected word, then re-arm to
    // the NEXT word's duration (NOT a fixed coarse tick — a fixed tick at high WPM
    // hits the engine's 4-word catch-up cap every tick and defeats drift-free
    // accumulation; resolves Story 3.1 deferred #4, architecture AR13). The engine
    // imports no System; the view supplies `now` via System.getTimer().
    function onTimerTick() as Void {
        var now = System.getTimer();
        _engine.onTick(now);
        // Chapter-boundary interception (Story 3.5, AC1): AFTER the engine advanced,
        // if the now-current word starts a chapter, raise the card. It freezes the
        // engine and arms its own resume path (Auto timer / Wait START), so we are
        // done for this tick.
        if (maybeEnterChapterCard(now)) {
            return;
        }
        // Gate V4 auto-replay (Story 3.9, Task 2) — GATE BUILD ONLY. On end-of-
        // book, seek back to word 0 and replay so the render loop + display +
        // BLE-connected radio run continuously for the full measurement hour
        // (the 228-word canned source is ~46 s at 300 WPM). Looping the small
        // buffered source keeps heap flat (NFR2) and re-exercises ramp + chapter
        // cards + Finished each lap. Behind BatteryGate.ENABLED (false in every
        // release build), so the shipped FINISHED behaviour — Finished screen,
        // BACK exits, no rewind (UX-DR14) — is untouched. seekTo(0) lands PAUSED
        // with no transition; play() re-anchors the ramp (no catch-up burst).
        if (BatteryGate.ENABLED && _engine.isFinished()) {
            _engine.seekTo(0);
            _engine.play(System.getTimer());
            armTimer();
            WatchUi.requestUpdate();
            return;
        }
        if (_engine.isPlaying() || _engine.isRamping()) {
            commitPosition(false); // steady stream: debounced ~15 s (Story 3.6)
            WatchUi.requestUpdate();
            armTimer();
        } else {
            // Paused / finished: stop ticking (no runaway timer, no per-tick work
            // while frozen). This branch is where coast-pause finalize, instant-
            // pause settle, and TRANSITION_FINISHED all land — one force-save
            // covers them (Story 3.6, AC1). Refresh the burn-in jitter for the
            // still frame BEFORE the repaint — no further tick comes while
            // frozen, so the new offset must be applied to the very next (and
            // only) requestUpdate or it is never drawn.
            commitPosition(true);
            recomputeJitter();
            WatchUi.requestUpdate();
        }
    }

    // ── chapter card lifecycle (Story 3.5, AC1) ──

    // If the engine just advanced (while playing) onto a word that starts a chapter,
    // enter card mode: snapshot number+title from the source catalog, freeze the
    // engine ON that word (pauseAtCurrent — instant, so coast can't overshoot the
    // chapter start), and arm the resume path. Returns true iff a card was raised.
    // Skips word 0 (the book's own start is never a card) and the already-carded
    // index (so a just-resumed chapter start does not immediately re-card).
    private function maybeEnterChapterCard(now as Number) as Boolean {
        if (_chapterCard || !_engine.isPlaying()) {
            return false;
        }
        var idx = _engine.index();
        if (idx <= 0 || idx == _cardedIndex) {
            return false;
        }
        var rec = _engine.currentRecord();
        if (rec == null || (rec.flags & Protocol.FLAG_CHAPTER_START) == 0) {
            return false;
        }
        var cat = _source.chapters();
        _cardChapterNum = cat.numberForWord(idx);
        _cardChapterTitle = cat.titleForWord(idx);
        _cardedIndex = idx;
        _engine.pauseAtCurrent(); // freeze ON the chapter's first word
        // Chapter boundary = a natural force-save point (Story 3.6, AC1 — the
        // Epic-4 chunk-boundary analog), and the card may sit ~2 s or hold on
        // Wait indefinitely.
        commitPosition(true);
        _chapterCard = true;
        if (_settings.chapterResume == SettingsModel.CHAPTER_RESUME_AUTO) {
            armCardTimer(); // breathe ~2 s, then resumeFromCard
        } else {
            _timer.stop();  // Wait: hold until START (no pending tick to run)
        }
        recomputeJitter(); // a fresh still frame for the card
        WatchUi.requestUpdate();
        return true;
    }

    // One-shot Auto-card timer. Reuses the single _timer instance (the playback loop
    // is stopped while the card is up), so there is no second Timer to leak.
    private function armCardTimer() as Void {
        _timer.start(method(:onCardTimeout), CHAPTER_CARD_MS, false);
    }

    // Auto card elapsed — resume the stream (no-op if START already resumed it).
    function onCardTimeout() as Void {
        if (!_chapterCard) {
            return;
        }
        resumeFromCard();
    }

    // Leave card mode and resume playback. play() (PAUSED -> ramp -> playing) is the
    // ONLY lever that re-anchors the engine's accumulator, so the ~2 s card does not
    // trigger onTick's catch-up burst; the 3-beat ramp is the intended "breath" on
    // chapter resume (EXPERIENCE.md:85). _cardedIndex stays set so this chapter-start
    // word does not immediately re-card.
    function resumeFromCard() as Void {
        // Play-site display guard (review 2026-07-20): refuse to resume the
        // stream onto an unreadable screen — the card stays up, holding like
        // a Wait card (the one-shot Auto timer has already fired), and a
        // START on a readable display resumes it. This also closes the
        // onShow-re-arm hole: an overlay hide/show cycle while the screen is
        // OFF re-arms the Auto breath, whose timeout lands here and is
        // refused instead of flowing words onto a dark screen.
        if (displayUnreadableNow()) {
            return;
        }
        _chapterCard = false;
        _engine.play(System.getTimer());
        armTimer();
        _display.onPlaybackStart(); // strategy lifecycle (3.7; app-mode no-op)
        WatchUi.requestUpdate();
    }

    private function armTimer() as Void {
        var interval = _engine.currentDuration();
        if (interval < TIMER_FLOOR_MS) {
            interval = TIMER_FLOOR_MS;
        }
        _timer.start(method(:onTimerTick), interval, false); // one-shot, re-armed
    }

    // Draw ONLY the already-selected word — no advancement here (all advancement is
    // in onTimerTick; architecture.md:287). Cheap: clear + one word + guides +
    // phantoms, so the firmware onUpdate watchdog is never at risk.
    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_TRANSPARENT, COLOR_VOID);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        // Chapter card (Story 3.5, AC1) and Finished screen (AC2) are two more
        // early-return draw modes — like the ramp / paused / null-record branches —
        // because both must coordinate the engine + the timer loop this view owns.
        // They intercede ONLY at a chapter boundary and at end-of-book; normal
        // playback below is untouched (AC4).
        if (_chapterCard) {
            drawChapterCard(dc, w, h);
            return;
        }
        if (_engine.isFinished()) {
            drawFinished(dc, w, h);
            return;
        }

        var anchorCol = OrpLayout.anchorX(w, _settings.anchorPct) + _jitterX;
        var cy = h / 2 + _jitterY;

        // Start ramp: the engine owns the 3-2-1 count/timing (Story 3.1); this view
        // owns the pixels. Countdown centered on the anchor in Ink — no word, no
        // phantoms (AC5 support).
        if (_engine.isRamping()) {
            drawGuides(dc, anchorCol, cy, w);
            dc.setColor(COLOR_INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(anchorCol, cy, fontFor(_fontIndex), _engine.rampRemaining().toString(),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            drawWpmReadout(dc, w, h);
            return;
        }

        var rec = _engine.currentRecord();
        if (rec == null) {
            // Unbuffered / empty book — draw nothing for the word, keep the frame
            // (bounds-check-and-degrade, NFR8/AR24).
            drawGuides(dc, anchorCol, cy, w);
            drawWpmReadout(dc, w, h);
            drawPausedReadout(dc, w, h);
            return;
        }

        drawGuides(dc, anchorCol, cy, w);
        drawWord(dc, rec, anchorCol, cy, w);
        drawWpmReadout(dc, w, h);
        drawPausedReadout(dc, w, h);
    }

    // Paused progress readout (AC1). Drawn ONLY on the paused still-frame — book %,
    // time-left, and the current WPM in Ink-Dim. Gated on isPaused() so ramp /
    // playing / FINISHED / IDLE draw NOTHING (UX-DR8: "while words flow, the screen
    // owes the reader nothing but the word"). Distinct from drawWpmReadout (the
    // transient PLAYING overlay, gated on isPlaying||isRamping) — the two can never
    // draw together. Pure draw over the already-frozen paused frame: it touches
    // neither the timer nor the engine (the paused state intentionally runs no
    // timer — onTimerTick self-stops on pause).
    //
    // "Fades in" → MVP renders IMMEDIATELY in Ink-Dim: Garmin drawText has no alpha,
    // and a multi-frame brightness ramp would need a timer re-armed on pause (the
    // paused state deliberately runs none). A true opacity fade stays OUT (optional
    // on-device polish). [DESIGN.md:153 "appears only when paused"; UX-DR8]
    private function drawPausedReadout(dc as Graphics.Dc, w as Number, h as Number) as Void {
        if (!_engine.isPaused()) {
            return;
        }
        var idx = _engine.index();
        var count = _source.wordCount();
        var pct = PausedLayout.bookPercent(idx, count);
        // wordsRemaining = the current word through the end, inclusive (so a pause on
        // the last word still reads 1 word / its bonus remaining). The bonus sum is
        // O(remaining) and recomputed on every paused repaint (cheap on the canned
        // source). Story 4.1 swaps the sum for the manifest's O(1) cumulative bonus
        // behind PausedLayout.
        var wordsRemaining = count - idx;
        var bonusRemaining = PausedLayout.sumBonusMs(_source, idx, count - 1);
        var timeLeft = PausedLayout.formatRemaining(
            PausedLayout.timeRemainingMs(wordsRemaining, _engine.wpm(), bonusRemaining));

        dc.setColor(COLOR_INK_DIM, Graphics.COLOR_TRANSPARENT);
        var font = Graphics.FONT_SYSTEM_TINY; // watch-meta ~22px (as drawWpmReadout)
        var lineH = dc.getFontHeight(font);
        var cx = w / 2 + _jitterX;
        // Lower third, clear of the focal word and the bottom split hairline, riding
        // the same ±2px session jitter as the rest of the composition (burn-in).
        var line1Y = h * 7 / 10 + _jitterY;
        dc.drawText(cx, line1Y, font, pct.toString() + "%",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, line1Y + lineH, font,
            timeLeft + " left · " + _engine.wpm().toString() + " wpm",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // General-use-AOD instruction (Story 3.7 app-mode, Task 6 — the
        // gates.md §V1 carry, re-targeted by ADR 0003). Armed after the
        // display reached OFF this session — with general-use Always On
        // enabled and the watch worn, OFF never arrives (on-device probe
        // 2026-07-16), so an observed OFF means the setting is off (or the
        // watch was off-wrist). Paused-frame-only chrome (UX-DR8), factual
        // wording (UX-DR23, reword on-device if it reads badly), Ink-Dim
        // XTINY in the upper third — clear of the word, guides, and the
        // lower-third readout — riding the session jitter like everything
        // else. Session-local state, not persisted.
        if (_sawDisplayOff) {
            dc.drawText(cx, h / 5 + _jitterY, Graphics.FONT_SYSTEM_XTINY,
                "Display > Always On",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Transient WPM readout (AC2). Drawn ONLY while NOT paused and while the
    // ~900 ms deadline set by stepWpm() has not elapsed. Ink-Dim, a small native
    // face (watch-meta 22px), seated in the lower third clear of the focal word,
    // carrying the same burn-in jitter as the rest of the composition. It is
    // transient and DIM — the one allowed playing-state overlay (UX) — so it does
    // NOT break Story 3.2 AC5 ("no persistent BRIGHT chrome while words flow"). It
    // self-clears: the playback loop repaints every word, and the first repaint
    // past the deadline simply does not draw it (no second clear-timer needed).
    private function drawWpmReadout(dc as Graphics.Dc, w as Number, h as Number) as Void {
        if (!(_engine.isPlaying() || _engine.isRamping())) {
            // Draw ONLY while the word stream is live (playing or ramping). Paused
            // gets no overlay (that readout is 3.4); FINISHED/IDLE have no repaint
            // loop, so a readout drawn there would never self-clear and would stick
            // as persistent chrome until the next input (review 2026-06-23 patch).
            return;
        }
        if (System.getTimer() >= _wpmReadoutUntil) {
            return; // flash has elapsed (or was never armed) — self-cleared
        }
        dc.setColor(COLOR_INK_DIM, Graphics.COLOR_TRANSPARENT);
        var rx = w / 2 + _jitterX;
        var ry = h * 3 / 4 + _jitterY; // lower third, below the bottom split hairline
        dc.drawText(rx, ry, Graphics.FONT_SYSTEM_TINY, _engine.wpm().toString() + " wpm",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Chapter card (AC1). Drawn ONLY in card mode (onUpdate returns before the word
    // branches). "Chapter N" meta label, the chapter title in the chapter-title role
    // (Ink, the largest native face that fits on one line — DESIGN 28/700; the true
    // bold Atkinson BMFont is the same deferred font-swap behind fontFor, native faces
    // have no 700 weight), and the book-progress percent beneath in Ink-Dim. Centered
    // on the anchor band where the round face is widest; the whole card rides the same
    // burn-in jitter as the rest of the composition.
    private function drawChapterCard(dc as Graphics.Dc, w as Number, h as Number) as Void {
        var cx = w / 2 + _jitterX;
        var cy = h / 2 + _jitterY;
        var title = _cardChapterTitle == null ? "" : _cardChapterTitle;
        var usable = w - 2 * CARD_EDGE;

        var labelFont = Graphics.FONT_SYSTEM_TINY; // watch-meta
        var titleFont = fitTitleFont(dc, title, usable);
        var labelH = dc.getFontHeight(labelFont);
        var titleH = dc.getFontHeight(titleFont);
        var gap = labelH / 2;

        // "Chapter N" label above the title (Ink-Dim meta).
        dc.setColor(COLOR_INK_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - titleH / 2 - gap, labelFont,
            "Chapter " + _cardChapterNum.toString(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // The chapter title — the one place bold is allowed (here: the largest native
        // face), in Ink (focal text on Void).
        dc.setColor(COLOR_INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, titleFont, title,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Progress beneath, Ink-Dim (reuse PausedLayout.bookPercent — don't reinvent).
        var pct = PausedLayout.bookPercent(_engine.index(), _source.wordCount());
        dc.setColor(COLOR_INK_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + titleH / 2 + gap, labelFont, pct.toString() + "%",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Finished screen (AC2). Replaces the frozen last word with an explicit end —
    // never a silent stop. Ink-Dim, status-view style, centered. BACK exits (the
    // delegate lets the system handle ACTION_EXIT); there is intentionally NO
    // rewind-into-text (UX-DR14, resolves deferred #107). The stat is total content
    // reading time, computed purely (the wall-clock "across N days" half lands with
    // Story 3.6 persistence — pass `days` then instead of null).
    private function drawFinished(dc as Graphics.Dc, w as Number, h as Number) as Void {
        // Ride the same per-session burn-in jitter as every other draw path (word,
        // guides, card, readouts). The Finished frame is the longest-lived static
        // screen (it holds until BACK), so omitting the offset is the worst place to
        // skip burn-in mitigation on true-black AMOLED.
        var cx = w / 2 + _jitterX;
        var cy = h / 2 + _jitterY;
        dc.setColor(COLOR_INK_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, Graphics.FONT_SYSTEM_SMALL,
            StatusLayout.formatFinished(totalReadingMs(), null),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Total content reading time in ms (Epic-3 Finished stat): wordCount * beat +
    // Σ bonus over the whole book, mirroring the paused-readout math exactly. The
    // O(book) bonus sum runs ONCE on the Finished frame (no repaint loop while
    // finished), cheap on the 228-word canned source; Story 4.1 swaps it for the
    // manifest's O(1) total behind PausedLayout. Empty book degrades to 0.
    private function totalReadingMs() as Number {
        var count = _source.wordCount();
        if (count <= 0) {
            return 0;
        }
        return count * (60000 / _engine.wpm())
            + PausedLayout.sumBonusMs(_source, 0, count - 1);
    }

    // The largest ramp face whose whole-width fits `usable` on one line (chapter
    // title fit-to-width, starting from the LARGEST face — independent of the
    // reading fontSize). Falls back to the smallest ramp font if even that overflows
    // (best effort, never truncate). A few measurements, only on card entry.
    private function fitTitleFont(dc as Graphics.Dc, text as String, usable as Number) as Graphics.FontType {
        for (var idx = 0; idx < RAMP_LENGTH - 1; idx++) {
            if (!OrpLayout.needsMarginClamp(dc.getTextWidthInPixels(text, fontFor(idx)), usable)) {
                return fontFor(idx);
            }
        }
        return fontFor(RAMP_LENGTH - 1);
    }

    // Split guide marks (AC2): split hairlines above/below in Ink-Faint with a gap
    // at the anchor column, and short anchor ticks in Pivot. The GEOMETRY (gap +
    // ticks), not color alone, points at the pivot — color-blind safe (UX-DR24).
    private function drawGuides(dc as Graphics.Dc, anchorCol as Number, cy as Number, w as Number) as Void {
        var left = WATCH_EDGE + _jitterX;
        var right = w - WATCH_EDGE + _jitterX;
        var topY = cy - HAIRLINE_OFFSET;
        var botY = cy + HAIRLINE_OFFSET;

        dc.setColor(COLOR_INK_FAINT, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        // Hairlines, split by a gap centered on the anchor column.
        dc.drawLine(left, topY, anchorCol - GAP_HALF, topY);
        dc.drawLine(anchorCol + GAP_HALF, topY, right, topY);
        dc.drawLine(left, botY, anchorCol - GAP_HALF, botY);
        dc.drawLine(anchorCol + GAP_HALF, botY, right, botY);

        // Anchor ticks: short vertical ticks in Pivot pointing inward at the pivot.
        dc.setColor(COLOR_PIVOT, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(anchorCol, topY, anchorCol, topY + TICK_LEN);          // down from top hairline
        dc.drawLine(anchorCol, botY - TICK_LEN, anchorCol, botY);          // up from bottom hairline
    }

    // Compose the focal word with the pivot's CENTER on the anchor column (AC1), so
    // the anchor does not move between words. Phantoms flank it (AC3). A word wider
    // than usable width is shown WHOLE, clamped at the margin with the pivot allowed
    // to drift off-anchor — never truncated/hyphenated (AC4).
    private function drawWord(dc as Graphics.Dc, rec as StreamDecoder.WordRecord,
                              anchorCol as Number, cy as Number, w as Number) as Void {
        var usable = w - 2 * FOCAL_EDGE;
        // Long-word fit-to-width (AC4 / DESIGN.md:131 "show whole"): a word wider
        // than the available width at the base font would run off the round display.
        // Step DOWN the font ramp to the LARGEST size whose whole-word width still
        // fits the focal budget (best-effort: the smallest ramp font if nothing fits)
        // — show whole at the most legible size that fits, never truncate/hyphenate.
        // The Atkinson BMFont swap re-tunes this behind the same seam (Font decision).
        // Normal words fit at the base font and keep it.
        var font = fontFor(fitFontIndex(dc, rec.word, usable));
        var parts = OrpLayout.splitAtPivot(rec.word, rec.orpPivot);
        var before = parts[0];
        var pivot = parts[1];
        var after = parts[2];

        var beforeW = dc.getTextWidthInPixels(before, font);
        var pivotW = dc.getTextWidthInPixels(pivot, font);
        var afterW = dc.getTextWidthInPixels(after, font);

        // Pivot centered on the anchor -> the whole word's three segment origins.
        var pivotLeftX = anchorCol - pivotW / 2;
        var beforeLeftX = pivotLeftX - beforeW;
        var afterLeftX = pivotLeftX + pivotW;

        // Bidirectional margin-clamp (AC4): anchoring the pivot at 35% can push a
        // long word past EITHER margin (the pivot is often near the word's start, so
        // the tail overruns the RIGHT edge). Shift the whole word so it sits inside
        // [marginLeft, marginRight]; the pivot drifts off-anchor. After fit-to-width
        // the word fits the focal budget, so it always fits between these margins and
        // at most one side overflows — never truncate, never hyphenate.
        var marginLeft = FOCAL_EDGE + _jitterX;
        var marginRight = w - FOCAL_EDGE + _jitterX;
        var shift = 0;
        if (beforeLeftX < marginLeft) {
            shift = marginLeft - beforeLeftX;            // overran left -> shift right
        } else if (afterLeftX + afterW > marginRight) {
            shift = marginRight - (afterLeftX + afterW); // overran right -> shift left
        }
        beforeLeftX += shift;
        pivotLeftX += shift;
        afterLeftX += shift;

        // Phantoms (AC3): previous/next words flank the focal word at the same
        // baseline in Ink-Faint, with a gap; null neighbours simply draw nothing.
        // FLAG_CONTINUATION is reserved (MUST be 0 in v1) — no branch on it (AC4).
        if (_settings.phantomWords) {
            dc.setColor(COLOR_INK_FAINT, Graphics.COLOR_TRANSPARENT);
            var prev = _source.wordAt(_engine.index() - 1);
            if (prev != null) {
                dc.drawText(beforeLeftX - PHANTOM_GAP, cy, font, prev.word,
                    Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            }
            var next = _source.wordAt(_engine.index() + 1);
            if (next != null) {
                dc.drawText(afterLeftX + afterW + PHANTOM_GAP, cy, font, next.word,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            }
        }

        // Focal word. Pivot in Pivot iff focusHighlight; else Ink (the guide gap +
        // ticks still point at it — color-blind safe, AC2). before/after in Ink.
        dc.setColor(COLOR_INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(beforeLeftX, cy, font, before,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(afterLeftX, cy, font, after,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(_settings.focusHighlight ? COLOR_PIVOT : COLOR_INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(pivotLeftX, cy, font, pivot,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Font seam (Task 5): the word-display face resolved in ONE place. Native ramp
    // = the documented escape hatch; index 0 is the largest native text face.
    private function fontFor(index as Number) as Graphics.FontType {
        if (index <= 0) { return Graphics.FONT_SYSTEM_LARGE; }
        if (index == 1) { return Graphics.FONT_SYSTEM_MEDIUM; }
        if (index == 2) { return Graphics.FONT_SYSTEM_SMALL; }
        if (index == 3) { return Graphics.FONT_SYSTEM_TINY; }
        return Graphics.FONT_SYSTEM_XTINY;
    }

    // The largest ramp index at or below the base font whose WHOLE-word width fits
    // `usable` (AC4 fit-to-width). Returns the base index for normal words (they fit
    // immediately) and the smallest ramp font if even that overflows (best effort —
    // never truncate). A handful of measurements, only for the focal word.
    private function fitFontIndex(dc as Graphics.Dc, word as String, usable as Number) as Number {
        var idx = _fontIndex;
        while (idx < RAMP_LENGTH - 1) {
            if (!OrpLayout.needsMarginClamp(dc.getTextWidthInPixels(word, fontFor(idx)), usable)) {
                return idx;
            }
            idx += 1;
        }
        return idx;
    }

    // Bounded ±2px random walk for the whole composition (AC5 burn-in). Math.rand()
    // is non-negative; (rand % 3) - 1 yields a -1/0/+1 step, clamped to [-2, 2].
    private function recomputeJitter() as Void {
        _jitterX = clampJitter(_jitterX + (Math.rand() % 3) - 1);
        _jitterY = clampJitter(_jitterY + (Math.rand() % 3) - 1);
    }

    private function clampJitter(v as Number) as Number {
        if (v < -2) { return -2; }
        if (v > 2) { return 2; }
        return v;
    }
}

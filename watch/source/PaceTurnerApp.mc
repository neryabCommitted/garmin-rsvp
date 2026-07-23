import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Gate V2 spike app (Story 1.4): receives chunkData envelopes from the
// companion, validates + decodes them with the existing protocol modules,
// acks every valid chunk back to the phone, and exposes live counters to
// GateV2View. The V1 session spike is retired (git preserves it). Temporary
// spike code — Epic 4's ProtocolClient supersedes the receive path.
class PaceTurnerApp extends Application.AppBase {

    // Single temporary Storage key for the previous run's compact evidence
    // string; the shared StorageKeys module is an Epic 4 deliverable.
    private const EVIDENCE_KEY = "gateV2RunLog";

    // Two-press reset window: one accidental START must not destroy a run's
    // evidence (it destroyed Run B's watch ledger at ~chunk 72).
    private const RESET_ARM_WINDOW_MS = 3000;

    private var _received as Number;
    private var _valid as Number;
    private var _invalid as Number;
    private var _acked as Number;
    private var _ackErrors as Number;
    private var _maxReceived as Number;
    private var _lastError as String?;
    private var _lastEncoding as String;
    private var _resetArmedAt as Number?;

    // The constructed playback view (Story 3.6): held so onStop can route the
    // last catchable exit save through the view's SyncManager. App→View strong
    // ref is fine — the App is the GC root and the view never references the
    // App back (no cycle, AR15).
    private var _playbackView as PlaybackView?;

    // Counter generation, bumped on every reset: ack listener callbacks from
    // before a reset are discarded so a straddling ack cannot skew the fresh
    // window (Run B's display showed A leading V exactly this way).
    private var _gen as Number;

    function initialize() {
        AppBase.initialize();
        _received = 0;
        _valid = 0;
        _invalid = 0;
        _acked = 0;
        _ackErrors = 0;
        _maxReceived = 0;
        _lastError = null;
        _lastEncoding = "?";
        _resetArmedAt = null;
        _playbackView = null;
        _gen = 0;
    }

    function onStart(state as Dictionary?) as Void {
        // Surface the previous run's evidence on launch — readable from the
        // device app log without extra UI (run protocol, docs/gates.md).
        var previous = null;
        try {
            previous = Storage.getValue(EVIDENCE_KEY);
        } catch (e) {
            previous = null;
        }
        if (previous != null) {
            System.println("GateV2 evidence (previous run):");
            System.println(previous);
        }
        Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
    }

    function onStop(state as Dictionary?) as Void {
        // Guarded Storage write — a persistence failure must not crash exit
        // and destroy the run's evidence (deferred-work V1 robustness #3).
        try {
            Storage.setValue(EVIDENCE_KEY, GateV2.evidenceString(
                _received, _valid, _invalid, _acked, _ackErrors,
                _maxReceived, _lastEncoding, _lastError));
        } catch (e) {
            System.println("GateV2: evidence persist failed");
        }
        // Story 3.6 (AC1): best-effort position force-save on the last catchable
        // exit hook. The abrupt carousel-kill does NOT reliably reach onStop
        // (UX-DR13 — no graceful-exit assumption); durability for that case
        // comes from the per-transition force-saves inside PlaybackView.
        if (_playbackView != null) {
            (_playbackView as PlaybackView).commitOnStop();
            // Story 3.8 review: also flush an in-flow WPM step on this cold-path
            // exit (position first — sacred — settings second), so a stepped
            // speed survives an onStop-reachable kill that skipped the view's
            // onHide. Cold path, once per session: no flash-wear concern.
            (_playbackView as PlaybackView).saveDirtySettings();
        }
        // Story 3.7 (Task 5): release the screen-on strategy — position save
        // FIRST, strategy teardown second (position is the sacred state).
        // App-mode's shutdown is a no-op (ADR 0003); the call stays wired so
        // the Active variant's session teardown swaps in behind the seam.
        if (_playbackView != null) {
            (_playbackView as PlaybackView).shutdownDisplay();
        }
    }

    // Display-mode transition (AppBase-only callback, API 5.0.0 — Story-1.3
    // precedent): route to the playback view, which owns the engine reaction
    // (auto-pause on unreadable / repaint on wake, Story 3.7). Broad-caught —
    // a display-mode transition must never crash the app (robustness #5), and
    // one println on failure only (AR25).
    function onDisplayModeChanged() as Void {
        try {
            if (_playbackView != null) {
                (_playbackView as PlaybackView).onDisplayModeChanged(
                    System.getDisplayMode() as Number);
            }
        } catch (e) {
            System.println("Display: mode-change route failed");
        }
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        // Epic 3 entry: the RSVP render surface over the canned dev source (Story
        // 3.2) plus its input adapter (Story 3.3). The view is constructed ONCE and
        // handed to the delegate so input flows delegate -> view -> engine (AR15).
        // The GateV2 spike view/delegate (GateV2View, GateV2Delegate) are
        // git-preserved reference — left compiled, simply no longer entered. The
        // spike's Communications lifecycle in onStart() is harmless to the playback
        // path (no UI binding) and is left intact as run evidence. BACK still exits
        // to the watch face: the delegate returns false for KEY_ESC.
        var view = new PlaybackView();
        _playbackView = view; // held for the onStop exit save (Story 3.6)
        return [view, new PlaybackDelegate(view)] as [WatchUi.Views, WatchUi.InputDelegates];
    }

    // System callback for every phone message. Uses receiveLight (O(1)
    // structural validate + bounded-prefix integrity touch + ack) — NOT the
    // full per-word decode, which trips the uncatchable device watchdog on
    // large chunks (Story 1.5) that no try/catch can contain. The broad catch
    // still guards against ordinary exceptions so the spike's receive callback
    // never crashes the run it is recording (deferred-work V1 robustness #5).
    // State is bounded counters plus two short strings — no growing in-memory
    // log (#6) and no per-message logging or Storage writes in the hot path
    // (logging budget; a mid-run Storage write would also pollute the
    // round-trip timing the phone is measuring).
    function onPhoneMessage(msg as Communications.PhoneAppMessage) as Void {
        try {
            _received++;
            var result = GateV2.receiveLight(msg.data);
            _lastEncoding = result.enc;
            if (result.ok && result.off != null) {
                _valid++;
                if (result.bytesLen > _maxReceived) {
                    _maxReceived = result.bytesLen;
                }
                transmitAck(result.off as Number);
            } else {
                _invalid++;
                _lastError = result.err;
            }
        } catch (e) {
            _invalid++;
            _lastError = GateV2.errLabel(e.getErrorMessage());
        }
    }

    // Generation-tagged ack callbacks: a stale generation means the counters
    // were reset while this ack was in flight — discard it.
    function onAckComplete(gen as Number) as Void {
        if (gen != _gen) { return; }
        _acked++;
    }

    function onAckError(gen as Number) as Void {
        if (gen != _gen) { return; }
        _ackErrors++;
        _lastError = "ackFail";
    }

    function receivedCount() as Number { return _received; }
    function validCount() as Number { return _valid; }
    function ackedCount() as Number { return _acked; }
    function maxReceived() as Number { return _maxReceived; }
    function lastError() as String? { return _lastError; }
    function lastEncoding() as String { return _lastEncoding; }

    // START: first press arms the reset, a second within the window performs
    // it — so Run A and Run B are measured separately, but one accidental
    // press cannot zero a live ledger. Window logic is pure-tested in GateV2.
    function requestReset() as Void {
        var now = System.getTimer();
        if (GateV2.armWindowOpen(_resetArmedAt, now, RESET_ARM_WINDOW_MS)) {
            resetCounters();
        } else {
            _resetArmedAt = now;
        }
    }

    function resetArmed() as Boolean {
        return GateV2.armWindowOpen(
            _resetArmedAt, System.getTimer(), RESET_ARM_WINDOW_MS);
    }

    function resetCounters() as Void {
        _received = 0;
        _valid = 0;
        _invalid = 0;
        _acked = 0;
        _ackErrors = 0;
        _maxReceived = 0;
        _lastError = null;
        _lastEncoding = "?";
        _resetArmedAt = null;
        _gen++;
    }

    private function transmitAck(off as Number) as Void {
        // Acks MUST be Dictionaries: the plugin's messageStream runs
        // Map.from(e) on every inbound event and throws on bare values.
        var ack = {
            GateV2.ACK_KEY => off,
            GateV2.ACK_OK_KEY => true
        };
        // Own guard: a throwing transmit is an ack failure, not an invalid
        // chunk — without it one message would count both valid and invalid
        // via the callback's outer catch.
        try {
            Communications.transmit(ack, null, new GateV2AckListener(self, _gen));
        } catch (e) {
            onAckError(_gen);
        }
    }
}

// Transmit listener for the spike's acks — counts watch→phone reliability
// (free bonus evidence for Epic 4's position-sync channel).
class GateV2AckListener extends Communications.ConnectionListener {

    private var _app as PaceTurnerApp;
    private var _gen as Number;

    function initialize(app as PaceTurnerApp, gen as Number) {
        ConnectionListener.initialize();
        _app = app;
        _gen = gen;
    }

    function onComplete() as Void {
        _app.onAckComplete(_gen);
    }

    function onError() as Void {
        _app.onAckError(_gen);
    }
}

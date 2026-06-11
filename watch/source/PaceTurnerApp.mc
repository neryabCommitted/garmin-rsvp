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

    private var _received as Number;
    private var _valid as Number;
    private var _invalid as Number;
    private var _acked as Number;
    private var _ackErrors as Number;
    private var _lastError as String?;
    private var _lastEncoding as String;

    function initialize() {
        AppBase.initialize();
        _received = 0;
        _valid = 0;
        _invalid = 0;
        _acked = 0;
        _ackErrors = 0;
        _lastError = null;
        _lastEncoding = "?";
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
                _lastEncoding, _lastError));
        } catch (e) {
            System.println("GateV2: evidence persist failed");
        }
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new GateV2View(self), new GateV2Delegate(self)];
    }

    // System callback for every phone message. Broad catch on purpose: this
    // spike's receive callback must never crash the run it is recording
    // (deferred-work V1 robustness #5). State is bounded counters plus two
    // short strings — no growing in-memory log (#6) and no per-message
    // logging or Storage writes in the hot path (logging budget; a mid-run
    // Storage write would also pollute the round-trip timing the phone is
    // measuring).
    function onPhoneMessage(msg as Communications.PhoneAppMessage) as Void {
        try {
            _received++;
            var result = GateV2.processMessage(msg.data);
            _lastEncoding = result.enc;
            if (result.ok && result.off != null) {
                _valid++;
                transmitAck(result.off as Number);
            } else {
                _invalid++;
                _lastError = result.err;
            }
        } catch (e) {
            _invalid++;
            _lastError = "exc";
        }
    }

    function onAckComplete() as Void {
        _acked++;
    }

    function onAckError() as Void {
        _ackErrors++;
        _lastError = "ackFail";
    }

    function receivedCount() as Number { return _received; }
    function validCount() as Number { return _valid; }
    function ackedCount() as Number { return _acked; }
    function lastError() as String? { return _lastError; }
    function lastEncoding() as String { return _lastEncoding; }

    // START resets everything so Run A and Run B are measured separately.
    function resetCounters() as Void {
        _received = 0;
        _valid = 0;
        _invalid = 0;
        _acked = 0;
        _ackErrors = 0;
        _lastError = null;
        _lastEncoding = "?";
    }

    private function transmitAck(off as Number) as Void {
        // Acks MUST be Dictionaries: the plugin's messageStream runs
        // Map.from(e) on every inbound event and throws on bare values.
        var ack = {
            GateV2.ACK_KEY => off,
            GateV2.ACK_OK_KEY => true
        };
        Communications.transmit(ack, null, new GateV2AckListener(self));
    }
}

// Transmit listener for the spike's acks — counts watch→phone reliability
// (free bonus evidence for Epic 4's position-sync channel).
class GateV2AckListener extends Communications.ConnectionListener {

    private var _app as PaceTurnerApp;

    function initialize(app as PaceTurnerApp) {
        ConnectionListener.initialize();
        _app = app;
    }

    function onComplete() as Void {
        _app.onAckComplete();
    }

    function onError() as Void {
        _app.onAckError();
    }
}

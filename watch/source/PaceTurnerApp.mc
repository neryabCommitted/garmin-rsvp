import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class PaceTurnerApp extends Application.AppBase {

    // Single temporary Storage key for the Gate V1 evidence log (Story 1.3);
    // the shared StorageKeys module is an Epic 4 deliverable.
    private const EVIDENCE_KEY = "gateV1DisplayModeLog";

    private var _session as ActivityRecording.Session?;
    private var _anchorMs as Number;               // System.getTimer() at session start
    private var _modeLog as Array<Array<Number> >; // [elapsedSeconds, DisplayMode] entries
    private var _backlightProbe as String?;        // optional Task-3 probe result

    function initialize() {
        AppBase.initialize();
        _session = null;
        _anchorMs = System.getTimer();
        _modeLog = [] as Array<Array<Number> >;
        _backlightProbe = null;
    }

    function onStart(state as Dictionary?) as Void {
        // Surface the previous run's evidence on launch — readable from the
        // device app log without extra UI (run protocol, docs/gates.md).
        var previous = Storage.getValue(EVIDENCE_KEY);
        if (previous != null) {
            System.println("GateV1 evidence (previous run):");
            System.println(previous);
        }
    }

    function onStop(state as Dictionary?) as Void {
        stopSession();
    }

    // API 5.0.0 — the objective record of HIGH→LOW→OFF transitions across the
    // 60-min hands-off run. Persisted on every change; no per-second logging
    // (architecture §Communication Patterns logging budget).
    function onDisplayModeChanged() as Void {
        _modeLog.add([elapsedSeconds(), System.getDisplayMode() as Number]);
        persistLog();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new GateV1View(self), new GateV1Delegate(self)];
    }

    function isSessionActive() as Boolean {
        return _session != null;
    }

    function elapsedSeconds() as Number {
        return (System.getTimer() - _anchorMs) / 1000;
    }

    function backlightProbeResult() as String? {
        return _backlightProbe;
    }

    // START toggles the session. Stop always discards — never save(), a spike
    // run must not pollute Garmin Connect.
    function toggleSession() as Void {
        if (_session == null) {
            startSession();
        } else {
            stopSession();
        }
    }

    // Optional Task-3 probe: document Attention.backlight's actual ceiling on
    // Fenix 8. Feeds the gates.md notes only — not a pass path.
    function probeBacklight() as Void {
        if (!(Attention has :backlight)) {
            _backlightProbe = "BL n/a";
            return;
        }
        try {
            Attention.backlight(true);
            _backlightProbe = "BL on";
        } catch (e instanceof Attention.BacklightOnTooLongException) {
            _backlightProbe = "BL exc";
            System.println("GateV1 backlight probe: BacklightOnTooLongException");
        }
    }

    private function startSession() as Void {
        var session = ActivityRecording.createSession({
            :name => "PaceTurner",
            :sport => Activity.SPORT_GENERIC,
            :subSport => Activity.SUB_SPORT_GENERIC
        });
        session.start();
        _session = session;
        // Re-anchor the clock and start a fresh evidence log with a baseline
        // entry, so the persisted record covers exactly this run.
        _anchorMs = System.getTimer();
        _modeLog = [[0, System.getDisplayMode() as Number]] as Array<Array<Number> >;
        persistLog();
    }

    private function stopSession() as Void {
        var session = _session;
        if (session != null) {
            session.stop();
            session.discard();
            _session = null;
            persistLog();
        }
    }

    private function persistLog() as Void {
        Storage.setValue(EVIDENCE_KEY, GateV1.logToString(_modeLog));
    }
}

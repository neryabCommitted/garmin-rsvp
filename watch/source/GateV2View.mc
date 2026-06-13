import Toybox.Graphics;
import Toybox.Lang;
import Toybox.StringUtil;
import Toybox.Timer;
import Toybox.WatchUi;

// Pure helpers for the Gate V2 spike, unit-tested in
// watch/source-test/GateV2Test.mc (Story 1.2/1.3 pattern).
module GateV2 {

    // Spike-local ack shape, mirrored by GateV2Runner.ackOffsetKey/ackOkKey in
    // companion/lib/gate_v2/gate_v2_runner.dart. Deliberately NOT in
    // Protocol.mc — the ack is not protocol; SPEC.md's five types are fixed
    // in v1.
    const ACK_KEY = "ack";
    const ACK_OK_KEY = "ok";

    // Spike-local error labels for failures the SPEC §8 codes don't cover.
    const ERR_NOT_DICT = "notDict";
    const ERR_BAD_PAYLOAD = "badPayload";

    // Outcome of processing one inbound phone message.
    class ProcessResult {
        public var ok as Boolean;
        public var off as Number?;     // chunk offset, set when ok
        public var err as String?;     // SPEC §8 code or spike-local label
        public var enc as String;      // payload encoding seen: String/Array/?

        function initialize() {
            ok = false;
            off = null;
            err = null;
            enc = "?";
        }
    }

    // Which transport encoding the payload arrived as (Run A vs Run B).
    function encodingLabel(p as Object?) as String {
        if (p instanceof Lang.String) { return "String"; }
        if (p instanceof Lang.Array) { return "Array"; }
        return "?";
    }

    // Run B transcode: Monkey C Array of Numbers → ByteArray, every element
    // bounds-checked. Returns null on any malformed element — never throws.
    function arrayToByteArray(arr as Array) as ByteArray? {
        var out = new [arr.size()]b;
        for (var i = 0; i < arr.size(); i++) {
            var v = arr[i];
            if (!(v instanceof Lang.Number)) {
                return null;
            }
            var b = v as Number;
            if (b < 0 || b > 255) {
                return null;
            }
            out[i] = b;
        }
        return out;
    }

    // Structural pre-check so malformed input never reaches
    // convertEncodedString (UNCATCHABLE system error on SDK 8.4.0 — Story
    // 1.2 lesson): non-empty, length % 4 == 0, base64 alphabet only, '='
    // only as final padding.
    function isPlausibleBase64(s as String) as Boolean {
        var len = s.length();
        if (len == 0 || len % 4 != 0) { return false; }
        var chars = s.toCharArray();
        for (var i = 0; i < len; i++) {
            var c = chars[i].toNumber();
            var alnum = (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
                || (c >= 48 && c <= 57);
            if (alnum || c == 43 || c == 47) { continue; }
            if (c == 61 && i >= len - 2) { continue; }
            return false;
        }
        // "ab=c" — padding at len-2 requires padding at len-1 too.
        if (chars[len - 2].toNumber() == 61 && chars[len - 1].toNumber() != 61) {
            return false;
        }
        return true;
    }

    // Run A transcode: base64 String → ByteArray. The plausibility guard
    // keeps malformed input away from convertEncodedString, which would
    // raise an uncatchable system error no callback try/catch can contain.
    function base64ToByteArray(s as String) as ByteArray? {
        if (!isPlausibleBase64(s)) {
            return null;
        }
        var decoded = StringUtil.convertEncodedString(s, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        });
        if (!(decoded instanceof Lang.ByteArray)) {
            return null;
        }
        return decoded as ByteArray;
    }

    // One inbound message → transcode p to ByteArray per its runtime type,
    // then the EXISTING validators unchanged: Protocol.validateEnvelope
    // (which only accepts a ByteArray payload for chunkData — hence
    // transcode-first) and StreamDecoder.decodeChunk, proving the SPEC §5
    // bytes survived the trip end-to-end. Pure: no Storage, no
    // Communications, fully host-testable.
    function processMessage(data as Object?) as ProcessResult {
        var r = new ProcessResult();
        if (!(data instanceof Lang.Dictionary)) {
            r.err = ERR_NOT_DICT;
            return r;
        }
        var d = data as Dictionary;
        var p = d[Protocol.KEY_PAYLOAD] as Lang.Object?;
        r.enc = encodingLabel(p);

        var bytes = null;
        if (p instanceof Lang.String) {
            bytes = base64ToByteArray(p as String);
        } else if (p instanceof Lang.Array) {
            bytes = arrayToByteArray(p as Array);
        }
        if (bytes == null) {
            r.err = ERR_BAD_PAYLOAD;
            return r;
        }

        var copy = {} as Dictionary;
        var keys = d.keys();
        for (var i = 0; i < keys.size(); i++) {
            copy[keys[i]] = d[keys[i]];
        }
        copy[Protocol.KEY_PAYLOAD] = bytes;

        var verdict = Protocol.validateEnvelope(copy);
        if (verdict != null) {
            r.err = verdict;
            return r;
        }
        // validateEnvelope accepts a ByteArray payload only for chunkData, so
        // the type is already pinned here.
        var n = copy[Protocol.KEY_COUNT] as Number;
        if (StreamDecoder.decodeChunk(bytes, n) == null) {
            r.err = Protocol.ERR_DECODE_FAILURE;
            return r;
        }
        r.ok = true;
        r.off = copy[Protocol.KEY_OFFSET] as Number;
        return r;
    }

    // Compact label for a caught exception's message — the receive
    // catch-all must record SOMETHING usable; "exc" only when the platform
    // gives nothing. Truncated to stay within the small live display.
    const ERR_LABEL_MAX = 24;

    function errLabel(message as String?) as String {
        if (message == null || message.length() == 0) {
            return "exc";
        }
        var m = message as String;
        if (m.length() > ERR_LABEL_MAX) {
            return m.substring(0, ERR_LABEL_MAX) as String;
        }
        return m;
    }

    // Two-press reset window (pure, ms ticks from System.getTimer): open
    // only while armed and now within [armedAt, armedAt + windowMs]. A timer
    // wraparound (now < armedAt) closes the window safely.
    function armWindowOpen(armedAt as Number?, now as Number, windowMs as Number) as Boolean {
        if (armedAt == null) {
            return false;
        }
        var dt = now - (armedAt as Number);
        return dt >= 0 && dt <= windowMs;
    }

    // Live-counter line: received / valid / acked.
    function countsLine(received as Number, valid as Number, acked as Number) as String {
        return "R:" + received.toString() + " V:" + valid.toString()
            + " A:" + acked.toString();
    }

    // Evidence wire form persisted at exit — a compact String, not nested
    // arrays (Storage value-type polys differ between SDK 8.4.0/9.1.0).
    function evidenceString(received as Number, valid as Number, invalid as Number,
            acked as Number, ackErrors as Number, enc as String, err as String?) as String {
        return "r:" + received.toString() + ",v:" + valid.toString()
            + ",i:" + invalid.toString() + ",a:" + acked.toString()
            + ",ae:" + ackErrors.toString() + ",enc:" + enc
            + ",err:" + (err == null ? "none" : err);
    }
}

// Gate V2 spike view (Story 1.4): live receive/validate/ack counters in a
// small lit-pixel area (UX-DR1 Ink on Void; burn-in citizenship). Temporary
// spike code — Epic 4's sync/ modules supersede it.
class GateV2View extends WatchUi.View {

    private const COLOR_INK = 0xEAE6DF;  // UX-DR1 Ink
    private const COLOR_VOID = 0x000000; // UX-DR1 Void

    private var _app as PaceTurnerApp;
    private var _timer as Timer.Timer;

    function initialize(app as PaceTurnerApp) {
        View.initialize();
        _app = app;
        _timer = new Timer.Timer();
    }

    function onShow() as Void {
        _timer.start(method(:onTick), 1000, true);
    }

    function onHide() as Void {
        _timer.stop();
    }

    function onTick() as Void {
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(COLOR_INK, COLOR_VOID);
        dc.clear();

        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var small = dc.getFontHeight(Graphics.FONT_XTINY);

        dc.drawText(cx, cy - small, Graphics.FONT_MEDIUM, "GateV2",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var counts = GateV2.countsLine(
            _app.receivedCount(), _app.validCount(), _app.ackedCount());
        dc.drawText(cx, cy + small, Graphics.FONT_XTINY, counts,
            Graphics.TEXT_JUSTIFY_CENTER);

        var err = _app.lastError();
        var status = "enc:" + _app.lastEncoding()
            + " err:" + (err == null ? "-" : err);
        dc.drawText(cx, cy + small * 2, Graphics.FONT_XTINY, status,
            Graphics.TEXT_JUSTIFY_CENTER);

        if (_app.resetArmed()) {
            dc.drawText(cx, cy + small * 3, Graphics.FONT_XTINY,
                "reset? press again", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}

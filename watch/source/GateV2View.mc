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
        public var bytesLen as Number; // decoded SPEC §5 binary size, set when ok

        function initialize() {
            ok = false;
            off = null;
            err = null;
            enc = "?";
            bytesLen = 0;
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
        // The watch's independent witness of the largest message that crossed
        // BLE — corroborates the phone-side last-good (gate V3, Story 1.5).
        r.bytesLen = bytes.size();
        return r;
    }

    // Gate V3 lighten-receive: the size sweep measures the TRANSPORT ceiling
    // (largest message that crosses BLE and is received), NOT decode time. A
    // full per-word decode in the receive callback (processMessage) trips the
    // device watchdog on large chunks — uncatchable, hardware-confirmed
    // Story 1.5 — and would mask the transport ceiling AC1 asks for. Connect
    // IQ has no threads, so heavy work must be timer-sliced (Epic 4's
    // ChunkedWordSource decodes incrementally, never a whole chunk in the BLE
    // callback). So the watch does O(1) work here: cheap structural envelope
    // validation, a bounded-prefix integrity touch, the received-size witness,
    // and the ack. processMessage (full decode) stays the host/CI integrity
    // proof, where there is no watchdog. Pure — no Storage/Communications.
    const RECEIVE_PREFIX_B64 = 64; // base64 chars decoded for the head touch (→ 48 bytes)

    function receiveLight(data as Object?) as ProcessResult {
        var r = new ProcessResult();
        if (!(data instanceof Lang.Dictionary)) {
            r.err = ERR_NOT_DICT;
            return r;
        }
        var d = data as Dictionary;
        var p = d[Protocol.KEY_PAYLOAD] as Lang.Object?;
        r.enc = encodingLabel(p);

        var structural = validateChunkEnvelopeLight(d, p);
        if (structural != null) {
            r.err = structural;
            return r;
        }

        var binLen;
        if (p instanceof Lang.String) {
            var s = p as String;
            binLen = base64BinaryLen(s);
            // A base64 chunk payload is always a whole number of 4-char units;
            // binLen == 0 means a malformed length (not multiple of 4, or < 4).
            // Reject rather than ack with a 0 witness that under-reports rcv:.
            if (binLen == 0) {
                r.err = ERR_BAD_PAYLOAD;
                return r;
            }
            // Bounded O(1) integrity touch: the head must decode and its first
            // SPEC §5 record header must be sane. Proves real chunk bytes
            // arrived, not a blob that merely deserialized as a string.
            if (!headDecodes(s)) {
                r.err = ERR_BAD_PAYLOAD;
                return r;
            }
        } else {
            // Run B (Number Array) is not swept (ADR 0002); record element count.
            binLen = (p as Array).size();
        }

        r.ok = true;
        r.off = d[Protocol.KEY_OFFSET] as Number;
        r.bytesLen = binLen;
        return r;
    }

    // Cheap structural chunkData-envelope validation — version, type, known
    // keys, fp/off/n presence+range — WITHOUT decoding the payload (our
    // transport p is a base64 String / Number Array, not yet a ByteArray, so
    // Protocol.validateEnvelope's ByteArray check can't be reused here).
    function validateChunkEnvelopeLight(d as Dictionary, p as Object?) as String? {
        var v = d[Protocol.KEY_VERSION];
        if (!(v instanceof Lang.Number) || (v as Number) != Protocol.PROTOCOL_VERSION) {
            return Protocol.ERR_VERSION_MISMATCH;
        }
        var t = d[Protocol.KEY_TYPE];
        if (!(t instanceof Lang.String) || !(t as String).equals(Protocol.MSG_CHUNK_DATA)) {
            return Protocol.ERR_UNKNOWN_TYPE;
        }
        var keys = d.keys();
        for (var i = 0; i < keys.size(); i++) {
            var key = keys[i];
            if (!(key instanceof Lang.String)) { return Protocol.ERR_MALFORMED_ENVELOPE; }
            var k = key as String;
            if (!(k.equals(Protocol.KEY_TYPE) || k.equals(Protocol.KEY_VERSION)
                    || k.equals(Protocol.KEY_FINGERPRINT) || k.equals(Protocol.KEY_OFFSET)
                    || k.equals(Protocol.KEY_COUNT) || k.equals(Protocol.KEY_PAYLOAD))) {
                return Protocol.ERR_MALFORMED_ENVELOPE;
            }
        }
        var fp = d[Protocol.KEY_FINGERPRINT] as Lang.Object?;
        var off = d[Protocol.KEY_OFFSET] as Lang.Object?;
        var n = d[Protocol.KEY_COUNT] as Lang.Object?;
        if (fp == null || !Protocol.isValidFingerprint(fp)) {
            return Protocol.ERR_MALFORMED_ENVELOPE;
        }
        if (!(off instanceof Lang.Number) || (off as Number) < 0) {
            return Protocol.ERR_MALFORMED_ENVELOPE;
        }
        if (!(n instanceof Lang.Number) || (n as Number) < 1) {
            return Protocol.ERR_MALFORMED_ENVELOPE;
        }
        if (p instanceof Lang.String) {
            if ((p as String).length() == 0) { return Protocol.ERR_MALFORMED_ENVELOPE; }
        } else if (!(p instanceof Lang.Array)) {
            return Protocol.ERR_MALFORMED_ENVELOPE;
        }
        return null;
    }

    // Binary size of a base64 string, read in O(1) from its length + padding —
    // never scans the whole (multi-KB) string (that itself risks the watchdog).
    function base64BinaryLen(s as String) as Number {
        var len = s.length();
        if (len < 4 || len % 4 != 0) { return 0; }
        var tail = s.substring(len - 2, len) as String;
        var tc = tail.toCharArray();
        var pad = 0;
        if (tc[1].toNumber() == 61) { pad++; }      // trailing '='
        if (tc[0].toNumber() == 61) { pad++; }
        return (len / 4) * 3 - pad;
    }

    // Bounded integrity touch: decode only the first RECEIVE_PREFIX_B64 base64
    // chars (a base64 prefix carries no padding, so it decodes cleanly) and
    // check the first SPEC §5 record header is in range. O(1) regardless of
    // chunk size — no watchdog risk.
    function headDecodes(s as String) as Boolean {
        var len = s.length();
        var take = len < RECEIVE_PREFIX_B64 ? len : RECEIVE_PREFIX_B64;
        take = (take / 4) * 4; // whole base64 units only
        if (take < 4) { return false; }
        var prefix = s.substring(0, take) as String;
        var bytes = base64ToByteArray(prefix); // guards convertEncodedString internally
        if (bytes == null || bytes.size() < Protocol.RECORD_HEADER_BYTES) {
            return false;
        }
        var wordLen = bytes[0] as Number;
        var orpPivot = bytes[2] as Number;
        return wordLen >= 1 && wordLen <= 255 && orpPivot < wordLen;
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

    // Max-received-size witness line (gate V3): the largest chunk (SPEC §5
    // binary bytes) the watch received + acked this run. Under lighten-receive
    // this is the watch's independent witness of the transport ceiling — the
    // largest message that crossed BLE. A bounded counter — no growing log
    // (AR25 logging-budget discipline).
    function maxReceivedLine(maxReceived as Number) as String {
        return "rcv:" + maxReceived.toString() + "B";
    }

    // Evidence wire form persisted at exit — a compact String, not nested
    // arrays (Storage value-type polys differ between SDK 8.4.0/9.1.0).
    function evidenceString(received as Number, valid as Number, invalid as Number,
            acked as Number, ackErrors as Number, maxReceived as Number,
            enc as String, err as String?) as String {
        return "r:" + received.toString() + ",v:" + valid.toString()
            + ",i:" + invalid.toString() + ",a:" + acked.toString()
            + ",ae:" + ackErrors.toString() + ",rcv:" + maxReceived.toString()
            + ",enc:" + enc + ",err:" + (err == null ? "none" : err);
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

        dc.drawText(cx, cy + small * 3, Graphics.FONT_XTINY,
            GateV2.maxReceivedLine(_app.maxReceived()), Graphics.TEXT_JUSTIFY_CENTER);

        if (_app.resetArmed()) {
            dc.drawText(cx, cy + small * 4, Graphics.FONT_XTINY,
                "reset? press again", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}

import Toybox.Lang;
import Toybox.StringUtil;
import Toybox.Test;

// Tests for the Gate V2 spike's pure helpers (Story 1.4). The spike itself is
// hardware-judged; only the extracted pure functions are unit-tested.
// NEVER feed malformed input DIRECTLY to convertEncodedString — it raises an
// UNCATCHABLE system error on SDK 8.4.0 (the CI image; Story 1.2 lesson).
// base64ToByteArray is safe for malformed input: its isPlausibleBase64 guard
// rejects garbage before the SDK call — which is exactly what the malformed
// cases below exercise.

module GateV2TestSupport {

    // Base64 of a well-formed ByteArray — encoding is safe; only decoding
    // malformed text is the landmine.
    function toBase64(bytes as ByteArray) as String {
        return StringUtil.convertEncodedString(bytes, {
            :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            :toRepresentation => StringUtil.REPRESENTATION_STRING_BASE64
        }) as String;
    }

    // The wire shape of Run B: the SPEC §5 bytes as a plain Array of Numbers.
    function toNumberArray(bytes as ByteArray) as Array<Number> {
        var out = [] as Array<Number>;
        for (var i = 0; i < bytes.size(); i++) {
            out.add(bytes[i] as Number);
        }
        return out;
    }

    // A valid chunkData envelope over the protocol worked example, with the
    // payload already transcoded for transport.
    function exampleEnvelope(transportPayload as Object) as Dictionary {
        return {
            "t" => Protocol.MSG_CHUNK_DATA,
            "v" => Protocol.PROTOCOL_VERSION,
            "fp" => "9f86d081",
            "off" => 0,
            "n" => 3,
            "p" => transportPayload
        };
    }

    // A large, well-formed SPEC §5 payload: n records of wordLen ASCII bytes
    // each (flags 0, orpPivot 0, bonus 0). Built byte-exact so the fixture is
    // always valid UTF-8 — convertEncodedString never sees malformed input
    // (Story 1.2 lesson). Lets the gate V3 witness test cross a multi-KB chunk.
    function largeChunk(n as Number, wordLen as Number) as ByteArray {
        var recordBytes = Protocol.RECORD_HEADER_BYTES + wordLen;
        var out = new [n * recordBytes]b;
        var pos = 0;
        for (var i = 0; i < n; i++) {
            out.encodeNumber(wordLen, Lang.NUMBER_FORMAT_UINT8, {:offset => pos});
            out.encodeNumber(0, Lang.NUMBER_FORMAT_UINT8, {:offset => pos + 1});
            out.encodeNumber(0, Lang.NUMBER_FORMAT_UINT8, {:offset => pos + 2});
            out.encodeNumber(0, Lang.NUMBER_FORMAT_UINT16,
                {:offset => pos + 3, :endianness => Lang.ENDIAN_LITTLE});
            for (var j = 0; j < wordLen; j++) {
                out[pos + Protocol.RECORD_HEADER_BYTES + j] = (0x61 + ((i + j) % 26)) as Number;
            }
            pos += recordBytes;
        }
        return out;
    }

    // A valid chunkData envelope for an arbitrary record count.
    function largeEnvelope(transportPayload as Object, n as Number) as Dictionary {
        return {
            "t" => Protocol.MSG_CHUNK_DATA,
            "v" => Protocol.PROTOCOL_VERSION,
            "fp" => "9f86d081",
            "off" => 0,
            "n" => n,
            "p" => transportPayload
        };
    }
}

(:test)
function gateV2ArrayToByteArrayTest(logger as Test.Logger) as Boolean {
    logger.debug("arrayToByteArray: valid bytes, bounds, wrong element types");
    var ok = GateV2.arrayToByteArray([0, 1, 127, 255] as Array);
    if (ok == null) { logger.error("valid array rejected"); return false; }
    if (!ProtocolTestSupport.bytesEqual(ok, [0x00, 0x01, 0x7F, 0xFF]b)) {
        logger.error("transcoded bytes differ"); return false;
    }
    var empty = GateV2.arrayToByteArray([] as Array);
    if (empty == null || empty.size() != 0) {
        logger.error("empty array should transcode to empty ByteArray"); return false;
    }
    if (GateV2.arrayToByteArray([0, 256] as Array) != null) {
        logger.error("element > 255 accepted"); return false;
    }
    if (GateV2.arrayToByteArray([-1] as Array) != null) {
        logger.error("negative element accepted"); return false;
    }
    if (GateV2.arrayToByteArray(["x"] as Array) != null) {
        logger.error("non-number element accepted"); return false;
    }
    return true;
}

(:test)
function gateV2Base64RoundTripTest(logger as Test.Logger) as Boolean {
    logger.debug("base64ToByteArray: well-formed round trip of the spec example");
    var payload = ProtocolTestSupport.examplePayload();
    var decoded = GateV2.base64ToByteArray(GateV2TestSupport.toBase64(payload));
    if (decoded == null) { logger.error("well-formed base64 rejected"); return false; }
    if (!ProtocolTestSupport.bytesEqual(decoded, payload)) {
        logger.error("round trip differs from spec example bytes"); return false;
    }
    return true;
}

(:test)
function gateV2IsPlausibleBase64Test(logger as Test.Logger) as Boolean {
    logger.debug("isPlausibleBase64: alphabet, length, and padding structure");
    var goods = ["QUJD", "QQ==", "QUI=", "ab+/", "AbC9efGh"];
    for (var i = 0; i < goods.size(); i++) {
        if (!GateV2.isPlausibleBase64(goods[i] as String)) {
            logger.error("rejected well-formed: " + goods[i]); return false;
        }
    }
    var real = GateV2TestSupport.toBase64(ProtocolTestSupport.examplePayload());
    if (!GateV2.isPlausibleBase64(real)) {
        logger.error("rejected real encoded payload"); return false;
    }
    var bads = ["", "abc", "####", "ab!d", "a=bc", "ab=c", "QUJD\n123", "=AAA"];
    for (var i = 0; i < bads.size(); i++) {
        if (GateV2.isPlausibleBase64(bads[i] as String)) {
            logger.error("accepted malformed: " + bads[i]); return false;
        }
    }
    return true;
}

(:test)
function gateV2Base64RejectsMalformedTest(logger as Test.Logger) as Boolean {
    logger.debug("base64ToByteArray: malformed input degrades to null, never crashes");
    if (GateV2.base64ToByteArray("####") != null) {
        logger.error("bad alphabet accepted"); return false;
    }
    if (GateV2.base64ToByteArray("ab=c") != null) {
        logger.error("interior padding accepted"); return false;
    }
    if (GateV2.base64ToByteArray("") != null) {
        logger.error("empty string accepted"); return false;
    }
    // And the guard does not break processMessage's Run A path on garbage.
    var msg = GateV2TestSupport.exampleEnvelope("not-base64-!");
    var r = GateV2.processMessage(msg);
    if (r.ok || !GateV2.ERR_BAD_PAYLOAD.equals(r.err)) {
        logger.error("malformed String payload accepted"); return false;
    }
    return true;
}

(:test)
function gateV2ErrLabelTest(logger as Test.Logger) as Boolean {
    logger.debug("errLabel: null/empty fallback, pass-through, truncation");
    if (!GateV2.errLabel(null).equals("exc")) {
        logger.error("null message"); return false;
    }
    if (!GateV2.errLabel("").equals("exc")) {
        logger.error("empty message"); return false;
    }
    if (!GateV2.errLabel("boom").equals("boom")) {
        logger.error("short message altered"); return false;
    }
    var long = "Unexpected Type Error in callback frame";
    var label = GateV2.errLabel(long);
    if (label.length() != GateV2.ERR_LABEL_MAX) {
        logger.error("not truncated to max: " + label); return false;
    }
    if (!(long.substring(0, GateV2.ERR_LABEL_MAX) as String).equals(label)) {
        logger.error("truncation altered content"); return false;
    }
    return true;
}

(:test)
function gateV2ArmWindowOpenTest(logger as Test.Logger) as Boolean {
    logger.debug("armWindowOpen: disarmed, inside, boundary, expired, wraparound");
    if (GateV2.armWindowOpen(null, 1000, 3000)) {
        logger.error("disarmed window open"); return false;
    }
    if (!GateV2.armWindowOpen(1000, 1000, 3000)) {
        logger.error("same-tick press rejected"); return false;
    }
    if (!GateV2.armWindowOpen(1000, 4000, 3000)) {
        logger.error("boundary press rejected"); return false;
    }
    if (GateV2.armWindowOpen(1000, 4001, 3000)) {
        logger.error("expired window open"); return false;
    }
    // System.getTimer() wraparound: now < armedAt must close the window.
    if (GateV2.armWindowOpen(1000, 500, 3000)) {
        logger.error("wraparound window open"); return false;
    }
    return true;
}

(:test)
function gateV2EncodingLabelTest(logger as Test.Logger) as Boolean {
    logger.debug("encodingLabel: String, Array, and everything else");
    if (!GateV2.encodingLabel("abc").equals("String")) {
        logger.error("String label"); return false;
    }
    if (!GateV2.encodingLabel([1, 2] as Array<Number>).equals("Array")) {
        logger.error("Array label"); return false;
    }
    if (!GateV2.encodingLabel(null).equals("?")) {
        logger.error("null label"); return false;
    }
    if (!GateV2.encodingLabel(42).equals("?")) {
        logger.error("Number label"); return false;
    }
    return true;
}

(:test)
function gateV2ProcessMessageStringPayloadTest(logger as Test.Logger) as Boolean {
    logger.debug("processMessage: Run A — base64 String payload end-to-end");
    var payload = ProtocolTestSupport.examplePayload();
    var msg = GateV2TestSupport.exampleEnvelope(GateV2TestSupport.toBase64(payload));
    var r = GateV2.processMessage(msg);
    if (!r.ok) { logger.error("valid String-payload chunk rejected: " + r.err); return false; }
    if (r.off != 0) { logger.error("offset"); return false; }
    if (!r.enc.equals("String")) { logger.error("encoding label"); return false; }
    if (r.err != null) { logger.error("err set on success"); return false; }
    if (r.bytesLen != payload.size()) {
        logger.error("bytesLen witness: " + r.bytesLen); return false;
    }
    return true;
}

(:test)
function gateV2ProcessMessageArrayPayloadTest(logger as Test.Logger) as Boolean {
    logger.debug("processMessage: Run B — Array<Number> payload end-to-end");
    var payload = ProtocolTestSupport.examplePayload();
    var msg = GateV2TestSupport.exampleEnvelope(GateV2TestSupport.toNumberArray(payload));
    var r = GateV2.processMessage(msg);
    if (!r.ok) { logger.error("valid Array-payload chunk rejected: " + r.err); return false; }
    if (r.off != 0) { logger.error("offset"); return false; }
    if (!r.enc.equals("Array")) { logger.error("encoding label"); return false; }
    return true;
}

(:test)
function gateV2ProcessMessageRejectionsTest(logger as Test.Logger) as Boolean {
    logger.debug("processMessage: malformed inputs degrade to errors, never crash");
    var payload = ProtocolTestSupport.examplePayload();

    // Not a dictionary at all.
    var r = GateV2.processMessage("hello");
    if (r.ok || !GateV2.ERR_NOT_DICT.equals(r.err)) {
        logger.error("non-dict accepted"); return false;
    }

    // Payload of an untranscodable runtime type.
    var badPayloadMsg = GateV2TestSupport.exampleEnvelope(42);
    r = GateV2.processMessage(badPayloadMsg);
    if (r.ok || !GateV2.ERR_BAD_PAYLOAD.equals(r.err)) {
        logger.error("Number payload accepted"); return false;
    }

    // Array payload with an out-of-range element.
    var badArrayMsg = GateV2TestSupport.exampleEnvelope([0, 999] as Array<Number>);
    r = GateV2.processMessage(badArrayMsg);
    if (r.ok || !GateV2.ERR_BAD_PAYLOAD.equals(r.err)) {
        logger.error("out-of-range array element accepted"); return false;
    }

    // Version gate still runs (SPEC §2) — existing validator, unchanged.
    var badVersion = GateV2TestSupport.exampleEnvelope(GateV2TestSupport.toBase64(payload));
    badVersion["v"] = 2;
    r = GateV2.processMessage(badVersion);
    if (r.ok || !Protocol.ERR_VERSION_MISMATCH.equals(r.err)) {
        logger.error("v=2 accepted"); return false;
    }

    // Missing fingerprint → malformedEnvelope from the existing validator.
    var noFp = GateV2TestSupport.exampleEnvelope(GateV2TestSupport.toBase64(payload));
    noFp.remove("fp");
    r = GateV2.processMessage(noFp);
    if (r.ok || !Protocol.ERR_MALFORMED_ENVELOPE.equals(r.err)) {
        logger.error("missing fp accepted"); return false;
    }

    // n disagreeing with the payload → decodeFailure (SPEC §4.3).
    var badN = GateV2TestSupport.exampleEnvelope(GateV2TestSupport.toBase64(payload));
    badN["n"] = 2;
    r = GateV2.processMessage(badN);
    if (r.ok || !Protocol.ERR_DECODE_FAILURE.equals(r.err)) {
        logger.error("n mismatch accepted"); return false;
    }
    return true;
}

(:test)
function gateV2CountsLineTest(logger as Test.Logger) as Boolean {
    logger.debug("countsLine: live-counter formatting");
    if (!GateV2.countsLine(0, 0, 0).equals("R:0 V:0 A:0")) {
        logger.error("zeros"); return false;
    }
    if (!GateV2.countsLine(200, 199, 198).equals("R:200 V:199 A:198")) {
        logger.error("run-sized counts"); return false;
    }
    return true;
}

(:test)
function gateV2EvidenceStringTest(logger as Test.Logger) as Boolean {
    logger.debug("evidenceString: compact persisted form (String, not nested arrays)");
    var s = GateV2.evidenceString(200, 199, 1, 198, 2, 9800, "String", Protocol.ERR_DECODE_FAILURE);
    if (!s.equals("r:200,v:199,i:1,a:198,ae:2,md:9800,enc:String,err:decodeFailure")) {
        logger.error("formatted: " + s); return false;
    }
    var clean = GateV2.evidenceString(5, 5, 0, 5, 0, 32, "Array", null);
    if (!clean.equals("r:5,v:5,i:0,a:5,ae:0,md:32,enc:Array,err:none")) {
        logger.error("clean run: " + clean); return false;
    }
    return true;
}

(:test)
function gateV2MaxDecodedLineTest(logger as Test.Logger) as Boolean {
    logger.debug("maxDecodedLine: bounded witness display");
    if (!GateV2.maxDecodedLine(0).equals("max:0B")) {
        logger.error("zero"); return false;
    }
    if (!GateV2.maxDecodedLine(10200).equals("max:10200B")) {
        logger.error("multi-KB"); return false;
    }
    return true;
}

(:test)
function gateV2LargeChunkWitnessTest(logger as Test.Logger) as Boolean {
    logger.debug("processMessage: a multi-KB well-formed chunk round-trips; bytesLen witnessed");
    // 32 records × 250-byte words = 8160 B binary (~10.9 KB base64) — well past
    // Story 1.4's ~900 B floor, exercising the larger-chunk receive path.
    var n = 32;
    var wordLen = 250;
    var payload = GateV2TestSupport.largeChunk(n, wordLen);
    var msg = GateV2TestSupport.largeEnvelope(GateV2TestSupport.toBase64(payload), n);
    var r = GateV2.processMessage(msg);
    if (!r.ok) { logger.error("large chunk rejected: " + r.err); return false; }
    if (r.off != 0) { logger.error("offset"); return false; }
    if (r.bytesLen != payload.size()) {
        logger.error("bytesLen witness wrong: " + r.bytesLen); return false;
    }
    if (r.bytesLen <= 900) {
        logger.error("fixture not larger than Story-1.4 size"); return false;
    }
    return true;
}

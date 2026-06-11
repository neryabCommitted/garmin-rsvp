import Toybox.Lang;
import Toybox.StringUtil;
import Toybox.Test;

// Tests for the Gate V2 spike's pure helpers (Story 1.4). The spike itself is
// hardware-judged; only the extracted pure functions are unit-tested.
// NEVER feed malformed input to the base64 path — convertEncodedString raises
// an UNCATCHABLE system error on SDK 8.4.0 (the CI image); well-formed
// fixtures only (Story 1.2 lesson).

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
    var s = GateV2.evidenceString(200, 199, 1, 198, 2, "String", Protocol.ERR_DECODE_FAILURE);
    if (!s.equals("r:200,v:199,i:1,a:198,ae:2,enc:String,err:decodeFailure")) {
        logger.error("formatted: " + s); return false;
    }
    var clean = GateV2.evidenceString(5, 5, 0, 5, 0, "Array", null);
    if (!clean.equals("r:5,v:5,i:0,a:5,ae:0,enc:Array,err:none")) {
        logger.error("clean run: " + clean); return false;
    }
    return true;
}

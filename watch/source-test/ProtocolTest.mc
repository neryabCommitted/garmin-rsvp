import Toybox.Lang;
import Toybox.StringUtil;
import Toybox.Test;

// Conformance tests pinned to the protocol's worked examples
// (protocol/examples/word-records.md, protocol/examples/envelopes.md).
// Literal values are asserted on purpose: constant drift in Protocol.mc must
// fail this build, not a code review (SPEC §3, §4, §6, §8).
module ProtocolTestSupport {

    // The 32-byte normative payload from protocol/examples/word-records.md:
    // "Pace" (paragraphStart|chapterStart) · "turns" · "שלום" (sentenceEnd, 350 ms).
    function examplePayload() as ByteArray {
        return [
            // record 0: "Pace", flags 0x06, pivot 1, bonus 0
            0x04, 0x06, 0x01, 0x00, 0x00, 0x50, 0x61, 0x63, 0x65,
            // record 1: "turns", flags 0x00, pivot 1, bonus 0
            0x05, 0x00, 0x01, 0x00, 0x00, 0x74, 0x75, 0x72, 0x6E, 0x73,
            // record 2: "שלום", flags 0x01, pivot 2 (byte index!), bonus 350 (5E 01 LE)
            0x08, 0x01, 0x02, 0x5E, 0x01, 0xD7, 0xA9, 0xD7, 0x9C, 0xD7, 0x95, 0xD7, 0x9D
        ]b;
    }

    // Expected word 2 built from its spec hex (not a source literal, so the
    // fixture stays byte-exact and ASCII-clean).
    function exampleHebrewWord() as String {
        return utf8ToString([0xD7, 0xA9, 0xD7, 0x9C, 0xD7, 0x95, 0xD7, 0x9D]b);
    }

    function utf8ToString(bytes as ByteArray) as String {
        return StringUtil.convertEncodedString(bytes, {
            :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            :toRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
            :encoding => StringUtil.CHAR_ENCODING_UTF8
        }) as String;
    }

    // Test-side encoder: re-encodes a decoded record per SPEC §5 so the watch
    // demonstrably reproduces the example bytes (AC3). Production encoding is
    // phone-side only; this helper exists for conformance proof.
    function encodeRecord(rec as StreamDecoder.WordRecord) as ByteArray {
        var wordBytes = rec.word.toUtf8Array();
        var out = new [Protocol.RECORD_HEADER_BYTES + wordBytes.size()]b;
        out.encodeNumber(wordBytes.size(), Lang.NUMBER_FORMAT_UINT8, {:offset => 0});  // SPEC §5 wordLen
        out.encodeNumber(rec.flags, Lang.NUMBER_FORMAT_UINT8, {:offset => 1});         // SPEC §5 flags
        out.encodeNumber(rec.orpPivot, Lang.NUMBER_FORMAT_UINT8, {:offset => 2});      // SPEC §5 orpPivot
        out.encodeNumber(rec.bonusMs, Lang.NUMBER_FORMAT_UINT16,
            {:offset => 3, :endianness => Lang.ENDIAN_LITTLE});                        // SPEC §5 bonusMs
        for (var i = 0; i < wordBytes.size(); i++) {
            out[Protocol.RECORD_HEADER_BYTES + i] = (wordBytes[i] as Number).toNumber();
        }
        return out;
    }

    function bytesEqual(a as ByteArray, b as ByteArray) as Boolean {
        if (a.size() != b.size()) {
            return false;
        }
        for (var i = 0; i < a.size(); i++) {
            if (a[i] != b[i]) {
                return false;
            }
        }
        return true;
    }
}

// ── Constant drift detection (AC2) ──────────────────────────────────────────

(:test)
function protocolConstantsMatchSpec(logger as Test.Logger) as Boolean {
    // SPEC §2
    if (Protocol.PROTOCOL_VERSION != 1) { logger.error("PROTOCOL_VERSION"); return false; }
    // SPEC §3 envelope keys
    if (!Protocol.KEY_TYPE.equals("t")) { logger.error("KEY_TYPE"); return false; }
    if (!Protocol.KEY_VERSION.equals("v")) { logger.error("KEY_VERSION"); return false; }
    if (!Protocol.KEY_FINGERPRINT.equals("fp")) { logger.error("KEY_FINGERPRINT"); return false; }
    if (!Protocol.KEY_OFFSET.equals("off")) { logger.error("KEY_OFFSET"); return false; }
    if (!Protocol.KEY_COUNT.equals("n")) { logger.error("KEY_COUNT"); return false; }
    if (!Protocol.KEY_PAYLOAD.equals("p")) { logger.error("KEY_PAYLOAD"); return false; }
    // SPEC §4 message types
    if (!Protocol.MSG_MANIFEST.equals("manifest")) { logger.error("MSG_MANIFEST"); return false; }
    if (!Protocol.MSG_CHUNK_REQUEST.equals("chunkRequest")) { logger.error("MSG_CHUNK_REQUEST"); return false; }
    if (!Protocol.MSG_CHUNK_DATA.equals("chunkData")) { logger.error("MSG_CHUNK_DATA"); return false; }
    if (!Protocol.MSG_POSITION.equals("position")) { logger.error("MSG_POSITION"); return false; }
    if (!Protocol.MSG_ERROR.equals("error")) { logger.error("MSG_ERROR"); return false; }
    // SPEC §4.1 / §4.4 / §4.5 payload keys
    if (!Protocol.KEY_TITLE.equals("ti")) { logger.error("KEY_TITLE"); return false; }
    if (!Protocol.KEY_TOTAL_WORDS.equals("tw")) { logger.error("KEY_TOTAL_WORDS"); return false; }
    if (!Protocol.KEY_TOTAL_BONUS_MS.equals("tb")) { logger.error("KEY_TOTAL_BONUS_MS"); return false; }
    if (!Protocol.KEY_CHAPTERS.equals("ch")) { logger.error("KEY_CHAPTERS"); return false; }
    if (!Protocol.KEY_CHAPTER_OFFSET.equals("o")) { logger.error("KEY_CHAPTER_OFFSET"); return false; }
    if (!Protocol.KEY_CHAPTER_CUM_BONUS_MS.equals("cb")) { logger.error("KEY_CHAPTER_CUM_BONUS_MS"); return false; }
    if (!Protocol.KEY_TIMESTAMP.equals("ts")) { logger.error("KEY_TIMESTAMP"); return false; }
    if (!Protocol.KEY_SOURCE.equals("src")) { logger.error("KEY_SOURCE"); return false; }
    if (!Protocol.SRC_WATCH.equals("watch")) { logger.error("SRC_WATCH"); return false; }
    if (!Protocol.SRC_PHONE.equals("phone")) { logger.error("SRC_PHONE"); return false; }
    if (!Protocol.KEY_ERROR_CODE.equals("c")) { logger.error("KEY_ERROR_CODE"); return false; }
    if (!Protocol.KEY_ERROR_MESSAGE.equals("m")) { logger.error("KEY_ERROR_MESSAGE"); return false; }
    // SPEC §6 flag bits
    if (Protocol.FLAG_SENTENCE_END != 0x01) { logger.error("FLAG_SENTENCE_END"); return false; }
    if (Protocol.FLAG_PARAGRAPH_START != 0x02) { logger.error("FLAG_PARAGRAPH_START"); return false; }
    if (Protocol.FLAG_CHAPTER_START != 0x04) { logger.error("FLAG_CHAPTER_START"); return false; }
    if (Protocol.FLAG_CONTINUATION != 0x08) { logger.error("FLAG_CONTINUATION"); return false; }
    if (Protocol.FLAG_RTL != 0x10) { logger.error("FLAG_RTL"); return false; }
    if (Protocol.FLAGS_RESERVED_MASK != 0xF8) { logger.error("FLAGS_RESERVED_MASK"); return false; }
    // SPEC §5 / §7 numeric constants
    if (Protocol.RECORD_HEADER_BYTES != 5) { logger.error("RECORD_HEADER_BYTES"); return false; }
    if (Protocol.FINGERPRINT_LENGTH != 8) { logger.error("FINGERPRINT_LENGTH"); return false; }
    // SPEC §8 error codes
    if (!Protocol.ERR_VERSION_MISMATCH.equals("versionMismatch")) { logger.error("ERR_VERSION_MISMATCH"); return false; }
    if (!Protocol.ERR_UNKNOWN_TYPE.equals("unknownType")) { logger.error("ERR_UNKNOWN_TYPE"); return false; }
    if (!Protocol.ERR_MALFORMED_ENVELOPE.equals("malformedEnvelope")) { logger.error("ERR_MALFORMED_ENVELOPE"); return false; }
    if (!Protocol.ERR_UNKNOWN_FINGERPRINT.equals("unknownFingerprint")) { logger.error("ERR_UNKNOWN_FINGERPRINT"); return false; }
    if (!Protocol.ERR_RANGE_UNAVAILABLE.equals("rangeUnavailable")) { logger.error("ERR_RANGE_UNAVAILABLE"); return false; }
    if (!Protocol.ERR_DECODE_FAILURE.equals("decodeFailure")) { logger.error("ERR_DECODE_FAILURE"); return false; }
    if (!Protocol.ERR_INTERNAL.equals("internal")) { logger.error("ERR_INTERNAL"); return false; }
    return true;
}

// ── SPEC §5 decode of the worked example (AC3) ──────────────────────────────

(:test)
function streamDecoderDecodesExampleBytes(logger as Test.Logger) as Boolean {
    var records = StreamDecoder.decodeChunk(ProtocolTestSupport.examplePayload(), 3);
    if (records == null) { logger.error("example payload failed to decode"); return false; }
    if (records.size() != 3) { logger.error("expected 3 records"); return false; }

    var r0 = records[0];
    if (!r0.word.equals("Pace")) { logger.error("r0.word"); return false; }
    if (r0.flags != (Protocol.FLAG_PARAGRAPH_START | Protocol.FLAG_CHAPTER_START)) { logger.error("r0.flags"); return false; }
    if (r0.orpPivot != 1) { logger.error("r0.orpPivot"); return false; }
    if (r0.bonusMs != 0) { logger.error("r0.bonusMs"); return false; }

    var r1 = records[1];
    if (!r1.word.equals("turns")) { logger.error("r1.word"); return false; }
    if (r1.flags != 0) { logger.error("r1.flags"); return false; }
    if (r1.orpPivot != 1) { logger.error("r1.orpPivot"); return false; }
    if (r1.bonusMs != 0) { logger.error("r1.bonusMs"); return false; }

    var r2 = records[2];
    if (!r2.word.equals(ProtocolTestSupport.exampleHebrewWord())) { logger.error("r2.word"); return false; }
    if (r2.flags != Protocol.FLAG_SENTENCE_END) { logger.error("r2.flags"); return false; }
    if (r2.orpPivot != 2) { logger.error("r2.orpPivot (byte index)"); return false; }
    if (r2.bonusMs != 350) { logger.error("r2.bonusMs"); return false; }
    return true;
}

// ── SPEC §5 re-encode reproduces the example bytes exactly (AC3) ────────────

(:test)
function streamRecordsReencodeToExampleBytes(logger as Test.Logger) as Boolean {
    var payload = ProtocolTestSupport.examplePayload();
    var records = StreamDecoder.decodeChunk(payload, 3);
    if (records == null) { logger.error("decode failed"); return false; }

    var reencoded = []b;
    for (var i = 0; i < records.size(); i++) {
        reencoded.addAll(ProtocolTestSupport.encodeRecord(records[i]));
    }
    if (!ProtocolTestSupport.bytesEqual(reencoded, payload)) {
        logger.error("re-encoded bytes differ from spec example");
        return false;
    }
    return true;
}

// ── SPEC §5 decode validation: malformed input degrades, never throws ───────

(:test)
function streamDecoderRejectsMalformedInput(logger as Test.Logger) as Boolean {
    var payload = ProtocolTestSupport.examplePayload();

    // Truncated mid-header.
    if (StreamDecoder.decodeChunk(payload.slice(0, 3), 1) != null) {
        logger.error("truncated header accepted"); return false;
    }
    // Truncated mid-word.
    if (StreamDecoder.decodeChunk(payload.slice(0, 7), 1) != null) {
        logger.error("truncated word accepted"); return false;
    }
    // Record count mismatch: fewer records than n.
    if (StreamDecoder.decodeChunk(payload.slice(0, 9), 2) != null) {
        logger.error("short record count accepted"); return false;
    }
    // Trailing bytes after n records (SPEC §4.3 exact-consumption rule).
    if (StreamDecoder.decodeChunk(payload, 2) != null) {
        logger.error("trailing bytes accepted"); return false;
    }
    // wordLen 0 is invalid (SPEC §5).
    if (StreamDecoder.decodeChunk([0x00, 0x00, 0x00, 0x00, 0x00]b, 1) != null) {
        logger.error("wordLen 0 accepted"); return false;
    }
    // orpPivot >= wordLen (SPEC §5).
    if (StreamDecoder.decodeChunk([0x01, 0x00, 0x01, 0x00, 0x00, 0x41]b, 1) != null) {
        logger.error("out-of-range pivot accepted"); return false;
    }
    // Reserved flag bits set (SPEC §6): every reserved bit individually —
    // 0x08 continuation, 0x10 rtl, and bits 5–7 — so a mask typo fails here.
    var reservedFlags = [0x08, 0x10, 0x20, 0x40, 0x80, 0xE0];
    for (var i = 0; i < reservedFlags.size(); i++) {
        var probe = [0x01, 0x00, 0x00, 0x00, 0x00, 0x41]b;
        probe[1] = reservedFlags[i] as Number;
        if (StreamDecoder.decodeChunk(probe, 1) != null) {
            logger.error("reserved flag bits accepted"); return false;
        }
    }
    // Invalid UTF-8 word bytes (SPEC §5): lone continuation byte 0x80 —
    // same probe as the companion's "rejects invalid UTF-8" test.
    if (StreamDecoder.decodeChunk([0x01, 0x00, 0x00, 0x00, 0x00, 0x80]b, 1) != null) {
        logger.error("invalid UTF-8 accepted"); return false;
    }
    // n < 1 is invalid.
    if (StreamDecoder.decodeChunk([]b, 0) != null) {
        logger.error("n=0 accepted"); return false;
    }
    return true;
}

// ── SPEC §3 step 3: structure validation mirrors the companion (AC2/AC4) ────

(:test)
function envelopeStructureIsValidated(logger as Test.Logger) as Boolean {
    // Valid envelopes per protocol/examples/envelopes.md are accepted.
    var manifest = {
        "t" => Protocol.MSG_MANIFEST,
        "v" => Protocol.PROTOCOL_VERSION,
        "fp" => "9f86d081",
        "p" => {
            "ti" => "Example Book",
            "tw" => 50000,
            "tb" => 412350,
            "ch" => [
                { "o" => 0, "ti" => "Chapter 1", "cb" => 0 },
                { "o" => 1000, "ti" => "Chapter 2", "cb" => 8350 }
            ]
        }
    };
    if (Protocol.validateEnvelope(manifest) != null) {
        logger.error("valid manifest rejected"); return false;
    }
    var position = {
        "t" => Protocol.MSG_POSITION,
        "v" => Protocol.PROTOCOL_VERSION,
        "fp" => "9f86d081",
        "off" => 1002,
        "p" => { "ts" => 1781049600, "src" => Protocol.SRC_WATCH }
    };
    if (Protocol.validateEnvelope(position) != null) {
        logger.error("valid position rejected"); return false;
    }
    var errorMsg = {
        "t" => Protocol.MSG_ERROR,
        "v" => Protocol.PROTOCOL_VERSION,
        "p" => { "c" => Protocol.ERR_DECODE_FAILURE }
    };
    if (Protocol.validateEnvelope(errorMsg) != null) {
        logger.error("valid error rejected"); return false;
    }

    // Missing required fields → malformedEnvelope (SPEC §3 step 3).
    var bareChunkData = {
        "t" => Protocol.MSG_CHUNK_DATA,
        "v" => Protocol.PROTOCOL_VERSION
    };
    var verdict = Protocol.validateEnvelope(bareChunkData);
    if (verdict == null || !verdict.equals(Protocol.ERR_MALFORMED_ENVELOPE)) {
        logger.error("chunkData without fp/off/n/p accepted"); return false;
    }

    // Unknown top-level key → malformedEnvelope (SPEC §3).
    var extraKey = {
        "t" => Protocol.MSG_CHUNK_REQUEST,
        "v" => Protocol.PROTOCOL_VERSION,
        "fp" => "9f86d081",
        "off" => 1000,
        "n" => 3,
        "x" => 1
    };
    verdict = Protocol.validateEnvelope(extraKey);
    if (verdict == null || !verdict.equals(Protocol.ERR_MALFORMED_ENVELOPE)) {
        logger.error("unknown key accepted"); return false;
    }

    // Malformed fingerprint shape → malformedEnvelope (SPEC §7).
    var badFp = {
        "t" => Protocol.MSG_CHUNK_REQUEST,
        "v" => Protocol.PROTOCOL_VERSION,
        "fp" => "9F86D081",
        "off" => 1000,
        "n" => 3
    };
    verdict = Protocol.validateEnvelope(badFp);
    if (verdict == null || !verdict.equals(Protocol.ERR_MALFORMED_ENVELOPE)) {
        logger.error("uppercase fingerprint accepted"); return false;
    }

    // Non-null value in an unused field → malformedEnvelope (SPEC §3).
    var manifestWithN = {
        "t" => Protocol.MSG_MANIFEST,
        "v" => Protocol.PROTOCOL_VERSION,
        "fp" => "9f86d081",
        "n" => 7,
        "p" => manifest["p"]
    };
    verdict = Protocol.validateEnvelope(manifestWithN);
    if (verdict == null || !verdict.equals(Protocol.ERR_MALFORMED_ENVELOPE)) {
        logger.error("manifest carrying n accepted"); return false;
    }

    // Out-of-range off / n → malformedEnvelope (SPEC §3).
    var negativeOff = {
        "t" => Protocol.MSG_CHUNK_REQUEST,
        "v" => Protocol.PROTOCOL_VERSION,
        "fp" => "9f86d081",
        "off" => -5,
        "n" => 3
    };
    verdict = Protocol.validateEnvelope(negativeOff);
    if (verdict == null || !verdict.equals(Protocol.ERR_MALFORMED_ENVELOPE)) {
        logger.error("off=-5 accepted"); return false;
    }
    var zeroN = {
        "t" => Protocol.MSG_CHUNK_REQUEST,
        "v" => Protocol.PROTOCOL_VERSION,
        "fp" => "9f86d081",
        "off" => 1000,
        "n" => 0
    };
    verdict = Protocol.validateEnvelope(zeroN);
    if (verdict == null || !verdict.equals(Protocol.ERR_MALFORMED_ENVELOPE)) {
        logger.error("n=0 accepted"); return false;
    }

    // Payload structure per SPEC §4: empty ch and wrong-kind ts rejected.
    var emptyChapters = {
        "t" => Protocol.MSG_MANIFEST,
        "v" => Protocol.PROTOCOL_VERSION,
        "fp" => "9f86d081",
        "p" => { "ti" => "Book", "tw" => 50000, "tb" => 412350, "ch" => [] }
    };
    verdict = Protocol.validateEnvelope(emptyChapters);
    if (verdict == null || !verdict.equals(Protocol.ERR_MALFORMED_ENVELOPE)) {
        logger.error("empty ch accepted"); return false;
    }
    var stringTs = {
        "t" => Protocol.MSG_POSITION,
        "v" => Protocol.PROTOCOL_VERSION,
        "fp" => "9f86d081",
        "off" => 1002,
        "p" => { "ts" => "noon", "src" => Protocol.SRC_WATCH }
    };
    verdict = Protocol.validateEnvelope(stringTs);
    if (verdict == null || !verdict.equals(Protocol.ERR_MALFORMED_ENVELOPE)) {
        logger.error("string ts accepted"); return false;
    }
    return true;
}

// ── SPEC §2/§3 envelope validation: unknown version rejected (AC4) ──────────

(:test)
function envelopeUnknownVersionIsRejected(logger as Test.Logger) as Boolean {
    // Valid header per protocol/examples/envelopes.md chunkRequest.
    var valid = {
        "t" => Protocol.MSG_CHUNK_REQUEST,
        "v" => Protocol.PROTOCOL_VERSION,
        "fp" => "9f86d081",
        "off" => 1000,
        "n" => 3
    };
    if (Protocol.validateEnvelope(valid) != null) {
        logger.error("valid envelope rejected"); return false;
    }

    // Unknown version → versionMismatch, never guessed (SPEC §2, AC4).
    var futureVersion = {
        "t" => Protocol.MSG_CHUNK_REQUEST,
        "v" => 2,
        "fp" => "9f86d081",
        "off" => 1000,
        "n" => 3
    };
    var verdict = Protocol.validateEnvelope(futureVersion);
    if (verdict == null || !verdict.equals(Protocol.ERR_VERSION_MISMATCH)) {
        logger.error("v=2 not rejected as versionMismatch"); return false;
    }

    // Missing version is a version failure too (SPEC §3 check order).
    var noVersion = { "t" => Protocol.MSG_CHUNK_REQUEST };
    verdict = Protocol.validateEnvelope(noVersion);
    if (verdict == null || !verdict.equals(Protocol.ERR_VERSION_MISMATCH)) {
        logger.error("missing v not rejected"); return false;
    }

    // Unknown message type → unknownType (SPEC §3).
    var badType = { "t" => "telemetry", "v" => Protocol.PROTOCOL_VERSION };
    verdict = Protocol.validateEnvelope(badType);
    if (verdict == null || !verdict.equals(Protocol.ERR_UNKNOWN_TYPE)) {
        logger.error("unknown type not rejected"); return false;
    }
    return true;
}

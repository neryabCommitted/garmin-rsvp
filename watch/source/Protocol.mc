import Toybox.Lang;

// Mirrored protocol constants — protocol/SPEC.md is the single source of
// truth; the companion mirror is companion/lib/protocol/protocol_keys.dart.
// The two sides never import each other: each is checked against the spec's
// worked examples by its own conformance tests. Never inline one of these
// strings at a call site (architecture AR8).
module Protocol {

    // SPEC §2 — versioning. v1 policy: exact match, reject + report otherwise.
    const PROTOCOL_VERSION = 1;

    // SPEC §3 — envelope keys {t, v, fp, off, n, p}.
    const KEY_TYPE = "t";
    const KEY_VERSION = "v";
    const KEY_FINGERPRINT = "fp";
    const KEY_OFFSET = "off";
    const KEY_COUNT = "n";
    const KEY_PAYLOAD = "p";

    // SPEC §4 — the five message types.
    const MSG_MANIFEST = "manifest";
    const MSG_CHUNK_REQUEST = "chunkRequest";
    const MSG_CHUNK_DATA = "chunkData";
    const MSG_POSITION = "position";
    const MSG_ERROR = "error";

    // SPEC §4.1 — manifest payload keys (`ti` is also the chapter-entry title).
    const KEY_TITLE = "ti";
    const KEY_TOTAL_WORDS = "tw";
    const KEY_TOTAL_BONUS_MS = "tb";
    const KEY_CHAPTERS = "ch";
    const KEY_CHAPTER_OFFSET = "o";
    const KEY_CHAPTER_CUM_BONUS_MS = "cb";

    // SPEC §4.4 — position payload keys and source values.
    const KEY_TIMESTAMP = "ts";
    const KEY_SOURCE = "src";
    const SRC_WATCH = "watch";
    const SRC_PHONE = "phone";

    // SPEC §4.5 — error payload keys.
    const KEY_ERROR_CODE = "c";
    const KEY_ERROR_MESSAGE = "m";

    // SPEC §6 — word-record flag bits.
    const FLAG_SENTENCE_END = 0x01;
    const FLAG_PARAGRAPH_START = 0x02;
    const FLAG_CHAPTER_START = 0x04;
    const FLAG_CONTINUATION = 0x08; // reserved, MUST be 0 in v1
    const FLAG_RTL = 0x10;          // reserved, MUST be 0 in v1
    const FLAGS_RESERVED_MASK = 0xF8;

    // SPEC §5 — fixed bytes before the UTF-8 word in a record.
    const RECORD_HEADER_BYTES = 5;

    // SPEC §7 — fingerprint wire form: exactly 8 lowercase hex chars.
    const FINGERPRINT_LENGTH = 8;

    // SPEC §8 — error codes.
    const ERR_VERSION_MISMATCH = "versionMismatch";
    const ERR_UNKNOWN_TYPE = "unknownType";
    const ERR_MALFORMED_ENVELOPE = "malformedEnvelope";
    const ERR_UNKNOWN_FINGERPRINT = "unknownFingerprint";
    const ERR_RANGE_UNAVAILABLE = "rangeUnavailable";
    const ERR_DECODE_FAILURE = "decodeFailure";
    const ERR_INTERNAL = "internal";

    // SPEC §3 validation order, steps 1–2: version gate first (SPEC §2 — an
    // unknown `v` is rejected before anything else is interpreted), then the
    // message-type gate. Returns null when the envelope header is acceptable,
    // else the SPEC §8 error code the caller MUST surface — never swallow.
    function validateEnvelope(msg as Dictionary) as String? {
        var v = msg[KEY_VERSION];
        if (!(v instanceof Lang.Number) || (v as Number) != PROTOCOL_VERSION) {
            return ERR_VERSION_MISMATCH;
        }
        var t = msg[KEY_TYPE];
        if (!(t instanceof Lang.String)) {
            return ERR_UNKNOWN_TYPE;
        }
        var type = t as String;
        if (!(type.equals(MSG_MANIFEST) || type.equals(MSG_CHUNK_REQUEST)
                || type.equals(MSG_CHUNK_DATA) || type.equals(MSG_POSITION)
                || type.equals(MSG_ERROR))) {
            return ERR_UNKNOWN_TYPE;
        }
        return null;
    }
}

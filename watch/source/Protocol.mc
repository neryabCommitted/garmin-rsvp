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

    // SPEC §3 validation order: version gate first (SPEC §2 — an unknown `v`
    // is rejected before anything else is interpreted), then the message-type
    // gate, then the step-3 structure check — required/unused field matrix,
    // field types and ranges, unknown-key rejection, §7 fingerprint shape,
    // §4 payload structure. Mirrors the companion's decodeEnvelope
    // (companion/lib/protocol/envelope_codec.dart). Returns null when the
    // envelope is acceptable, else the SPEC §8 error code the caller MUST
    // surface — never swallow.
    function validateEnvelope(msg as Dictionary) as String? {
        // SPEC §3 step 1: version.
        var v = msg[KEY_VERSION];
        if (!(v instanceof Lang.Number) || (v as Number) != PROTOCOL_VERSION) {
            return ERR_VERSION_MISMATCH;
        }
        // SPEC §3 step 2: message type.
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
        // SPEC §3 step 3: no unknown top-level keys.
        var keys = msg.keys();
        for (var i = 0; i < keys.size(); i++) {
            var key = keys[i];
            if (!(key instanceof Lang.String)) {
                return ERR_MALFORMED_ENVELOPE;
            }
            var k = key as String;
            if (!(k.equals(KEY_TYPE) || k.equals(KEY_VERSION)
                    || k.equals(KEY_FINGERPRINT) || k.equals(KEY_OFFSET)
                    || k.equals(KEY_COUNT) || k.equals(KEY_PAYLOAD))) {
                return ERR_MALFORMED_ENVELOPE;
            }
        }
        // SPEC §3 step 3: field types and ranges, wherever present.
        var fp = msg[KEY_FINGERPRINT] as Lang.Object?;
        var off = msg[KEY_OFFSET] as Lang.Object?;
        var n = msg[KEY_COUNT] as Lang.Object?;
        var p = msg[KEY_PAYLOAD] as Lang.Object?;
        if (fp != null && !isValidFingerprint(fp)) {
            return ERR_MALFORMED_ENVELOPE; // SPEC §7 wire form
        }
        if (off != null && (!(off instanceof Lang.Number) || (off as Number) < 0)) {
            return ERR_MALFORMED_ENVELOPE; // SPEC §3: off >= 0
        }
        if (n != null && (!(n instanceof Lang.Number) || (n as Number) < 1)) {
            return ERR_MALFORMED_ENVELOPE; // SPEC §3: n >= 1
        }
        // SPEC §3 step 3: the required/unused matrix — required fields
        // non-null, unused ("—") fields null (no implicit extensions, §2) —
        // plus the §4 payload structure for the type.
        if (type.equals(MSG_MANIFEST)) {
            if (fp == null || off != null || n != null
                    || !isValidManifestPayload(p)) {
                return ERR_MALFORMED_ENVELOPE;
            }
        } else if (type.equals(MSG_CHUNK_REQUEST)) {
            if (fp == null || off == null || n == null || p != null) {
                return ERR_MALFORMED_ENVELOPE;
            }
        } else if (type.equals(MSG_CHUNK_DATA)) {
            if (fp == null || off == null || n == null
                    || !(p instanceof Lang.ByteArray)) {
                return ERR_MALFORMED_ENVELOPE;
            }
        } else if (type.equals(MSG_POSITION)) {
            if (fp == null || off == null || n != null
                    || !isValidPositionPayload(p)) {
                return ERR_MALFORMED_ENVELOPE;
            }
        } else { // MSG_ERROR — fp/off optional (SPEC §4.5), n unused
            if (n != null || !isValidErrorPayload(p)) {
                return ERR_MALFORMED_ENVELOPE;
            }
        }
        return null;
    }

    // SPEC §7 — fingerprint wire form: exactly 8 lowercase hex chars.
    function isValidFingerprint(fp as Object?) as Boolean {
        if (!(fp instanceof Lang.String)) {
            return false;
        }
        var bytes = (fp as String).toUtf8Array();
        if (bytes.size() != FINGERPRINT_LENGTH) {
            return false;
        }
        for (var i = 0; i < bytes.size(); i++) {
            var b = bytes[i] as Number;
            if (!((b >= 0x30 && b <= 0x39) || (b >= 0x61 && b <= 0x66))) {
                return false; // not [0-9a-f]
            }
        }
        return true;
    }

    // SPEC §4.1 — manifest payload: ti string, tw/tb numbers, ch a non-empty
    // array of {o: number, ti: string, cb: number}. Value semantics beyond
    // type (ordering, ch[0].o == 0) are the consumer's concern (SPEC §3).
    function isValidManifestPayload(p as Object?) as Boolean {
        if (!(p instanceof Lang.Dictionary)) {
            return false;
        }
        var d = p as Dictionary;
        if (!(d[KEY_TITLE] instanceof Lang.String)
                || !(d[KEY_TOTAL_WORDS] instanceof Lang.Number)
                || !(d[KEY_TOTAL_BONUS_MS] instanceof Lang.Number)) {
            return false;
        }
        var ch = d[KEY_CHAPTERS];
        if (!(ch instanceof Lang.Array)) {
            return false;
        }
        var chapters = ch as Array<Object?>;
        if (chapters.size() < 1) {
            return false;
        }
        for (var i = 0; i < chapters.size(); i++) {
            var entry = chapters[i];
            if (!(entry instanceof Lang.Dictionary)) {
                return false;
            }
            var e = entry as Dictionary;
            if (!(e[KEY_CHAPTER_OFFSET] instanceof Lang.Number)
                    || !(e[KEY_TITLE] instanceof Lang.String)
                    || !(e[KEY_CHAPTER_CUM_BONUS_MS] instanceof Lang.Number)) {
                return false;
            }
        }
        return true;
    }

    // SPEC §4.4 — position payload: {ts: number, src: string}.
    function isValidPositionPayload(p as Object?) as Boolean {
        if (!(p instanceof Lang.Dictionary)) {
            return false;
        }
        var d = p as Dictionary;
        if (!(d[KEY_TIMESTAMP] instanceof Lang.Number)
                || !(d[KEY_SOURCE] instanceof Lang.String)) {
            return false;
        }
        return true;
    }

    // SPEC §4.5 — error payload: {c: string, m: optional string}.
    function isValidErrorPayload(p as Object?) as Boolean {
        if (!(p instanceof Lang.Dictionary)) {
            return false;
        }
        var d = p as Dictionary;
        if (!(d[KEY_ERROR_CODE] instanceof Lang.String)) {
            return false;
        }
        var m = d[KEY_ERROR_MESSAGE];
        if (m != null && !(m instanceof Lang.String)) {
            return false;
        }
        return true;
    }
}

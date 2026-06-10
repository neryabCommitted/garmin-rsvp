import Toybox.Lang;
import Toybox.StringUtil;

// Pure SPEC §5 word-record decoder. Deliberately host-testable: no
// Toybox.WatchUi, no Toybox.Communications — transport wiring is Epic 4.
// Error posture (SPEC §5/§8): bounds-check every read; malformed input
// returns null (a typed decode failure the caller MUST surface as
// Protocol.ERR_DECODE_FAILURE) — never throws past this boundary, never
// guesses fields, never skips bytes.
module StreamDecoder {

    // One decoded SPEC §5 word record.
    class WordRecord {
        public var word as String;       // SPEC §5 — the UTF-8 word
        public var flags as Number;      // SPEC §6 — flag bits
        public var orpPivot as Number;   // SPEC §5 — byte index into the UTF-8 word
        public var bonusMs as Number;    // SPEC §5.1 — WPM-invariant additive dwell bonus

        function initialize(word as String, flags as Number, orpPivot as Number, bonusMs as Number) {
            self.word = word;
            self.flags = flags;
            self.orpPivot = orpPivot;
            self.bonusMs = bonusMs;
        }
    }

    // Decode a chunkData payload of exactly n records (SPEC §4.3): the
    // payload MUST contain n well-formed records and nothing else. Returns
    // the records in stream order, or null if the payload is malformed.
    function decodeChunk(payload as ByteArray, n as Number) as Array<WordRecord>? {
        if (n < 1) {
            return null;
        }
        var records = [] as Array<WordRecord>;
        var pos = 0;
        var size = payload.size();

        for (var i = 0; i < n; i++) {
            if (pos + Protocol.RECORD_HEADER_BYTES > size) {
                return null; // truncated header
            }
            // SPEC §5 fixed header: u8 wordLen · u8 flags · u8 orpPivot · u16le bonusMs.
            var wordLen = (payload.decodeNumber(Lang.NUMBER_FORMAT_UINT8, {:offset => pos}) as Number);
            var flags = (payload.decodeNumber(Lang.NUMBER_FORMAT_UINT8, {:offset => pos + 1}) as Number);
            var orpPivot = (payload.decodeNumber(Lang.NUMBER_FORMAT_UINT8, {:offset => pos + 2}) as Number);
            var bonusMs = (payload.decodeNumber(Lang.NUMBER_FORMAT_UINT16,
                {:offset => pos + 3, :endianness => Lang.ENDIAN_LITTLE}) as Number);

            if (wordLen == 0) {
                return null; // SPEC §5: wordLen is 1–255
            }
            if (orpPivot >= wordLen) {
                return null; // SPEC §5: pivot is a byte index < wordLen
            }
            if ((flags & Protocol.FLAGS_RESERVED_MASK) != 0) {
                return null; // SPEC §6: reserved bits MUST be 0 in v1
            }
            var wordEnd = pos + Protocol.RECORD_HEADER_BYTES + wordLen;
            if (wordEnd > size) {
                return null; // truncated word bytes
            }

            // Invalid UTF-8 is a decode failure, not a crash (SPEC §5).
            // convertEncodedString cannot be trusted with bad input — on
            // SDK 8.4.0 it dies with an UNCATCHABLE system error ("Failed
            // invoking <symbol>") — so the bytes are validated structurally
            // first and conversion only ever sees well-formed UTF-8.
            var wordBytes = payload.slice(pos + Protocol.RECORD_HEADER_BYTES, wordEnd);
            if (!isValidUtf8(wordBytes)) {
                return null;
            }
            var decoded = StringUtil.convertEncodedString(wordBytes, {
                :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
                :toRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
                :encoding => StringUtil.CHAR_ENCODING_UTF8
            });
            if (!(decoded instanceof Lang.String)) {
                return null; // conversion failed despite valid input
            }

            records.add(new WordRecord(decoded as String, flags, orpPivot, bonusMs));
            pos = wordEnd;
        }

        if (pos != size) {
            return null; // SPEC §4.3: decoding must consume the payload exactly
        }
        return records;
    }

    // Structural UTF-8 validation (RFC 3629): correct lead/continuation
    // bytes, no overlongs, no surrogates, max U+10FFFF. Required because
    // StringUtil.convertEncodedString is not safe on malformed input.
    function isValidUtf8(bytes as ByteArray) as Boolean {
        var i = 0;
        var size = bytes.size();
        while (i < size) {
            var b = bytes[i] as Number;
            var len;
            if (b <= 0x7F) {
                len = 1;
            } else if (b >= 0xC2 && b <= 0xDF) {
                len = 2;
            } else if (b >= 0xE0 && b <= 0xEF) {
                len = 3;
            } else if (b >= 0xF0 && b <= 0xF4) {
                len = 4;
            } else {
                return false; // stray continuation byte or invalid lead
            }
            if (i + len > size) {
                return false; // truncated sequence
            }
            for (var j = 1; j < len; j++) {
                var c = bytes[i + j] as Number;
                if (c < 0x80 || c > 0xBF) {
                    return false; // not a continuation byte
                }
            }
            if (len == 3) {
                var c1 = bytes[i + 1] as Number;
                if ((b == 0xE0 && c1 < 0xA0) || (b == 0xED && c1 > 0x9F)) {
                    return false; // overlong / UTF-16 surrogate range
                }
            } else if (len == 4) {
                var c1 = bytes[i + 1] as Number;
                if ((b == 0xF0 && c1 < 0x90) || (b == 0xF4 && c1 > 0x8F)) {
                    return false; // overlong / above U+10FFFF
                }
            }
            i += len;
        }
        return true;
    }
}

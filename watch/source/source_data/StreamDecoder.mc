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

            var word;
            try {
                word = StringUtil.convertEncodedString(
                    payload.slice(pos + Protocol.RECORD_HEADER_BYTES, wordEnd), {
                        :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
                        :toRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
                        :encoding => StringUtil.CHAR_ENCODING_UTF8
                    }) as String;
            } catch (ex) {
                return null; // invalid UTF-8 is a decode failure, not a crash (SPEC §5)
            }

            records.add(new WordRecord(word, flags, orpPivot, bonusMs));
            pos = wordEnd;
        }

        if (pos != size) {
            return null; // SPEC §4.3: decoding must consume the payload exactly
        }
        return records;
    }
}

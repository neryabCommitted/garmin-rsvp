import Toybox.Lang;
import Toybox.StringUtil;
import Toybox.WatchUi;

// Epic-3-ONLY dev word source — the local stand-in for ChunkedWordSource (Epic 4
// / Story 4.1). It is NOT the production source path: it bundles the committed
// companion fixture dev_sample_book.stream (228 SPEC §5 records, fp 4bd588b9) as a
// base64 string resource and decodes it ONCE at startup so PlaybackView has real
// words — real ORP byte pivots (café/naïve), the long word, and chapter flags —
// to render before any transfer exists.
//
// Decode discipline (deferred-work.md#L53, watch-decode-watchdog memo): the whole
// chunk is decoded in initialize() — at startup, OUTSIDE any BLE/timer callback.
// Decoding a full chunk inside a callback trips an uncatchable device watchdog;
// that is an Epic-4 concern, but the discipline is kept here.
//
// This ships in source/ (NOT source-test/): FakeWordSource is the test-only double
// stripped from release builds and cannot feed the running app.
class CannedWordSource extends BookWordSource {

    // The committed fixture's exact record count (manifest tw=228). decodeChunk
    // requires the count up front and consumes the payload exactly.
    private const WORD_COUNT = 228;

    // The dev book's 3 chapters, verbatim from the committed fixture
    // companion/test/fixtures/streams/dev_sample_book.manifest.json (`ch[].o` /
    // `ch[].ti`). Regenerate from that fixture if it changes — same drift contract
    // as WORD_COUNT above (the companion's dev_sample_book_test.dart guards it, and
    // the offsets MUST agree with where FLAG_CHAPTER_START sits in the stream). In
    // Epic 4 ChunkedWordSource builds the same ChapterCatalog from the live manifest.
    private const CHAPTER_OFFSETS = [0, 81, 170];
    private const CHAPTER_TITLES = [
        "I. The Harbor at Dusk",
        "II. A Café and a Question",
        "III. What the Tide Returned"
    ];

    private var _records as Array<StreamDecoder.WordRecord>;
    private var _chapters as ChapterCatalog;

    function initialize() {
        BookWordSource.initialize();
        _records = decode();
        // Built once at startup, beside the stream decode — no per-tick / callback
        // work (the catalog is read on the chapter-card path, in a timer callback).
        _chapters = new ChapterCatalog(
            CHAPTER_OFFSETS as Array<Number>, CHAPTER_TITLES as Array<String>);
    }

    // Base64 string resource -> ByteArray -> decoded records. Any failure degrades
    // to an empty book (wordCount 0) rather than crashing — the engine's empty-book
    // guard then refuses to play and the view draws nothing (NFR8/AR24).
    private function decode() as Array<StreamDecoder.WordRecord> {
        var b64 = WatchUi.loadResource(Rez.Strings.devSampleStream) as String;
        var payload = StringUtil.convertEncodedString(b64, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        });
        if (!(payload instanceof Lang.ByteArray)) {
            return [] as Array<StreamDecoder.WordRecord>;
        }
        var recs = StreamDecoder.decodeChunk(payload as ByteArray, WORD_COUNT);
        if (recs == null) {
            return [] as Array<StreamDecoder.WordRecord>;
        }
        return recs;
    }

    // The TRUE length of the whole book (all records are in memory, so buffer
    // length == book length — atEnd() behaves exactly as against the real source).
    function wordCount() as Number {
        return _records.size();
    }

    function wordAt(index as Number) as StreamDecoder.WordRecord? {
        if (index < 0 || index >= _records.size()) {
            return null; // bounds-check-and-degrade (NFR8/AR24)
        }
        return _records[index];
    }

    function prefetchAround(index as Number) as Void {
        // No-op: the whole canned book is already in memory.
    }

    // The bundled chapter metadata (Story 3.5). Built once in initialize().
    function chapters() as ChapterCatalog {
        return _chapters;
    }
}

import Toybox.Lang;

// Hand-authored BookWordSource test double (Story 3.1). Fully in-memory, so
// wordCount() is always the TRUE book length and atEnd() is exercisable exactly
// as it will be against the real ChunkedWordSource (Story 4.1). It reuses the
// existing StreamDecoder.WordRecord — no new word struct.
//
// `wordAtCalls` counts wordAt() reads so tests can prove that a WPM change does
// NOT re-fetch content (AC3).
class FakeWordSource extends BookWordSource {
    private var _words as Array<StreamDecoder.WordRecord>;
    public var wordAtCalls as Number;

    function initialize(words as Array<StreamDecoder.WordRecord>) {
        BookWordSource.initialize();
        _words = words;
        wordAtCalls = 0;
    }

    function wordCount() as Number {
        return _words.size();
    }

    function wordAt(index as Number) as StreamDecoder.WordRecord? {
        wordAtCalls += 1;
        if (index < 0 || index >= _words.size()) {
            return null;
        }
        return _words[index];
    }

    function prefetchAround(index as Number) as Void {
        // No-op: the whole book is already in memory.
    }
}

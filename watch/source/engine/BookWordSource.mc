import Toybox.Lang;

// The content seam the ReaderEngine sits on top of (AR11, addendum #5) — the
// engine asks for words by ABSOLUTE word index and never owns transfer or
// buffering. Three methods:
//
//   wordCount()          → the TRUE length of the whole book, NOT the buffered
//                          window. This is what makes "end of book" (atEnd)
//                          distinct from "end of buffer" under chunked delivery
//                          (Epic 4) — see the engine's atEnd() / the Story 2.1
//                          carry-forward note.
//   wordAt(index)        → the decoded record at an absolute index, or null if
//                          that index is out of range or not yet buffered.
//   prefetchAround(index)→ a hint that reading is near `index`; a chunked source
//                          uses it to pull neighbouring chunks ahead of time.
//
// This base class is the typed contract. `FakeWordSource` (Story 3.1, tests) and
// `ChunkedWordSource` (Story 4.1) both extend it. The base implementations model
// an empty book so a misconfigured subclass degrades quietly rather than crashing
// (NFR8/AR24); subclasses MUST override all three.
class BookWordSource {

    function initialize() {
    }

    function wordCount() as Number {
        return 0;
    }

    function wordAt(index as Number) as StreamDecoder.WordRecord? {
        return null;
    }

    function prefetchAround(index as Number) as Void {
    }
}

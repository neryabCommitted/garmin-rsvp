/// Library-management service (Story 2.5, AC3). Coordinates the deletion
/// primitives already built in 2.3/2.4 behind the `ui/ → services/ → data/`
/// layering (architecture.md:452): the UI never touches drift/`StreamStore`
/// directly — it calls [removeBook] through `libraryServiceProvider`.
///
/// PURE-ish: depends only on `data/` (`AppDatabase`, `StreamStore`) — **no
/// `package:flutter/*`** here (architecture.md:285). Constructor-injected for
/// tests.
library;

import '../../data/db/database.dart';
import '../../data/stream_store.dart';

/// Not `final`/sealed so widget tests can supply a fake via
/// `libraryServiceProvider.overrideWithValue(...)` without real drift/disk
/// (Story 2.5, Task 5).
class LibraryService {
  /// Constructor-injected (architecture.md:285). Positional `data/` deps mirror
  /// the sibling `ImportService(this._db, this._store, …)`.
  LibraryService(this._db, this._store);

  final AppDatabase _db;
  final StreamStore _store;

  /// Removes [book] entirely: its drift rows (`Books` + cascaded `Chapters`),
  /// its stream file (`<fingerprint>.stream` + sibling `.jsonl`), and its cover
  /// file when set.
  ///
  /// **Order = drift rows first, then files.** Deleting the rows is the
  /// user-visible guarantee ("disappears from the library") — `watchAllBooks`
  /// fires on the row delete. If a later file-delete failed, it would leave only
  /// an orphaned *file* (a benign local-disk leak), never an orphaned *row
  /// pointing at a missing stream* (which would break a later Send-to-watch).
  ///
  /// The file deletes are idempotent (a missing file does not throw), so the
  /// common "already gone" path never errors. An *unexpected* error is **not**
  /// swallowed (no silent `catch {}` — architecture.md:293) — it propagates so
  /// the UI can surface it.
  Future<void> removeBook(Book book) async {
    await _db.deleteBookCascade(book.id);
    await _store.delete(book.streamPath);
    final coverPath = book.coverPath;
    if (coverPath != null) {
      await _store.deleteCover(coverPath);
    }
  }
}

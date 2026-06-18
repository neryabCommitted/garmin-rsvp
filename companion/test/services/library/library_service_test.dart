import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/data/db/database.dart';
import 'package:paceturner_companion/data/stream_store.dart';
import 'package:paceturner_companion/services/library/library_service.dart';

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late StreamStore store;
  late LibraryService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('library_service_test');
    store = StreamStore(tempDir);
    service = LibraryService(db, store);
  });
  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  final bytes = Uint8List.fromList(<int>[1, 2, 3, 4, 250, 0, 99]);
  final coverBytes = Uint8List.fromList(<int>[137, 80, 78, 71, 1, 2, 3]);
  const jsonl = <String>['{"manifest":1}', '{"w":"hi"}'];

  /// Writes a real stream (+jsonl) and inserts a Books row pointing at it, plus
  /// one chapter. Returns the persisted [Book] and its [StoredStream].
  Future<(Book, StoredStream)> seedBook({
    String fingerprint = 'abc12345',
    String? coverPath,
  }) async {
    final stored = await store.write(
      streamBytes: bytes,
      debugJsonl: jsonl,
      fingerprint: fingerprint,
    );
    final id = await db.insertBook(BooksCompanion(
      title: const Value('Doomed'),
      streamPath: Value(stored.streamPath),
      coverPath: Value(coverPath),
      fingerprint: Value(fingerprint),
      totalWords: const Value(100),
      totalBonusMs: const Value(0),
      createdAtEpochS: const Value(1),
    ));
    await db.insertChapters(<ChaptersCompanion>[
      ChaptersCompanion(
        bookId: Value(id),
        chapterIndex: const Value(0),
        title: const Value('Only'),
        wordOffset: const Value(0),
        cumulativeBonusMs: const Value(0),
      ),
    ]);
    final book = (await db.watchBookById(id).first)!;
    return (book, stored);
  }

  test('removeBook deletes rows, stream+jsonl, and the cover (AC3)', () async {
    final coverPath = await store.writeCover(
      bytes: coverBytes,
      fingerprint: 'abc12345',
      format: 'jpg',
    );
    final (book, stored) = await seedBook(coverPath: coverPath);

    await service.removeBook(book);

    // drift rows gone (book disappears from the reactive library list)
    expect(await db.watchAllBooks().first, isEmpty);
    expect(await db.select(db.chapters).get(), isEmpty);
    // files gone
    expect(await File(stored.streamPath).exists(), isFalse);
    expect(await File(stored.jsonlPath).exists(), isFalse);
    expect(await File(coverPath).exists(), isFalse);
  });

  test('removeBook with no cover does not throw (coverPath == null)', () async {
    final (book, stored) = await seedBook();
    expect(book.coverPath, isNull);

    await expectLater(service.removeBook(book), completes);
    expect(await db.watchAllBooks().first, isEmpty);
    expect(await File(stored.streamPath).exists(), isFalse);
  });

  test('removeBook is idempotent when files are already gone', () async {
    final coverPath = await store.writeCover(
      bytes: coverBytes,
      fingerprint: 'abc12345',
      format: 'jpg',
    );
    final (book, stored) = await seedBook(coverPath: coverPath);

    // Delete the files out from under the row before removing.
    await store.delete(stored.streamPath);
    await store.deleteCover(coverPath);

    await expectLater(service.removeBook(book), completes);
    expect(await db.watchAllBooks().first, isEmpty);
  });

  test('round-trip write → insertBook → removeBook deletes the .jsonl sibling '
      '(locks the 2.3-deferred StreamStore.delete contract)', () async {
    final (book, stored) = await seedBook();
    // The Books.streamPath always ends in `<fingerprint>.stream`, so delete()
    // reconstructs the correct `.jsonl` sibling — assert it is gone.
    expect(stored.jsonlPath.endsWith('.jsonl'), isTrue);
    expect(await File(stored.jsonlPath).exists(), isTrue);

    await service.removeBook(book);

    expect(await File(stored.jsonlPath).exists(), isFalse);
  });
}

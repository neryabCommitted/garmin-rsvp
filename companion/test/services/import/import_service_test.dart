import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/data/db/database.dart';
import 'package:paceturner_companion/data/stream_store.dart';
import 'package:paceturner_companion/services/import/import_service.dart';
import 'package:paceturner_companion/services/import/pipeline.dart';

import '../../fixtures/epubs/epub_fixture_builder.dart';

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late StreamStore store;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('import_service_test');
    store = StreamStore(tempDir);
  });
  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // Synchronous runners (no isolate) + fixed salt → deterministic fingerprints.
  ImportService make({AppDatabase? database}) => ImportService(
        database ?? db,
        store,
        runner: (entry, req) async => entry(req),
        epubRunner: (entry, req) => entry(req),
        saltSource: () => 42,
      );

  Future<int> streamFileCount() async {
    final dir = Directory('${tempDir.path}${Platform.pathSeparator}streams');
    if (!await dir.exists()) return 0;
    return dir.listSync().whereType<File>().length;
  }

  Future<int> coverFileCount() async {
    final dir = Directory('${tempDir.path}${Platform.pathSeparator}covers');
    if (!await dir.exists()) return 0;
    return dir.listSync().whereType<File>().length;
  }

  test('small .txt → ImportSuccess with one Books row and one Chapters row',
      () async {
    const text = 'The quick brown fox. Jumps over the lazy dog.';
    final result = await make().importFile(
      path: '/downloads/My Book.txt',
      bytes: utf8.encode(text),
    );

    expect(result, isA<ImportSuccess>());

    final books = await db.watchAllBooks().first;
    expect(books.length, 1);
    final book = books.single;
    expect(book.title, 'My Book'); // filename-derived, extension stripped
    expect(book.author, isNull);
    expect(book.coverPath, isNull);
    expect(book.lastReadEpochS, isNull);

    // Fingerprint/words match the pure pipeline with the same salt.
    final expected = runPipeline(const PipelineRequest(
      rawText: text,
      isMarkdown: false,
      title: 'My Book',
      salt: 42,
    ));
    expect(book.fingerprint, expected.manifest.fingerprint);
    expect(book.totalWords, expected.manifest.totalWords);
    expect(book.totalBonusMs, expected.manifest.totalBonusMs);

    expect(await File(book.streamPath).exists(), isTrue);

    final chapters = await db.select(db.chapters).get();
    expect(chapters.length, 1);
    expect(chapters.single.wordOffset, 0);
    expect(chapters.single.chapterIndex, 0);
  });

  test('.md import preserves paragraph structure', () async {
    const md = 'First paragraph here.\n\nSecond paragraph begins now.';
    final result = await make().importFile(
      path: '/x/notes.md',
      bytes: utf8.encode(md),
    );
    expect(result, isA<ImportSuccess>());

    final book = (await db.watchAllBooks().first).single;
    final expected = runPipeline(const PipelineRequest(
      rawText: md,
      isMarkdown: true,
      title: 'notes',
      salt: 42,
    ));
    expect(book.totalWords, expected.manifest.totalWords);
    expect(book.fingerprint, expected.manifest.fingerprint);
  });

  test('.markdown extension is also treated as markdown', () async {
    final result = await make().importFile(
      path: '/x/doc.markdown',
      bytes: utf8.encode('Alpha.\n\nBeta.'),
    );
    expect(result, isA<ImportSuccess>());
  });

  test('empty file → ImportFailure(emptyContent), no rows, no stream file',
      () async {
    final result = await make().importFile(
      path: '/x/empty.txt',
      bytes: const <int>[],
    );

    expect(result, isA<ImportFailure>());
    expect((result as ImportFailure).reason, ImportFailureReason.emptyContent);
    expect(result.filename, 'empty.txt');

    expect(await db.watchAllBooks().first, isEmpty);
    expect(await db.select(db.chapters).get(), isEmpty);
    expect(await streamFileCount(), 0);
  });

  test('whitespace-only file → ImportFailure(emptyContent), no partial state',
      () async {
    final result = await make().importFile(
      path: '/x/blank.txt',
      bytes: utf8.encode('   \n\n  \t'),
    );
    expect((result as ImportFailure).reason, ImportFailureReason.emptyContent);
    expect(await db.watchAllBooks().first, isEmpty);
    expect(await streamFileCount(), 0);
  });

  test('drift failure rolls back the already-written stream file (AC7)',
      () async {
    // The stream gets written, then the drift insert throws.
    final throwingDb = _ThrowingInsertDb();
    addTearDown(throwingDb.close);

    final result = await make(database: throwingDb).importFile(
      path: '/x/Good Text.txt',
      bytes: utf8.encode('Some perfectly valid text here.'),
    );

    expect(result, isA<ImportFailure>());
    expect((result as ImportFailure).reason, ImportFailureReason.ioError);
    // No orphaned stream file left behind.
    expect(await streamFileCount(), 0);
  });

  group('.epub import (Story 2.4)', () {
    test('clean fixture → success: Books row w/ author + cover_path + N chapters',
        () async {
      final result = await make().importFile(
        path: '/downloads/My EPUB.epub',
        bytes: cleanThreeChapterEpub(),
      );
      expect(result, isA<ImportSuccess>());

      final book = (await db.watchAllBooks().first).single;
      expect(book.title, 'A Clean Book'); // OPF title, not the filename
      expect(book.author, 'Ada Author');
      expect(book.coverPath, isNotNull);
      expect(book.fingerprint, matches(RegExp(r'^[0-9a-f]{8}$')));
      expect(book.totalWords, greaterThan(0));

      // Stream + cover files present.
      expect(await File(book.streamPath).exists(), isTrue);
      expect(await File(book.coverPath!).exists(), isTrue);
      expect(await streamFileCount(), 2); // .stream + .jsonl
      expect(await coverFileCount(), 1);

      // One Chapters row per manifest chapter, in order, offsets ascending.
      final chapters = await db.select(db.chapters).get()
        ..sort((a, b) => a.chapterIndex.compareTo(b.chapterIndex));
      expect(chapters.length, 3);
      expect(chapters.map((c) => c.chapterIndex), [0, 1, 2]);
      expect(chapters.first.wordOffset, 0);
      expect(chapters[1].wordOffset, greaterThan(0));
      expect(chapters.map((c) => c.title),
          ['Chapter One', 'Chapter Two', 'Chapter Three']);
    });

    test('no-cover fixture → success, cover_path null, no cover file', () async {
      final result = await make().importFile(
        path: '/x/plain.epub',
        bytes: noCoverEpub(),
      );
      expect(result, isA<ImportSuccess>());

      final book = (await db.watchAllBooks().first).single;
      expect(book.coverPath, isNull);
      expect(await coverFileCount(), 0);
      expect(await streamFileCount(), 2); // .stream + .jsonl, no cover
    });

    test('corrupt fixture → ImportFailure(unreadable), zero rows, no files',
        () async {
      final result = await make().importFile(
        path: '/x/broken.epub',
        bytes: corruptEpubBytes(),
      );
      expect((result as ImportFailure).reason, ImportFailureReason.unreadable);
      expect(await db.watchAllBooks().first, isEmpty);
      expect(await db.select(db.chapters).get(), isEmpty);
      expect(await streamFileCount(), 0);
      expect(await coverFileCount(), 0);
    });

    test('empty-spine fixture → ImportFailure(emptyContent), no partial state',
        () async {
      final result = await make().importFile(
        path: '/x/hollow.epub',
        bytes: emptySpineEpub(),
      );
      expect((result as ImportFailure).reason, ImportFailureReason.emptyContent);
      expect(await db.watchAllBooks().first, isEmpty);
      expect(await streamFileCount(), 0);
      expect(await coverFileCount(), 0);
    });

    test('drift failure rolls back BOTH stream and cover (AC5)', () async {
      final throwingDb = _ThrowingInsertDb();
      addTearDown(throwingDb.close);

      final result = await make(database: throwingDb).importFile(
        path: '/x/good.epub',
        bytes: cleanThreeChapterEpub(),
      );
      expect((result as ImportFailure).reason, ImportFailureReason.ioError);
      expect(await streamFileCount(), 0);
      expect(await coverFileCount(), 0);
    });
  });
}

/// An [AppDatabase] whose book insert always throws, to exercise the AC7
/// stream-written-but-drift-failed rollback path.
class _ThrowingInsertDb extends AppDatabase {
  _ThrowingInsertDb() : super(NativeDatabase.memory());

  @override
  Future<int> insertBook(BooksCompanion book) =>
      Future<int>.error(StateError('insert failed'));
}

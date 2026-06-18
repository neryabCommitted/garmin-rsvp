import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/data/db/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  BooksCompanion book(String title, {required int createdAt}) => BooksCompanion(
        title: Value(title),
        streamPath: Value('/streams/$title.stream'),
        fingerprint: Value('deadbeef'),
        totalWords: const Value(100),
        totalBonusMs: const Value(0),
        createdAtEpochS: Value(createdAt),
      );

  test('only Books and Chapters tables exist (AC5 — no Positions)', () {
    final names = db.allTables.map((t) => t.actualTableName).toSet();
    expect(names, <String>{'books', 'chapters'});
  });

  test('insertBook then watchAllBooks emits the row', () async {
    final id = await db.insertBook(book('Alpha', createdAt: 1));
    expect(id, isPositive);

    final rows = await db.watchAllBooks().first;
    expect(rows.length, 1);
    expect(rows.single.title, 'Alpha');
    expect(rows.single.author, isNull); // null for txt/md
    expect(rows.single.coverPath, isNull); // null until 2.4
    expect(rows.single.lastReadEpochS, isNull); // AC2 placeholder
  });

  test('watchAllBooks orders by createdAtEpochS descending', () async {
    await db.insertBook(book('Older', createdAt: 10));
    await db.insertBook(book('Newer', createdAt: 20));

    final rows = await db.watchAllBooks().first;
    expect(rows.map((b) => b.title).toList(), <String>['Newer', 'Older']);
  });

  test('watchAllBooks is reactive — emits again after an insert', () async {
    final emissions = <int>[];
    final sub = db.watchAllBooks().listen((rows) => emissions.add(rows.length));

    await db.insertBook(book('One', createdAt: 1));
    await db.insertBook(book('Two', createdAt: 2));
    await pumpEventQueue();
    await sub.cancel();

    expect(emissions.last, 2);
    expect(emissions.length, greaterThan(1));
  });

  test('insertChapters persists chapter rows for a book', () async {
    final bookId = await db.insertBook(book('WithChapters', createdAt: 1));
    await db.insertChapters(<ChaptersCompanion>[
      ChaptersCompanion(
        bookId: Value(bookId),
        chapterIndex: const Value(0),
        title: const Value('Chapter 1'),
        wordOffset: const Value(0),
        cumulativeBonusMs: const Value(0),
      ),
    ]);

    final chapters = await db.select(db.chapters).get();
    expect(chapters.length, 1);
    expect(chapters.single.bookId, bookId);
    expect(chapters.single.wordOffset, 0);
  });

  test('deleteBookCascade removes the book and its chapters (AC7 rollback)',
      () async {
    final bookId = await db.insertBook(book('Doomed', createdAt: 1));
    await db.insertChapters(<ChaptersCompanion>[
      ChaptersCompanion(
        bookId: Value(bookId),
        chapterIndex: const Value(0),
        title: const Value('Only'),
        wordOffset: const Value(0),
        cumulativeBonusMs: const Value(0),
      ),
    ]);

    await db.deleteBookCascade(bookId);

    expect(await db.watchAllBooks().first, isEmpty);
    expect(await db.select(db.chapters).get(), isEmpty);
  });

  group('watchBookById (Story 2.5, AC1)', () {
    test('emits the book then null after deleteBookCascade', () async {
      final bookId = await db.insertBook(book('Detail', createdAt: 1));

      expect((await db.watchBookById(bookId).first)?.title, 'Detail');

      // The detail screen relies on a null emission to pop on Remove (Task 5).
      final emissions = <Book?>[];
      final sub = db.watchBookById(bookId).listen(emissions.add);
      await db.deleteBookCascade(bookId);
      await pumpEventQueue();
      await sub.cancel();

      expect(emissions.first?.title, 'Detail');
      expect(emissions.last, isNull);
    });

    test('emits null for an unknown id', () async {
      expect(await db.watchBookById(999).first, isNull);
    });
  });

  group('chaptersForBook (Story 2.5, AC1)', () {
    ChaptersCompanion chapter(int bookId, int index, String title) =>
        ChaptersCompanion(
          bookId: Value(bookId),
          chapterIndex: Value(index),
          title: Value(title),
          wordOffset: Value(index * 100),
          cumulativeBonusMs: const Value(0),
        );

    test('emits the chapters in chapterIndex order', () async {
      final bookId = await db.insertBook(book('Multi', createdAt: 1));
      // Insert out of order to prove the orderBy, not insertion order.
      await db.insertChapters(<ChaptersCompanion>[
        chapter(bookId, 2, 'Third'),
        chapter(bookId, 0, 'First'),
        chapter(bookId, 1, 'Second'),
      ]);

      final rows = await db.chaptersForBook(bookId).first;
      expect(rows.map((c) => c.title).toList(),
          <String>['First', 'Second', 'Third']);
    });

    test('emits an empty list for a book with no chapters', () async {
      final bookId = await db.insertBook(book('Bare', createdAt: 1));
      expect(await db.chaptersForBook(bookId).first, isEmpty);
    });

    test('scopes chapters to the requested book', () async {
      final a = await db.insertBook(book('A', createdAt: 1));
      final b = await db.insertBook(book('B', createdAt: 2));
      await db.insertChapters(<ChaptersCompanion>[
        chapter(a, 0, 'A-ch'),
        chapter(b, 0, 'B-ch'),
      ]);

      final rows = await db.chaptersForBook(a).first;
      expect(rows.map((c) => c.title).toList(), <String>['A-ch']);
    });
  });
}

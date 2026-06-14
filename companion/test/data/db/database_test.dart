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
}

/// The companion's local metadata store (Story 2.3, AC5). drift owns the
/// **Books** and **Chapters** rows; the bulk word-stream bytes live as flat
/// files (`stream_store.dart`), referenced by `Books.streamPath`
/// (architecture.md:177,453 — never put multi-MB blobs in SQLite).
///
/// **Exactly two tables** land here (AC5). `Positions`/progress/sync is Epic 4
/// (Story 4.5); adding a position column now would violate AC5. The AC2 "0%
/// progress bar" and the last-read subtitle are **UI placeholders** until then.
///
/// Connection: the stable native setup (`LazyDatabase` +
/// `NativeDatabase.createInBackground`) over `path_provider`'s app-support dir —
/// chosen over the `drift_flutter ^0.3.1-wip` pre-release (Task 0 decision). The
/// constructor accepts an injected [QueryExecutor] so tests pass
/// `NativeDatabase.memory()` without the platform channel.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// Book metadata. Columns are `snake_case` in SQL (architecture.md:254); the
/// Dart accessors stay camelCase.
class Books extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();

  /// Null for txt/md (Story 2.3); 2.4 fills it from the EPUB OPF.
  TextColumn get author => text().nullable()();

  /// Null here; 2.4 sets it when it extracts a cover.
  TextColumn get coverPath => text().named('cover_path').nullable()();

  /// Path to the flat-file word stream (`stream_store`).
  TextColumn get streamPath => text().named('stream_path')();
  TextColumn get fingerprint => text()();
  IntColumn get totalWords => integer().named('total_words')();
  IntColumn get totalBonusMs => integer().named('total_bonus_ms')();
  IntColumn get createdAtEpochS => integer().named('created_at_epoch_s')();

  /// AC2 last-read placeholder; stays null until Epic 4 wires reading progress.
  IntColumn get lastReadEpochS =>
      integer().named('last_read_epoch_s').nullable()();
}

/// Chapter rows — one per `BookManifest.chapters` entry (txt/md = exactly one).
class Chapters extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId => integer().named('book_id').references(Books, #id)();
  IntColumn get chapterIndex => integer().named('chapter_index')();
  TextColumn get title => text()();

  /// Absolute first-word index — mirrors `ChapterEntry.offset`.
  IntColumn get wordOffset => integer().named('word_offset')();
  IntColumn get cumulativeBonusMs =>
      integer().named('cumulative_bonus_ms')();
}

@DriftDatabase(tables: <Type>[Books, Chapters])
class AppDatabase extends _$AppDatabase {
  /// Inject the executor (tests pass `NativeDatabase.memory()`).
  AppDatabase(super.executor);

  /// The on-device connection: a lazily-opened native SQLite file in the app
  /// support dir.
  AppDatabase.open() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  /// Reactive list for the library (FR16-ready), newest first.
  Stream<List<Book>> watchAllBooks() => (select(books)
        ..orderBy(<OrderingTerm Function($BooksTable)>[
          (b) => OrderingTerm.desc(b.createdAtEpochS),
        ]))
      .watch();

  Future<int> insertBook(BooksCompanion book) => into(books).insert(book);

  Future<void> insertChapters(List<ChaptersCompanion> rows) =>
      batch((b) => b.insertAll(chapters, rows));

  /// Removes a book and its chapters in one transaction (AC7 rollback; backs
  /// 2.5 Remove). Chapters are deleted first since FK enforcement is off by
  /// default.
  Future<void> deleteBookCascade(int id) => transaction(() async {
        await (delete(chapters)..where((c) => c.bookId.equals(id))).go();
        await (delete(books)..where((b) => b.id.equals(id))).go();
      });
}

LazyDatabase _openConnection() => LazyDatabase(() async {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/paceturner.sqlite');
      return NativeDatabase.createInBackground(file);
    });

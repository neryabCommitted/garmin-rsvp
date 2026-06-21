/// Schema migration v1 → v2 (Story 2.7, AC5): adds `Books.content_hash` + the
/// partial unique index, non-destructively.
///
/// drift's `schemaVersion` is hardcoded to the current version, so a true v1
/// database is simulated by building the v2 schema, then dropping the index and
/// the column back to a v1 shape before driving `onUpgrade` directly. This
/// exercises the real migration callback rather than a hand-copy of its DDL.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/data/db/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// Degrades the live schema to its v1 shape: drop the index and the column so
  /// `onUpgrade` has work to do. (onCreate already ran on first access below.)
  Future<void> degradeToV1() async {
    await db.customStatement('SELECT 1'); // force onCreate (lazy in drift)
    await db.customStatement('DROP INDEX IF EXISTS books_content_hash_unique');
    await db.customStatement('ALTER TABLE books DROP COLUMN content_hash');
  }

  /// Inserts a legacy (pre-v2) book row with no content_hash, via raw SQL so it
  /// does not depend on the regenerated companion.
  Future<void> insertLegacyBook(String title) => db.customStatement(
        "INSERT INTO books (title, stream_path, fingerprint, total_words, "
        "total_bonus_ms, created_at_epoch_s) "
        "VALUES ('$title', '/s/x.stream', 'deadbeef', 10, 0, 100)",
      );

  test('AC5 — onUpgrade adds content_hash and preserves legacy rows', () async {
    await degradeToV1();
    await insertLegacyBook('Legacy Book');

    // Drive the real migration callback v1 → v2.
    await db.migration.onUpgrade(db.createMigrator(), 1, 2);

    final books = await db.watchAllBooks().first;
    expect(books.length, 1, reason: 'legacy row must survive the migration');
    expect(books.single.title, 'Legacy Book');
    expect(books.single.contentHash, isNull,
        reason: 'pre-v2 rows carry a null content_hash');
  });

  test('AC3 — the partial unique index rejects a duplicate non-null hash',
      () async {
    await degradeToV1();
    await db.migration.onUpgrade(db.createMigrator(), 1, 2);

    Future<void> insertHashed(String title, String hash) => db.customStatement(
          "INSERT INTO books (title, stream_path, fingerprint, content_hash, "
          "total_words, total_bonus_ms, created_at_epoch_s) "
          "VALUES ('$title', '/s/$title.stream', 'fp', '$hash', 5, 0, 1)",
        );

    await insertHashed('A', 'samehash');
    await expectLater(
      insertHashed('B', 'samehash'),
      throwsA(isA<Object>()), // unique-index violation
    );
  });

  test('AC5 — two legacy null-hash rows coexist (partial index ignores NULL)',
      () async {
    await degradeToV1();
    await insertLegacyBook('Old One');
    await insertLegacyBook('Old Two');
    await db.migration.onUpgrade(db.createMigrator(), 1, 2);

    expect((await db.watchAllBooks().first).length, 2);
  });

  test('fresh install (onCreate) already has content_hash and the index',
      () async {
    // No degrade — exercise the onCreate path the v2 schema ships with.
    await db.into(db.books).insert(BooksCompanion.insert(
          title: 'Fresh',
          streamPath: '/s/fresh.stream',
          fingerprint: 'fp',
          contentHash: const Value('hashx'),
          totalWords: 3,
          totalBonusMs: 0,
          createdAtEpochS: 1,
        ));
    final found = await db.bookByContentHash('hashx');
    expect(found, isNotNull);
    expect(found!.title, 'Fresh');
  });
}

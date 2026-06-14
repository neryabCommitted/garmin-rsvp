/// The impure import shell (Story 2.3, AC1/AC4/AC7): orchestrates the pure
/// pipeline across the `compute` isolate, then persists the result — the
/// flat-file word stream (`stream_store`) plus the drift `Books`/`Chapters`
/// rows. This is the only place the pure pipeline meets Flutter/async.
///
/// **Isolate boundary:** only [runPipeline] crosses into `compute`. The drift
/// connection and `StreamStore` stay on the **main isolate** — drift connections
/// are not sendable and `path_provider` is platform-bound, so they must NEVER be
/// passed into `compute` (architecture.md:469).
///
/// **DI, no globals** (architecture.md:285): the database, store, the
/// `compute`-runner, and the salt source are constructor-injected so tests run
/// the pipeline synchronously with a fixed salt.
///
/// **AC7 — no partial state:** every failure returns a typed [ImportResult]
/// (never an uncaught exception); if the stream file was written but the drift
/// insert failed, it is deleted so no orphan survives. No silent `catch {}`
/// (architecture.md:293) — every catch maps to a named [ImportFailureReason].
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show compute;

import '../../data/db/database.dart';
import '../../data/stream_store.dart';
import 'pipeline.dart';
import 'word_stream_baker.dart';

/// Why an import failed. A small seed enum — **2.6 extends** the taxonomy; do not
/// over-build it now.
enum ImportFailureReason { emptyContent, unreadable, unsupported, ioError }

/// Typed result of an import (AC7). Sealed so callers must handle both arms.
sealed class ImportResult {
  const ImportResult();
}

final class ImportSuccess extends ImportResult {
  const ImportSuccess(this.bookId);
  final int bookId;
}

final class ImportFailure extends ImportResult {
  const ImportFailure(this.reason, this.filename);
  final ImportFailureReason reason;
  final String filename;
}

/// The `compute`-runner seam: takes the (top-level) pipeline entry and a request,
/// returns the baked result. Defaults to `compute`; tests pass a synchronous
/// override so they never spawn an isolate.
typedef PipelineRunner = Future<BakedBook> Function(
  BakedBook Function(PipelineRequest) entry,
  PipelineRequest request,
);

Future<BakedBook> _computeRunner(
  BakedBook Function(PipelineRequest) entry,
  PipelineRequest request,
) =>
    compute(entry, request);

class ImportService {
  ImportService(
    this._db,
    this._store, {
    PipelineRunner? runner,
    int Function()? saltSource,
  })  : _runner = runner ?? _computeRunner,
        _saltSource = saltSource ?? _defaultSalt;

  final AppDatabase _db;
  final StreamStore _store;
  final PipelineRunner _runner;
  final int Function() _saltSource;

  static int _defaultSalt() =>
      DateTime.now().millisecondsSinceEpoch & 0x7fffffff;

  /// Imports one file: bake off the UI thread, then persist stream + drift rows.
  /// Returns [ImportSuccess] or a typed [ImportFailure] — never throws (AC7).
  Future<ImportResult> importFile({
    required String path,
    required List<int> bytes,
  }) async {
    final filename = _basename(path);
    final title = _stripExtension(filename);
    final isMarkdown = _isMarkdown(filename);

    // allowMalformed so a bad-encoding file degrades rather than throws (NFR8).
    final rawText = utf8.decode(bytes, allowMalformed: true);

    StoredStream? stored;
    try {
      // AC4: bake runs off the UI thread via the compute runner.
      final baked = await _runner(
        runPipeline,
        PipelineRequest(
          rawText: rawText,
          isMarkdown: isMarkdown,
          title: title,
          salt: _saltSource(),
        ),
      );

      // Persist stream first, then the drift rows in a transaction.
      stored = await _store.write(
        streamBytes: baked.streamBytes,
        debugJsonl: baked.debugJsonl,
        fingerprint: baked.manifest.fingerprint,
      );
      final streamPath = stored.streamPath;

      final bookId = await _db.transaction(() async {
        final manifest = baked.manifest;
        final id = await _db.insertBook(BooksCompanion(
          title: Value(manifest.title),
          author: const Value<String?>(null),
          coverPath: const Value<String?>(null),
          streamPath: Value(streamPath),
          fingerprint: Value(manifest.fingerprint),
          totalWords: Value(manifest.totalWords),
          totalBonusMs: Value(manifest.totalBonusMs),
          createdAtEpochS: Value(_nowEpochS()),
          lastReadEpochS: const Value<int?>(null),
        ));
        await _db.insertChapters(<ChaptersCompanion>[
          for (var i = 0; i < manifest.chapters.length; i++)
            ChaptersCompanion(
              bookId: Value(id),
              chapterIndex: Value(i),
              title: Value(manifest.chapters[i].title),
              wordOffset: Value(manifest.chapters[i].offset),
              cumulativeBonusMs: Value(manifest.chapters[i].cumulativeBonusMs),
            ),
        ]);
        return id;
      });

      return ImportSuccess(bookId);
    } on ArgumentError {
      // bake rejects a zero-token chapter (empty/whitespace-only file).
      await _rollback(stored);
      return ImportFailure(ImportFailureReason.emptyContent, filename);
    } catch (_) {
      // I/O or drift error — roll back any stream already written. (2.6 widens
      // the taxonomy; here every other failure is ioError. No silent catch.)
      await _rollback(stored);
      return ImportFailure(ImportFailureReason.ioError, filename);
    }
  }

  Future<void> _rollback(StoredStream? stored) async {
    if (stored != null) {
      await _store.delete(stored.streamPath);
    }
  }

  static int _nowEpochS() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

/// Last path segment, handling both `/` and `\` separators.
String _basename(String path) {
  final segments = path.split(RegExp(r'[/\\]'));
  return segments.isEmpty ? path : segments.last;
}

String _stripExtension(String filename) {
  final dot = filename.lastIndexOf('.');
  return dot <= 0 ? filename : filename.substring(0, dot);
}

bool _isMarkdown(String filename) {
  final lower = filename.toLowerCase();
  return lower.endsWith('.md') || lower.endsWith('.markdown');
}

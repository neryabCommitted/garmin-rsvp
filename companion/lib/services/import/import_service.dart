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
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show compute;

import '../../data/db/database.dart';
import '../../data/stream_store.dart';
import 'epub_extractor.dart';
import 'import_exceptions.dart';
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

/// The file's bytes are already in the library (Story 2.7 dedup). NOT an
/// [ImportFailure] — nothing went wrong; the librarian just already has this
/// exact file. Carries the [existingBookId] so the UI could surface/route to it.
final class ImportDuplicate extends ImportResult {
  const ImportDuplicate(this.existingBookId, this.filename);
  final int existingBookId;
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

/// The `compute`-runner seam for the EPUB path (mirrors [PipelineRunner]). The
/// entry is async because `EpubReader.readBook` is async; tests pass a
/// synchronous override so they never spawn an isolate.
typedef EpubPipelineRunner = Future<EpubBaked> Function(
  Future<EpubBaked> Function(EpubPipelineRequest) entry,
  EpubPipelineRequest request,
);

Future<EpubBaked> _computeEpubRunner(
  Future<EpubBaked> Function(EpubPipelineRequest) entry,
  EpubPipelineRequest request,
) =>
    compute(entry, request);

class ImportService {
  ImportService(
    this._db,
    this._store, {
    PipelineRunner? runner,
    EpubPipelineRunner? epubRunner,
    int Function()? saltSource,
  })  : _runner = runner ?? _computeRunner,
        _epubRunner = epubRunner ?? _computeEpubRunner,
        _saltSource = saltSource ?? _defaultSalt;

  final AppDatabase _db;
  final StreamStore _store;
  final PipelineRunner _runner;
  final EpubPipelineRunner _epubRunner;
  final int Function() _saltSource;

  static int _defaultSalt() =>
      DateTime.now().millisecondsSinceEpoch & 0x7fffffff;

  /// Imports one file: bake off the UI thread, then persist stream + drift rows.
  /// Returns [ImportSuccess], [ImportDuplicate], or a typed [ImportFailure] —
  /// never throws (AC7). Dispatches `.epub` to [_importEpub]; everything else
  /// takes the txt/md path.
  ///
  /// Re-import dedup (Story 2.7): a SHA-256 of the raw [bytes] is the content
  /// identity. It is computed **before** the time-derived stream salt and checked
  /// against the library; an exact match short-circuits to [ImportDuplicate]
  /// before anything is baked or written (no partial state). The same hash is
  /// persisted on the new row so future re-imports dedup too.
  Future<ImportResult> importFile({
    required String path,
    required List<int> bytes,
  }) async {
    final filename = _basename(path);
    final contentHash = _contentHash(bytes);

    // Pre-check: an exact-bytes match is already shelved — stop before baking.
    final existing = await _db.bookByContentHash(contentHash);
    if (existing != null) {
      return ImportDuplicate(existing.id, filename);
    }

    if (_isEpub(filename)) {
      return _importEpub(filename, bytes, contentHash);
    }
    return _importText(filename, bytes, contentHash);
  }

  /// SHA-256 (lowercase hex) of the raw source bytes — the dedup identity key.
  static String _contentHash(List<int> bytes) => sha256.convert(bytes).toString();

  Future<ImportResult> _importText(
    String filename,
    List<int> bytes,
    String contentHash,
  ) async {
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
          contentHash: Value(contentHash),
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
    } on TextEmptyContentException {
      // Zero tokens (empty/whitespace/all-punctuation) — typed by the pipeline
      // before bake, so a non-empty file is never mislabeled "empty".
      await _rollback(stored);
      return ImportFailure(ImportFailureReason.emptyContent, filename);
    } on UnencodableContentException {
      // A non-empty file whose token the wire can't carry (>255 bytes / unpaired
      // surrogate) → unsupported, NOT emptyContent (deferred-work 2.3, line 7).
      await _rollback(stored);
      return ImportFailure(ImportFailureReason.unsupported, filename);
    } catch (_) {
      // I/O or drift error — roll back any stream already written. A lost dedup
      // race (the partial unique index rejected a concurrent duplicate insert)
      // surfaces here too; re-resolve it to ImportDuplicate rather than ioError.
      await _rollback(stored);
      return _ioErrorOrDuplicate(filename, contentHash);
    }
  }

  /// The `.epub` path (AC1·AC2·AC3·AC5): parse + bake off the UI thread, then
  /// persist the stream, the phone-only cover file, and the drift rows (Books +
  /// one Chapters row per manifest chapter). Never throws — every failure maps
  /// to a typed [ImportFailure], rolling back the stream AND cover together
  /// (AC5 no-partial-state).
  Future<ImportResult> _importEpub(
    String filename,
    List<int> bytes,
    String contentHash,
  ) async {
    // Parse + bake in the isolate. The EPUB is a ZIP — NEVER utf8.decode it.
    final EpubBaked epubBaked;
    try {
      epubBaked = await _epubRunner(
        runEpubPipeline,
        EpubPipelineRequest(
          epubBytes: Uint8List.fromList(bytes),
          salt: _saltSource(),
        ),
      );
    } on EpubEmptyContentException {
      // No tokens (empty spine / nav-only / all-symbol). Nothing written yet.
      return ImportFailure(ImportFailureReason.emptyContent, filename);
    } on EpubEncryptedException {
      // Structural DRM signal (META-INF/encryption.xml). Nothing written yet.
      return ImportFailure(ImportFailureReason.unsupported, filename);
    } on UnencodableContentException {
      // A chapter word the SPEC §5 wire can't carry (e.g. a >255-byte token).
      return ImportFailure(ImportFailureReason.unsupported, filename);
    } catch (_) {
      // Anything else epub_pro throws — not-a-zip, missing/invalid OPF,
      // malformed structure → unreadable. Nothing written yet, so no rollback.
      return ImportFailure(ImportFailureReason.unreadable, filename);
    }

    // Persist on the main isolate: stream → cover → drift rows. Any failure here
    // is I/O-class; roll back the stream and cover before returning (AC5).
    StoredStream? stored;
    String? coverPath;
    try {
      final baked = epubBaked.baked;
      final manifest = baked.manifest;

      stored = await _store.write(
        streamBytes: baked.streamBytes,
        debugJsonl: baked.debugJsonl,
        fingerprint: manifest.fingerprint,
      );

      if (epubBaked.coverBytes != null) {
        coverPath = await _store.writeCover(
          bytes: epubBaked.coverBytes!,
          fingerprint: manifest.fingerprint,
          format: epubBaked.coverFormat ?? 'jpg',
        );
      }

      final streamPath = stored.streamPath;
      final bookId = await _db.transaction(() async {
        final id = await _db.insertBook(BooksCompanion(
          title: Value(manifest.title),
          author: Value<String?>(epubBaked.author),
          coverPath: Value<String?>(coverPath),
          streamPath: Value(streamPath),
          fingerprint: Value(manifest.fingerprint),
          contentHash: Value(contentHash),
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
    } catch (_) {
      // I/O-class failure; roll back stream + cover. A lost dedup race re-resolves
      // to ImportDuplicate rather than ioError (see [_importText]).
      await _rollbackEpub(stored, coverPath);
      return _ioErrorOrDuplicate(filename, contentHash);
    }
  }

  /// Disambiguates a post-insert failure: if a row with [contentHash] now exists,
  /// a concurrent import won the race (the partial unique index rejected ours) —
  /// report [ImportDuplicate]; otherwise it was a genuine I/O/drift error.
  Future<ImportResult> _ioErrorOrDuplicate(
    String filename,
    String contentHash,
  ) async {
    final raced = await _db.bookByContentHash(contentHash);
    if (raced != null) {
      return ImportDuplicate(raced.id, filename);
    }
    return ImportFailure(ImportFailureReason.ioError, filename);
  }

  Future<void> _rollback(StoredStream? stored) async {
    if (stored != null) {
      await _store.delete(stored.streamPath);
    }
  }

  /// AC5 rollback for the EPUB path: delete the stream pair AND the cover file
  /// so no partial state (no row was committed — the transaction rolls itself
  /// back — and no `.stream`/`.jsonl`/cover may survive).
  Future<void> _rollbackEpub(StoredStream? stored, String? coverPath) async {
    if (stored != null) {
      await _store.delete(stored.streamPath);
    }
    if (coverPath != null) {
      await _store.deleteCover(coverPath);
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

bool _isEpub(String filename) => filename.toLowerCase().endsWith('.epub');

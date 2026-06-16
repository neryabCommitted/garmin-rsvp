/// Flat-file store for the bulk word-stream artifacts (Story 2.3, AC1/AC7).
///
/// drift owns metadata; **this module owns the bytes** (architecture.md:177,433,
/// 453): the SPEC §5 binary stream (`<fingerprint>.stream`) plus the JSONL debug
/// master (`<fingerprint>.jsonl`), written under the app support dir's `streams/`
/// subdir. `Books.streamPath` is the bridge from a drift row to its stream file.
/// Never put multi-MB blobs in SQLite.
///
/// The base directory is **injectable** so tests use a temp dir without
/// `path_provider`'s platform channel; in production it resolves to
/// `getApplicationSupportDirectory()`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// The paths written by [StreamStore.write].
final class StoredStream {
  const StoredStream({required this.streamPath, required this.jsonlPath});

  /// Absolute path to the binary `<fingerprint>.stream` (goes in `Books.streamPath`).
  final String streamPath;

  /// Absolute path to the sibling `<fingerprint>.jsonl` debug master.
  final String jsonlPath;
}

class StreamStore {
  /// An optional [baseDir] overrides the app support dir (tests inject a temp
  /// dir); production leaves it null and resolves via `path_provider`.
  StreamStore([this._baseDir]);

  final Directory? _baseDir;

  static const String _streamExt = '.stream';
  static const String _jsonlExt = '.jsonl';

  Future<Directory> _streamsDir() => _subDir('streams');

  /// Covers live in a sibling `covers/` subdir (Story 2.4, AC2) — kept apart
  /// from the `.stream`/`.jsonl` artifacts so the phone-only cover never
  /// co-mingles with the word stream.
  Future<Directory> _coversDir() => _subDir('covers');

  Future<Directory> _subDir(String name) async {
    final base = _baseDir ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}$name');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Writes the stream + JSONL master under `streams/`, named by [fingerprint].
  /// Returns the absolute paths; the caller stores `streamPath` on the Books row.
  Future<StoredStream> write({
    required Uint8List streamBytes,
    required List<String> debugJsonl,
    required String fingerprint,
  }) async {
    final dir = await _streamsDir();
    final stem = '${dir.path}${Platform.pathSeparator}$fingerprint';
    final streamFile = File('$stem$_streamExt');
    final jsonlFile = File('$stem$_jsonlExt');
    await streamFile.writeAsBytes(streamBytes, flush: true);
    try {
      await jsonlFile.writeAsString(debugJsonl.join('\n'), flush: true);
    } catch (_) {
      // Atomicity (AC7): the `.stream` landed but its sibling `.jsonl` did not.
      // Delete the orphan so no half-written pair survives — import_service's
      // rollback only fires once `write` returns a StoredStream, which it won't
      // here — then rethrow for the caller to map to a typed failure.
      if (await streamFile.exists()) {
        await streamFile.delete();
      }
      rethrow;
    }
    return StoredStream(
      streamPath: streamFile.path,
      jsonlPath: jsonlFile.path,
    );
  }

  /// Writes the cover image to `covers/<fingerprint>.<ext>` and returns its
  /// absolute path (goes in `Books.cover_path`). The cover is phone-only — it
  /// never enters the word stream or the protocol (AC2). Atomic like [write]: a
  /// failed write leaves no partial file behind (2.3 review patch — rollback
  /// must cover the cover too).
  Future<String> writeCover({
    required Uint8List bytes,
    required String fingerprint,
    required String format,
  }) async {
    final dir = await _coversDir();
    final ext = format.startsWith('.') ? format : '.$format';
    final file = File('${dir.path}${Platform.pathSeparator}$fingerprint$ext');
    try {
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }
    return file.path;
  }

  /// Deletes the cover file at [coverPath]. Idempotent — no throw if it is
  /// already gone (AC5 rollback / 2.5 Remove).
  Future<void> deleteCover(String coverPath) async {
    final file = File(coverPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Deletes the `.stream` at [streamPath] and its sibling `.jsonl`. Idempotent —
  /// no throw if either is already gone (AC7 rollback / 2.5 Remove).
  Future<void> delete(String streamPath) async {
    final streamFile = File(streamPath);
    if (await streamFile.exists()) {
      await streamFile.delete();
    }
    final jsonlPath = streamPath.endsWith(_streamExt)
        ? '${streamPath.substring(0, streamPath.length - _streamExt.length)}$_jsonlExt'
        : '$streamPath$_jsonlExt';
    final jsonlFile = File(jsonlPath);
    if (await jsonlFile.exists()) {
      await jsonlFile.delete();
    }
  }
}

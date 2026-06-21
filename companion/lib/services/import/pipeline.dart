/// The pure import pipeline entry point that crosses the isolate boundary
/// (Story 2.3, AC1/AC4). [runPipeline] is a **top-level** function so it can be
/// handed to `compute(runPipeline, request)` from `import_service`, running the
/// `extract → sanitize → tokenize → bake` chain off the UI thread.
///
/// Everything here is pure Dart (AR19) — `html_extractor`, `text_sanitizer`,
/// `tokenizer`, and `word_stream_baker` carry no `package:flutter/*`, no async
/// I/O, and no global mutable state, so the whole chain runs unchanged on a
/// background isolate. The impure shell (drift, `stream_store`, `compute`
/// invocation) lives in `import_service.dart`; it must NEVER be reached from
/// here.
///
/// txt/md is a **single chapter** (no chapter discovery, [runPipeline]). EPUB's
/// many-chapter spine is [runEpubPipeline] (Story 2.4): same `compute`-boundary
/// shape, but it parses the OCF/OPF/spine into real chapters and carries the
/// OPF author + decoded cover bytes back out (neither lives in the manifest).
library;

import 'dart:typed_data';

import 'epub_extractor.dart';
import 'html_extractor.dart';
import 'import_exceptions.dart';
import 'text_sanitizer.dart';
import 'tokenizer.dart';
import 'word_stream_baker.dart';

/// Immutable, sendable request for [runPipeline]. Only primitives, so it crosses
/// the `compute` isolate boundary without custom serialization.
final class PipelineRequest {
  const PipelineRequest({
    required this.rawText,
    required this.isMarkdown,
    required this.title,
    required this.salt,
  });

  /// The decoded file contents.
  final String rawText;

  /// True for `.md`/`.markdown`; false for `.txt`.
  final bool isMarkdown;

  /// Filename-derived book title (also the single chapter's title).
  final String title;

  /// Caller-supplied fingerprint salt (SPEC §7; `word_stream_baker.dart:165`).
  final int salt;
}

/// Runs the full pure pipeline and returns the [BakedBook] (sendable: `Uint8List`
/// + immutable value objects), so `compute` can return it across the isolate.
///
/// Typed failures (Story 2.6, AC1) — `import_service` catches each by type:
/// - [TextEmptyContentException] when the file yields zero tokens
///   (empty/whitespace/all-punctuation), thrown **before** `bake` so the cause
///   is typed rather than an opaque `ArgumentError` from the baker.
/// - [UnencodableContentException] when a token cannot ride the SPEC §5 wire
///   (over 255 UTF-8 bytes / unpaired surrogate). `bake` here always receives
///   one chapter with ≥1 token, so its only remaining `ArgumentError` source is
///   `encodeChunk`'s wire-validity rejection — reclassified to the typed failure.
BakedBook runPipeline(PipelineRequest req) {
  final plain = extractPlainText(req.rawText, isMarkdown: req.isMarkdown);
  final sanitized = sanitize(plain);
  final tokens = tokenize(sanitized);
  if (tokens.isEmpty) {
    throw const TextEmptyContentException(
      'file produced no readable words (empty, whitespace, or all-punctuation)',
    );
  }
  final chapter = BakeChapter(title: req.title, tokens: tokens);
  try {
    return bake(
      title: req.title,
      chapters: <BakeChapter>[chapter],
      salt: req.salt,
    );
  } on ArgumentError catch (e) {
    // One chapter with ≥1 token reaches bake, so this is `encodeChunk`
    // rejecting a wire-invalid word (oversized / unpaired surrogate), not the
    // baker's empty-input guard.
    throw UnencodableContentException(e.message?.toString() ?? e.toString());
  }
}

/// Immutable, sendable request for [runEpubPipeline]. The raw EPUB (a ZIP) is
/// carried as bytes — never `utf8.decode`d — so it crosses the `compute` boundary
/// intact.
final class EpubPipelineRequest {
  const EpubPipelineRequest({required this.epubBytes, required this.salt});

  /// The raw `.epub` (OCF zip) bytes.
  final Uint8List epubBytes;

  /// Caller-supplied fingerprint salt (SPEC §7), as for [runPipeline].
  final int salt;
}

/// The sendable result of [runEpubPipeline]: the [BakedBook] plus the two
/// EPUB-only values that are NOT in the manifest — the OPF [author] (→ `Books`
/// row) and the decoded cover [coverBytes]/[coverFormat] (→ `stream_store`
/// cover file on the main isolate). All fields cross the isolate boundary.
final class EpubBaked {
  const EpubBaked({
    required this.baked,
    required this.author,
    required this.coverBytes,
    required this.coverFormat,
  });

  final BakedBook baked;
  final String? author;
  final Uint8List? coverBytes;
  final String? coverFormat;
}

/// Runs the full EPUB pipeline (`readBook → pre-filter spine walk →
/// sanitize/tokenize → multi-chapter bake → cover decode`) and returns the
/// sendable [EpubBaked]. Top-level so `compute(runEpubPipeline, request)` works.
///
/// `bake` sets the `chapterStart` flag on each chapter's first word and builds
/// the manifest chapter index (AC3). Throws [EpubEmptyContentException] when the
/// EPUB yields no tokens, [EpubEncryptedException] on DRM/encrypted containers,
/// [UnencodableContentException] when a chapter word cannot ride the wire, and
/// propagates `epub_pro`'s parse throws (corrupt / malformed) — `import_service`
/// maps each to a typed failure.
Future<EpubBaked> runEpubPipeline(EpubPipelineRequest req) async {
  final parse = await extractEpub(req.epubBytes);
  final BakedBook baked;
  try {
    baked = bake(
      title: parse.title,
      chapters: parse.chapters,
      salt: req.salt,
    );
  } on ArgumentError catch (e) {
    // `extractEpub` guarantees ≥1 chapter, each with ≥1 token, so this is
    // `encodeChunk` rejecting a wire-invalid word (e.g. a >255-byte token),
    // not the baker's empty-input guard.
    throw UnencodableContentException(e.message?.toString() ?? e.toString());
  }
  return EpubBaked(
    baked: baked,
    author: parse.author,
    coverBytes: parse.coverBytes,
    coverFormat: parse.coverFormat,
  );
}

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
/// txt/md is a **single chapter** (no chapter discovery). EPUB's many-chapter
/// spine is Story 2.4.
library;

import 'html_extractor.dart';
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
/// Throws [ArgumentError] when the input yields zero tokens (empty/whitespace
/// file): `bake` rejects a zero-token chapter. `import_service` (Task 5) catches
/// this boundary and maps it to a typed `ImportFailure` (AC7) — never let it
/// escape as an unhandled crash.
BakedBook runPipeline(PipelineRequest req) {
  final plain = extractPlainText(req.rawText, isMarkdown: req.isMarkdown);
  final sanitized = sanitize(plain);
  final tokens = tokenize(sanitized);
  final chapter = BakeChapter(title: req.title, tokens: tokens);
  return bake(title: req.title, chapters: <BakeChapter>[chapter], salt: req.salt);
}

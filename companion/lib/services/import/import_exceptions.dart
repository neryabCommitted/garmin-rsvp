/// Typed failure causes thrown by the **pure** import pipeline (Story 2.6,
/// AC1/AC3). Mirrors the existing `EpubEmptyContentException`
/// (`epub_extractor.dart`): each is a small, message-bearing exception that the
/// impure shell (`import_service`) catches **by type** and maps to a named
/// `ImportFailureReason` — never by substring-matching a locale- or
/// library-version-dependent message (the brittleness this story removes).
///
/// **Pure Dart** (no `package:flutter/*`, no `dart:io`): these cross the
/// `compute` isolate boundary unchanged, just like the rest of the pipeline
/// (AR19, architecture.md:265).
library;

/// Thrown when a txt/md file yields **zero tokens** (empty, whitespace-only, or
/// all-punctuation). Distinguished from [UnencodableContentException] so a
/// non-empty file is never mislabeled "empty" (deferred-work 2.3, line 7).
/// `import_service` maps this to `ImportFailureReason.emptyContent`.
///
/// The EPUB path has its own `EpubEmptyContentException` for the same cause;
/// they stay separate because the EPUB one is thrown from the extractor before
/// bake, while this one guards the single-chapter txt/md bake.
class TextEmptyContentException implements Exception {
  const TextEmptyContentException(this.message);
  final String message;

  @override
  String toString() => 'TextEmptyContentException: $message';
}

/// Thrown when a file is non-empty but carries a token the SPEC §5 wire cannot
/// represent — a word over 255 UTF-8 bytes, or one with an unpaired UTF-16
/// surrogate (the `encodeChunk` throw sites at `stream_codec.dart:99-114`).
/// `import_service` maps this to `ImportFailureReason.unsupported` ("contains
/// text we can't encode"), NOT `emptyContent`.
class UnencodableContentException implements Exception {
  const UnencodableContentException(this.message);
  final String message;

  @override
  String toString() => 'UnencodableContentException: $message';
}

/// Thrown when an EPUB carries OCF-standard encryption/DRM metadata
/// (`META-INF/encryption.xml`) — detected **structurally** (its presence in the
/// container), not by guessing from `epub_pro`'s parse-error text. Deterministic
/// and locale-independent (deferred-work 2.4, line 50). `import_service` maps
/// this to `ImportFailureReason.unsupported`.
class EpubEncryptedException implements Exception {
  const EpubEncryptedException(this.message);
  final String message;

  @override
  String toString() => 'EpubEncryptedException: $message';
}

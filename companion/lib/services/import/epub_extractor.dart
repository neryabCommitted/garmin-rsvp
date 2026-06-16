/// EPUB structure extractor (Story 2.4, Task 3 / AC1·AC3·AC4) — PURE Dart.
///
/// Reads OCF/OPF/spine/TOC via `epub_pro`, flattens the chapter hierarchy in
/// reading order, runs each chapter's HTML through the **same** AC1 DOM
/// pre-filter + `sanitize → tokenize` chain as txt/md (no parallel linguistics),
/// and returns the title/author/cover-bytes plus a `List<BakeChapter>` ready for
/// the multi-chapter [bake]. It does NOT bake, persist, or write files.
///
/// **Composes the lazy API (`openBook` + `getChapters`/`readChapters` +
/// `readCover`) instead of `EpubReader.readBook`.** `readBook` eagerly loads
/// *every* manifest resource (`readContent`), which throws on real-world books
/// whose manifest references a stray file — e.g. Calibre exports listing
/// `META-INF/calibre_bookmarks.txt` via an `OEBPS/../` href that doesn't resolve.
/// We need only the spine chapters + cover, so skipping `readContent` makes the
/// extractor robust to that large real-world class while staying on the book's
/// *real* TOC/spine chapters (never `readBookWithSplitChapters`'s >3000-word
/// arbitrary splits — the watch's BLE chunking is independent of chapters).
///
/// **ORP word-char-free-token contract (2.2-deferred → resolved here):** every
/// chapter's text flows through `tokenize`, which drops pure-punctuation tokens,
/// so a word-char-free token is never produced from the EPUB path and
/// `orp.dart`'s byte-0 degrade is unreachable. The only adjacent risk — a
/// chapter that is *entirely* symbols → zero tokens — is filtered HERE (a
/// zero-token chapter would make [bake] throw), so it never reaches the baker.
/// Decision: document-the-accept, no guard added to `bake()`.
///
/// Pure Dart: `epub_pro`, `package:image` (via `cover_extractor`), `package:html`
/// (via `html_extractor`), and the sanitizer/tokenizer are all pure Dart — no
/// `package:flutter/*`, no `dart:io` — so this runs unchanged inside `compute`
/// (AR §452 / AR19).
library;

import 'dart:typed_data';

import 'package:epub_pro/epub_pro.dart';

import 'cover_extractor.dart';
import 'html_extractor.dart';
import 'text_sanitizer.dart';
import 'tokenizer.dart';
import 'word_stream_baker.dart';

/// Title used when an EPUB has no usable `<dc:title>`.
const String _defaultTitle = 'Untitled';

/// Title used for a chapter node with no usable navLabel/title.
const String _defaultChapterTitle = 'Untitled chapter';

/// Thrown when an EPUB parses but yields **no baker-eligible content** — no
/// chapter produces a single token (empty spine, nav-only nodes, all-symbol
/// chapters). `import_service` maps this to `ImportFailureReason.emptyContent`
/// (AC5); never let it reach [bake] as an empty chapter list.
class EpubEmptyContentException implements Exception {
  const EpubEmptyContentException(this.message);
  final String message;

  @override
  String toString() => 'EpubEmptyContentException: $message';
}

/// Pure, sendable result of parsing an EPUB (crosses the `compute` boundary).
final class EpubParse {
  const EpubParse({
    required this.title,
    required this.author,
    required this.chapters,
    required this.coverBytes,
    required this.coverFormat,
  });

  final String title;
  final String? author;
  final List<BakeChapter> chapters;
  final Uint8List? coverBytes;
  final String? coverFormat;
}

/// Parses [epubBytes] into an [EpubParse]. Async because `EpubReader.readBook`
/// is async (`compute` accepts async callbacks).
///
/// Throws [EpubEmptyContentException] when nothing tokenizes; lets `epub_pro`'s
/// own throws (corrupt/DRM/unsupported) propagate for `import_service` to map.
Future<EpubParse> extractEpub(List<int> epubBytes) async {
  final bookRef = await EpubReader.openBook(epubBytes);
  final chapterNodes = await EpubReader.readChapters(bookRef.getChapters());

  final chapters = <BakeChapter>[];
  for (final node in chapterNodes) {
    _flatten(node, chapters);
  }
  if (chapters.isEmpty) {
    throw const EpubEmptyContentException(
      'EPUB produced no readable chapters (empty spine or no prose)',
    );
  }

  // Cover is best-effort: a malformed/missing cover must not sink an otherwise
  // good import (AC2 — no-cover is a valid state).
  Uint8List? coverBytes;
  String? coverFormat;
  try {
    final coverImage = await bookRef.readCover();
    if (coverImage != null) {
      final cover = encodeCover(coverImage);
      coverBytes = cover.bytes;
      coverFormat = cover.format;
    }
  } catch (_) {
    coverBytes = null;
    coverFormat = null;
  }

  return EpubParse(
    title: _nonBlank(bookRef.title) ?? _defaultTitle,
    author: _nonBlank(bookRef.author),
    chapters: chapters,
    coverBytes: coverBytes,
    coverFormat: coverFormat,
  );
}

/// Depth-first flatten in reading order: a node's own `htmlContent` first, then
/// its subchapters. Chapters that tokenize to zero tokens are skipped (see the
/// ORP contract in the library doc).
void _flatten(EpubChapter node, List<BakeChapter> out) {
  final html = node.htmlContent;
  if (html != null && html.trim().isNotEmpty) {
    final text = extractFromHtml(html, epubFilter: true);
    final tokens = tokenize(sanitize(text));
    if (tokens.isNotEmpty) {
      out.add(BakeChapter(
        title: _nonBlank(node.title) ?? _defaultChapterTitle,
        tokens: tokens,
      ));
    }
  }
  for (final sub in node.subChapters) {
    _flatten(sub, out);
  }
}

String? _nonBlank(String? s) {
  if (s == null) {
    return null;
  }
  final trimmed = s.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Cover extraction (Story 2.4, Task 4 / AC2) — PURE Dart.
///
/// Turns an EPUB's decoded cover [img.Image] into bounded, re-encoded **bytes**.
/// It deliberately does NOT touch the filesystem: a `compute`-run module cannot
/// use `dart:io`, so the *file* is written by `stream_store.writeCover` on the
/// main isolate — the same bytes-in-isolate / file-on-main split as the word
/// stream. The cover **never** enters `streamBytes` or any protocol message;
/// it is a phone-only sidecar referenced by `Books.cover_path`
/// (architecture.md:178,589).
///
/// Pure Dart: `package:image` and `package:epub_pro` are pure Dart — no
/// `package:flutter/*`, no `dart:io` — so this runs unchanged inside `compute`
/// (AR §452 / AR19).
library;

import 'dart:typed_data';

import 'package:epub_pro/epub_pro.dart';
import 'package:image/image.dart' as img;

/// Longest-side cap for the stored cover, to bound the on-disk thumbnail size.
const int kMaxCoverDimension = 600;

/// JPEG quality for the re-encoded cover.
const int _coverJpegQuality = 80;

/// Extracts [book]'s cover as `(bytes, format)`, or null when the EPUB carries
/// no cover (a valid case — AC2). The image is downscaled to [kMaxCoverDimension]
/// on its longest side (aspect preserved) and re-encoded as JPEG to bound size.
({Uint8List bytes, String format})? extractCover(EpubBook book) {
  final image = book.coverImage;
  if (image == null) {
    return null;
  }
  return encodeCover(image);
}

/// Downscales and re-encodes a decoded cover [image] to bounded JPEG bytes.
/// Split out so the extractor can encode a cover read via the lazy
/// `EpubBookRef.readCover()` path without materializing a whole [EpubBook].
({Uint8List bytes, String format}) encodeCover(img.Image image) {
  final bounded = _downscale(image);
  final bytes = img.encodeJpg(bounded, quality: _coverJpegQuality);
  return (bytes: Uint8List.fromList(bytes), format: 'jpg');
}

img.Image _downscale(img.Image image) {
  final longest = image.width >= image.height ? image.width : image.height;
  if (longest <= kMaxCoverDimension) {
    return image;
  }
  return image.width >= image.height
      ? img.copyResize(image, width: kMaxCoverDimension)
      : img.copyResize(image, height: kMaxCoverDimension);
}

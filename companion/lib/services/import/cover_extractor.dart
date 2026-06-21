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
/// Pure Dart: `package:image` is pure Dart — no `package:flutter/*`, no
/// `dart:io` — so this runs unchanged inside `compute` (AR §452 / AR19).
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Longest-side cap for the stored cover, to bound the on-disk thumbnail size.
const int kMaxCoverDimension = 600;

/// Hard ceiling on a *source* cover's dimensions (Story 2.6, Task 4). A decoded
/// cover larger than this on either axis is rejected by [coverWithinBounds] →
/// degraded to no-cover, so the subsequent `copyResize` + `encodeJpg` never
/// allocate buffers for a pathologically large image (the OOM risk flagged in
/// deferred-work 2.4, line 52). Generous vs. any real cover (already capped to
/// [kMaxCoverDimension] on output); only the absurd outliers trip it.
const int kMaxCoverSourceDimension = 5000;

/// JPEG quality for the re-encoded cover.
const int _coverJpegQuality = 80;

/// True when [image] is small enough to safely re-encode. The caller degrades a
/// `false` to the no-cover state (AC2 valid state) instead of crashing — see
/// [kMaxCoverSourceDimension].
bool coverWithinBounds(img.Image image) =>
    image.width <= kMaxCoverSourceDimension &&
    image.height <= kMaxCoverSourceDimension;

/// Downscales and re-encodes a decoded cover [image] to bounded JPEG bytes.
/// Encodes a cover read via the lazy `EpubBookRef.readCover()` path; the
/// no-cover case (a valid state — AC2) is handled by the caller, which only
/// calls this when `readCover()` returns a non-null image.
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

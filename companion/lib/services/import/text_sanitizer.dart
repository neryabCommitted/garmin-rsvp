import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Stage 1 of the Epic 2 import pipeline (`sanitize → tokenize → …`, AR20):
/// cleans raw book text before tokenization.
///
/// Pure Dart (no `package:flutter/*`, no global mutable state, no async I/O) so
/// it runs unchanged in the import isolate (AR19) and tests without a widget
/// tree. Dart's core `String` has no `normalize()`, so NFC comes from the
/// zero-dependency `unorm_dart` package.
///
/// Why it matters: ORP pivots (Story 2.2) are UTF-8 *byte* indices (SPEC §5).
/// A leftover soft hyphen or zero-width char shifts every downstream byte
/// offset and silently corrupts pivots, so invisibles are removed completely
/// here rather than tolerated later.

/// Soft hyphen (U+00AD) plus the zero-width set: ZWSP (U+200B), ZWNJ (U+200C),
/// ZWJ (U+200D), word-joiner (U+2060) and ZWNBSP/BOM (U+FEFF). All carry no
/// visible glyph and must not survive into byte-indexed records.
final RegExp _invisibles = RegExp('[­​‌‍⁠﻿]');

/// Line-ending normalizer: CRLF (`\r\n`) and bare CR (`\r`, classic-Mac / some
/// EPUB extraction) → LF (`\n`). The tokenizer's paragraph boundary is
/// `\n\s*\n`, so a blank line expressed with CRs would otherwise be missed and
/// silently drop a `paragraphStart`.
final RegExp _lineEndings = RegExp(r'\r\n?');

/// ASCII-fold table (AC2). Each entry maps a glyph the watch font lacks to its
/// closest ASCII form. Applied only when `asciiFold` is true; kept small and
/// fully covered by tests. The ellipsis (U+2026 → "...") is one-to-many and is
/// handled separately before this per-character pass.
const Map<String, String> _foldMap = <String, String>{
  // Curly single quotes → straight apostrophe.
  '‘': "'", // ‘
  '’': "'", // ’
  // Curly double quotes → straight quote.
  '“': '"', // “
  '”': '"', // ”
  // En/em dash → hyphen-minus.
  '–': '-', // –
  '—': '-', // —
  // Common Latin-1 accented letters → base letter (lowercase).
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n', 'ý': 'y', 'ÿ': 'y',
  // Uppercase counterparts.
  'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A',
  'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E',
  'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I',
  'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O',
  'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U',
  'Ç': 'C', 'Ñ': 'N', 'Ý': 'Y',
};

/// Sanitizes [raw] book text (AC1, AC2).
///
/// Pipeline order matters: NFC-normalize **first** (normalization can change
/// which codepoints are present — e.g. a decomposed accent becomes a single
/// precomposed codepoint), then strip invisibles and normalize spaces, then
/// optionally ASCII-fold.
///
/// With [asciiFold] off (default) glyphs missing from the watch font pass
/// through unchanged; with it on they are folded to ASCII per [_foldMap].
///
/// NFR8: returns a clean [String] for any input — empty, whitespace-only, or
/// fully invisible text degrade to a valid (possibly empty) result; never
/// throws.
String sanitize(String raw, {bool asciiFold = false}) {
  // AC1 — NFC before any codepoint-level edits.
  var text = unorm.nfc(raw);

  // AC1 — drop soft hyphen + zero-width set entirely.
  text = text.replaceAll(_invisibles, '');

  // Normalize CR/CRLF line endings to LF so paragraph detection (\n\s*\n) sees
  // blank lines regardless of the source's line-ending convention.
  text = text.replaceAll(_lineEndings, '\n');

  // AC1 — NBSP (U+00A0) and narrow NBSP (U+202F) → regular space (U+0020).
  text = text.replaceAll(' ', ' ').replaceAll(' ', ' ');

  // AC2 — optional fold of watch-font-missing glyphs.
  if (asciiFold) {
    text = _asciiFold(text);
  }
  return text;
}

/// Applies the [_foldMap] per character, after expanding the one-to-many
/// ellipsis. Iterates runes so multi-code-unit input is handled safely.
String _asciiFold(String s) {
  final String expanded = s.replaceAll('…', '...'); // … → ...
  final StringBuffer buffer = StringBuffer();
  for (final int rune in expanded.runes) {
    final String ch = String.fromCharCode(rune);
    buffer.write(_foldMap[ch] ?? ch);
  }
  return buffer.toString();
}

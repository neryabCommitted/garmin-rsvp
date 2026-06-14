/// Stage 4 of the Epic 2 import pipeline (`… → pace → ORP → …`, AR20):
/// computes each word's ORP (optimal-recognition-point) pivot.
///
/// SPEC §5: `orpPivot` is a 0-based **byte** index into the word's UTF-8 bytes
/// pointing at the first byte of the pivot character; the watch never recomputes
/// it. The pivot character is chosen by Nano's `orpOrdinalForLength` table over
/// **word-characters only** (letters/digits — punctuation is skipped when
/// counting, so leading quotes/brackets don't shift the pivot off a letter),
/// then mapped to the byte offset of that character within `utf8.encode(word)`
/// (the full stored word, punctuation included).
///
/// Pure Dart (no `package:flutter/*`, no global mutable state, no async I/O) so
/// it runs unchanged in the import isolate (AR19).
library;

import 'dart:convert';

/// Word-character class (letters + digits), matching the tokenizer's keep rule
/// and the pacing length count.
final RegExp _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Nano `orpOrdinalForLength`: length ≤1 → 0th, ≤5 → 1st, ≤9 → 2nd, ≤13 → 3rd,
/// else 4th. The returned ordinal is always `< wordCharCount` (for any
/// `wordCharCount ≥ 1`), so the pivot always lands on a real word-character.
int _ordinalForLength(int wordCharCount) {
  if (wordCharCount <= 1) {
    return 0;
  }
  if (wordCharCount <= 5) {
    return 1;
  }
  if (wordCharCount <= 9) {
    return 2;
  }
  if (wordCharCount <= 13) {
    return 3;
  }
  return 4;
}

/// Returns the 0-based UTF-8 byte index of [word]'s ORP pivot (AC2).
///
/// The result points at the first byte of the chosen pivot character, is
/// `< utf8.encode(word).length`, and lands on a letter/digit — exactly the
/// conditions `encodeChunk` enforces at the wire boundary.
int orpPivot(String word) {
  final int wordCharCount = _wordChar.allMatches(word).length;
  final int ordinal = _ordinalForLength(wordCharCount);

  int byteOffset = 0;
  int seen = 0;
  for (final int rune in word.runes) {
    final String ch = String.fromCharCode(rune);
    if (_wordChar.hasMatch(ch)) {
      if (seen == ordinal) {
        return byteOffset;
      }
      seen++;
    }
    byteOffset += utf8.encode(ch).length;
  }
  // Defensive: a word with no word-characters never reaches here (the tokenizer
  // drops pure-punctuation tokens), but degrade to the front byte rather than
  // returning an out-of-range index.
  return 0;
}

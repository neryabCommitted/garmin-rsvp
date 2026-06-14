import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/services/import/orp.dart';

/// Story 2.2 AC2 — the ORP pivot is a 0-based **UTF-8 byte index** into the
/// stored word, chosen by Nano's length→ordinal table over **word-characters
/// only** (punctuation skipped). The index MUST be `< wordLen`, point at the
/// first byte of a UTF-8 sequence (`byte & 0xC0 != 0x80`), and land on a
/// letter/digit. SPEC §5 example #2 (שלום → pivot 2) is the canonical proof
/// that this is a byte index, not a character index.

void main() {
  group('orpPivot — ordinal table over word-characters (AC2)', () {
    test('single char → 0th', () {
      expect(orpPivot('a'), 0);
    });

    test('<=5 word-chars → 1st character', () {
      expect(orpPivot('Pace'), 1); // matches the SPEC §5 fixture record
      expect(orpPivot('turns'), 1);
      expect(orpPivot('hello'), 1);
    });

    test('<=9 word-chars → 2nd character', () {
      expect(orpPivot('sentence'), 2); // 8 chars → s e [n] → byte 2
    });

    test('<=13 word-chars → 3rd character', () {
      expect(orpPivot('extraordinary'), 3); // 13 chars → e x t [r] → byte 3
    });

    test('>=14 word-chars → 4th character (capped)', () {
      expect(orpPivot('internationalization'), 4); // i n t e [r] → byte 4
    });
  });

  group('orpPivot — byte index, not char index (AC2)', () {
    test('Hebrew שלום → byte 2 (start of the 2nd 2-byte character)', () {
      // 4 word-chars → ordinal 1 → second character ל; ש is 2 UTF-8 bytes, so
      // the byte offset is 2 (SPEC §5 example #2).
      expect(orpPivot('שלום'), 2);
    });

    test('accented multi-byte word counts characters, returns byte offset', () {
      // "über": ü is 2 bytes; 4 chars → ordinal 1 → 'b' at byte offset 2.
      expect(orpPivot('über'), 2);
      // "café": all leading chars are 1 byte; ordinal 1 → 'a' at byte 1.
      expect(orpPivot('café'), 1);
    });
  });

  group('orpPivot — punctuation does not shift the pivot off a letter (AC2)',
      () {
    test('leading quote is counted in bytes but not as a word-char', () {
      // word-chars of `"hello"` = 5 → ordinal 1 → 'e'; the opening quote is 1
      // byte, so the byte offset is 2 and still lands on a letter.
      expect(orpPivot('"hello"'), 2);
    });

    test('leading bracket', () {
      expect(orpPivot('(world)'), 2); // '(' + 'w' → 'o' at byte 2
    });

    test('trailing punctuation does not change the front-anchored pivot', () {
      expect(orpPivot('world.'), 1); // 5 chars → ordinal 1 → 'o'
      expect(orpPivot('however,'), 2); // 7 chars → ordinal 2 → 'w'
    });
  });

  group('orpPivot — invariants the encoder enforces (AC2)', () {
    const words = <String>[
      'a',
      'Pace',
      'turns',
      'שלום',
      'über',
      '"hello"',
      'world.',
      'internationalization',
      'mother-in-law',
      'café',
    ];

    test('pivot < wordLen, on a UTF-8 sequence start, on a letter/digit', () {
      final wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);
      for (final w in words) {
        final bytes = utf8.encode(w);
        final pivot = orpPivot(w);
        expect(pivot, inInclusiveRange(0, bytes.length - 1), reason: '$w len');
        expect(bytes[pivot] & 0xC0 == 0x80, isFalse,
            reason: '$w: pivot must not be a continuation byte');
        // The byte at the pivot starts a rune that is a word-character.
        final rune = utf8.decode(bytes.sublist(pivot)).runes.first;
        expect(wordChar.hasMatch(String.fromCharCode(rune)), isTrue,
            reason: '$w: pivot must land on a letter/digit');
      }
    });
  });
}

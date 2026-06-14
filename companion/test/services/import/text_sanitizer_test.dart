import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/services/import/text_sanitizer.dart';

/// Story 2.1 AC1 (sanitation), AC2 (optional ASCII-fold), AC5 (pure Dart),
/// NFR8 (bounds-check-and-degrade). The sanitizer is the first stage of the
/// import pipeline; leftover soft-hyphens/zero-widths shift UTF-8 byte offsets
/// and silently corrupt 2.2's ORP pivots, so they must be removed completely.

void main() {
  group('sanitize — NFC normalization (AC1)', () {
    test('decomposed accent normalizes to precomposed (NFC)', () {
      // "café": e + U+0301 (combining acute) → must equal precomposed U+00E9.
      const decomposed = 'café';
      const precomposed = 'café';
      expect(decomposed == precomposed, isFalse, reason: 'inputs differ pre-NFC');
      expect(sanitize(decomposed), equals(precomposed));
      expect(sanitize(precomposed), equals(precomposed));
    });

    test('precomposed and decomposed inputs sanitize identically', () {
      expect(sanitize('café'), equals(sanitize('café')));
    });
  });

  group('sanitize — strip invisible codepoints (AC1)', () {
    test('strips soft hyphen U+00AD', () {
      expect(sanitize('sub­word'), equals('subword'));
    });

    test('strips the full zero-width set', () {
      // ZWSP, ZWNJ, ZWJ, word-joiner, ZWNBSP/BOM.
      expect(sanitize('a​b‌c‍d⁠e﻿f'),
          equals('abcdef'));
    });

    test('zero-width char mid-word collapses to a clean word', () {
      expect(sanitize('word‌boundary'), equals('wordboundary'));
    });
  });

  group('sanitize — normalize spaces (AC1)', () {
    test('NBSP U+00A0 becomes a regular space', () {
      expect(sanitize('a b'), equals('a b'));
    });

    test('narrow NBSP U+202F becomes a regular space', () {
      expect(sanitize('a b'), equals('a b'));
    });
  });

  group('sanitize — normalize line endings (AC1)', () {
    test('CRLF becomes LF', () {
      expect(sanitize('a\r\nb'), equals('a\nb'));
    });

    test('bare CR becomes LF', () {
      expect(sanitize('a\rb'), equals('a\nb'));
    });

    test('CR-pair blank line becomes an LF paragraph boundary', () {
      expect(sanitize('one\r\rtwo'), equals('one\n\ntwo'));
    });

    test('LF passes through unchanged', () {
      expect(sanitize('a\n\nb'), equals('a\n\nb'));
    });
  });

  group('sanitize — ASCII-fold off by default (AC2)', () {
    test('curly quotes, dashes, ellipsis, accents pass through when off', () {
      const fancy = '“quote” ‘x’ em—dash en–dash '
          'go… café';
      expect(sanitize(fancy), equals(fancy));
      expect(sanitize(fancy, asciiFold: false), equals(fancy));
    });
  });

  group('sanitize — ASCII-fold on (AC2)', () {
    test('folds curly quotes to straight', () {
      expect(sanitize('“hi”', asciiFold: true), equals('"hi"'));
      expect(sanitize('it’s ‘x’', asciiFold: true),
          equals("it's 'x'"));
    });

    test('folds em/en dash to hyphen', () {
      expect(sanitize('a—b–c', asciiFold: true), equals('a-b-c'));
    });

    test('folds ellipsis char to three dots', () {
      expect(sanitize('wait…', asciiFold: true), equals('wait...'));
    });

    test('folds common accented letters to base', () {
      expect(sanitize('café naïve résumé', asciiFold: true),
          equals('cafe naive resume'));
    });
  });

  group('sanitize — NFR8 bounds-check-and-degrade', () {
    test('empty string returns empty', () {
      expect(sanitize(''), equals(''));
      expect(sanitize('', asciiFold: true), equals(''));
    });

    test('whitespace-only input does not crash and space-normalizes', () {
      expect(sanitize('   '), equals('   '));
      expect(sanitize('  '), equals('  '));
    });

    test('plain ASCII passes through unchanged', () {
      expect(sanitize('Hello, world.'), equals('Hello, world.'));
    });
  });
}

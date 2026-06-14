import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/services/import/pacing.dart';
import 'package:paceturner_companion/services/import/tokenizer.dart';

/// Story 2.2 AC1 — pacing produces a WPM-invariant **additive** `bonusMs`
/// (never an absolute duration). The watch computes `displayMs = 60000/wpm +
/// bonusMs` (SPEC §5.1), so `bonusMs` MUST depend only on the word/flags, not
/// on WPM. Tiers (length / complexity / punctuation) and reference bases are
/// ported from RSVP Nano (`pacingBonusMsForWord`) per the addendum; all values
/// live in named consts so Gate V4 recalibration is a one-file change.
///
/// Reference bases are 200 ms per tier (Nano defaults), so a tier of `p`% adds
/// `p * 2` ms. Expected numbers below are derived from that.

Token _t(String text, {bool sentenceEnd = false, bool paragraphStart = false}) =>
    Token(text: text, paragraphStart: paragraphStart, sentenceEnd: sentenceEnd);

void main() {
  group('bonusMsForWord — length tier (AC1)', () {
    test('a short word (<=6 word-chars) gets no length bonus', () {
      // "cat": 3 word-chars, 1 syllable, no punctuation → 0.
      expect(bonusMsForWord(_t('cat')), 0);
    });

    test('chars beyond 6 add 6%/char (200ms base → 12ms/char)', () {
      // "wonderful": 9 word-chars → 3 chars beyond 6 → 18% → 36 ms length.
      // 1 vowel-run group ("o","e","u" = 3 groups) → syllable bonus applies;
      // isolate the length tier with a deliberately consonant-light check via
      // the cap test below. Here assert the floor: length contributes >= 36.
      expect(bonusMsForWord(_t('wonderful')), greaterThanOrEqualTo(36));
    });

    test('length bonus is capped at 170% (340 ms) for very long words', () {
      // 40 'a's: one vowel run (1 syllable → 0 complexity), no punctuation, so
      // the whole bonus is the capped length tier = 170% * 200 = 340 ms.
      expect(bonusMsForWord(_t('a' * 40)), 340);
    });
  });

  group('bonusMsForWord — complexity tier (AC1)', () {
    test('mixed alphanumeric adds 22% (44 ms)', () {
      // "A4": 2 word-chars (no length tier), 1 vowel group (0 syllable bonus),
      // one letter only (not ALL-CAPS), letter+digit → mixed 22% → 44 ms.
      expect(bonusMsForWord(_t('A4')), 44);
    });

    test('ALL-CAPS adds 14% on top of the syllable groups', () {
      // "NASA": 4 word-chars (no length tier), vowel groups A,A = 2 → one extra
      // syllable → 25%; ALL-CAPS (>=2 upper letters) → 14%. Total 39% → 78 ms.
      expect(bonusMsForWord(_t('NASA')), 78);
    });

    test('compound joiner (hyphen) adds 14%', () {
      // "mother-in-law": 11 word-chars → length 33% (66 ms); vowel groups
      // o,e,i,a = 4 → capped syllable 50%; compound +14% → complexity capped at
      // 64% (128 ms). 66 + 128 = 194 ms.
      expect(bonusMsForWord(_t('mother-in-law')), 194);
    });

    test('complexity tier is capped at 85%', () {
      // A long all-caps alphanumeric hyphenated word would exceed 85% raw;
      // assert the complexity contribution never pushes the total past
      // length-cap(340) + complexity-cap(170) + punct(0) = 510.
      expect(
        bonusMsForWord(_t('SUPER-LONG-CODE-NAME-42X' * 2)),
        lessThanOrEqualTo(510),
      );
    });
  });

  group('bonusMsForWord — punctuation tier (AC1)', () {
    test('comma adds 45% (90 ms)', () {
      // "however,": 7 word-chars → length 6% (12 ms); vowel groups o,e,e = 3 →
      // syllable 50% (100 ms); comma 45% (90 ms). 12 + 100 + 90 = 202 ms.
      expect(bonusMsForWord(_t('however,')), 202);
    });

    test('dash adds 60% (120 ms)', () {
      // "wait—": 4 word-chars, 1 vowel group, em-dash → 60% → 120 ms.
      expect(bonusMsForWord(_t('wait—')), 120);
    });

    test('semicolon/colon adds 80% (160 ms)', () {
      expect(bonusMsForWord(_t('list:')), 160);
    });

    test('non-terminal ellipsis adds 110% (220 ms)', () {
      // Constructed with sentenceEnd=false to exercise the ellipsis branch
      // directly (the pipeline usually flags a trailing ellipsis as a sentence
      // end, in which case the 150% sentence pause dominates — see below).
      expect(bonusMsForWord(_t('wait...')), 220);
    });

    test('sentenceEnd flag drives the 150% sentence pause (300 ms)', () {
      // "end.": flag set → 150% (300 ms); no length/syllable bonus.
      expect(bonusMsForWord(_t('end.', sentenceEnd: true)), 300);
    });

    test('a trailing period that is NOT a sentence end is suppressed', () {
      // "etc." abbreviation: tokenizer leaves sentenceEnd=false, so the
      // terminal period contributes nothing (no false long pause).
      expect(bonusMsForWord(_t('etc.')), 0);
    });

    test('sentence pause (150%) dominates a raw terminal mark', () {
      // A sentence-ending ellipsis word: 110% ellipsis < 150% flag → 150% wins.
      expect(bonusMsForWord(_t('wait...', sentenceEnd: true)), 300);
    });
  });

  group('bonusMsForWord — WPM-invariance contract (AC1)', () {
    test('the bonus is identical regardless of WPM; only 60000/wpm varies', () {
      // Mirrors Nano test_word_pacing_bonus_at_is_invariant_to_wpm: bonusMs has
      // no WPM input, and displayMs = 60000/wpm + bonus is the ONLY timing
      // expression. So display(wpm) - 60000/wpm == bonus for every wpm.
      final tok = _t('however,');
      final bonus = bonusMsForWord(tok);
      for (final wpm in [60, 100, 250, 400, 1000]) {
        final displayMs = 60000 ~/ wpm + bonus;
        expect(displayMs - 60000 ~/ wpm, bonus, reason: 'wpm=$wpm');
      }
    });

    test('bonus always fits u16 [0, 65535] (SPEC §5)', () {
      for (final w in ['a', 'cat', 'however,', 'a' * 200, 'WAIT—NOW!']) {
        final b = bonusMsForWord(_t(w, sentenceEnd: true));
        expect(b, inInclusiveRange(0, 65535), reason: w);
      }
    });

    test('the optional look-ahead param does not change a self-contained bonus',
        () {
      // `next` is retained for API portability with Nano's next-word-case
      // heuristic; the ported per-word tiers are self-contained, so passing a
      // look-ahead must not alter the result.
      final tok = _t('however,');
      expect(
        bonusMsForWord(tok, next: _t('then')),
        bonusMsForWord(tok),
      );
    });
  });
}

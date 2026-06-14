import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/services/import/tokenizer.dart';

/// Story 2.1 AC3 (tokenization + flags), AC4 (abbreviation-aware sentence-end),
/// AC5 (pure Dart), NFR8 (degrade, never crash). These flags are baked once on
/// the phone and consumed verbatim by the watch (FR17): a false `sentenceEnd`
/// from "Dr." silently breaks the two-stage pause (FR8) and sentence-rewind
/// (FR10) on-device, so the abbreviation cases are correctness-critical.

List<String> _words(List<Token> t) => t.map((Token w) => w.text).toList();
List<bool> _sentenceEnds(List<Token> t) =>
    t.map((Token w) => w.sentenceEnd).toList();
List<bool> _paragraphStarts(List<Token> t) =>
    t.map((Token w) => w.paragraphStart).toList();

void main() {
  group('Token value type', () {
    test('== / hashCode by value', () {
      const a = Token(text: 'hi', paragraphStart: true, sentenceEnd: false);
      const b = Token(text: 'hi', paragraphStart: true, sentenceEnd: false);
      const c = Token(text: 'hi', paragraphStart: false, sentenceEnd: false);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toString surfaces fields', () {
      const t = Token(text: 'hi', paragraphStart: true, sentenceEnd: false);
      expect(t.toString(), contains('hi'));
    });
  });

  group('tokenize — word splitting (AC3)', () {
    test('splits on whitespace and keeps trailing punctuation on the token', () {
      expect(_words(tokenize('Hello, world.')), equals(['Hello,', 'world.']));
    });

    test('keeps digit-only and alphanumeric tokens', () {
      expect(_words(tokenize('chapter 12 and A4')),
          equals(['chapter', '12', 'and', 'A4']));
    });

    test('drops whitespace runs without emitting empty tokens', () {
      expect(_words(tokenize('a   b\tc')), equals(['a', 'b', 'c']));
    });

    test('drops pure-punctuation tokens (no letter or digit)', () {
      expect(_words(tokenize('hello ... world')), equals(['hello', 'world']));
    });
  });

  group('tokenize — paragraph flags (AC3)', () {
    test('first token of text and first after a blank line start a paragraph',
        () {
      final t = tokenize('First para here.\n\nSecond para now.');
      expect(_words(t),
          equals(['First', 'para', 'here.', 'Second', 'para', 'now.']));
      expect(_paragraphStarts(t),
          equals([true, false, false, true, false, false]));
    });

    test('multiple blank lines collapse to one boundary', () {
      final t = tokenize('one\n\n\n\ntwo');
      expect(_paragraphStarts(t), equals([true, true]));
    });
  });

  group('tokenize — sentence-end basics (AC3)', () {
    test('. ! ? terminate a sentence', () {
      final t = tokenize('Stop. Go! Why? ok');
      expect(_sentenceEnds(t), equals([true, true, true, false]));
    });

    test('no-terminal-punctuation tail is not a sentence end', () {
      final t = tokenize('a clean ending without punctuation');
      expect(t.last.sentenceEnd, isFalse);
    });

    test('terminal punctuation behind a closing quote/paren still counts', () {
      // "left." then a closing quote; "(happily)." then the period.
      final t = tokenize('He left." She smiled (happily).');
      expect(t.firstWhere((Token w) => w.text == 'left."').sentenceEnd, isTrue);
      expect(t.last.sentenceEnd, isTrue);
    });
  });

  group('tokenize — abbreviation-aware sentence-end (AC4)', () {
    test('titles and initialisms do not end a sentence', () {
      final t = tokenize('Dr. Smith went to the U.S. yesterday.');
      final ends = {
        for (final Token w in t) w.text: w.sentenceEnd,
      };
      expect(ends['Dr.'], isFalse);
      expect(ends['U.S.'], isFalse);
      expect(ends['yesterday.'], isTrue);
    });

    test('e.g. and i.e. mid-sentence do not split', () {
      final t = tokenize('Bring snacks, e.g. chips and i.e. dip.');
      final ends = {for (final Token w in t) w.text: w.sentenceEnd};
      expect(ends['e.g.'], isFalse);
      expect(ends['i.e.'], isFalse);
      expect(ends['dip.'], isTrue);
    });

    test('single capital initial does not end a sentence', () {
      final t = tokenize('Written by J. Smith.');
      final ends = {for (final Token w in t) w.text: w.sentenceEnd};
      expect(ends['J.'], isFalse);
      expect(ends['Smith.'], isTrue);
    });

    test('internal decimal dot does not end a sentence', () {
      final t = tokenize('The value is 3.14 today.');
      final ends = {for (final Token w in t) w.text: w.sentenceEnd};
      expect(ends['3.14'], isFalse);
      expect(ends['today.'], isTrue);
    });

    test('trailing ellipsis (char or three dots) ends a sentence', () {
      final t = tokenize('Wait... what?');
      final ends = {for (final Token w in t) w.text: w.sentenceEnd};
      expect(ends['Wait...'], isTrue);
      expect(ends['what?'], isTrue);
    });
  });

  group('tokenize — NFR8 degrade, never crash', () {
    test('empty string yields no tokens', () {
      expect(tokenize(''), isEmpty);
    });

    test('whitespace-only yields no tokens', () {
      expect(tokenize('   \n\t  '), isEmpty);
    });

    test('single word, no punctuation', () {
      final t = tokenize('word');
      expect(t.length, equals(1));
      expect(t.single,
          equals(const Token(text: 'word', paragraphStart: true, sentenceEnd: false)));
    });
  });
}

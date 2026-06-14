import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/services/import/html_extractor.dart';
import 'package:paceturner_companion/services/import/text_sanitizer.dart';
import 'package:paceturner_companion/services/import/tokenizer.dart';

void main() {
  group('extractPlainText — .txt (isMarkdown: false)', () {
    test('returns the raw text unchanged (blank lines preserved)', () {
      const raw = 'First paragraph.\n\nSecond paragraph.';
      expect(extractPlainText(raw, isMarkdown: false), raw);
    });

    test('empty input returns empty', () {
      expect(extractPlainText('', isMarkdown: false), '');
    });
  });

  group('extractPlainText — .md (isMarkdown: true)', () {
    test('two paragraphs become blank-line-separated blocks', () {
      const md = 'First paragraph.\n\nSecond paragraph.';
      expect(extractPlainText(md, isMarkdown: true),
          'First paragraph.\n\nSecond paragraph.');
    });

    test('heading and body are separate blocks', () {
      const md = '# Title\n\nBody text here.';
      expect(extractPlainText(md, isMarkdown: true), 'Title\n\nBody text here.');
    });

    test('list items become separate blocks', () {
      const md = '- alpha\n- beta';
      expect(extractPlainText(md, isMarkdown: true), 'alpha\n\nbeta');
    });

    test('inline formatting is reduced to its text', () {
      const md = 'A **bold** and *italic* word.';
      expect(extractPlainText(md, isMarkdown: true), 'A bold and italic word.');
    });

    test('soft line breaks inside a paragraph collapse to spaces', () {
      const md = 'one\ntwo\nthree';
      // markdown treats single newlines as soft breaks within one paragraph;
      // the extractor must NOT introduce a blank line there (else a spurious
      // paragraph boundary would be baked).
      expect(extractPlainText(md, isMarkdown: true), 'one two three');
    });

    test('script/style nodes are dropped', () {
      const md = 'Visible text.\n\n<script>evil()</script>\n\nMore text.';
      final out = extractPlainText(md, isMarkdown: true);
      expect(out.contains('evil'), isFalse);
      expect(out.contains('Visible text.'), isTrue);
      expect(out.contains('More text.'), isTrue);
    });

    test('empty / whitespace-only markdown returns empty', () {
      expect(extractPlainText('', isMarkdown: true), '');
      expect(extractPlainText('   \n\n   ', isMarkdown: true), '');
    });
  });

  group('paragraph boundary survives the full extract→sanitize→tokenize chain',
      () {
    test('first token of paragraph 2 has paragraphStart == true (md)', () {
      const md = 'First paragraph here.\n\nSecond paragraph begins.';
      final plain = extractPlainText(md, isMarkdown: true);
      final tokens = tokenize(sanitize(plain));

      // Find the first token of the second paragraph: the second token with
      // paragraphStart == true (the very first token is always a paragraph
      // start by the tokenizer's contract).
      final starts =
          tokens.where((t) => t.paragraphStart).toList(growable: false);
      expect(starts.length, 2, reason: 'two paragraphs → two paragraph starts');
      expect(starts[1].text, 'Second');
    });

    test('the same chain on .txt also preserves the boundary', () {
      const raw = 'First paragraph here.\n\nSecond paragraph begins.';
      final plain = extractPlainText(raw, isMarkdown: false);
      final tokens = tokenize(sanitize(plain));
      final starts = tokens.where((t) => t.paragraphStart).length;
      expect(starts, 2);
    });
  });
}

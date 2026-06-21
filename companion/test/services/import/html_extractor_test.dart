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

  group('extractFromHtml — shared core (no filter)', () {
    test('walks block elements into blank-line-separated paragraphs', () {
      const html = '<html><body><p>First.</p><p>Second.</p></body></html>';
      expect(extractFromHtml(html), 'First.\n\nSecond.');
    });

    test('soft line breaks inside a block collapse to spaces', () {
      const html = '<body><p>one\ntwo\nthree</p></body>';
      expect(extractFromHtml(html), 'one two three');
    });

    test('script/style are dropped', () {
      const html = '<body><p>Keep.</p><script>evil()</script></body>';
      expect(extractFromHtml(html), 'Keep.');
    });
  });

  group('extractFromHtml — EPUB pre-filter (AC1)', () {
    test('drops noteref/footnote subtree marked by epub:type', () {
      const html = '<body><p>Before NOTEREFMARK'
          '<a epub:type="noteref" href="#fn1">99</a> after.</p></body>';
      final out = extractFromHtml(html, epubFilter: true);
      expect(out.contains('99'), isFalse, reason: 'footnote anchor text dropped');
      expect(out, contains('Before NOTEREFMARK'));
      expect(out, contains('after.'));
    });

    test('drops an <a> footnote ref marked by class', () {
      const html =
          '<body><p>Text <a class="footnote" href="#f">CLASSFNMARK</a> end.</p></body>';
      final out = extractFromHtml(html, epubFilter: true);
      expect(out.contains('CLASSFNMARK'), isFalse);
      expect(out, contains('Text'));
      expect(out, contains('end.'));
    });

    test('drops <rt>/<rp> ruby readings, keeps the base text', () {
      const html =
          '<body><p><ruby>漢<rt>kan</rt>字<rp>(</rp><rt>ji</rt><rp>)</rp></ruby> word.</p></body>';
      final out = extractFromHtml(html, epubFilter: true);
      expect(out.contains('kan'), isFalse);
      expect(out.contains('ji'), isFalse);
      expect(out, contains('漢'));
      expect(out, contains('字'));
      expect(out, contains('word.'));
    });

    test('image alt/title text is never read (assert-and-lock)', () {
      const html =
          '<body><p>Caption <img src="x.png" alt="ALTVANISH" title="TITLEVANISH"/> only.</p></body>';
      final out = extractFromHtml(html, epubFilter: true);
      expect(out.contains('ALTVANISH'), isFalse);
      expect(out.contains('TITLEVANISH'), isFalse);
      expect(out, contains('Caption'));
    });

    test('tables are linearized: each row one block, cells inline', () {
      const html = '<body><table>'
          '<tr><td>Cell A</td><td>Cell B</td></tr>'
          '<tr><td>Cell C</td><td>Cell D</td></tr>'
          '</table></body>';
      expect(extractFromHtml(html, epubFilter: true), 'Cell A Cell B\n\nCell C Cell D');
    });

    test('a nested table is NOT double-emitted (Story 2.6, Task 3)', () {
      // The inner cell's prose must appear once — folded into the outer cell —
      // never a second time as its own row (the descendant-tr bug).
      const html = '<body><table>'
          '<tr><td>Before <table><tr><td>Inner</td></tr></table> after</td></tr>'
          '</table></body>';
      final out = extractFromHtml(html, epubFilter: true);
      expect('Inner'.allMatches(out).length, 1);
      expect(out, contains('Before'));
      expect(out, contains('after'));
    });

    test('linearizes rows wrapped in thead/tbody', () {
      const html = '<body><table>'
          '<thead><tr><th>Head A</th><th>Head B</th></tr></thead>'
          '<tbody><tr><td>Body A</td><td>Body B</td></tr></tbody>'
          '</table></body>';
      expect(
        extractFromHtml(html, epubFilter: true),
        'Head A Head B\n\nBody A Body B',
      );
    });

    test('without the filter a plain paragraph is unchanged', () {
      const html = '<body><p>Plain text.</p></body>';
      expect(extractFromHtml(html, epubFilter: false), 'Plain text.');
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

import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/services/import/epub_extractor.dart';

import '../../fixtures/epubs/epub_fixture_builder.dart';

void main() {
  group('extractEpub — structure (AC1/AC3/AC4)', () {
    test('clean 3-chapter book → title, author, 3 chapters in reading order',
        () async {
      final parse = await extractEpub(cleanThreeChapterEpub());

      expect(parse.title, 'A Clean Book');
      expect(parse.author, 'Ada Author');
      expect(parse.chapters.length, 3);
      expect(parse.chapters.map((c) => c.title),
          ['Chapter One', 'Chapter Two', 'Chapter Three']);
      // Each chapter tokenized to at least one word.
      expect(parse.chapters.every((c) => c.tokens.isNotEmpty), isTrue);
      expect(parse.coverBytes, isNotNull);
    });

    test('no-author book → null author, still parses', () async {
      final parse = await extractEpub(noAuthorEpub());
      expect(parse.author, isNull);
      expect(parse.chapters, isNotEmpty);
    });

    test('no-cover book → null cover bytes', () async {
      final parse = await extractEpub(noCoverEpub());
      expect(parse.coverBytes, isNull);
      expect(parse.coverFormat, isNull);
      expect(parse.chapters, isNotEmpty);
    });
  });

  group('extractEpub — DOM pre-filter applied end-to-end (AC1)', () {
    test('footnote / ruby readings / img alt are dropped; prose + table survive',
        () async {
      final parse = await extractEpub(preFilterEpub());
      final words = parse.chapters
          .expand((c) => c.tokens)
          .map((t) => t.text)
          .toList();
      final joined = words.join(' ');

      // Dropped.
      expect(joined.contains('noterefmark'), isFalse);
      expect(joined.contains('kanreading'), isFalse);
      expect(joined.contains('jireading'), isFalse);
      expect(joined.contains('altvanish'), isFalse);
      // Surviving prose.
      expect(words, contains('Realprose'));
      expect(words, contains('afterword.'));
      expect(words, contains('wordtail.'));
      expect(words, contains('tailword.'));
      // Linearized table cells survived.
      expect(words, contains('Cellalpha'));
      expect(words, contains('Celldelta'));
    });
  });

  group('extractEpub — empty-content contract (AC5/ORP)', () {
    test('all-punctuation single chapter → zero tokens → emptyContent', () async {
      await expectLater(
        extractEpub(allPunctuationChapterEpub()),
        throwsA(isA<EpubEmptyContentException>()),
      );
    });

    test('empty-spine book → emptyContent', () async {
      await expectLater(
        extractEpub(emptySpineEpub()),
        throwsA(isA<EpubEmptyContentException>()),
      );
    });

    test('a zero-token chapter is filtered, prose chapter survives', () async {
      final parse = await extractEpub(mixedEmptyChapterEpub());
      // The all-punctuation "Empty" chapter is dropped before bake.
      expect(parse.chapters.length, 1);
      expect(parse.chapters.single.title, 'Real');
    });
  });

  group('extractEpub — corrupt input surfaces as a throw (AC5)', () {
    test('non-zip bytes throw (mapped to unreadable by import_service)', () async {
      await expectLater(extractEpub(corruptEpubBytes()), throwsA(anything));
    });
  });
}

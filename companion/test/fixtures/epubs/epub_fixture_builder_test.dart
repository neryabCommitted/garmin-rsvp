import 'package:epub_pro/epub_pro.dart';
import 'package:flutter_test/flutter_test.dart';

import 'epub_fixture_builder.dart';

/// Validates the synthetic fixture builder itself before the real modules
/// (epub_extractor/cover_extractor) consume it — if these round-trips fail, a
/// downstream test failure would be ambiguous.
void main() {
  test('clean 3-chapter fixture round-trips through EpubReader.readBook', () async {
    final book = await EpubReader.readBook(cleanThreeChapterEpub());

    expect(book.title, 'A Clean Book');
    expect(book.author, 'Ada Author');
    expect(book.chapters.length, 3);
    expect(book.chapters.map((c) => c.title), ['Chapter One', 'Chapter Two', 'Chapter Three']);
    expect(book.coverImage, isNotNull);
    // Chapter HTML is loaded eagerly.
    expect(book.chapters.first.htmlContent, contains('first chapter'));
  });

  test('no-cover fixture yields a null cover (no first-image fallback)', () async {
    final book = await EpubReader.readBook(noCoverEpub());
    expect(book.coverImage, isNull);
    expect(book.chapters, isNotEmpty);
  });

  test('no-author fixture yields a null author but valid chapters', () async {
    final book = await EpubReader.readBook(noAuthorEpub());
    expect(book.author, anyOf(isNull, isEmpty));
    expect(book.chapters, isNotEmpty);
  });

  test('empty-spine fixture yields zero chapters', () async {
    final book = await EpubReader.readBook(emptySpineEpub());
    expect(book.chapters, isEmpty);
  });

  test('corrupt bytes throw (not a valid zip)', () async {
    await expectLater(EpubReader.readBook(corruptEpubBytes()), throwsA(anything));
  });
}

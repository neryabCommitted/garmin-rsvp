import 'package:epub_pro/epub_pro.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:paceturner_companion/services/import/cover_extractor.dart';

import '../../fixtures/epubs/epub_fixture_builder.dart';

void main() {
  test('cover-bearing EPUB → non-empty JPEG bytes + format', () async {
    final book = await EpubReader.readBook(cleanThreeChapterEpub());
    final cover = extractCover(book);

    expect(cover, isNotNull);
    expect(cover!.bytes, isNotEmpty);
    expect(cover.format, 'jpg');
    // Re-decodable as an image.
    expect(img.decodeImage(cover.bytes), isNotNull);
  });

  test('no-cover EPUB → null', () async {
    final book = await EpubReader.readBook(noCoverEpub());
    expect(extractCover(book), isNull);
  });

  test('oversized cover is downscaled to the bounded longest side', () {
    final book = EpubBook(coverImage: img.Image(width: 1200, height: 800));
    final cover = extractCover(book);

    expect(cover, isNotNull);
    final decoded = img.decodeImage(cover!.bytes)!;
    expect(decoded.width, kMaxCoverDimension);
    expect(decoded.height, lessThanOrEqualTo(kMaxCoverDimension));
  });

  test('a within-bounds cover is not upscaled', () {
    final book = EpubBook(coverImage: img.Image(width: 100, height: 140));
    final cover = extractCover(book);

    final decoded = img.decodeImage(cover!.bytes)!;
    expect(decoded.width, 100);
    expect(decoded.height, 140);
  });
}

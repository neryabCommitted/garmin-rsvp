import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:paceturner_companion/services/import/cover_extractor.dart';

void main() {
  test('decoded cover → non-empty, re-decodable JPEG bytes + format', () {
    final cover = encodeCover(img.Image(width: 100, height: 140));

    expect(cover.bytes, isNotEmpty);
    expect(cover.format, 'jpg');
    // Re-decodable as an image.
    expect(img.decodeImage(cover.bytes), isNotNull);
  });

  test('oversized cover is downscaled to the bounded longest side', () {
    final cover = encodeCover(img.Image(width: 1200, height: 800));

    final decoded = img.decodeImage(cover.bytes)!;
    expect(decoded.width, kMaxCoverDimension);
    expect(decoded.height, lessThanOrEqualTo(kMaxCoverDimension));
  });

  test('a within-bounds cover is not upscaled', () {
    final cover = encodeCover(img.Image(width: 100, height: 140));

    final decoded = img.decodeImage(cover.bytes)!;
    expect(decoded.width, 100);
    expect(decoded.height, 140);
  });
}

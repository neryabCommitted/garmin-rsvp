/// Synthetic EPUB test-fixture builder (Story 2.4, Task 1).
///
/// Assembles **tiny, valid EPUB2 (OCF zip)** archives entirely in memory with
/// `package:archive`, so the EPUB-parse / cover / chapter ACs are testable with
/// *crafted* HTML we fully control — never a real, copyrighted book. The real
/// corpus at `/home/nerya/Desktop/epub` is for **manual exploratory testing
/// only** (2.4/2.6) and is never committed or used as a test input
/// (memory: epub-corpus-location).
///
/// Layout produced (a minimal but spec-valid OCF container):
/// ```
/// mimetype                 (STORED, first entry — OCF requirement)
/// META-INF/container.xml   → OEBPS/content.opf
/// OEBPS/content.opf        (OPF: metadata + manifest + spine, EPUB2)
/// OEBPS/toc.ncx            (NCX navMap — epub_pro needs navigation present)
/// OEBPS/chapter{i}.xhtml   (one per [FixtureChapter])
/// OEBPS/cover.png          (a ~2×2 PNG, only when withCover)
/// ```
///
/// This is test-only code (lives under `test/`), so importing `dart:typed_data`
/// + `package:archive` + `package:image` here is fine — it is NOT one of the
/// pure `compute`-run modules.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

/// One synthetic chapter: a navMap title plus the inner HTML of its `<body>`.
class FixtureChapter {
  const FixtureChapter({required this.title, required this.bodyHtml});

  /// Becomes the NCX `navLabel` text → `EpubChapter.title` → `BakeChapter.title`.
  final String title;

  /// Raw inner-HTML of the chapter's `<body>` (passed through verbatim, so tests
  /// can embed footnotes/ruby/alt/tables to exercise the AC1 pre-filter).
  final String bodyHtml;
}

/// Builds a minimal valid EPUB2 archive as bytes.
///
/// - [title]/[author] → OPF `<dc:title>`/`<dc:creator>` (omitted when null).
/// - [chapters] → one xhtml file + NCX navPoint + spine itemref each. An empty
///   list yields an empty spine and empty navMap (the AC5 empty-spine fixture).
/// - [withCover] embeds a tiny PNG and the `<meta name="cover">` wiring.
Uint8List buildEpub({
  required String? title,
  required String? author,
  required List<FixtureChapter> chapters,
  bool withCover = true,
}) {
  final archive = Archive();

  // OCF §: `mimetype` MUST be the first entry and stored (uncompressed).
  final mimetype = ascii.encode('application/epub+zip');
  archive.add(ArchiveFile.noCompress('mimetype', mimetype.length, mimetype));

  _addString(archive, 'META-INF/container.xml', _containerXml());

  for (var i = 0; i < chapters.length; i++) {
    _addString(
      archive,
      'OEBPS/chapter$i.xhtml',
      _chapterXhtml(chapters[i].title, chapters[i].bodyHtml),
    );
  }

  if (withCover) {
    _addBytes(archive, 'OEBPS/cover.png', _coverPng());
  }

  _addString(archive, 'OEBPS/toc.ncx', _ncxXml(title ?? 'Untitled', chapters));
  _addString(
    archive,
    'OEBPS/content.opf',
    _opfXml(
      title: title,
      author: author,
      chapterCount: chapters.length,
      withCover: withCover,
    ),
  );

  final bytes = ZipEncoder().encode(archive);
  return Uint8List.fromList(bytes);
}

// ── Scenario helpers (the Task 1 (a)–(f) matrix) ──────────────────────────────

/// (a) A clean 3-chapter book with a cover and an author.
Uint8List cleanThreeChapterEpub() => buildEpub(
      title: 'A Clean Book',
      author: 'Ada Author',
      chapters: const <FixtureChapter>[
        FixtureChapter(title: 'Chapter One', bodyHtml: '<p>The first chapter has plain prose.</p>'),
        FixtureChapter(title: 'Chapter Two', bodyHtml: '<p>The second chapter continues the tale.</p>'),
        FixtureChapter(title: 'Chapter Three', bodyHtml: '<p>The third and final chapter ends it.</p>'),
      ],
    );

/// (b) A book whose single chapter carries a footnote anchor, a `<rt>` ruby
/// reading, an `<img alt>`, and a `<table>` — to exercise the AC1 pre-filter.
Uint8List preFilterEpub() => buildEpub(
      title: 'Pre-filter Book',
      author: 'Note Taker',
      chapters: const <FixtureChapter>[
        FixtureChapter(
          title: 'Filtered',
          bodyHtml: '<p>Realprose before the marker'
              '<a epub:type="noteref" href="#fn1" id="fnref1">noterefmark</a> and afterword.</p>'
              '<p>Ruby <ruby>漢<rt>kanreading</rt>字<rt>jireading</rt></ruby> wordtail.</p>'
              '<p>Imagecaption <img src="pic.png" alt="altvanish"/> tailword.</p>'
              '<table><tr><td>Cellalpha</td><td>Cellbeta</td></tr>'
              '<tr><td>Cellgamma</td><td>Celldelta</td></tr></table>',
        ),
      ],
    );

/// (c) A valid book with no cover (no images at all, so epub_pro's first-image
/// cover fallback also yields nothing).
Uint8List noCoverEpub() => buildEpub(
      title: 'Cover-less Book',
      author: 'No Artist',
      withCover: false,
      chapters: const <FixtureChapter>[
        FixtureChapter(title: 'Only Chapter', bodyHtml: '<p>Some words live in this coverless book.</p>'),
      ],
    );

/// (d) A valid book with a cover but no author.
Uint8List noAuthorEpub() => buildEpub(
      title: 'Anonymous Book',
      author: null,
      chapters: const <FixtureChapter>[
        FixtureChapter(title: 'Lone Chapter', bodyHtml: '<p>Authorless yet perfectly readable prose.</p>'),
      ],
    );

/// (e) A book whose one chapter is entirely punctuation/symbols → zero tokens
/// (the ORP word-char-free-token contract; Task 3/4).
Uint8List allPunctuationChapterEpub() => buildEpub(
      title: 'Symbols Only',
      author: 'Sym Bol',
      withCover: false,
      chapters: const <FixtureChapter>[
        FixtureChapter(title: 'Punctuation', bodyHtml: '<p>!!! --- *** ??? ... ;;; ::: ###</p>'),
      ],
    );

/// (e2) A clean chapter followed by an all-punctuation chapter — proves the
/// zero-token chapter is *filtered* while the prose chapter survives.
Uint8List mixedEmptyChapterEpub() => buildEpub(
      title: 'Mixed',
      author: 'Mix Author',
      withCover: false,
      chapters: const <FixtureChapter>[
        FixtureChapter(title: 'Real', bodyHtml: '<p>This chapter has genuine words to read.</p>'),
        FixtureChapter(title: 'Empty', bodyHtml: '<p>--- !!! ;;;</p>'),
      ],
    );

/// (f1) A book with no spine items and an empty navMap → zero chapters (AC5
/// `emptyContent`).
Uint8List emptySpineEpub() =>
    buildEpub(title: 'Hollow', author: 'No One', withCover: false, chapters: const <FixtureChapter>[]);

/// (f2) Bytes that are not a valid zip at all (AC5 `unreadable`).
Uint8List corruptEpubBytes() =>
    Uint8List.fromList(<int>[0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0xFF, 0xFE]);

// ── XML/asset builders ────────────────────────────────────────────────────────

String _containerXml() => '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
    '  <rootfiles>\n'
    '    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>\n'
    '  </rootfiles>\n'
    '</container>\n';

String _chapterXhtml(String title, String bodyHtml) =>
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">\n'
    '<head><title>${_esc(title)}</title></head>\n'
    '<body>$bodyHtml</body>\n'
    '</html>\n';

String _opfXml({
  required String? title,
  required String? author,
  required int chapterCount,
  required bool withCover,
}) {
  final manifest = StringBuffer()
    ..writeln('    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>');
  if (withCover) {
    manifest.writeln('    <item id="cover-image" href="cover.png" media-type="image/png"/>');
  }
  for (var i = 0; i < chapterCount; i++) {
    manifest.writeln(
        '    <item id="chap$i" href="chapter$i.xhtml" media-type="application/xhtml+xml"/>');
  }

  final spine = StringBuffer();
  for (var i = 0; i < chapterCount; i++) {
    spine.writeln('    <itemref idref="chap$i"/>');
  }

  final meta = StringBuffer()
    ..writeln('    <dc:identifier id="bookid">urn:uuid:test-fixture</dc:identifier>')
    ..writeln('    <dc:language>en</dc:language>');
  if (title != null) {
    meta.writeln('    <dc:title>${_esc(title)}</dc:title>');
  }
  if (author != null) {
    meta.writeln('    <dc:creator opf:role="aut">${_esc(author)}</dc:creator>');
  }
  if (withCover) {
    meta.writeln('    <meta name="cover" content="cover-image"/>');
  }

  return '<?xml version="1.0" encoding="utf-8"?>\n'
      '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid">\n'
      '  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:opf="http://www.idpf.org/2007/opf">\n'
      '$meta'
      '  </metadata>\n'
      '  <manifest>\n'
      '$manifest'
      '  </manifest>\n'
      '  <spine toc="ncx">\n'
      '$spine'
      '  </spine>\n'
      '</package>\n';
}

String _ncxXml(String title, List<FixtureChapter> chapters) {
  final navPoints = StringBuffer();
  for (var i = 0; i < chapters.length; i++) {
    navPoints
      ..writeln('    <navPoint id="navpoint-$i" playOrder="${i + 1}">')
      ..writeln('      <navLabel><text>${_esc(chapters[i].title)}</text></navLabel>')
      ..writeln('      <content src="chapter$i.xhtml"/>')
      ..writeln('    </navPoint>');
  }

  return '<?xml version="1.0" encoding="utf-8"?>\n'
      '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">\n'
      '  <head>\n'
      '    <meta name="dtb:uid" content="urn:uuid:test-fixture"/>\n'
      '  </head>\n'
      '  <docTitle><text>${_esc(title)}</text></docTitle>\n'
      '  <navMap>\n'
      '$navPoints'
      '  </navMap>\n'
      '</ncx>\n';
}

/// A tiny 2×2 opaque-blue PNG.
Uint8List _coverPng() {
  final image = img.Image(width: 2, height: 2);
  img.fill(image, color: img.ColorRgb8(20, 80, 200));
  return img.encodePng(image);
}

void _addString(Archive archive, String name, String content) {
  archive.add(ArchiveFile.string(name, content));
}

void _addBytes(Archive archive, String name, Uint8List data) {
  archive.add(ArchiveFile.bytes(name, data));
}

/// Minimal XML text escaping for the values we inject into OPF/NCX.
String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

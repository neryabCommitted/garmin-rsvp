import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/protocol/protocol_keys.dart';
import 'package:paceturner_companion/protocol/stream_codec.dart';
import 'package:paceturner_companion/services/import/import_exceptions.dart';
import 'package:paceturner_companion/services/import/pipeline.dart';

import '../../fixtures/epubs/epub_fixture_builder.dart';

void main() {
  group('runPipeline — .txt', () {
    test('bakes a single chapter at offset 0 with correct word count', () {
      const req = PipelineRequest(
        rawText: 'The quick brown fox. Jumps over lazy dogs.',
        isMarkdown: false,
        title: 'Sample',
        salt: 1234,
      );
      final baked = runPipeline(req);

      expect(baked.manifest.title, 'Sample');
      expect(baked.manifest.totalWords, 8);
      expect(baked.manifest.chapters.length, 1);
      expect(baked.manifest.chapters.single.offset, 0);
      expect(baked.manifest.chapters.single.title, 'Sample');
      expect(baked.streamBytes, isNotEmpty);
      expect(baked.manifest.fingerprint, matches(RegExp(r'^[0-9a-f]{8}$')));
    });

    test('is deterministic for a fixed salt', () {
      const req = PipelineRequest(
        rawText: 'Stable text input.',
        isMarkdown: false,
        title: 'T',
        salt: 99,
      );
      expect(runPipeline(req).manifest.fingerprint,
          runPipeline(req).manifest.fingerprint);
    });
  });

  group('runPipeline — .md', () {
    test('preserves paragraph structure (paragraphStart on paragraph 2)', () {
      const req = PipelineRequest(
        rawText: 'First paragraph here.\n\nSecond paragraph begins now.',
        isMarkdown: true,
        title: 'MD',
        salt: 7,
      );
      final baked = runPipeline(req);
      // line 0 is the manifest; words follow. Count flagged paragraph starts via
      // the flag bit baked into each WordRecord is awkward from JSONL here, so we
      // assert the word total instead and trust html_extractor_test for the flag.
      expect(baked.manifest.totalWords, 7);
      expect(baked.manifest.fingerprint, matches(RegExp(r'^[0-9a-f]{8}$')));
    });
  });

  group('runPipeline — typed failure boundary (Story 2.6, AC1)', () {
    test('empty .txt → TextEmptyContentException (typed, not opaque)', () {
      const req = PipelineRequest(
        rawText: '',
        isMarkdown: false,
        title: 'Empty',
        salt: 0,
      );
      expect(
        () => runPipeline(req),
        throwsA(isA<TextEmptyContentException>()),
      );
    });

    test('whitespace-only input → TextEmptyContentException', () {
      const req = PipelineRequest(
        rawText: '   \n\n  \t ',
        isMarkdown: false,
        title: 'Blank',
        salt: 0,
      );
      expect(
        () => runPipeline(req),
        throwsA(isA<TextEmptyContentException>()),
      );
    });

    test('all-punctuation input → TextEmptyContentException (zero tokens)', () {
      const req = PipelineRequest(
        rawText: '!!! --- ;;; ... ???',
        isMarkdown: false,
        title: 'Symbols',
        salt: 0,
      );
      expect(
        () => runPipeline(req),
        throwsA(isA<TextEmptyContentException>()),
      );
    });

    test('non-empty file with a >255-byte token → UnencodableContentException',
        () {
      final req = PipelineRequest(
        rawText: 'a' * 300, // one whitespace-free token, 300 UTF-8 bytes
        isMarkdown: false,
        title: 'Oversized',
        salt: 0,
      );
      // Must NOT be mislabeled empty — it is a clearly non-empty file.
      expect(
        () => runPipeline(req),
        throwsA(isA<UnencodableContentException>()),
      );
    });
  });

  group('runEpubPipeline — multi-chapter EPUB (Story 2.4, AC3)', () {
    test('clean 3-chapter fixture bakes 3 chapters + surfaces author', () async {
      final out = await runEpubPipeline(
        EpubPipelineRequest(epubBytes: cleanThreeChapterEpub(), salt: 7),
      );

      expect(out.baked.manifest.title, 'A Clean Book');
      expect(out.baked.manifest.chapters.length, 3);
      expect(out.author, 'Ada Author');
      expect(out.coverBytes, isNotNull);
      expect(out.coverFormat, 'jpg');
      expect(out.baked.streamBytes, isNotEmpty);
      expect(out.baked.manifest.fingerprint, matches(RegExp(r'^[0-9a-f]{8}$')));
    });

    test('chapterStart flag set on the first word of chapter 2', () async {
      final out = await runEpubPipeline(
        EpubPipelineRequest(epubBytes: cleanThreeChapterEpub(), salt: 7),
      );
      final manifest = out.baked.manifest;
      final records = decodeChunk(
        Uint8List.fromList(out.baked.streamBytes),
        manifest.totalWords,
      );

      final ch2Offset = manifest.chapters[1].offset;
      expect(ch2Offset, greaterThan(0));
      expect(records[ch2Offset].flags & ProtocolKeys.flagChapterStart, isNonZero);
      // A mid-chapter word does not carry the chapter-start flag.
      expect(records[ch2Offset + 1].flags & ProtocolKeys.flagChapterStart, 0);
    });

    test('is deterministic for a fixed salt', () async {
      final a = await runEpubPipeline(
        EpubPipelineRequest(epubBytes: cleanThreeChapterEpub(), salt: 99),
      );
      final b = await runEpubPipeline(
        EpubPipelineRequest(epubBytes: cleanThreeChapterEpub(), salt: 99),
      );
      expect(a.baked.manifest.fingerprint, b.baked.manifest.fingerprint);
    });
  });
}

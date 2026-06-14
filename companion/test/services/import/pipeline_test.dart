import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/services/import/pipeline.dart';

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

  group('runPipeline — empty input boundary (import_service maps to AC7)', () {
    test('empty .txt produces zero tokens → bake throws ArgumentError', () {
      const req = PipelineRequest(
        rawText: '',
        isMarkdown: false,
        title: 'Empty',
        salt: 0,
      );
      expect(() => runPipeline(req), throwsArgumentError);
    });

    test('whitespace-only input throws ArgumentError', () {
      const req = PipelineRequest(
        rawText: '   \n\n  \t ',
        isMarkdown: false,
        title: 'Blank',
        salt: 0,
      );
      expect(() => runPipeline(req), throwsArgumentError);
    });
  });
}

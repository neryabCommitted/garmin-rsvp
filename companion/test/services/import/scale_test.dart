import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/protocol/stream_codec.dart';
import 'package:paceturner_companion/services/import/pipeline.dart';

/// NFR5 (AC4): a ~100k-word file imports correctly. The non-block is **structural**
/// (bake runs in a `compute` isolate, never on the UI thread), so we prove
/// throughput/correctness here rather than gate on a flaky wall-clock. The
/// ≤30 s target is validated manually on-device; the soft bound below only
/// catches a pathological regression.
void main() {
  test('100k-word input bakes correctly and the stream round-trips', () {
    const targetWords = 100000;
    final buffer = StringBuffer();
    for (var i = 0; i < targetWords; i++) {
      buffer.write('word$i');
      // Sentence end roughly every 12 words.
      buffer.write((i % 12 == 11) ? '. ' : ' ');
      // Paragraph break roughly every 60 words.
      if (i % 60 == 59) buffer.write('\n\n');
    }

    final sw = Stopwatch()..start();
    final baked = runPipeline(PipelineRequest(
      rawText: buffer.toString(),
      isMarkdown: false,
      title: 'Big Book',
      salt: 1,
    ));
    sw.stop();

    expect(baked.manifest.totalWords, targetWords);
    expect(baked.manifest.fingerprint, matches(RegExp(r'^[0-9a-f]{8}$')));
    expect(baked.streamBytes, isNotEmpty);

    // Well-formed: the binary stream decodes back to exactly totalWords records.
    final decoded = decodeChunk(baked.streamBytes, baked.manifest.totalWords);
    expect(decoded.length, targetWords);

    // Soft pathological-regression guard only — NOT the NFR5 on-device gate.
    expect(sw.elapsed, lessThan(const Duration(seconds: 120)),
        reason: 'pure bake of 100k words should be far under 120s');
  });
}

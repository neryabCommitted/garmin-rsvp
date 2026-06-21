/// Generator for the Epic 3 dev-stream fixture. Run from the `companion/` dir:
///
///     dart run test/fixtures/streams/generate.dart
///
/// It bakes [buildDevSampleBook] and writes three sibling artifacts next to this
/// file:
///   - `dev_sample_book.stream`        — SPEC §5 binary word stream (the file the
///                                        watch dev path bundles / serves).
///   - `dev_sample_book.manifest.json` — SPEC §4.1 manifest (title, totals, fp,
///                                        chapter index) — human-readable.
///   - `dev_sample_book.jsonl`         — line-delimited debug master (line 0 =
///                                        manifest, 1..n = one word each).
///
/// The output is deterministic (fixed salt), so re-running produces byte-
/// identical files; `dev_sample_book_test.dart` is the drift guard that fails if
/// the committed `.stream` ever diverges from a fresh bake.
library;

import 'dart:convert';
import 'dart:io';

import 'package:paceturner_companion/protocol/protocol_keys.dart';

import 'dev_sample_book.dart';

void main() {
  final baked = buildDevSampleBook();
  final dir = File.fromUri(Platform.script).parent.path;

  File('$dir/dev_sample_book.stream').writeAsBytesSync(baked.streamBytes);
  File('$dir/dev_sample_book.jsonl')
      .writeAsStringSync('${baked.debugJsonl.join('\n')}\n');

  final m = baked.manifest;
  const encoder = JsonEncoder.withIndent('  ');
  File('$dir/dev_sample_book.manifest.json').writeAsStringSync('${encoder.convert(<String, Object?>{
        ProtocolKeys.keyTitle: m.title,
        ProtocolKeys.keyTotalWords: m.totalWords,
        ProtocolKeys.keyTotalBonusMs: m.totalBonusMs,
        ProtocolKeys.keyFingerprint: m.fingerprint,
        ProtocolKeys.keyChapters: [
          for (final ch in m.chapters)
            <String, Object?>{
              ProtocolKeys.keyChapterOffset: ch.offset,
              ProtocolKeys.keyTitle: ch.title,
              ProtocolKeys.keyChapterCumBonusMs: ch.cumulativeBonusMs,
            },
        ],
      })}\n');

  stdout.writeln('Wrote dev_sample_book.{stream,manifest.json,jsonl} '
      '— ${m.totalWords} words, ${m.chapters.length} chapters, '
      'fp ${m.fingerprint}, ${baked.streamBytes.length} stream bytes.');
}

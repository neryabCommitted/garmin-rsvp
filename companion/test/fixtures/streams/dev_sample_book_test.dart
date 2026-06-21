/// Drift guard + structural contract for the Epic 3 dev-stream fixture.
///
/// The committed `dev_sample_book.stream` is consumed by Epic 3 (Story 3.1/3.2)
/// as a canned word source. This test fails if the committed artifact ever
/// diverges from a fresh bake of [buildDevSampleBook] (regenerate with
/// `dart run test/fixtures/streams/generate.dart`), and pins the structural
/// properties Epic 3 relies on when rendering.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/protocol/protocol_keys.dart';
import 'package:paceturner_companion/protocol/stream_codec.dart';

import 'dev_sample_book.dart';

void main() {
  final baked = buildDevSampleBook();
  final dir = Directory.current.path.endsWith('companion')
      ? '${Directory.current.path}/test/fixtures/streams'
      : 'test/fixtures/streams';
  final streamFile = File('$dir/dev_sample_book.stream');

  test('committed .stream matches a fresh bake (regenerate if this fails)', () {
    expect(
      streamFile.existsSync(),
      isTrue,
      reason: 'run: dart run test/fixtures/streams/generate.dart',
    );
    expect(
      streamFile.readAsBytesSync(),
      orderedEquals(baked.streamBytes),
      reason: 'fixture drifted from the pipeline — regenerate it',
    );
  });

  test('manifest exposes the 3 chapters with a valid SPEC §4.1 index', () {
    final m = baked.manifest;
    expect(m.title, kDevSampleTitle);
    expect(m.chapters.length, 3);
    // ch[0] anchored at 0; offsets strictly increasing and < totalWords.
    expect(m.chapters.first.offset, 0);
    expect(m.chapters.first.cumulativeBonusMs, 0);
    for (var i = 1; i < m.chapters.length; i++) {
      expect(m.chapters[i].offset, greaterThan(m.chapters[i - 1].offset));
      expect(m.chapters[i].offset, lessThan(m.totalWords));
    }
    expect(m.fingerprint, matches(RegExp(r'^[0-9a-f]{8}$')));
  });

  test('stream round-trips and carries the flags Epic 3 reads', () {
    final records = decodeChunk(baked.streamBytes, baked.manifest.totalWords);
    expect(records.length, baked.manifest.totalWords);

    // Every manifest chapter offset is flagged chapterStart in the stream.
    for (final ch in baked.manifest.chapters) {
      expect(
        records[ch.offset].flags & ProtocolKeys.flagChapterStart,
        isNonZero,
        reason: 'word ${ch.offset} ("${ch.title}") must be a chapter start',
      );
    }

    // The terminal-boundary guarantee (Story 2.1): the very last word of the
    // book carries sentenceEnd, so Epic 3's coast-pause / rewind has a real
    // boundary at the true end without a read-time atEnd() recompute.
    expect(
      records.last.flags & ProtocolKeys.flagSentenceEnd,
      isNonZero,
      reason: 'last word must be baked sentenceEnd (2.1 terminal boundary)',
    );

    // At least one paragraph start beyond the chapter heads (blank-line breaks).
    expect(
      records.where((r) => r.flags & ProtocolKeys.flagParagraphStart != 0),
      hasLength(greaterThan(baked.manifest.chapters.length)),
    );
  });

  test('exercises long-word handling (FR7) — a >20-char token survives the wire',
      () {
    final records = decodeChunk(baked.streamBytes, baked.manifest.totalWords);
    expect(
      records.any((r) => r.word == 'counterrevolutionaries'),
      isTrue,
      reason: 'the long word must bake + decode intact for FR7 render tests',
    );
  });
}

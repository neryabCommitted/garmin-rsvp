import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/protocol/protocol_keys.dart';
import 'package:paceturner_companion/protocol/stream_codec.dart';
import 'package:paceturner_companion/services/import/fingerprint.dart';
import 'package:paceturner_companion/services/import/orp.dart';
import 'package:paceturner_companion/services/import/pacing.dart';
import 'package:paceturner_companion/services/import/tokenizer.dart';
import 'package:paceturner_companion/services/import/word_stream_baker.dart';

/// Story 2.2 AC3/AC4/AC5/AC6 — the bake orchestrator: tokens → `WordRecord`s →
/// SPEC §5 stream (via the existing `encodeChunk`), §4.1 manifest, §7
/// fingerprint, and a JSONL debug master. We cross-check against the real
/// `orpPivot`/`bonusMsForWord` (not re-pinned numbers) so this test owns the
/// orchestration contract, and round-trip through `decodeChunk` (AC4).

const _salt = 12345;

BakeChapter _ch(String title, List<Token> tokens) =>
    BakeChapter(title: title, tokens: tokens);

Token _t(String text, {bool paragraphStart = false, bool sentenceEnd = false}) =>
    Token(text: text, paragraphStart: paragraphStart, sentenceEnd: sentenceEnd);

/// The two-chapter fixture used across the orchestration tests.
List<BakeChapter> _fixture() => [
      _ch('One', [
        _t('Hello', paragraphStart: true),
        _t('world.', sentenceEnd: true),
      ]),
      _ch('Two', [
        _t('Second', paragraphStart: true),
        _t('chapter.', sentenceEnd: true),
      ]),
    ];

void main() {
  group('bake — value types (AC6 idiom)', () {
    test('BakeChapter / ChapterEntry == and hashCode by value', () {
      final a = _ch('X', [_t('hi')]);
      final b = _ch('X', [_t('hi')]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      const e1 = ChapterEntry(offset: 0, title: 'A', cumulativeBonusMs: 0);
      const e2 = ChapterEntry(offset: 0, title: 'A', cumulativeBonusMs: 0);
      expect(e1, equals(e2));
      expect(e1.hashCode, equals(e2.hashCode));
    });
  });

  group('bake — stream + records (AC3, AC4)', () {
    test('round-trips: decodeChunk(streamBytes, tw) == baker records', () {
      final baked = bake(title: 'Book', chapters: _fixture(), salt: _salt);

      // Reconstruct the records the baker MUST have produced, using the real
      // unit functions for orp/bonus and the SPEC §6 flag mapping.
      final expected = <WordRecord>[
        WordRecord(
          word: 'Hello',
          flags: ProtocolKeys.flagParagraphStart | ProtocolKeys.flagChapterStart,
          orpPivot: orpPivot('Hello'),
          bonusMs: bonusMsForWord(_t('Hello', paragraphStart: true)),
        ),
        WordRecord(
          word: 'world.',
          flags: ProtocolKeys.flagSentenceEnd,
          orpPivot: orpPivot('world.'),
          bonusMs: bonusMsForWord(_t('world.', sentenceEnd: true)),
        ),
        WordRecord(
          word: 'Second',
          flags: ProtocolKeys.flagParagraphStart | ProtocolKeys.flagChapterStart,
          orpPivot: orpPivot('Second'),
          bonusMs: bonusMsForWord(_t('Second', paragraphStart: true)),
        ),
        WordRecord(
          word: 'chapter.',
          flags: ProtocolKeys.flagSentenceEnd,
          orpPivot: orpPivot('chapter.'),
          bonusMs: bonusMsForWord(_t('chapter.', sentenceEnd: true)),
        ),
      ];

      expect(baked.streamBytes, equals(encodeChunk(expected)));
      expect(decodeChunk(baked.streamBytes, baked.manifest.totalWords),
          equals(expected));
    });

    test('flagChapterStart marks the first word of every chapter only', () {
      final baked = bake(title: 'Book', chapters: _fixture(), salt: _salt);
      final records = decodeChunk(baked.streamBytes, 4);
      bool chapterStart(int i) =>
          records[i].flags & ProtocolKeys.flagChapterStart != 0;
      expect(chapterStart(0), isTrue); // ch "One" first word
      expect(chapterStart(1), isFalse);
      expect(chapterStart(2), isTrue); // ch "Two" first word
      expect(chapterStart(3), isFalse);
    });

    test('reserved flag bits stay 0 (encodeChunk would otherwise throw)', () {
      final baked = bake(title: 'Book', chapters: _fixture(), salt: _salt);
      for (final r in decodeChunk(baked.streamBytes, 4)) {
        expect(r.flags & ProtocolKeys.flagsReservedMask, 0);
      }
    });
  });

  group('bake — manifest (AC5)', () {
    test('SPEC §4.1 shape: tw, tb, fingerprint, chapter offsets & cum bonuses',
        () {
      final baked = bake(title: 'Book', chapters: _fixture(), salt: _salt);
      final m = baked.manifest;

      expect(m.title, 'Book');
      expect(m.totalWords, 4);

      final bonuses = [
        bonusMsForWord(_t('Hello', paragraphStart: true)),
        bonusMsForWord(_t('world.', sentenceEnd: true)),
        bonusMsForWord(_t('Second', paragraphStart: true)),
        bonusMsForWord(_t('chapter.', sentenceEnd: true)),
      ];
      expect(m.totalBonusMs, bonuses.reduce((a, b) => a + b));

      expect(m.chapters, hasLength(2));
      expect(m.chapters[0].offset, 0);
      expect(m.chapters[0].title, 'One');
      expect(m.chapters[0].cumulativeBonusMs, 0); // ch[0].cb == 0
      expect(m.chapters[1].offset, 2);
      expect(m.chapters[1].title, 'Two');
      // cumulative bonus of all words BEFORE offset 2.
      expect(m.chapters[1].cumulativeBonusMs, bonuses[0] + bonuses[1]);

      // Strictly increasing offsets, all < tw (SPEC §4.1).
      expect(m.chapters[0].offset < m.chapters[1].offset, isTrue);
      expect(m.chapters.last.offset < m.totalWords, isTrue);
    });

    test('fingerprint is the §7 fp of the encoded stream + salt', () {
      final baked = bake(title: 'Book', chapters: _fixture(), salt: _salt);
      expect(baked.manifest.fingerprint,
          fingerprint(baked.streamBytes, salt: _salt));
      expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(baked.manifest.fingerprint),
          isTrue);
    });

    test('a different salt yields a different fingerprint (re-bake, SPEC §7)',
        () {
      final a = bake(title: 'Book', chapters: _fixture(), salt: 1);
      final b = bake(title: 'Book', chapters: _fixture(), salt: 2);
      expect(a.streamBytes, equals(b.streamBytes)); // same content
      expect(a.manifest.fingerprint, isNot(b.manifest.fingerprint));
    });
  });

  group('bake — bounds-check-and-degrade (NFR8, Task 5)', () {
    test('no chapters → typed ArgumentError (never reaches encodeChunk)', () {
      expect(() => bake(title: 'x', chapters: const [], salt: _salt),
          throwsArgumentError);
    });

    test('a chapter with zero tokens → typed ArgumentError', () {
      expect(
        () => bake(
          title: 'x',
          chapters: [
            _ch('Empty', const []),
          ],
          salt: _salt,
        ),
        throwsArgumentError,
      );
    });

    test('single-word book: tw=1, ch[0].o==0 & cb==0, round-trips', () {
      final baked = bake(
        title: 'Tiny',
        chapters: [
          _ch('Only', [_t('word', paragraphStart: true, sentenceEnd: true)]),
        ],
        salt: _salt,
      );
      expect(baked.manifest.totalWords, 1);
      expect(baked.manifest.chapters.single.offset, 0);
      expect(baked.manifest.chapters.single.cumulativeBonusMs, 0);
      final records = decodeChunk(baked.streamBytes, 1);
      expect(records.single.word, 'word');
      expect(records.single.flags & ProtocolKeys.flagChapterStart, isNot(0));
    });

    test('single-word chapters: strictly increasing offsets, each chapterStart',
        () {
      final baked = bake(
        title: 'Three',
        chapters: [
          _ch('A', [_t('alpha')]),
          _ch('B', [_t('beta')]),
          _ch('C', [_t('gamma', sentenceEnd: true)]),
        ],
        salt: _salt,
      );
      final offsets = baked.manifest.chapters.map((c) => c.offset).toList();
      expect(offsets, [0, 1, 2]);
      final records = decodeChunk(baked.streamBytes, 3);
      for (final r in records) {
        expect(r.flags & ProtocolKeys.flagChapterStart, isNot(0));
      }
    });

    test('multi-byte grapheme, long word & punctuation all bake & round-trip',
        () {
      final longWord = 'a' * 50; // >14 chars → length cap; <=255 bytes
      final chapters = [
        _ch('Edge', [
          _t('é', paragraphStart: true), // single 2-byte grapheme
          _t('שלום'), // RTL multi-byte
          _t(longWord),
          _t('"quoted,"'),
          _t(longWord, sentenceEnd: true),
        ]),
      ];
      final baked = bake(title: 'Edges', chapters: chapters, salt: _salt);

      // If any record were wire-invalid, encodeChunk inside bake() would have
      // thrown — reaching here proves wordLen/pivot/bonus/flags all validate.
      final records = decodeChunk(baked.streamBytes, 5);
      for (final r in records) {
        expect(r.bonusMs, inInclusiveRange(0, 65535), reason: r.word);
      }
      // The long word hits the bonus length cap (170% * 200 = 340 ms).
      expect(records[2].bonusMs, 340);
    });

    test('a pathological >255-byte word surfaces encodeChunk ArgumentError', () {
      // The tokenizer never emits this; documenting the codec contract — a word
      // the wire cannot carry is a typed baking failure, not a silent mangle.
      expect(
        () => bake(
          title: 'x',
          chapters: [
            _ch('big', [_t('a' * 256, sentenceEnd: true)]),
          ],
          salt: _salt,
        ),
        throwsArgumentError,
      );
    });
  });

  group('bake — JSONL debug master (AC3)', () {
    test('one manifest line + one line per word, all valid JSON', () {
      final baked = bake(title: 'Book', chapters: _fixture(), salt: _salt);
      expect(baked.debugJsonl, hasLength(1 + 4)); // manifest + 4 words

      final header = jsonDecode(baked.debugJsonl.first) as Map<String, dynamic>;
      expect(header[ProtocolKeys.keyTitle], 'Book');
      expect(header[ProtocolKeys.keyTotalWords], 4);
      expect(header[ProtocolKeys.keyFingerprint], baked.manifest.fingerprint);

      final firstWord =
          jsonDecode(baked.debugJsonl[1]) as Map<String, dynamic>;
      expect(firstWord['i'], 0);
      expect(firstWord['w'], 'Hello');
      expect(firstWord['ch'], 0);
      final lastWord = jsonDecode(baked.debugJsonl[4]) as Map<String, dynamic>;
      expect(lastWord['i'], 3);
      expect(lastWord['ch'], 1); // belongs to chapter index 1
    });
  });
}

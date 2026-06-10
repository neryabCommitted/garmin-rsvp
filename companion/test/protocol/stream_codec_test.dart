import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/protocol/protocol_keys.dart';
import 'package:paceturner_companion/protocol/stream_codec.dart';

/// Conformance tests pinned to protocol/examples/word-records.md (SPEC §5/§6).
/// The hex below is the normative 32-byte fixture; the watch pins the same
/// bytes in watch/source-test/ProtocolTest.mc, so drift on either side fails
/// against the shared example, not against the other implementation.

Uint8List hexBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

final Uint8List examplePayload = hexBytes(
  '0406010000506163650500010000'
  '7475726e730801025e01d7a9d79cd795d79d',
);

const exampleRecords = [
  WordRecord(
    word: 'Pace',
    flags: ProtocolKeys.flagParagraphStart | ProtocolKeys.flagChapterStart,
    orpPivot: 1,
    bonusMs: 0,
  ),
  WordRecord(word: 'turns', flags: 0, orpPivot: 1, bonusMs: 0),
  WordRecord(
    word: 'שלום',
    flags: ProtocolKeys.flagSentenceEnd,
    orpPivot: 2, // byte index: start of the 2nd character's 2-byte sequence
    bonusMs: 350,
  ),
];

void main() {
  group('encodeChunk (SPEC §5)', () {
    test('encodes the worked example to its exact bytes (AC3)', () {
      expect(encodeChunk(exampleRecords), equals(examplePayload));
    });

    test('rejects a word longer than 255 UTF-8 bytes', () {
      expect(
        () => encodeChunk([
          WordRecord(word: 'a' * 256, flags: 0, orpPivot: 0, bonusMs: 0),
        ]),
        throwsArgumentError,
      );
    });

    test('rejects an empty word', () {
      expect(
        () => encodeChunk(
          const [WordRecord(word: '', flags: 0, orpPivot: 0, bonusMs: 0)],
        ),
        throwsArgumentError,
      );
    });

    test('rejects an out-of-range orpPivot (byte index, SPEC §5)', () {
      expect(
        () => encodeChunk(
          const [WordRecord(word: 'ab', flags: 0, orpPivot: 2, bonusMs: 0)],
        ),
        throwsArgumentError,
      );
    });

    test('rejects bonusMs outside u16 range', () {
      expect(
        () => encodeChunk(
          const [WordRecord(word: 'a', flags: 0, orpPivot: 0, bonusMs: 65536)],
        ),
        throwsArgumentError,
      );
    });

    test('rejects reserved flag bits (SPEC §6: must be 0 in v1)', () {
      expect(
        () => encodeChunk([
          const WordRecord(
            word: 'a',
            flags: ProtocolKeys.flagContinuation,
            orpPivot: 0,
            bonusMs: 0,
          ),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('decodeChunk (SPEC §5)', () {
    test('decodes the worked example, every field (AC3)', () {
      final records = decodeChunk(examplePayload, 3);
      expect(records, hasLength(3));
      for (var i = 0; i < 3; i++) {
        expect(records[i].word, exampleRecords[i].word, reason: 'word $i');
        expect(records[i].flags, exampleRecords[i].flags, reason: 'flags $i');
        expect(
          records[i].orpPivot,
          exampleRecords[i].orpPivot,
          reason: 'orpPivot $i',
        );
        expect(
          records[i].bonusMs,
          exampleRecords[i].bonusMs,
          reason: 'bonusMs $i',
        );
      }
    });

    test('round-trips: decode(encode(records)) == records', () {
      expect(decodeChunk(encodeChunk(exampleRecords), 3), exampleRecords);
    });

    test('rejects a payload truncated mid-header', () {
      expect(
        () => decodeChunk(examplePayload.sublist(0, 3), 1),
        throwsA(isA<StreamDecodeException>()),
      );
    });

    test('rejects a payload truncated mid-word', () {
      expect(
        () => decodeChunk(examplePayload.sublist(0, 7), 1),
        throwsA(isA<StreamDecodeException>()),
      );
    });

    test('rejects fewer records than n', () {
      expect(
        () => decodeChunk(examplePayload.sublist(0, 9), 2),
        throwsA(isA<StreamDecodeException>()),
      );
    });

    test('rejects trailing bytes (SPEC §4.3 exact-consumption rule)', () {
      expect(
        () => decodeChunk(examplePayload, 2),
        throwsA(isA<StreamDecodeException>()),
      );
    });

    test('rejects wordLen 0 (SPEC §5)', () {
      expect(
        () => decodeChunk(hexBytes('0000000000'), 1),
        throwsA(isA<StreamDecodeException>()),
      );
    });

    test('rejects orpPivot >= wordLen (SPEC §5)', () {
      expect(
        () => decodeChunk(hexBytes('010001000041'), 1),
        throwsA(isA<StreamDecodeException>()),
      );
    });

    test('rejects reserved flag bits set (SPEC §6 degrade case)', () {
      // 0x08 = continuation, reserved in v1.
      expect(
        () => decodeChunk(hexBytes('010800000041'), 1),
        throwsA(isA<StreamDecodeException>()),
      );
    });

    test('rejects invalid UTF-8 word bytes', () {
      // wordLen 1 with lone continuation byte 0x80.
      expect(
        () => decodeChunk(hexBytes('010000000080'), 1),
        throwsA(isA<StreamDecodeException>()),
      );
    });

    test('rejects n < 1', () {
      expect(
        () => decodeChunk(Uint8List(0), 0),
        throwsA(isA<StreamDecodeException>()),
      );
    });
  });
}

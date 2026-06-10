import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/protocol/envelope_codec.dart';
import 'package:paceturner_companion/protocol/protocol_keys.dart';

/// Conformance tests pinned to protocol/examples/envelopes.md (SPEC §3/§4).
/// Literal keys and values are asserted on purpose: constant drift in
/// protocol_keys.dart must fail this suite, not a code review.

final Uint8List exampleChunkBytes = Uint8List.fromList(const [
  0x04, 0x06, 0x01, 0x00, 0x00, 0x50, 0x61, 0x63, 0x65, //
  0x05, 0x00, 0x01, 0x00, 0x00, 0x74, 0x75, 0x72, 0x6E, 0x73, //
  0x08, 0x01, 0x02, 0x5E, 0x01, 0xD7, 0xA9, 0xD7, 0x9C, 0xD7, 0x95, 0xD7, 0x9D,
]);

Map<String, Object?> exampleChunkRequest() => <String, Object?>{
      't': 'chunkRequest',
      'v': 1,
      'fp': '9f86d081',
      'off': 1000,
      'n': 3,
    };

void main() {
  test('constants match the spec literals (AC2 drift detection)', () {
    expect(ProtocolKeys.protocolVersion, 1);
    expect(ProtocolKeys.keyType, 't');
    expect(ProtocolKeys.keyVersion, 'v');
    expect(ProtocolKeys.keyFingerprint, 'fp');
    expect(ProtocolKeys.keyOffset, 'off');
    expect(ProtocolKeys.keyCount, 'n');
    expect(ProtocolKeys.keyPayload, 'p');
    expect(ProtocolKeys.msgManifest, 'manifest');
    expect(ProtocolKeys.msgChunkRequest, 'chunkRequest');
    expect(ProtocolKeys.msgChunkData, 'chunkData');
    expect(ProtocolKeys.msgPosition, 'position');
    expect(ProtocolKeys.msgError, 'error');
    expect(ProtocolKeys.keyTitle, 'ti');
    expect(ProtocolKeys.keyTotalWords, 'tw');
    expect(ProtocolKeys.keyTotalBonusMs, 'tb');
    expect(ProtocolKeys.keyChapters, 'ch');
    expect(ProtocolKeys.keyChapterOffset, 'o');
    expect(ProtocolKeys.keyChapterCumBonusMs, 'cb');
    expect(ProtocolKeys.keyTimestamp, 'ts');
    expect(ProtocolKeys.keySource, 'src');
    expect(ProtocolKeys.srcWatch, 'watch');
    expect(ProtocolKeys.srcPhone, 'phone');
    expect(ProtocolKeys.keyErrorCode, 'c');
    expect(ProtocolKeys.keyErrorMessage, 'm');
    expect(ProtocolKeys.flagSentenceEnd, 0x01);
    expect(ProtocolKeys.flagParagraphStart, 0x02);
    expect(ProtocolKeys.flagChapterStart, 0x04);
    expect(ProtocolKeys.flagContinuation, 0x08);
    expect(ProtocolKeys.flagRtl, 0x10);
    expect(ProtocolKeys.flagsReservedMask, 0xF8);
    expect(ProtocolKeys.errVersionMismatch, 'versionMismatch');
    expect(ProtocolKeys.errUnknownType, 'unknownType');
    expect(ProtocolKeys.errMalformedEnvelope, 'malformedEnvelope');
    expect(ProtocolKeys.errUnknownFingerprint, 'unknownFingerprint');
    expect(ProtocolKeys.errRangeUnavailable, 'rangeUnavailable');
    expect(ProtocolKeys.errDecodeFailure, 'decodeFailure');
    expect(ProtocolKeys.errInternal, 'internal');
  });

  group('builders match the spec examples (SPEC §4)', () {
    test('manifest (SPEC §4.1)', () {
      final envelope = manifestEnvelope(
        fingerprint: '9f86d081',
        title: 'Example Book',
        totalWords: 50000,
        totalBonusMs: 412350,
        chapters: const [
          ChapterEntry(offset: 0, title: 'Chapter 1', cumBonusMs: 0),
          ChapterEntry(offset: 1000, title: 'Chapter 2', cumBonusMs: 8350),
        ],
      );
      expect(envelope, <String, Object?>{
        't': 'manifest',
        'v': 1,
        'fp': '9f86d081',
        'p': <String, Object?>{
          'ti': 'Example Book',
          'tw': 50000,
          'tb': 412350,
          'ch': <Object?>[
            <String, Object?>{'o': 0, 'ti': 'Chapter 1', 'cb': 0},
            <String, Object?>{'o': 1000, 'ti': 'Chapter 2', 'cb': 8350},
          ],
        },
      });
    });

    test('chunkRequest (SPEC §4.2)', () {
      expect(
        chunkRequestEnvelope(fingerprint: '9f86d081', offset: 1000, count: 3),
        exampleChunkRequest(),
      );
    });

    test('chunkData carries the worked example payload (SPEC §4.3)', () {
      final envelope = chunkDataEnvelope(
        fingerprint: '9f86d081',
        offset: 1000,
        count: 3,
        payload: exampleChunkBytes,
      );
      expect(envelope, <String, Object?>{
        't': 'chunkData',
        'v': 1,
        'fp': '9f86d081',
        'off': 1000,
        'n': 3,
        'p': exampleChunkBytes,
      });
    });

    test('position (SPEC §4.4)', () {
      final envelope = positionEnvelope(
        fingerprint: '9f86d081',
        offset: 1002,
        timestamp: 1781049600,
        source: ProtocolKeys.srcWatch,
      );
      expect(envelope, <String, Object?>{
        't': 'position',
        'v': 1,
        'fp': '9f86d081',
        'off': 1002,
        'p': <String, Object?>{'ts': 1781049600, 'src': 'watch'},
      });
    });

    test('error (SPEC §4.5)', () {
      final envelope = errorEnvelope(
        code: ProtocolKeys.errDecodeFailure,
        message: 'record 2: wordLen exceeds remaining payload',
        fingerprint: '9f86d081',
        offset: 1000,
      );
      expect(envelope, <String, Object?>{
        't': 'error',
        'v': 1,
        'fp': '9f86d081',
        'off': 1000,
        'p': <String, Object?>{
          'c': 'decodeFailure',
          'm': 'record 2: wordLen exceeds remaining payload',
        },
      });
    });
  });

  group('decodeEnvelope (SPEC §3 validation order)', () {
    test('accepts the spec chunkRequest example', () {
      final envelope = decodeEnvelope(exampleChunkRequest());
      expect(envelope.type, ProtocolKeys.msgChunkRequest);
      expect(envelope.version, 1);
      expect(envelope.fingerprint, '9f86d081');
      expect(envelope.offset, 1000);
      expect(envelope.count, 3);
      expect(envelope.payload, isNull);
    });

    test('unknown version is rejected, never guessed (SPEC §2, AC4)', () {
      final raw = exampleChunkRequest()..['v'] = 2;
      expect(
        () => decodeEnvelope(raw),
        throwsA(
          isA<EnvelopeException>().having(
            (e) => e.code,
            'code',
            ProtocolKeys.errVersionMismatch,
          ),
        ),
      );
    });

    test('missing version is a version failure (SPEC §3 step 1)', () {
      final raw = exampleChunkRequest()..remove('v');
      expect(
        () => decodeEnvelope(raw),
        throwsA(
          isA<EnvelopeException>().having(
            (e) => e.code,
            'code',
            ProtocolKeys.errVersionMismatch,
          ),
        ),
      );
    });

    test('unknown message type is rejected (SPEC §3 step 2)', () {
      final raw = exampleChunkRequest()..['t'] = 'telemetry';
      expect(
        () => decodeEnvelope(raw),
        throwsA(
          isA<EnvelopeException>().having(
            (e) => e.code,
            'code',
            ProtocolKeys.errUnknownType,
          ),
        ),
      );
    });

    test('missing required field is a typed error (SPEC §3 step 3)', () {
      final raw = exampleChunkRequest()..remove('n');
      expect(
        () => decodeEnvelope(raw),
        throwsA(
          isA<EnvelopeException>().having(
            (e) => e.code,
            'code',
            ProtocolKeys.errMalformedEnvelope,
          ),
        ),
      );
    });

    test('null required field equals missing (SPEC §3)', () {
      final raw = exampleChunkRequest()..['n'] = null;
      expect(
        () => decodeEnvelope(raw),
        throwsA(
          isA<EnvelopeException>().having(
            (e) => e.code,
            'code',
            ProtocolKeys.errMalformedEnvelope,
          ),
        ),
      );
    });

    test('unknown top-level key is rejected (SPEC §3)', () {
      final raw = exampleChunkRequest()..['x'] = 1;
      expect(
        () => decodeEnvelope(raw),
        throwsA(
          isA<EnvelopeException>().having(
            (e) => e.code,
            'code',
            ProtocolKeys.errMalformedEnvelope,
          ),
        ),
      );
    });

    test('malformed fingerprint shape is rejected (SPEC §7)', () {
      for (final bad in ['9F86D081', '9f86d08', '9f86d0811', 'not-hex!']) {
        final raw = exampleChunkRequest()..['fp'] = bad;
        expect(
          () => decodeEnvelope(raw),
          throwsA(
            isA<EnvelopeException>().having(
              (e) => e.code,
              'code',
              ProtocolKeys.errMalformedEnvelope,
            ),
          ),
          reason: 'fp=$bad',
        );
      }
    });

    test('chunkData payload must be bytes (SPEC §4.3)', () {
      final raw = <String, Object?>{
        't': 'chunkData',
        'v': 1,
        'fp': '9f86d081',
        'off': 1000,
        'n': 3,
        'p': 'not-bytes',
      };
      expect(
        () => decodeEnvelope(raw),
        throwsA(
          isA<EnvelopeException>().having(
            (e) => e.code,
            'code',
            ProtocolKeys.errMalformedEnvelope,
          ),
        ),
      );
    });

    test('position payload requires ts and src (SPEC §4.4)', () {
      final raw = <String, Object?>{
        't': 'position',
        'v': 1,
        'fp': '9f86d081',
        'off': 1002,
        'p': <String, Object?>{'ts': 1781049600},
      };
      expect(
        () => decodeEnvelope(raw),
        throwsA(
          isA<EnvelopeException>().having(
            (e) => e.code,
            'code',
            ProtocolKeys.errMalformedEnvelope,
          ),
        ),
      );
    });

    test('error payload requires a code (SPEC §4.5)', () {
      final raw = <String, Object?>{
        't': 'error',
        'v': 1,
        'p': <String, Object?>{'m': 'context only'},
      };
      expect(
        () => decodeEnvelope(raw),
        throwsA(
          isA<EnvelopeException>().having(
            (e) => e.code,
            'code',
            ProtocolKeys.errMalformedEnvelope,
          ),
        ),
      );
    });

    test('round-trips every spec example envelope', () {
      final examples = <Map<String, Object?>>[
        manifestEnvelope(
          fingerprint: '9f86d081',
          title: 'Example Book',
          totalWords: 50000,
          totalBonusMs: 412350,
          chapters: const [
            ChapterEntry(offset: 0, title: 'Chapter 1', cumBonusMs: 0),
            ChapterEntry(offset: 1000, title: 'Chapter 2', cumBonusMs: 8350),
          ],
        ),
        chunkRequestEnvelope(fingerprint: '9f86d081', offset: 1000, count: 3),
        chunkDataEnvelope(
          fingerprint: '9f86d081',
          offset: 1000,
          count: 3,
          payload: exampleChunkBytes,
        ),
        positionEnvelope(
          fingerprint: '9f86d081',
          offset: 1002,
          timestamp: 1781049600,
          source: ProtocolKeys.srcWatch,
        ),
        errorEnvelope(
          code: ProtocolKeys.errDecodeFailure,
          message: 'record 2: wordLen exceeds remaining payload',
          fingerprint: '9f86d081',
          offset: 1000,
        ),
      ];
      for (final raw in examples) {
        final envelope = decodeEnvelope(raw);
        expect(envelope.type, raw['t']);
        expect(envelope.version, 1);
      }
    });
  });
}

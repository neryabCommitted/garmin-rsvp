import 'dart:typed_data';

import 'protocol_keys.dart';

/// SPEC §3/§4 envelope codec — builds and validates the five message
/// envelopes as plain maps (the Connect IQ bridge transmits dictionaries).
/// Pure Dart; transport wiring is Epic 4. The watch-side validation mirror is
/// `Protocol.validateEnvelope` in `watch/source/Protocol.mc`.

/// SPEC §7 — fingerprint wire form: exactly 8 lowercase hex chars.
final RegExp _fingerprintForm =
    RegExp('^[0-9a-f]{${ProtocolKeys.fingerprintLength}}\$');

/// Typed envelope rejection carrying its SPEC §8 [code] —
/// `versionMismatch`, `unknownType`, or `malformedEnvelope`. Callers surface
/// it as a named state — never swallow (SPEC §8).
final class EnvelopeException implements Exception {
  EnvelopeException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'EnvelopeException($code): $message';
}

/// One entry of the manifest's chapter map (SPEC §4.1 `ch`).
final class ChapterEntry {
  const ChapterEntry({
    required this.offset,
    required this.title,
    required this.cumBonusMs,
  });

  /// Absolute word index of the chapter's first word.
  final int offset;

  /// Chapter title, shown on the chapter-transition card.
  final String title;

  /// Cumulative bonusMs of all words before [offset].
  final int cumBonusMs;

  /// SPEC §4.1 wire shape: `{o, ti, cb}`.
  Map<String, Object?> toMap() => <String, Object?>{
        ProtocolKeys.keyChapterOffset: offset,
        ProtocolKeys.keyTitle: title,
        ProtocolKeys.keyChapterCumBonusMs: cumBonusMs,
      };
}

/// A validated SPEC §3 envelope. Fields unused by [type] are null.
final class Envelope {
  const Envelope({
    required this.type,
    required this.version,
    this.fingerprint,
    this.offset,
    this.count,
    this.payload,
  });

  final String type;
  final int version;
  final String? fingerprint;
  final int? offset;
  final int? count;
  final Object? payload;
}

/// SPEC §4.1 — `manifest` envelope (phone → watch).
Map<String, Object?> manifestEnvelope({
  required String fingerprint,
  required String title,
  required int totalWords,
  required int totalBonusMs,
  required List<ChapterEntry> chapters,
}) =>
    <String, Object?>{
      ProtocolKeys.keyType: ProtocolKeys.msgManifest,
      ProtocolKeys.keyVersion: ProtocolKeys.protocolVersion,
      ProtocolKeys.keyFingerprint: fingerprint,
      ProtocolKeys.keyPayload: <String, Object?>{
        ProtocolKeys.keyTitle: title,
        ProtocolKeys.keyTotalWords: totalWords,
        ProtocolKeys.keyTotalBonusMs: totalBonusMs,
        ProtocolKeys.keyChapters: <Object?>[
          for (final chapter in chapters) chapter.toMap(),
        ],
      },
    };

/// SPEC §4.2 — `chunkRequest` envelope (watch → phone).
Map<String, Object?> chunkRequestEnvelope({
  required String fingerprint,
  required int offset,
  required int count,
}) =>
    <String, Object?>{
      ProtocolKeys.keyType: ProtocolKeys.msgChunkRequest,
      ProtocolKeys.keyVersion: ProtocolKeys.protocolVersion,
      ProtocolKeys.keyFingerprint: fingerprint,
      ProtocolKeys.keyOffset: offset,
      ProtocolKeys.keyCount: count,
    };

/// SPEC §4.3 — `chunkData` envelope (phone → watch). [payload] is the SPEC §5
/// binary produced by `encodeChunk`, exactly [count] records from [offset].
Map<String, Object?> chunkDataEnvelope({
  required String fingerprint,
  required int offset,
  required int count,
  required Uint8List payload,
}) =>
    <String, Object?>{
      ProtocolKeys.keyType: ProtocolKeys.msgChunkData,
      ProtocolKeys.keyVersion: ProtocolKeys.protocolVersion,
      ProtocolKeys.keyFingerprint: fingerprint,
      ProtocolKeys.keyOffset: offset,
      ProtocolKeys.keyCount: count,
      ProtocolKeys.keyPayload: payload,
    };

/// SPEC §4.4 — `position` envelope (both directions). [timestamp] is Unix
/// epoch seconds; [source] is `ProtocolKeys.srcWatch` or `srcPhone`.
Map<String, Object?> positionEnvelope({
  required String fingerprint,
  required int offset,
  required int timestamp,
  required String source,
}) =>
    <String, Object?>{
      ProtocolKeys.keyType: ProtocolKeys.msgPosition,
      ProtocolKeys.keyVersion: ProtocolKeys.protocolVersion,
      ProtocolKeys.keyFingerprint: fingerprint,
      ProtocolKeys.keyOffset: offset,
      ProtocolKeys.keyPayload: <String, Object?>{
        ProtocolKeys.keyTimestamp: timestamp,
        ProtocolKeys.keySource: source,
      },
    };

/// SPEC §4.5 — `error` envelope (both directions). [fingerprint] and [offset]
/// are context, set when known.
Map<String, Object?> errorEnvelope({
  required String code,
  String? message,
  String? fingerprint,
  int? offset,
}) =>
    <String, Object?>{
      ProtocolKeys.keyType: ProtocolKeys.msgError,
      ProtocolKeys.keyVersion: ProtocolKeys.protocolVersion,
      ProtocolKeys.keyFingerprint: ?fingerprint,
      ProtocolKeys.keyOffset: ?offset,
      ProtocolKeys.keyPayload: <String, Object?>{
        ProtocolKeys.keyErrorCode: code,
        ProtocolKeys.keyErrorMessage: ?message,
      },
    };

/// Validates a received envelope per the SPEC §3 order — version gate first
/// (SPEC §2: an unknown `v` is rejected before anything else is interpreted,
/// AC4), then message type, then the required-field matrix — and returns the
/// typed [Envelope]. Throws [EnvelopeException] on any violation.
Envelope decodeEnvelope(Map<Object?, Object?> raw) {
  // SPEC §3 step 1: version.
  final version = raw[ProtocolKeys.keyVersion];
  if (version is! int || version != ProtocolKeys.protocolVersion) {
    throw EnvelopeException(
      ProtocolKeys.errVersionMismatch,
      'SPEC §2: expected v=${ProtocolKeys.protocolVersion}, got $version',
    );
  }

  // SPEC §3 step 2: message type.
  final type = raw[ProtocolKeys.keyType];
  if (type is! String || !_requiredFields.containsKey(type)) {
    throw EnvelopeException(
      ProtocolKeys.errUnknownType,
      'SPEC §4: unknown message type $type',
    );
  }

  // SPEC §3 step 3: the required/unused field matrix.
  final required = _requiredFields[type]!;
  for (final key in raw.keys) {
    if (key is! String || !_envelopeKeys.contains(key)) {
      throw EnvelopeException(
        ProtocolKeys.errMalformedEnvelope,
        'SPEC §3: unknown envelope key $key',
      );
    }
  }
  for (final key in required) {
    if (raw[key] == null) {
      throw EnvelopeException(
        ProtocolKeys.errMalformedEnvelope,
        'SPEC §3: $type requires $key',
      );
    }
  }

  final fingerprint = raw[ProtocolKeys.keyFingerprint];
  if (fingerprint != null &&
      (fingerprint is! String || !_fingerprintForm.hasMatch(fingerprint))) {
    throw EnvelopeException(
      ProtocolKeys.errMalformedEnvelope,
      'SPEC §7: fingerprint must be ${ProtocolKeys.fingerprintLength} '
      'lowercase hex chars',
    );
  }
  final offset = raw[ProtocolKeys.keyOffset];
  final count = raw[ProtocolKeys.keyCount];
  if (offset is! int?) {
    throw EnvelopeException(
      ProtocolKeys.errMalformedEnvelope,
      'SPEC §3: off must be an integer',
    );
  }
  if (count is! int?) {
    throw EnvelopeException(
      ProtocolKeys.errMalformedEnvelope,
      'SPEC §3: n must be an integer',
    );
  }

  final payload = raw[ProtocolKeys.keyPayload];
  _validatePayload(type, payload);

  return Envelope(
    type: type,
    version: version,
    fingerprint: fingerprint as String?,
    offset: offset,
    count: count,
    payload: payload,
  );
}

const Set<String> _envelopeKeys = {
  ProtocolKeys.keyType,
  ProtocolKeys.keyVersion,
  ProtocolKeys.keyFingerprint,
  ProtocolKeys.keyOffset,
  ProtocolKeys.keyCount,
  ProtocolKeys.keyPayload,
};

/// SPEC §3 required-field matrix (the `t`/`v` gates run before it).
const Map<String, List<String>> _requiredFields = {
  ProtocolKeys.msgManifest: [
    ProtocolKeys.keyFingerprint,
    ProtocolKeys.keyPayload,
  ],
  ProtocolKeys.msgChunkRequest: [
    ProtocolKeys.keyFingerprint,
    ProtocolKeys.keyOffset,
    ProtocolKeys.keyCount,
  ],
  ProtocolKeys.msgChunkData: [
    ProtocolKeys.keyFingerprint,
    ProtocolKeys.keyOffset,
    ProtocolKeys.keyCount,
    ProtocolKeys.keyPayload,
  ],
  ProtocolKeys.msgPosition: [
    ProtocolKeys.keyFingerprint,
    ProtocolKeys.keyOffset,
    ProtocolKeys.keyPayload,
  ],
  ProtocolKeys.msgError: [ProtocolKeys.keyPayload],
};

/// SPEC §4 payload-kind checks: binary for `chunkData`, dictionaries with
/// their required keys elsewhere. Deep payload semantics (chapter ordering,
/// source values) are the consumer's concern, not the codec's.
void _validatePayload(String type, Object? payload) {
  switch (type) {
    case ProtocolKeys.msgChunkData:
      if (payload is! Uint8List) {
        throw EnvelopeException(
          ProtocolKeys.errMalformedEnvelope,
          'SPEC §4.3: chunkData payload must be binary',
        );
      }
    case ProtocolKeys.msgManifest:
      _requirePayloadKeys(type, payload, const [
        ProtocolKeys.keyTitle,
        ProtocolKeys.keyTotalWords,
        ProtocolKeys.keyTotalBonusMs,
        ProtocolKeys.keyChapters,
      ]);
    case ProtocolKeys.msgPosition:
      _requirePayloadKeys(type, payload, const [
        ProtocolKeys.keyTimestamp,
        ProtocolKeys.keySource,
      ]);
    case ProtocolKeys.msgError:
      _requirePayloadKeys(type, payload, const [ProtocolKeys.keyErrorCode]);
    default:
      // chunkRequest carries no payload; its absence was already accepted by
      // the matrix (p is unused for it, SPEC §4.2).
      break;
  }
}

void _requirePayloadKeys(String type, Object? payload, List<String> keys) {
  if (payload is! Map<Object?, Object?>) {
    throw EnvelopeException(
      ProtocolKeys.errMalformedEnvelope,
      'SPEC §4: $type payload must be a dictionary',
    );
  }
  for (final key in keys) {
    if (payload[key] == null) {
      throw EnvelopeException(
        ProtocolKeys.errMalformedEnvelope,
        'SPEC §4: $type payload requires $key',
      );
    }
  }
}

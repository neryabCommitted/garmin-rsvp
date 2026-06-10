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

// Builder input validation: an envelope the peer is bound to reject is a
// phone-side bug, caught here as [ArgumentError] — the same posture as
// `encodeChunk`.

void _checkFingerprint(String fingerprint) {
  if (!_fingerprintForm.hasMatch(fingerprint)) {
    throw ArgumentError.value(
      fingerprint,
      'fingerprint',
      'SPEC §7: fingerprint must be ${ProtocolKeys.fingerprintLength} '
          'lowercase hex chars',
    );
  }
}

void _checkOffset(int offset) {
  if (offset < 0) {
    throw ArgumentError.value(offset, 'offset', 'SPEC §3: off must be >= 0');
  }
}

void _checkCount(int count) {
  if (count < 1) {
    throw ArgumentError.value(count, 'count', 'SPEC §3: n must be >= 1');
  }
}

/// Counts SPEC §5 records by hopping headers (`wordLen` only — no field
/// validation); returns -1 when the hops don't land exactly on the payload
/// end.
int _recordCount(Uint8List payload) {
  var count = 0;
  var pos = 0;
  while (pos < payload.length) {
    final wordLen = payload[pos];
    if (wordLen == 0) {
      return -1;
    }
    pos += ProtocolKeys.recordHeaderBytes + wordLen;
    count++;
  }
  return pos == payload.length ? count : -1;
}

/// SPEC §4.1 — `manifest` envelope (phone → watch).
Map<String, Object?> manifestEnvelope({
  required String fingerprint,
  required String title,
  required int totalWords,
  required int totalBonusMs,
  required List<ChapterEntry> chapters,
}) {
  _checkFingerprint(fingerprint);
  if (chapters.isEmpty) {
    throw ArgumentError.value(
      chapters,
      'chapters',
      'SPEC §4.1: ch must have at least one entry',
    );
  }
  return <String, Object?>{
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
}

/// SPEC §4.2 — `chunkRequest` envelope (watch → phone).
Map<String, Object?> chunkRequestEnvelope({
  required String fingerprint,
  required int offset,
  required int count,
}) {
  _checkFingerprint(fingerprint);
  _checkOffset(offset);
  _checkCount(count);
  return <String, Object?>{
    ProtocolKeys.keyType: ProtocolKeys.msgChunkRequest,
    ProtocolKeys.keyVersion: ProtocolKeys.protocolVersion,
    ProtocolKeys.keyFingerprint: fingerprint,
    ProtocolKeys.keyOffset: offset,
    ProtocolKeys.keyCount: count,
  };
}

/// SPEC §4.3 — `chunkData` envelope (phone → watch). [payload] is the SPEC §5
/// binary produced by `encodeChunk`, exactly [count] records from [offset].
Map<String, Object?> chunkDataEnvelope({
  required String fingerprint,
  required int offset,
  required int count,
  required Uint8List payload,
}) {
  _checkFingerprint(fingerprint);
  _checkOffset(offset);
  _checkCount(count);
  final records = _recordCount(payload);
  if (records != count) {
    throw ArgumentError.value(
      count,
      'count',
      'SPEC §4.3: payload carries '
          '${records < 0 ? 'a malformed record sequence' : '$records records'}'
          ', n says $count',
    );
  }
  return <String, Object?>{
    ProtocolKeys.keyType: ProtocolKeys.msgChunkData,
    ProtocolKeys.keyVersion: ProtocolKeys.protocolVersion,
    ProtocolKeys.keyFingerprint: fingerprint,
    ProtocolKeys.keyOffset: offset,
    ProtocolKeys.keyCount: count,
    ProtocolKeys.keyPayload: payload,
  };
}

/// SPEC §4.4 — `position` envelope (both directions). [timestamp] is Unix
/// epoch seconds; [source] is `ProtocolKeys.srcWatch` or `srcPhone`.
Map<String, Object?> positionEnvelope({
  required String fingerprint,
  required int offset,
  required int timestamp,
  required String source,
}) {
  _checkFingerprint(fingerprint);
  _checkOffset(offset);
  return <String, Object?>{
    ProtocolKeys.keyType: ProtocolKeys.msgPosition,
    ProtocolKeys.keyVersion: ProtocolKeys.protocolVersion,
    ProtocolKeys.keyFingerprint: fingerprint,
    ProtocolKeys.keyOffset: offset,
    ProtocolKeys.keyPayload: <String, Object?>{
      ProtocolKeys.keyTimestamp: timestamp,
      ProtocolKeys.keySource: source,
    },
  };
}

/// SPEC §4.5 — `error` envelope (both directions). [fingerprint] and [offset]
/// are context, set when known.
Map<String, Object?> errorEnvelope({
  required String code,
  String? message,
  String? fingerprint,
  int? offset,
}) {
  if (fingerprint != null) {
    _checkFingerprint(fingerprint);
  }
  if (offset != null) {
    _checkOffset(offset);
  }
  return <String, Object?>{
    ProtocolKeys.keyType: ProtocolKeys.msgError,
    ProtocolKeys.keyVersion: ProtocolKeys.protocolVersion,
    ProtocolKeys.keyFingerprint: ?fingerprint,
    ProtocolKeys.keyOffset: ?offset,
    ProtocolKeys.keyPayload: <String, Object?>{
      ProtocolKeys.keyErrorCode: code,
      ProtocolKeys.keyErrorMessage: ?message,
    },
  };
}

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
  // SPEC §3: a non-null value in an unused ("—") field is malformed — there
  // are no implicit extensions.
  for (final key in _unusedFields[type]!) {
    if (raw[key] != null) {
      throw EnvelopeException(
        ProtocolKeys.errMalformedEnvelope,
        'SPEC §3: $type does not use $key',
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
  if (offset is! int? || (offset != null && offset < 0)) {
    throw EnvelopeException(
      ProtocolKeys.errMalformedEnvelope,
      'SPEC §3: off must be an integer >= 0',
    );
  }
  if (count is! int? || (count != null && count < 1)) {
    throw EnvelopeException(
      ProtocolKeys.errMalformedEnvelope,
      'SPEC §3: n must be an integer >= 1',
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

/// SPEC §3 unused ("—") fields per type — a non-null value here is malformed.
const Map<String, List<String>> _unusedFields = {
  ProtocolKeys.msgManifest: [ProtocolKeys.keyOffset, ProtocolKeys.keyCount],
  ProtocolKeys.msgChunkRequest: [ProtocolKeys.keyPayload],
  ProtocolKeys.msgChunkData: [],
  ProtocolKeys.msgPosition: [ProtocolKeys.keyCount],
  ProtocolKeys.msgError: [ProtocolKeys.keyCount],
};

/// SPEC §4 payload-structure checks: binary for `chunkData`; dictionaries
/// elsewhere with their required keys present in the kinds the §4 tables
/// declare. Value semantics beyond type (chapter ordering, `src` values,
/// range arithmetic) are the consumer's concern, not the codec's (SPEC §3).
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
      final map = _payloadMap(type, payload);
      _requireKind<String>(type, map, ProtocolKeys.keyTitle);
      _requireKind<int>(type, map, ProtocolKeys.keyTotalWords);
      _requireKind<int>(type, map, ProtocolKeys.keyTotalBonusMs);
      final chapters =
          _requireKind<List<Object?>>(type, map, ProtocolKeys.keyChapters);
      if (chapters.isEmpty) {
        throw EnvelopeException(
          ProtocolKeys.errMalformedEnvelope,
          'SPEC §4.1: ch must have at least one entry',
        );
      }
      for (final entry in chapters) {
        if (entry is! Map<Object?, Object?>) {
          throw EnvelopeException(
            ProtocolKeys.errMalformedEnvelope,
            'SPEC §4.1: ch entries must be dictionaries',
          );
        }
        _requireKind<int>(type, entry, ProtocolKeys.keyChapterOffset);
        _requireKind<String>(type, entry, ProtocolKeys.keyTitle);
        _requireKind<int>(type, entry, ProtocolKeys.keyChapterCumBonusMs);
      }
    case ProtocolKeys.msgPosition:
      final map = _payloadMap(type, payload);
      _requireKind<int>(type, map, ProtocolKeys.keyTimestamp);
      _requireKind<String>(type, map, ProtocolKeys.keySource);
    case ProtocolKeys.msgError:
      final map = _payloadMap(type, payload);
      _requireKind<String>(type, map, ProtocolKeys.keyErrorCode);
      final message = map[ProtocolKeys.keyErrorMessage];
      if (message != null && message is! String) {
        throw EnvelopeException(
          ProtocolKeys.errMalformedEnvelope,
          'SPEC §4.5: m must be a string',
        );
      }
    default:
      // chunkRequest carries no payload; a non-null `p` was already rejected
      // by the unused-field check (SPEC §4.2).
      break;
  }
}

Map<Object?, Object?> _payloadMap(String type, Object? payload) {
  if (payload is! Map<Object?, Object?>) {
    throw EnvelopeException(
      ProtocolKeys.errMalformedEnvelope,
      'SPEC §4: $type payload must be a dictionary',
    );
  }
  return payload;
}

T _requireKind<T>(String type, Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is! T) {
    throw EnvelopeException(
      ProtocolKeys.errMalformedEnvelope,
      'SPEC §4: $type payload requires $key as $T',
    );
  }
  return value;
}

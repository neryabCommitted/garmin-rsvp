import 'dart:convert';
import 'dart:typed_data';

import 'protocol_keys.dart';

/// SPEC §5 word-record codec — pure Dart (`dart:typed_data` +
/// `dart:convert` only; no Flutter imports), so it runs in an isolate and
/// tests without a widget tree. The watch-side decode mirror is
/// `watch/source/source_data/StreamDecoder.mc`.

/// One SPEC §5 word record.
final class WordRecord {
  const WordRecord({
    required this.word,
    required this.flags,
    required this.orpPivot,
    required this.bonusMs,
  });

  /// SPEC §5 — the word (UTF-8 on the wire, 1–255 bytes).
  final String word;

  /// SPEC §6 — flag bits.
  final int flags;

  /// SPEC §5 — 0-based byte index of the ORP character into the UTF-8 word.
  final int orpPivot;

  /// SPEC §5.1 — WPM-invariant additive dwell bonus, ms (u16).
  final int bonusMs;

  @override
  bool operator ==(Object other) =>
      other is WordRecord &&
      other.word == word &&
      other.flags == flags &&
      other.orpPivot == orpPivot &&
      other.bonusMs == bonusMs;

  @override
  int get hashCode => Object.hash(word, flags, orpPivot, bonusMs);

  @override
  String toString() =>
      'WordRecord($word, flags: 0x${flags.toRadixString(16)}, '
      'orpPivot: $orpPivot, bonusMs: $bonusMs)';
}

/// Typed SPEC §8 `decodeFailure`: the chunk payload violates SPEC §5/§4.3.
/// Callers surface it as a named state — never swallow (SPEC §8).
final class StreamDecodeException implements Exception {
  StreamDecodeException(this.message);

  /// SPEC §8 error code this failure maps to on the wire.
  final String code = ProtocolKeys.errDecodeFailure;
  final String message;

  @override
  String toString() => 'StreamDecodeException($code): $message';
}

/// Encodes records as a SPEC §5 `chunkData` payload: tightly concatenated,
/// little-endian, 5-byte header + UTF-8 word per record.
///
/// Throws [ArgumentError] for records the wire format cannot carry — that is
/// a phone-side baking bug, not a protocol error.
Uint8List encodeChunk(List<WordRecord> records) {
  final builder = BytesBuilder(copy: false);
  for (final record in records) {
    final wordBytes = utf8.encode(record.word);
    if (wordBytes.isEmpty || wordBytes.length > 255) {
      throw ArgumentError.value(
        record.word,
        'records',
        'SPEC §5: word must be 1–255 UTF-8 bytes, got ${wordBytes.length}',
      );
    }
    if (record.orpPivot < 0 || record.orpPivot >= wordBytes.length) {
      throw ArgumentError.value(
        record.orpPivot,
        'records',
        'SPEC §5: orpPivot must be a byte index < wordLen',
      );
    }
    if (record.bonusMs < 0 || record.bonusMs > 0xFFFF) {
      throw ArgumentError.value(
        record.bonusMs,
        'records',
        'SPEC §5: bonusMs must fit u16',
      );
    }
    if (record.flags & ProtocolKeys.flagsReservedMask != 0 ||
        record.flags < 0) {
      throw ArgumentError.value(
        record.flags,
        'records',
        'SPEC §6: reserved flag bits must be 0 in v1',
      );
    }

    final header = ByteData(ProtocolKeys.recordHeaderBytes)
      ..setUint8(0, wordBytes.length) // SPEC §5 wordLen
      ..setUint8(1, record.flags) // SPEC §6 flags
      ..setUint8(2, record.orpPivot) // SPEC §5 orpPivot
      ..setUint16(3, record.bonusMs, Endian.little); // SPEC §5.1 bonusMs
    builder
      ..add(header.buffer.asUint8List())
      ..add(wordBytes);
  }
  return builder.takeBytes();
}

/// Decodes a SPEC §4.3 `chunkData` payload of exactly [n] records.
///
/// Error posture (SPEC §5/§8): every read is bounds-checked; any violation —
/// truncation, `wordLen` 0, out-of-range pivot, reserved flag bits, invalid
/// UTF-8, leftover bytes — throws a typed [StreamDecodeException]. Nothing is
/// guessed or skipped.
List<WordRecord> decodeChunk(Uint8List payload, int n) {
  if (n < 1) {
    throw StreamDecodeException('SPEC §4.2: n must be >= 1, got $n');
  }
  final data = ByteData.sublistView(payload);
  final records = <WordRecord>[];
  var pos = 0;

  for (var i = 0; i < n; i++) {
    if (pos + ProtocolKeys.recordHeaderBytes > payload.length) {
      throw StreamDecodeException('record $i: truncated header at byte $pos');
    }
    // SPEC §5 fixed header: u8 wordLen · u8 flags · u8 orpPivot · u16le bonusMs.
    final wordLen = data.getUint8(pos);
    final flags = data.getUint8(pos + 1);
    final orpPivot = data.getUint8(pos + 2);
    final bonusMs = data.getUint16(pos + 3, Endian.little);

    if (wordLen == 0) {
      throw StreamDecodeException('record $i: SPEC §5 forbids wordLen 0');
    }
    if (orpPivot >= wordLen) {
      throw StreamDecodeException(
        'record $i: orpPivot $orpPivot >= wordLen $wordLen (SPEC §5)',
      );
    }
    if (flags & ProtocolKeys.flagsReservedMask != 0) {
      throw StreamDecodeException(
        'record $i: reserved flag bits set '
        '(0x${flags.toRadixString(16)}, SPEC §6)',
      );
    }
    final wordStart = pos + ProtocolKeys.recordHeaderBytes;
    if (wordStart + wordLen > payload.length) {
      throw StreamDecodeException(
        'record $i: wordLen $wordLen exceeds remaining payload',
      );
    }

    final String word;
    try {
      word = utf8.decode(payload.sublist(wordStart, wordStart + wordLen));
    } on FormatException catch (e) {
      throw StreamDecodeException('record $i: invalid UTF-8 (${e.message})');
    }

    records.add(
      WordRecord(word: word, flags: flags, orpPivot: orpPivot, bonusMs: bonusMs),
    );
    pos = wordStart + wordLen;
  }

  if (pos != payload.length) {
    throw StreamDecodeException(
      'SPEC §4.3: ${payload.length - pos} trailing bytes after $n records',
    );
  }
  return records;
}

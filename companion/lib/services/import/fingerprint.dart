/// Stage 5 of the Epic 2 import pipeline (`… → ORP → fingerprint → encode`,
/// AR20): computes the SPEC §7 content fingerprint over the encoded word stream.
///
/// SPEC §7: `fp` is an **opaque equality token** — exactly 8 lowercase hex chars
/// (32 bits). Any algorithm conforms provided distinct conversions get distinct
/// values with high probability AND a re-bake of identical source yields a new
/// value. We use **FNV-1a (32-bit)** — a tiny, dependency-free, isolate-safe
/// hash — over the stream bytes plus a per-bake `salt`. The salt is what makes a
/// re-bake of identical text produce a fresh fingerprint (SPEC §7) while keeping
/// the function deterministic for a fixed salt (so tests/fixtures pin). The
/// **caller** (Story 2.3 `import_service`) supplies the salt (e.g. a timestamp),
/// keeping this module pure (AR19).
library;

import 'dart:typed_data';

import '../../protocol/protocol_keys.dart';

const int _fnvOffsetBasis = 0x811c9dc5;
const int _fnvPrime = 0x01000193;
const int _mask32 = 0xFFFFFFFF;

/// Returns the SPEC §7 fingerprint of [streamBytes] under [salt]: exactly
/// `ProtocolKeys.fingerprintLength` (8) lowercase hex chars (AC3).
String fingerprint(Uint8List streamBytes, {required int salt}) {
  int hash = _fnvOffsetBasis;
  for (final int b in streamBytes) {
    hash = ((hash ^ b) * _fnvPrime) & _mask32;
  }
  // Fold 8 little-endian bytes of the salt so a re-bake (new salt) yields a new
  // fingerprint; 8 bytes covers timestamp-sized (> 32-bit) salts.
  int s = salt;
  for (int i = 0; i < 8; i++) {
    hash = ((hash ^ (s & 0xFF)) * _fnvPrime) & _mask32;
    s >>= 8;
  }
  return hash.toRadixString(16).padLeft(ProtocolKeys.fingerprintLength, '0');
}

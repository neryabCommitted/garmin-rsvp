import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/protocol/protocol_keys.dart';
import 'package:paceturner_companion/services/import/fingerprint.dart';

/// Story 2.2 AC3 (fingerprint part) — the §7 content fingerprint: exactly 8
/// lowercase hex chars (`[0-9a-f]{8}`). It is an opaque equality token; SPEC §7
/// requires distinct conversions to get distinct values with high probability
/// AND a re-bake of identical source to yield a NEW fingerprint. The latter is
/// achieved by a per-bake `salt` (supplied by the caller, Story 2.3), keeping
/// this module pure and deterministic for a fixed salt.

final RegExp _hex8 = RegExp(r'^[0-9a-f]{8}$');

void main() {
  group('fingerprint — wire form (SPEC §7)', () {
    test('always exactly 8 lowercase hex chars, including zero-padding', () {
      // Length is a hard guarantee (32-bit value, padLeft to 8): never more,
      // never fewer. Sweep salts so a small hash exercises the leading-zero
      // padding path too.
      for (var salt = 0; salt < 64; salt++) {
        final fp = fingerprint(Uint8List.fromList([1, 2, 3, 4]), salt: salt);
        expect(fp.length, ProtocolKeys.fingerprintLength);
        expect(_hex8.hasMatch(fp), isTrue, reason: 'salt=$salt → $fp');
      }
    });
  });

  group('fingerprint — determinism & salt (SPEC §7)', () {
    final bytes = Uint8List.fromList([10, 20, 30, 40, 50]);

    test('same bytes + same salt → identical fingerprint (deterministic)', () {
      expect(fingerprint(bytes, salt: 7), fingerprint(bytes, salt: 7));
    });

    test('same bytes + different salt → different fingerprint (re-bake → new fp)',
        () {
      expect(fingerprint(bytes, salt: 1), isNot(fingerprint(bytes, salt: 2)));
    });

    test('different bytes + same salt → different fingerprint (high prob.)', () {
      final a = fingerprint(Uint8List.fromList([1, 2, 3]), salt: 99);
      final b = fingerprint(Uint8List.fromList([1, 2, 4]), salt: 99);
      expect(a, isNot(b));
    });

    test('handles a large (timestamp-sized) salt without overflow', () {
      // Story 2.3 may pass an epoch-ms timestamp (> 32 bits).
      final fp = fingerprint(bytes, salt: 1749900000000);
      expect(_hex8.hasMatch(fp), isTrue);
    });
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/gate_v2/gate_v2_runner.dart';
import 'package:paceturner_companion/protocol/protocol_keys.dart';
import 'package:paceturner_companion/protocol/stream_codec.dart';

/// What the fake bridge does with one send attempt.
enum FakeAction {
  /// Send future completes; watch ack arrives.
  ack,

  /// Send future never completes and no ack arrives — the documented
  /// silent-hang bug (mode a).
  hang,

  /// Send future errors with a `[FAILURE_DURING_TRANSFER]`-style code
  /// (mode c, surfaced by the runner's bridge adapter as
  /// [SpikeSendException]).
  throwTransferError,

  /// Send future completes (the SDK's `SUCCESS`) but no ack ever arrives —
  /// the success-is-not-success case AC1 guards against.
  successNoAck,

  /// Ack arrives but for the wrong offset — must be ignored, not matched.
  ackWrongOffset,

  /// Ack arrives with the right offset but `ok: false` — must be ignored.
  ackNotOk,

  /// The matching ack arrives twice — the duplicate must be discarded.
  ackTwice,

  /// The stream emits an error event (the plugin's `Map.from` mapper throws
  /// on a non-Map inbound), then the ack arrives normally.
  streamErrorThenAck,

  /// Ack arrives and the attempt settles, then the send future errors late.
  ackThenLateError,
}

/// What [FakeBridge.reinit] does when the defense calls it.
enum ReinitBehavior { succeed, throwError, hang }

/// Scripted [SpikeBridge]: the [script] decides each attempt's fate keyed by
/// chunk offset and 1-based attempt number for that offset.
class FakeBridge implements SpikeBridge {
  FakeBridge(this.script);

  final FakeAction Function(int offset, int attempt) script;

  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, Object?>> sent = [];
  final Map<int, int> _attemptsByOffset = {};
  ReinitBehavior reinitBehavior = ReinitBehavior.succeed;
  int reinitCalls = 0;
  int inFlight = 0;
  int maxInFlight = 0;

  @override
  Stream<Map<String, dynamic>> get messages => _controller.stream;

  @override
  Future<void> reinit() {
    reinitCalls++;
    switch (reinitBehavior) {
      case ReinitBehavior.succeed:
        return Future<void>.value();
      case ReinitBehavior.throwError:
        return Future<void>.error(SpikeSendException('[REINIT_FAILED]'));
      case ReinitBehavior.hang:
        return Completer<void>().future;
    }
  }

  void _ack(int offset, {bool ok = true}) {
    _controller.add(<String, dynamic>{
      GateV2Runner.ackOffsetKey: offset,
      GateV2Runner.ackOkKey: ok,
    });
  }

  @override
  Future<void> send(Map<String, Object?> msg) {
    inFlight++;
    if (inFlight > maxInFlight) {
      maxInFlight = inFlight;
    }
    sent.add(msg);
    final offset = msg[ProtocolKeys.keyOffset]! as int;
    final attempt = (_attemptsByOffset[offset] ?? 0) + 1;
    _attemptsByOffset[offset] = attempt;
    switch (script(offset, attempt)) {
      case FakeAction.ack:
        inFlight--;
        _ack(offset);
        return Future<void>.value();
      case FakeAction.hang:
        // Deliberately never completes and never decrements inFlight: the
        // native call is wedged, exactly like the documented bug.
        return Completer<void>().future;
      case FakeAction.throwTransferError:
        inFlight--;
        return Future<void>.error(
          SpikeSendException('[FAILURE_DURING_TRANSFER]'),
        );
      case FakeAction.successNoAck:
        inFlight--;
        return Future<void>.value();
      case FakeAction.ackWrongOffset:
        inFlight--;
        _ack(offset + 1);
        return Future<void>.value();
      case FakeAction.ackNotOk:
        inFlight--;
        _ack(offset, ok: false);
        return Future<void>.value();
      case FakeAction.ackTwice:
        inFlight--;
        _ack(offset);
        _ack(offset);
        return Future<void>.value();
      case FakeAction.streamErrorThenAck:
        inFlight--;
        _controller.addError(StateError('mapper threw on non-Map event'));
        _ack(offset);
        return Future<void>.value();
      case FakeAction.ackThenLateError:
        inFlight--;
        _ack(offset);
        return Future<void>.delayed(
          const Duration(milliseconds: 1),
          () => throw SpikeSendException('[LATE_FAILURE]'),
        );
    }
  }
}

GateV2Runner makeRunner(
  FakeBridge bridge, {
  PayloadEncoding encoding = PayloadEncoding.base64String,
  int totalChunks = 5,
  int recordsPerChunk = 3,
  void Function(GateV2Progress)? onProgress,
}) {
  return GateV2Runner(
    bridge: bridge,
    encoding: encoding,
    totalChunks: totalChunks,
    recordsPerChunk: recordsPerChunk,
    sendTimeout: const Duration(milliseconds: 40),
    onProgress: onProgress,
  );
}

void main() {
  group('all-success run', () {
    test('Run A: every chunk acks first try, stats and envelopes correct',
        () async {
      final bridge = FakeBridge((_, _) => FakeAction.ack);
      final summary = await makeRunner(bridge).run();

      expect(summary.firstTryAcks, 5);
      expect(summary.retriedThenAcked, 0);
      expect(summary.failedAfterDefense, 0);
      expect(summary.completedChunks, 5);
      expect(summary.requestedChunks, 5);
      expect(summary.timeoutCount, 0);
      expect(summary.exceptionCodes, isEmpty);
      expect(summary.reinitActivations, isEmpty);
      expect(summary.aborted, isFalse);
      expect(bridge.reinitCalls, 0);

      // One-in-flight: the runner never overlaps healthy sends.
      expect(bridge.maxInFlight, 1);

      // Chunk plan: offset-addressed, off += n, fixed fingerprint.
      expect(bridge.sent, hasLength(5));
      for (var i = 0; i < bridge.sent.length; i++) {
        final msg = bridge.sent[i];
        expect(msg[ProtocolKeys.keyType], ProtocolKeys.msgChunkData);
        expect(msg[ProtocolKeys.keyVersion], ProtocolKeys.protocolVersion);
        expect(msg[ProtocolKeys.keyFingerprint], GateV2Runner.fingerprint);
        expect(msg[ProtocolKeys.keyOffset], i * 3);
        expect(msg[ProtocolKeys.keyCount], 3);
      }
    });

    test('Run A: payload is a base64 String round-tripping to the SPEC bytes',
        () async {
      final bridge = FakeBridge((_, _) => FakeAction.ack);
      final runner = makeRunner(bridge);
      await runner.run();

      final payload = bridge.sent.first[ProtocolKeys.keyPayload];
      expect(payload, isA<String>());
      final bytes = base64.decode(payload! as String);
      // The wire bytes must decode as exactly recordsPerChunk SPEC §5
      // records — end-to-end integrity is the point of the spike.
      final records = decodeChunk(Uint8List.fromList(bytes), 3);
      expect(records, hasLength(3));
    });

    test('Run B: payload is a plain List<int>, never a Uint8List', () async {
      final bridge = FakeBridge((_, _) => FakeAction.ack);
      await makeRunner(bridge, encoding: PayloadEncoding.intList).run();

      final payload = bridge.sent.first[ProtocolKeys.keyPayload];
      expect(payload, isA<List<int>>());
      // A Uint8List arrives native-side as byte[] and crashes the SDK 2.0.3
      // serializer (FAILURE_INVALID_FORMAT) — the transcode must produce a
      // plain list.
      expect(payload, isNot(isA<Uint8List>()));
      final records =
          decodeChunk(Uint8List.fromList(payload! as List<int>), 3);
      expect(records, hasLength(3));
    });
  });

  group('silent-hang defense (bug mode a)', () {
    test('hang → timeout → retry same chunk → ack', () async {
      final bridge = FakeBridge(
        (offset, attempt) => offset == 0 && attempt == 1
            ? FakeAction.hang
            : FakeAction.ack,
      );
      final summary = await makeRunner(bridge).run();

      expect(summary.timeoutCount, 1);
      expect(summary.firstTryAcks, 4);
      expect(summary.retriedThenAcked, 1);
      expect(summary.failedAfterDefense, 0);
      expect(summary.reinitActivations, isEmpty);
      expect(summary.aborted, isFalse);
      expect(summary.chunkResults.first.outcome, ChunkOutcome.retriedThenAcked);
      expect(summary.chunkResults.first.attempts, 2);
      // The retry re-sent the SAME chunk (idempotent, FR20).
      expect(bridge.sent[0][ProtocolKeys.keyOffset], 0);
      expect(bridge.sent[1][ProtocolKeys.keyOffset], 0);
    });

    test('SDK SUCCESS without watch ack is NOT success', () async {
      final bridge = FakeBridge(
        (offset, attempt) => offset == 0 && attempt == 1
            ? FakeAction.successNoAck
            : FakeAction.ack,
      );
      final summary = await makeRunner(bridge).run();

      expect(summary.timeoutCount, 1);
      expect(summary.retriedThenAcked, 1);
      expect(summary.firstTryAcks, 4);
    });

    test('K=3 consecutive timeouts → reinit exactly once → resend acks',
        () async {
      final bridge = FakeBridge(
        (offset, attempt) => offset == 0 && attempt <= 3
            ? FakeAction.hang
            : FakeAction.ack,
      );
      final summary = await makeRunner(bridge).run();

      expect(bridge.reinitCalls, 1);
      expect(summary.timeoutCount, 3);
      expect(summary.reinitActivations, hasLength(1));
      expect(summary.reinitActivations.single.chunkIndex, 0);
      expect(summary.reinitActivations.single.recovered, isTrue);
      expect(summary.chunkResults.first.outcome, ChunkOutcome.retriedThenAcked);
      expect(summary.chunkResults.first.attempts, 4);
      expect(summary.completedChunks, 5);
      expect(summary.aborted, isFalse);
    });

    test('defense fails → chunk failedAfterDefense, run aborts (OQ2 evidence)',
        () async {
      final bridge = FakeBridge(
        (offset, _) => offset == 0 ? FakeAction.hang : FakeAction.ack,
      );
      final summary = await makeRunner(bridge).run();

      expect(bridge.reinitCalls, 1);
      expect(summary.timeoutCount, 4); // 3 pre-defense + 1 post-reinit
      expect(summary.reinitActivations.single.recovered, isFalse);
      expect(summary.failedAfterDefense, 1);
      expect(summary.chunkResults.single.outcome,
          ChunkOutcome.failedAfterDefense);
      expect(summary.aborted, isTrue);
      expect(summary.completedChunks, 0);
      // Decisive evidence — the run stops, chunk 1 is never attempted.
      expect(
        bridge.sent.every((m) => m[ProtocolKeys.keyOffset] == 0),
        isTrue,
      );
    });
  });

  group('ack matching guards', () {
    test('wrong-offset ack is ignored → timeout → retry → ack', () async {
      final bridge = FakeBridge(
        (offset, attempt) => offset == 0 && attempt == 1
            ? FakeAction.ackWrongOffset
            : FakeAction.ack,
      );
      final summary = await makeRunner(bridge).run();

      expect(summary.timeoutCount, 1);
      expect(summary.firstTryAcks, 4);
      expect(summary.retriedThenAcked, 1);
      expect(summary.completedChunks, 5);
    });

    test('ok:false ack is ignored → timeout → retry → ack', () async {
      final bridge = FakeBridge(
        (offset, attempt) => offset == 0 && attempt == 1
            ? FakeAction.ackNotOk
            : FakeAction.ack,
      );
      final summary = await makeRunner(bridge).run();

      expect(summary.timeoutCount, 1);
      expect(summary.retriedThenAcked, 1);
      expect(summary.completedChunks, 5);
    });

    test('duplicate matching ack is discarded, not double-counted', () async {
      final snapshots = <GateV2Progress>[];
      final bridge = FakeBridge(
        (offset, _) =>
            offset == 0 ? FakeAction.ackTwice : FakeAction.ack,
      );
      final summary =
          await makeRunner(bridge, onProgress: snapshots.add).run();

      expect(summary.completedChunks, 5);
      expect(summary.firstTryAcks, 5);
      expect(snapshots.last.acked, 5);
    });
  });

  group('stream and late-error evidence', () {
    test('stream error event is recorded as evidence, run survives',
        () async {
      final bridge = FakeBridge(
        (offset, _) => offset == 0
            ? FakeAction.streamErrorThenAck
            : FakeAction.ack,
      );
      final summary = await makeRunner(bridge).run();

      expect(summary.completedChunks, 5);
      expect(summary.aborted, isFalse);
      expect(
        summary.exceptionCodes.where((c) => c.startsWith('stream:')),
        hasLength(1),
      );
    });

    test('late send error after the attempt settled is recorded, not lost',
        () async {
      final bridge = FakeBridge((offset, attempt) {
        if (offset == 0) {
          return FakeAction.ackThenLateError;
        }
        // Chunk 1 hangs once so the run is still alive when the late error
        // from chunk 0's send future fires.
        if (offset == 3 && attempt == 1) {
          return FakeAction.hang;
        }
        return FakeAction.ack;
      });
      final summary = await makeRunner(bridge).run();

      expect(summary.completedChunks, 5);
      expect(summary.exceptionCodes, contains('late:[LATE_FAILURE]'));
    });
  });

  group('re-init failure paths', () {
    test('reinit throws → prefixed code recorded → resend still recovers',
        () async {
      final bridge = FakeBridge(
        (offset, attempt) => offset == 0 && attempt <= 3
            ? FakeAction.hang
            : FakeAction.ack,
      )..reinitBehavior = ReinitBehavior.throwError;
      final summary = await makeRunner(bridge).run();

      expect(bridge.reinitCalls, 1);
      expect(summary.exceptionCodes, contains('reinit:[REINIT_FAILED]'));
      expect(summary.reinitActivations.single.recovered, isTrue);
      expect(summary.completedChunks, 5);
      expect(summary.aborted, isFalse);
    });

    test('reinit hangs → timeout-wrapped, recorded → resend still recovers',
        () async {
      final bridge = FakeBridge(
        (offset, attempt) => offset == 0 && attempt <= 3
            ? FakeAction.hang
            : FakeAction.ack,
      )..reinitBehavior = ReinitBehavior.hang;
      final summary = await makeRunner(bridge).run();

      expect(bridge.reinitCalls, 1);
      expect(summary.exceptionCodes, contains('reinit:timeout'));
      expect(summary.reinitActivations.single.recovered, isTrue);
      expect(summary.completedChunks, 5);
    });
  });

  group('per-chunk payload and timing evidence', () {
    test('payloads vary per chunk at identical size', () async {
      final bridge = FakeBridge((_, _) => FakeAction.ack);
      await makeRunner(bridge).run();

      final payloads = bridge.sent
          .map((m) => m[ProtocolKeys.keyPayload]! as String)
          .toList();
      expect(payloads.toSet(), hasLength(5));
      expect(payloads.map((p) => p.length).toSet(), hasLength(1));
    });

    test('attempt wall-clocks are recorded per send, not per chunk',
        () async {
      final bridge = FakeBridge(
        (offset, attempt) => offset == 0 && attempt == 1
            ? FakeAction.hang
            : FakeAction.ack,
      );
      final summary = await makeRunner(bridge).run();

      final retried = summary.chunkResults.first;
      expect(retried.attempts, 2);
      expect(retried.attemptWallClocks, hasLength(2));
      // The first attempt rode the full timeout; the ack-confirmed second
      // attempt did not.
      expect(
        retried.attemptWallClocks.first,
        greaterThanOrEqualTo(const Duration(milliseconds: 40)),
      );
      expect(summary.chunkResults.last.attemptWallClocks, hasLength(1));
    });
  });

  group('PlatformException-style failures (bug mode c)', () {
    test('send error → code recorded verbatim → retry same chunk → ack',
        () async {
      final bridge = FakeBridge(
        (offset, attempt) => offset == 3 && attempt == 1
            ? FakeAction.throwTransferError
            : FakeAction.ack,
      );
      final summary = await makeRunner(bridge).run();

      expect(summary.exceptionCodes, ['[FAILURE_DURING_TRANSFER]']);
      expect(summary.timeoutCount, 0);
      expect(summary.retriedThenAcked, 1);
      expect(summary.firstTryAcks, 4);
      expect(summary.aborted, isFalse);
    });
  });

  group('progress reporting', () {
    test('onProgress streams live counters and last error', () async {
      final snapshots = <GateV2Progress>[];
      final bridge = FakeBridge(
        (offset, attempt) => offset == 0 && attempt == 1
            ? FakeAction.throwTransferError
            : FakeAction.ack,
      );
      await makeRunner(bridge, onProgress: snapshots.add).run();

      expect(snapshots, isNotEmpty);
      final last = snapshots.last;
      expect(last.sent, 6); // 5 chunks + 1 retry
      expect(last.acked, 5);
      expect(last.retries, 1);
      expect(last.defenseActivations, 0);
      expect(
        snapshots.any((p) => p.lastError == '[FAILURE_DURING_TRANSFER]'),
        isTrue,
      );
    });
  });

  group('summary transcript', () {
    test('contains the numbers Task 3 transcribes into gates.md', () async {
      final bridge = FakeBridge(
        (offset, attempt) => offset == 0 && attempt <= 3
            ? FakeAction.hang
            : FakeAction.ack,
      );
      final summary = await makeRunner(bridge).run();
      final text = summary.transcript();

      expect(text, contains('base64String'));
      expect(text, contains('chunks acked: 5/5'));
      expect(text, contains('first-try acks: 4'));
      expect(text, contains('retried-then-acked: 1'));
      expect(text, contains('timeouts: 3'));
      expect(text, contains('re-init activations: 1 (recovered: 1)'));
    });
  });
}

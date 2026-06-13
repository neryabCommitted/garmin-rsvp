import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../protocol/envelope_codec.dart';
import '../protocol/protocol_keys.dart';
import '../protocol/stream_codec.dart';

/// Gate V2 spike engine (Story 1.4) — pure Dart, no Flutter imports, so the
/// retry/defense logic is testable with a fake bridge. Disposable spike code:
/// Epic 4's TransferEngine inherits whatever defense this run validates, in
/// one place (architecture §Process Patterns); this file does not graduate.
///
/// AC1 success definition: a send succeeds only when the watch's ack arrives
/// back on the phone within the timeout — end-to-end. The SDK's `SUCCESS`
/// callback is documented to lie (it can be reported alongside failure, and
/// the listener can silently never fire), so the plugin future completing is
/// deliberately NOT treated as success.

/// Minimal transport seam: the real implementation wraps
/// `watch_connectivity_garmin` (in gate_v2_screen.dart); tests drive a fake.
abstract class SpikeBridge {
  /// Sends one message. May hang forever (the documented bug — callers must
  /// timeout-wrap) or error with a [SpikeSendException].
  Future<void> send(Map<String, Object?> msg);

  /// Re-initializes the underlying SDK session — the V2 defense. Whether
  /// this actually recovers a wedged session is what the hardware run
  /// measures.
  Future<void> reinit();

  /// Inbound messages from the watch (acks, for this spike).
  Stream<Map<String, dynamic>> get messages;
}

/// A send failure with the platform error code verbatim (e.g.
/// `"[FAILURE_DURING_TRANSFER]"`). The bridge adapter translates
/// `PlatformException`s into this so the runner stays Flutter-free.
final class SpikeSendException implements Exception {
  SpikeSendException(this.code, [this.message]);

  /// Platform error code, recorded verbatim in the run stats.
  final String code;
  final String? message;

  @override
  String toString() =>
      'SpikeSendException($code)${message == null ? '' : ': $message'}';
}

/// The two transports SDK 2.0.3 can actually carry (it cannot serialize byte
/// arrays — `MonkeyByteArray` only exists in SDK 2.4.0). Run A vs Run B of
/// the hardware experiment.
enum PayloadEncoding {
  /// `p` as a base64 String (~33% inflation; watch decodes via
  /// `StringUtil.convertEncodedString`).
  base64String,

  /// `p` as a plain `List<int>` (arrives as a Monkey C `Array` of `Number`s;
  /// heavier per-element serialization). Never a `Uint8List` — that reaches
  /// the native serializer as `byte[]` and throws `FAILURE_INVALID_FORMAT`.
  intList,
}

/// Per-chunk end state.
enum ChunkOutcome {
  /// Acked on the first attempt.
  firstTryAck,

  /// Acked after one or more retries (with or without the re-init defense).
  retriedThenAcked,

  /// Still failing after timeout → re-init → resend; the run aborts here —
  /// decisive OQ2 evidence.
  failedAfterDefense,
}

/// One activation of the V2 defense (re-init after K consecutive failures)
/// and whether the post-re-init resend was acked.
final class ReinitActivation {
  const ReinitActivation({required this.chunkIndex, required this.recovered});

  final int chunkIndex;
  final bool recovered;
}

/// One chunk's accounting.
final class ChunkResult {
  const ChunkResult({
    required this.index,
    required this.offset,
    required this.outcome,
    required this.attempts,
    required this.wallClock,
    required this.attemptWallClocks,
  });

  final int index;
  final int offset;
  final ChunkOutcome outcome;
  final int attempts;

  /// Wall-clock across all of this chunk's attempts (excludes any re-init
  /// time between attempts).
  final Duration wallClock;

  /// Per-send-attempt wall-clock, in attempt order — the "wall-clock per
  /// send" evidence (throughput baseline expectation: 1–2 s round trips). A
  /// retried chunk's individual attempts stay distinguishable here.
  final List<Duration> attemptWallClocks;
}

/// Live counters for the harness UI, emitted after every attempt.
final class GateV2Progress {
  const GateV2Progress({
    required this.sent,
    required this.acked,
    required this.retries,
    required this.defenseActivations,
    required this.currentChunk,
    required this.totalChunks,
    this.lastError,
  });

  /// Send attempts fired (including retries).
  final int sent;

  /// Chunks ack-confirmed by the watch.
  final int acked;

  /// Resends (attempts beyond each chunk's first).
  final int retries;

  /// Re-init defense activations.
  final int defenseActivations;

  /// 0-based index of the chunk in flight.
  final int currentChunk;
  final int totalChunks;

  /// Last failure seen: `'timeout'` or a platform code verbatim.
  final String? lastError;
}

/// The measured evidence — transcribed into docs/gates.md and the OQ2 ADR.
final class GateV2Summary {
  const GateV2Summary({
    required this.encoding,
    required this.requestedChunks,
    required this.completedChunks,
    required this.recordsPerChunk,
    required this.payloadBytesPerChunk,
    required this.firstTryAcks,
    required this.retriedThenAcked,
    required this.failedAfterDefense,
    required this.timeoutCount,
    required this.exceptionCodes,
    required this.reinitActivations,
    required this.chunkResults,
    required this.totalWallClock,
    required this.aborted,
  });

  final PayloadEncoding encoding;
  final int requestedChunks;

  /// Chunks ack-confirmed (= [firstTryAcks] + [retriedThenAcked]).
  final int completedChunks;
  final int recordsPerChunk;
  final int payloadBytesPerChunk;
  final int firstTryAcks;
  final int retriedThenAcked;
  final int failedAfterDefense;
  final int timeoutCount;

  /// Platform error codes verbatim, in observation order.
  final List<String> exceptionCodes;
  final List<ReinitActivation> reinitActivations;
  final List<ChunkResult> chunkResults;
  final Duration totalWallClock;

  /// True when a chunk failed even after the defense and the run stopped.
  final bool aborted;

  /// The per-run numbers Task 3 transcribes into gates.md.
  String transcript() {
    final recovered =
        reinitActivations.where((a) => a.recovered).length;
    final codes =
        exceptionCodes.isEmpty ? '(none)' : exceptionCodes.join(', ');
    return [
      'Gate V2 run — encoding: ${encoding.name}',
      'chunks acked: $completedChunks/$requestedChunks'
          '${aborted ? ' (ABORTED after defense failure)' : ''}',
      'records/chunk: $recordsPerChunk, '
          'payload bytes/chunk: $payloadBytesPerChunk',
      'first-try acks: $firstTryAcks',
      'retried-then-acked: $retriedThenAcked',
      'failed-after-defense: $failedAfterDefense',
      'timeouts: $timeoutCount',
      'exception codes: $codes',
      're-init activations: ${reinitActivations.length} '
          '(recovered: $recovered)',
      'total wall-clock: ${totalWallClock.inMilliseconds} ms',
    ].join('\n');
  }
}

/// Drives one spike run: N sequential `chunkData` envelopes, offset-addressed
/// (`off += n`, fixed fingerprint), one AWAITED send in flight (the plugin
/// does not queue — concurrent sends run on parallel native threads; a
/// timed-out attempt's wedged native call cannot be cancelled from Dart and
/// may still be pending when the retry fires), every
/// send timeout-wrapped (the Dart future can hang forever on the known bug),
/// retry-same-chunk on failure (idempotent per FR20), and after
/// [failuresBeforeReinit] consecutive failures the V2 defense: bridge
/// re-init, then one resend. A chunk that fails even then aborts the run —
/// that outcome is decisive OQ2 evidence, not noise to push through.
final class GateV2Runner {
  GateV2Runner({
    required this.bridge,
    required this.encoding,
    this.totalChunks = 200,
    this.recordsPerChunk = 100,
    this.sendTimeout = const Duration(seconds: 10),
    this.failuresBeforeReinit = 3,
    this.onProgress,
  }) {
    if (totalChunks < 1) {
      throw ArgumentError.value(totalChunks, 'totalChunks', 'must be >= 1');
    }
    if (recordsPerChunk < 1 || recordsPerChunk > 999) {
      throw ArgumentError.value(
        recordsPerChunk,
        'recordsPerChunk',
        'must be 1–999',
      );
    }
    if (failuresBeforeReinit < 1) {
      throw ArgumentError.value(
        failuresBeforeReinit,
        'failuresBeforeReinit',
        'must be >= 1',
      );
    }
  }

  /// Fixed spike fingerprint (SPEC §7 wire form; the content is filler).
  static const String fingerprint = 'ab12cd34';

  // Spike-local ack shape, mirrored by named consts in
  // watch/source/GateV2View.mc. Deliberately NOT in protocol_keys.dart —
  // the ack is not protocol and SPEC.md's five types are fixed in v1.
  static const String ackOffsetKey = 'ack';
  static const String ackOkKey = 'ok';

  final SpikeBridge bridge;
  final PayloadEncoding encoding;
  final int totalChunks;
  final int recordsPerChunk;
  final Duration sendTimeout;
  final int failuresBeforeReinit;
  final void Function(GateV2Progress)? onProgress;

  // Pending-ack slot for the single in-flight send.
  Completer<void>? _pendingAck;
  int _pendingOffset = -1;

  // Live counters (snapshotted into GateV2Progress).
  int _sent = 0;
  int _acked = 0;
  int _retries = 0;
  int _defenseActivations = 0;
  int _currentChunk = 0;
  String? _lastError;

  bool _ran = false;

  /// Runs the spike to completion (or defense-failure abort) and returns the
  /// evidence summary. Single-shot: build a new runner per run.
  Future<GateV2Summary> run() async {
    if (_ran) {
      throw StateError('GateV2Runner is single-shot; build a new one per run');
    }
    _ran = true;

    // Filler is size-stable but varies per chunk, so cross-chunk
    // misdelivery, duplication, or reordering cannot decode silently as the
    // right chunk's bytes.
    final payloadBytesPerChunk = encodeChunk(_fillerRecords(0)).length;

    final timeoutCountBox = _Counter();
    final exceptionCodes = <String>[];
    final reinitActivations = <ReinitActivation>[];
    final chunkResults = <ChunkResult>[];
    var firstTryAcks = 0;
    var retriedThenAcked = 0;
    var failedAfterDefense = 0;
    var aborted = false;

    // onError: the plugin's stream mapper can throw on unexpected inbound
    // events (`Map.from` on a non-Map) — an error event must become
    // evidence, not an unhandled async error that kills the run.
    final subscription = bridge.messages.listen(
      _onMessage,
      onError: (Object e) {
        exceptionCodes.add('stream:${_codeOf(e)}');
        _lastError = 'stream:${_codeOf(e)}';
        _emitProgress();
      },
    );
    final totalWatch = Stopwatch()..start();
    try {
      for (var i = 0; i < totalChunks && !aborted; i++) {
        _currentChunk = i;
        final offset = i * recordsPerChunk;
        // Validate through the real codec, then swap `p` for the run's wire
        // encoding. The SPEC §5 bytes underneath are unchanged — the watch
        // reconstructs and StreamDecoder-decodes them, proving end-to-end
        // integrity.
        final payload = encodeChunk(_fillerRecords(i));
        final transport = _transcode(payload);
        final msg = Map<String, Object?>.of(
          chunkDataEnvelope(
            fingerprint: fingerprint,
            offset: offset,
            count: recordsPerChunk,
            payload: payload,
          ),
        )..[ProtocolKeys.keyPayload] = transport;

        final chunkWatch = Stopwatch()..start();
        final attemptWallClocks = <Duration>[];
        var attempts = 0;
        var consecutiveFailures = 0;
        var reinitDone = false;
        ChunkOutcome outcome;
        while (true) {
          attempts++;
          if (attempts > 1) {
            _retries++;
          }
          _sent++;
          final attemptWatch = Stopwatch()..start();
          final failed = !await _attemptAcked(
            msg,
            offset,
            timeoutCountBox,
            exceptionCodes,
          );
          attemptWatch.stop();
          attemptWallClocks.add(attemptWatch.elapsed);
          _emitProgress();
          if (!failed) {
            _acked++;
            _emitProgress();
            outcome = attempts == 1
                ? ChunkOutcome.firstTryAck
                : ChunkOutcome.retriedThenAcked;
            if (reinitDone) {
              reinitActivations
                  .add(ReinitActivation(chunkIndex: i, recovered: true));
            }
            break;
          }
          consecutiveFailures++;
          if (reinitDone) {
            // The defense itself failed — decisive OQ2 evidence. Record and
            // stop; pushing on would only pollute the measurement.
            outcome = ChunkOutcome.failedAfterDefense;
            reinitActivations
                .add(ReinitActivation(chunkIndex: i, recovered: false));
            aborted = true;
            break;
          }
          if (consecutiveFailures >= failuresBeforeReinit) {
            _defenseActivations++;
            // The re-init talks to the same possibly-wedged plugin as the
            // sends — it gets the same timeout discipline, and its failure
            // codes are prefixed so the evidence keeps re-init failures
            // distinguishable from transfer exceptions.
            try {
              await bridge.reinit().timeout(sendTimeout);
            } on TimeoutException {
              exceptionCodes.add('reinit:timeout');
              _lastError = 'reinit:timeout';
            } catch (e) {
              // A failing re-init is itself evidence; the resend still runs.
              exceptionCodes.add('reinit:${_codeOf(e)}');
              _lastError = 'reinit:${_codeOf(e)}';
            }
            reinitDone = true;
            _emitProgress();
          }
        }
        chunkWatch.stop();
        switch (outcome) {
          case ChunkOutcome.firstTryAck:
            firstTryAcks++;
          case ChunkOutcome.retriedThenAcked:
            retriedThenAcked++;
          case ChunkOutcome.failedAfterDefense:
            failedAfterDefense++;
        }
        chunkResults.add(ChunkResult(
          index: i,
          offset: offset,
          outcome: outcome,
          attempts: attempts,
          wallClock: chunkWatch.elapsed,
          attemptWallClocks: List<Duration>.unmodifiable(attemptWallClocks),
        ));
      }
    } finally {
      totalWatch.stop();
      await subscription.cancel();
    }

    return GateV2Summary(
      encoding: encoding,
      requestedChunks: totalChunks,
      completedChunks: firstTryAcks + retriedThenAcked,
      recordsPerChunk: recordsPerChunk,
      payloadBytesPerChunk: payloadBytesPerChunk,
      firstTryAcks: firstTryAcks,
      retriedThenAcked: retriedThenAcked,
      failedAfterDefense: failedAfterDefense,
      timeoutCount: timeoutCountBox.value,
      exceptionCodes: List.unmodifiable(exceptionCodes),
      reinitActivations: List.unmodifiable(reinitActivations),
      chunkResults: List.unmodifiable(chunkResults),
      totalWallClock: totalWatch.elapsed,
      aborted: aborted,
    );
  }

  /// One attempt: fire the send, then wait for the watch's matching ack
  /// within [sendTimeout]. Returns true on ack; false on timeout or send
  /// error (both recorded). The plugin future completing is NOT success.
  Future<bool> _attemptAcked(
    Map<String, Object?> msg,
    int offset,
    _Counter timeoutCount,
    List<String> exceptionCodes,
  ) async {
    final ack = Completer<void>();
    _pendingAck = ack;
    _pendingOffset = offset;
    bridge.send(msg).then<void>(
      (_) {
        // SDK-level SUCCESS — wait for the real ack.
      },
      onError: (Object e) {
        if (!ack.isCompleted) {
          ack.completeError(e);
        } else {
          // The attempt already settled (acked or timed out) — the late code
          // no longer drives retry accounting, but it is still evidence and
          // is recorded, prefixed to stay distinguishable.
          exceptionCodes.add('late:${_codeOf(e)}');
        }
      },
    );
    try {
      await ack.future.timeout(sendTimeout);
      return true;
    } on TimeoutException {
      timeoutCount.value++;
      _lastError = 'timeout';
      return false;
    } catch (e) {
      exceptionCodes.add(_codeOf(e));
      _lastError = _codeOf(e);
      return false;
    } finally {
      _pendingAck = null;
      _pendingOffset = -1;
    }
  }

  void _onMessage(Map<String, dynamic> msg) {
    final ack = _pendingAck;
    if (ack != null &&
        !ack.isCompleted &&
        msg[ackOkKey] == true &&
        msg[ackOffsetKey] == _pendingOffset) {
      ack.complete();
    }
  }

  void _emitProgress() {
    onProgress?.call(GateV2Progress(
      sent: _sent,
      acked: _acked,
      retries: _retries,
      defenseActivations: _defenseActivations,
      currentChunk: _currentChunk,
      totalChunks: totalChunks,
      lastError: _lastError,
    ));
  }

  /// ~9 bytes per record (5-byte header + 4-char ASCII word): the default
  /// 100 records ≈ 900 B, under the conservative ≤1 KB cap (the size sweep
  /// is gate V3 / Story 1.5, not here — AR29). Words derive from the global
  /// record ordinal so consecutive chunks carry different bytes at an
  /// identical size.
  List<WordRecord> _fillerRecords(int chunkIndex) {
    final base = chunkIndex * recordsPerChunk;
    return List<WordRecord>.generate(
      recordsPerChunk,
      (i) => WordRecord(
        word: 'w${((base + i) % 999 + 1).toString().padLeft(3, '0')}',
        flags: 0,
        orpPivot: 1,
        bonusMs: 0,
      ),
    );
  }

  Object _transcode(Uint8List payload) {
    switch (encoding) {
      case PayloadEncoding.base64String:
        return base64.encode(payload);
      case PayloadEncoding.intList:
        // A growable plain list — never hand the serializer a Uint8List.
        return payload.toList();
    }
  }

  String _codeOf(Object e) =>
      e is SpikeSendException ? e.code : e.toString();
}

/// Mutable int box so [GateV2Runner._attemptAcked] can bump the run's timeout
/// tally without widening its return type.
final class _Counter {
  int value = 0;
}

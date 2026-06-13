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
    this.cancelled = false,
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

  /// True when [GateV2Runner.cancel] stopped the run before it finished its
  /// requested chunks (cooperative stop — the in-flight native send may still
  /// be pending; see [GateV2Runner.cancel]).
  final bool cancelled;

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
      'total wall-clock: ${totalWallClock.inMilliseconds} ms'
          '${cancelled ? ' (CANCELLED mid-run)' : ''}',
    ].join('\n');
  }
}

// ── Gate V3 (Story 1.5): per-message size-ceiling sweep ──────────────────────

/// How one sweep send ended. Splits Story 1.4's single `timeoutCount` bucket
/// so a V3 timeout is attributable (deferred-work item #2):
/// - [silentTimeout] vs [successNoAckTimeout] separate the mode-a hung future
///   (send future never completed) from SDK-SUCCESS-without-ack (future
///   completed, watch ack still never arrived) — the runner cannot see the
///   SDK code directly but CAN see whether the send future settled first.
enum SweepSendOutcome {
  /// Watch ack arrived within the timeout — the size carried cleanly.
  ack,

  /// Send errored with a size-class code (`*TOO_LARGE*` / `-102`) — the
  /// rejection the gate hunts for. Class (α phone-cap vs β BLE) is read from
  /// the verbatim code.
  sizeError,

  /// Send errored with a non-size platform code — recorded verbatim, not a
  /// size finding on its own.
  genericError,

  /// Timeout, send future NEVER completed — mode-a silent hang (suspect (c)
  /// until a re-test reproduces it at the same size).
  silentTimeout,

  /// Timeout, but the send future COMPLETED first — SDK said SUCCESS yet no
  /// ack arrived. A reproduced, size-monotonic instance is consistent with a
  /// β BLE reject that suppressed delivery.
  successNoAckTimeout,
}

/// Which ceiling the sweep attributed the reproduced rejection to — the
/// gate's whole point (story Threshold definition α/β/c).
enum RejectionClass {
  /// No reproduced rejection below the cap (no ceiling found in range).
  none,

  /// (α) Phone-side SDK 2.0.3 serializer cap (`FAILURE_MESSAGE_TOO_LARGE`,
  /// ~16 384 serialized bytes) — bites before BLE.
  phoneCapAlpha,

  /// (β) Watch-side BLE per-message cap (`BLE_REQUEST_TOO_LARGE` / `-102`, or
  /// a reproduced delivery-suppressing timeout).
  bleCapBeta,

  /// (c) Mode-a silent hang reproduced at a size — size-independent
  /// reliability bug masquerading as a ceiling; flagged, not treated as one.
  silentHangC,

  /// A reproduced non-size platform error — recorded verbatim for the human
  /// verdict, not a clean size ceiling.
  genericError,
}

/// One sweep send's record — the row-level evidence the gate is built on.
final class SweepStep {
  const SweepStep({
    required this.targetBytes,
    required this.binaryBytes,
    required this.wireBytes,
    required this.sendIndex,
    required this.outcome,
    required this.futureCompleted,
    required this.isRetest,
    this.codeVerbatim,
  });

  /// Requested SPEC §5 payload size for this step.
  final int targetBytes;

  /// Actual SPEC §5 binary payload bytes sent (== [targetBytes] by
  /// construction; recorded as the witness, not assumed).
  final int binaryBytes;

  /// base64 wire length of the payload string `p` — the size the phone-side
  /// (α) serializer cap actually measures against (plus envelope overhead).
  final int wireBytes;

  /// 0-based send index within this size's M sends.
  final int sendIndex;

  final SweepSendOutcome outcome;

  /// Whether the send future settled before the ack timeout — separates
  /// mode-a hang from SUCCESS-without-ack on a [SweepSendOutcome.silentTimeout]
  /// / [SweepSendOutcome.successNoAckTimeout].
  final bool futureCompleted;

  /// True when this send was part of the once-only re-test that rules out a
  /// (c) silent-hang before a size is called the ceiling.
  final bool isRetest;

  /// Platform error code verbatim for size/generic errors; null otherwise.
  final String? codeVerbatim;
}

/// Live sweep readout for the harness UI, emitted after every sweep send.
final class GateV3SweepProgress {
  const GateV3SweepProgress({
    required this.phase,
    required this.currentBytes,
    required this.currentWireBytes,
    required this.sends,
    required this.acks,
    required this.lastGoodBytes,
    this.lastOutcome,
    this.lastCode,
  });

  /// `'coarse'` (geometric) or `'bisect'`.
  final String phase;
  final int currentBytes;
  final int currentWireBytes;
  final int sends;
  final int acks;
  final int? lastGoodBytes;
  final SweepSendOutcome? lastOutcome;
  final String? lastCode;
}

/// The V3 measurement — three numbers + a signature, transcribed into
/// docs/gates.md §V3 and consumed by Epic 4's chunk-size calibration hook
/// (AR23). Sizes are carried in BOTH SPEC §5 binary bytes and base64-wire
/// bytes because the phone cap (α) binds on the wire/serialized size while the
/// BLE cap (β) binds on the message.
final class GateV3SweepSummary {
  const GateV3SweepSummary({
    required this.encoding,
    required this.sendsPerSize,
    required this.safeMarginBytes,
    required this.avgWordBytes,
    required this.lastGoodBytes,
    required this.lastGoodWireBytes,
    required this.firstFailBytes,
    required this.firstFailWireBytes,
    required this.rejectionClass,
    required this.rejectionCode,
    required this.safeWorkingBytes,
    required this.safeWorkingWireBytes,
    required this.perStep,
    required this.totalWallClock,
    required this.cancelled,
  });

  final PayloadEncoding encoding;

  /// M — sends required to ack at each size before stepping up.
  final int sendsPerSize;

  /// Bytes subtracted from last-good for the safe working size (BLE variance +
  /// envelope-overhead headroom).
  final int safeMarginBytes;

  /// Assumed average bytes per real word for the ~words/chunk translation
  /// (5-byte SPEC §5 header + average word length) — stated, not measured.
  final int avgWordBytes;

  /// Highest size that ack-confirmed all M sends (null if even the start size
  /// failed).
  final int? lastGoodBytes;
  final int? lastGoodWireBytes;

  /// Lowest size whose rejection reproduced (null if no ceiling was found in
  /// range — the channel is transport-cap-bounded, not BLE-bounded).
  final int? firstFailBytes;
  final int? firstFailWireBytes;

  final RejectionClass rejectionClass;

  /// The reproduced rejection's platform code verbatim (or a timeout label).
  final String? rejectionCode;

  /// Last-good minus [safeMarginBytes] — the value Epic 4 adopts.
  final int? safeWorkingBytes;
  final int? safeWorkingWireBytes;

  final List<SweepStep> perStep;
  final Duration totalWallClock;

  /// True when [GateV2Runner.cancel] stopped the sweep before it converged.
  final bool cancelled;

  /// ~words/chunk the safe working size affords Epic 4's 200–500-word boundary
  /// chunker (AR23), at [avgWordBytes] bytes/word.
  int? get safeWorkingWords =>
      safeWorkingBytes == null ? null : safeWorkingBytes! ~/ avgWordBytes;

  /// The gates.md §V3-ready evidence block.
  String transcript() {
    String bw(int? binary, int? wire) =>
        binary == null ? '(none)' : '$binary B binary / $wire B wire';
    final acked = perStep.where((s) => s.outcome == SweepSendOutcome.ack).length;
    return [
      'Gate V3 sweep — encoding: ${encoding.name}, M=$sendsPerSize sends/size',
      'last-good size:    ${bw(lastGoodBytes, lastGoodWireBytes)}',
      'first-fail size:   ${bw(firstFailBytes, firstFailWireBytes)}',
      'rejection class:   ${rejectionClass.name}'
          '${rejectionCode == null ? '' : ' (code: $rejectionCode)'}',
      'safe working size: ${bw(safeWorkingBytes, safeWorkingWireBytes)} '
          '(= last-good − $safeMarginBytes B margin)',
      '~words/chunk:      ${safeWorkingWords ?? '(n/a)'} '
          '(at ~$avgWordBytes B/word)',
      'sweep sends:       ${perStep.length} (acked: $acked)'
          '${cancelled ? ' — CANCELLED before convergence' : ''}',
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
    this.onSweepProgress,
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
  final void Function(GateV3SweepProgress)? onSweepProgress;

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

  /// Cooperative cancel flag (deferred-work item #1, now required for the V3
  /// sweep's Stop button). Checked at each chunk/step and send-attempt
  /// boundary. A native send already in flight cannot be force-killed from
  /// Dart (the same uncancellable-pending-call limit Story 1.4 documented for
  /// the retry path), so cancel stops *scheduling* further work and lets the
  /// current attempt settle or time out; the run then returns a partial,
  /// well-formed summary rather than throwing.
  bool _cancelled = false;

  /// Requests a cooperative stop of an in-flight [run] or [runSweep]. Safe to
  /// call from the UI at any time; idempotent.
  void cancel() {
    _cancelled = true;
  }

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
      for (var i = 0; i < totalChunks && !aborted && !_cancelled; i++) {
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
      cancelled: _cancelled,
    );
  }

  // Sweep-local accounting (single-shot runner; reset is implicit per run).
  int _sweepSends = 0;
  int _sweepAcks = 0;
  int _sweepOffset = 0;
  int _seed = 0;
  String _sweepPhase = 'coarse';

  /// Runs the gate V3 size-ceiling sweep: send M chunks at each size, require
  /// all M to ack before stepping up, find the first size whose rejection
  /// reproduces (re-testing once to rule out the (c) silent-hang), then bisect
  /// the last-good→first-fail gap to pin the ceiling. Geometric-coarse then
  /// bisect — the recommended shape (fewest hardware sends, sharpest
  /// threshold). Single-shot: build a new runner per run.
  ///
  /// Sizes are SPEC §5 binary payload bytes. The sweep terminates at
  /// [maxBytes] even if no ceiling appears (then the channel is
  /// transport-cap-bounded, not BLE-bounded — AC1 still records a safe size).
  Future<GateV3SweepSummary> runSweep({
    int startBytes = 768,
    int maxBytes = 20000,
    int sendsPerSize = 3,
    double growthFactor = 2.0,
    int bisectMarginBytes = 256,
    int safeMarginBytes = 512,
    int avgWordBytes = 10,
  }) async {
    if (_ran) {
      throw StateError('GateV2Runner is single-shot; build a new one per run');
    }
    _ran = true;
    if (startBytes < ProtocolKeys.recordHeaderBytes + 1) {
      throw ArgumentError.value(startBytes, 'startBytes', 'must be >= 6');
    }
    if (maxBytes < startBytes) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'must be >= startBytes');
    }
    if (sendsPerSize < 1) {
      throw ArgumentError.value(sendsPerSize, 'sendsPerSize', 'must be >= 1');
    }
    if (growthFactor <= 1.0) {
      throw ArgumentError.value(growthFactor, 'growthFactor', 'must be > 1.0');
    }

    final steps = <SweepStep>[];
    final subscription = bridge.messages.listen(
      _onMessage,
      onError: (Object e) {/* stream errors surface per-send via timeout */},
    );
    final totalWatch = Stopwatch()..start();

    int? lastGood;
    int? firstFail;
    var rejectionClass = RejectionClass.none;
    String? rejectionCode;

    try {
      // ── Coarse (geometric) phase ──
      _sweepPhase = 'coarse';
      var size = startBytes;
      while (size <= maxBytes && !_cancelled) {
        final first = await _probeSize(size, sendsPerSize, isRetest: false, steps: steps);
        if (_cancelled) break;
        if (first.allAcked) {
          lastGood = size;
          size = _grow(size, growthFactor, maxBytes);
          continue;
        }
        // A rejection — re-test the same size once to rule out a (c) hang.
        final retest = await _probeSize(size, sendsPerSize, isRetest: true, steps: steps);
        if (_cancelled) break;
        if (retest.allAcked) {
          // Did not reproduce → transient (mode-a / (c)) noise, not a ceiling.
          lastGood = size;
          size = _grow(size, growthFactor, maxBytes);
          continue;
        }
        // Reproduced → the ceiling is between lastGood and this size.
        firstFail = size;
        rejectionClass = _classify(first, retest);
        rejectionCode = _rejectionCode(first, retest);
        break;
      }

      // ── Bisect phase ──
      if (lastGood != null && firstFail != null && !_cancelled) {
        _sweepPhase = 'bisect';
        var lo = lastGood;
        var hi = firstFail;
        while (hi - lo > bisectMarginBytes && !_cancelled) {
          final mid = lo + (hi - lo) ~/ 2;
          final first = await _probeSize(mid, sendsPerSize, isRetest: false, steps: steps);
          if (_cancelled) break;
          if (first.allAcked) {
            lo = mid;
            continue;
          }
          final retest = await _probeSize(mid, sendsPerSize, isRetest: true, steps: steps);
          if (_cancelled) break;
          if (retest.allAcked) {
            lo = mid;
            continue;
          }
          hi = mid;
          rejectionClass = _classify(first, retest);
          rejectionCode = _rejectionCode(first, retest);
        }
        lastGood = lo;
        firstFail = hi;
      }
    } finally {
      totalWatch.stop();
      await subscription.cancel();
    }

    final safeWorking = lastGood == null
        ? null
        : (lastGood - safeMarginBytes).clamp(0, lastGood);
    return GateV3SweepSummary(
      encoding: encoding,
      sendsPerSize: sendsPerSize,
      safeMarginBytes: safeMarginBytes,
      avgWordBytes: avgWordBytes,
      lastGoodBytes: lastGood,
      lastGoodWireBytes: lastGood == null ? null : _wireBytesFor(lastGood),
      firstFailBytes: firstFail,
      firstFailWireBytes: firstFail == null ? null : _wireBytesFor(firstFail),
      rejectionClass: rejectionClass,
      rejectionCode: rejectionCode,
      safeWorkingBytes: safeWorking,
      safeWorkingWireBytes:
          safeWorking == null ? null : _wireBytesFor(safeWorking),
      perStep: List.unmodifiable(steps),
      totalWallClock: totalWatch.elapsed,
      cancelled: _cancelled,
    );
  }

  /// Sends M chunks at [targetBytes], stopping at the first non-ack. Each send
  /// regenerates size-stable content-varying filler so a misdelivered chunk
  /// cannot decode silently as another (the Story-1.4 property, preserved).
  Future<_ProbeResult> _probeSize(
    int targetBytes,
    int sendsPerSize, {
    required bool isRetest,
    required List<SweepStep> steps,
  }) async {
    final fails = <SweepStep>[];
    for (var s = 0; s < sendsPerSize && !_cancelled; s++) {
      final records = _recordsForBytes(targetBytes, _seed++);
      final payload = encodeChunk(records);
      final binaryBytes = payload.length;
      final wireBytes = base64.encode(payload).length;
      final transport = _transcode(payload);
      final offset = _sweepOffset;
      _sweepOffset += records.length;
      final msg = Map<String, Object?>.of(
        chunkDataEnvelope(
          fingerprint: fingerprint,
          offset: offset,
          count: records.length,
          payload: payload,
        ),
      )..[ProtocolKeys.keyPayload] = transport;

      _sweepSends++;
      final outcome = await _attemptSweepSend(msg, offset);
      if (outcome.outcome == SweepSendOutcome.ack) {
        _sweepAcks++;
      }
      final step = SweepStep(
        targetBytes: targetBytes,
        binaryBytes: binaryBytes,
        wireBytes: wireBytes,
        sendIndex: s,
        outcome: outcome.outcome,
        futureCompleted: outcome.futureCompleted,
        isRetest: isRetest,
        codeVerbatim: outcome.code,
      );
      steps.add(step);
      _emitSweepProgress(binaryBytes, wireBytes, lastGood: null, last: step);
      if (outcome.outcome != SweepSendOutcome.ack) {
        fails.add(step);
        return _ProbeResult(allAcked: false, fails: fails);
      }
    }
    return _ProbeResult(allAcked: !_cancelled, fails: fails);
  }

  /// One sweep send: fire, await the matching ack within [sendTimeout], and
  /// classify the end state — size-class code, generic code, mode-a hang, or
  /// SUCCESS-without-ack (distinguished by whether the send future settled).
  Future<_SweepSendResult> _attemptSweepSend(
    Map<String, Object?> msg,
    int offset,
  ) async {
    final ack = Completer<void>();
    _pendingAck = ack;
    _pendingOffset = offset;
    var futureCompleted = false;
    bridge.send(msg).then<void>(
      (_) => futureCompleted = true,
      onError: (Object e) {
        if (!ack.isCompleted) {
          ack.completeError(e);
        }
      },
    );
    try {
      await ack.future.timeout(sendTimeout);
      return const _SweepSendResult(SweepSendOutcome.ack, null, true);
    } on TimeoutException {
      return _SweepSendResult(
        futureCompleted
            ? SweepSendOutcome.successNoAckTimeout
            : SweepSendOutcome.silentTimeout,
        null,
        futureCompleted,
      );
    } catch (e) {
      final code = _codeOf(e);
      return _SweepSendResult(
        _isSizeError(code)
            ? SweepSendOutcome.sizeError
            : SweepSendOutcome.genericError,
        code,
        futureCompleted,
      );
    } finally {
      _pendingAck = null;
      _pendingOffset = -1;
    }
  }

  /// Case-insensitive match against the known size-class signatures (story
  /// Threshold definition): the SDK serializer cap and the BLE -102 cap.
  static bool _isSizeError(String code) {
    final c = code.toUpperCase();
    return c.contains('TOO_LARGE') || c.contains('-102');
  }

  /// The reproduced failure to attribute — the re-test's, if it failed, else
  /// the first probe's. Null when neither failed.
  SweepStep? _reproducedFail(_ProbeResult first, _ProbeResult retest) {
    final fails = retest.fails.isNotEmpty ? retest.fails : first.fails;
    return fails.isEmpty ? null : fails.last;
  }

  RejectionClass _classify(_ProbeResult first, _ProbeResult retest) {
    final fail = _reproducedFail(first, retest);
    if (fail == null) return RejectionClass.none;
    switch (fail.outcome) {
      case SweepSendOutcome.sizeError:
        final code = (fail.codeVerbatim ?? '').toUpperCase();
        // -102 / BLE_REQUEST_TOO_LARGE is the watch-side BLE cap (β); a plain
        // *MESSAGE_TOO_LARGE* is the phone-side serializer cap (α).
        if (code.contains('-102') || code.contains('BLE')) {
          return RejectionClass.bleCapBeta;
        }
        return RejectionClass.phoneCapAlpha;
      case SweepSendOutcome.successNoAckTimeout:
        // Reproduced, size-monotonic delivery suppression — consistent with β.
        return RejectionClass.bleCapBeta;
      case SweepSendOutcome.silentTimeout:
        return RejectionClass.silentHangC;
      case SweepSendOutcome.genericError:
        return RejectionClass.genericError;
      case SweepSendOutcome.ack:
        return RejectionClass.none;
    }
  }

  String? _rejectionCode(_ProbeResult first, _ProbeResult retest) {
    final fail = _reproducedFail(first, retest);
    if (fail == null) return null;
    return fail.codeVerbatim ?? fail.outcome.name;
  }

  int _grow(int size, double factor, int max) {
    var next = (size * factor).round();
    if (next <= size) next = size + 1;
    if (next > max && size < max) next = max;
    return next;
  }

  /// base64-wire length of a payload of [targetBytes] SPEC §5 binary bytes —
  /// the size the phone serializer cap (α) measures. Deterministic; used to
  /// report sizes the sweep computed but may not have sent (safe-working).
  int _wireBytesFor(int targetBytes) =>
      base64.encode(encodeChunk(_recordsForBytes(targetBytes, 0))).length;

  /// Builds SPEC §5 records summing to EXACTLY [targetBytes] binary bytes, with
  /// content that varies by [seed] at a fixed size (so cross-send misdelivery
  /// can't decode as the right chunk). A record spans 6–260 bytes (5-byte
  /// header + 1–255 ASCII bytes); the tiling keeps every record valid,
  /// including the trailing remainder.
  List<WordRecord> _recordsForBytes(int targetBytes, int seed) {
    const minRecord = ProtocolKeys.recordHeaderBytes + 1; // 6
    const maxRecord = ProtocolKeys.recordHeaderBytes + 255; // 260
    var remaining = targetBytes < minRecord ? minRecord : targetBytes;
    final records = <WordRecord>[];
    var ord = seed;
    while (remaining > 0) {
      final int recordBytes;
      if (remaining <= maxRecord) {
        recordBytes = remaining; // final record: 6..260
      } else if (remaining <= maxRecord + minRecord - 1) {
        // 261..265 would strand 1..5 bytes — split so the leftover stays >= 6.
        recordBytes = remaining - minRecord;
      } else {
        recordBytes = maxRecord;
      }
      final wordLen = recordBytes - ProtocolKeys.recordHeaderBytes; // 1..255
      records.add(WordRecord(
        word: _fillerWord(wordLen, ord++),
        flags: 0,
        orpPivot: 0, // ASCII byte 0 is always a UTF-8 lead byte
        bonusMs: 0,
      ));
      remaining -= recordBytes;
    }
    return records;
  }

  /// [wordLen] ASCII letters (1 byte each), rotated by [ord] so equal-length
  /// words differ across sends.
  String _fillerWord(int wordLen, int ord) {
    return String.fromCharCodes(
      List<int>.generate(wordLen, (i) => 0x61 + ((ord + i) % 26)),
    );
  }

  void _emitSweepProgress(
    int currentBytes,
    int currentWireBytes, {
    required int? lastGood,
    required SweepStep last,
  }) {
    onSweepProgress?.call(GateV3SweepProgress(
      phase: _sweepPhase,
      currentBytes: currentBytes,
      currentWireBytes: currentWireBytes,
      sends: _sweepSends,
      acks: _sweepAcks,
      lastGoodBytes: lastGood,
      lastOutcome: last.outcome,
      lastCode: last.codeVerbatim,
    ));
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

/// One sweep send's classified end state (internal to [GateV2Runner.runSweep]).
final class _SweepSendResult {
  const _SweepSendResult(this.outcome, this.code, this.futureCompleted);

  final SweepSendOutcome outcome;
  final String? code;
  final bool futureCompleted;
}

/// One size-probe's verdict: did all M sends ack, and the failing steps if not.
final class _ProbeResult {
  const _ProbeResult({required this.allAcked, required this.fails});

  final bool allAcked;
  final List<SweepStep> fails;
}

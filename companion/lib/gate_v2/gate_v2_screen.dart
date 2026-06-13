import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:watch_connectivity_garmin/watch_connectivity_garmin.dart';

import 'gate_v2_runner.dart';

/// Gate V2 harness UI (Story 1.4) — disposable spike screen driving
/// [GateV2Runner] over the real Garmin bridge. Run protocol: phone unlocked,
/// Garmin Connect Mobile installed and paired, watch app foregrounded,
/// `flutter run` keeps the device awake over USB debug.

/// Watch app id from watch/manifest.xml.
const String _watchApplicationId = 'dd7ace3fb3f44551bce0cd350896426f';

/// [SpikeBridge] over `watch_connectivity_garmin`. Translates
/// [PlatformException]s into [SpikeSendException]s so the runner stays
/// Flutter-free. `reinit` re-calls the plugin's `initialize` — whether that
/// recovers a wedged session (the plugin never reaches SDK `shutdown()`) is
/// exactly what the hardware run measures.
class GarminSpikeBridge implements SpikeBridge {
  final WatchConnectivityGarmin _plugin = WatchConnectivityGarmin();

  // urlScheme is required by the options class but iOS-only; placeholder.
  // connectType defaults to wireless — Task 3 forbids tethered measurement
  // (SDK 2.0.3's tethered SUCCESS/FAILURE_UNKNOWN bug would pollute it).
  static const GarminInitializationOptions _options =
      GarminInitializationOptions(
    applicationId: _watchApplicationId,
    urlScheme: 'paceturner',
  );

  Future<void> initialize() => _wrap(() => _plugin.initialize(_options));

  @override
  Future<void> reinit() => _wrap(() => _plugin.initialize(_options));

  @override
  Future<void> send(Map<String, Object?> msg) =>
      _wrap(() => _plugin.sendMessage(Map<String, dynamic>.of(msg)));

  @override
  Stream<Map<String, dynamic>> get messages => _plugin.messageStream;

  Future<void> _wrap(Future<void> Function() op) async {
    try {
      await op();
    } on PlatformException catch (e) {
      throw SpikeSendException(e.code, e.message);
    }
  }
}

/// Harness mode: the Story-1.4 fixed-N reliability run, or the Story-1.5 size
/// sweep. One harness, two modes — the runner is shared.
enum _GateMode { reliability, sweep }

class GateV2Screen extends StatefulWidget {
  const GateV2Screen({super.key});

  @override
  State<GateV2Screen> createState() => _GateV2ScreenState();
}

class _GateV2ScreenState extends State<GateV2Screen> {
  final TextEditingController _chunksController =
      TextEditingController(text: '200');
  final TextEditingController _startBytesController =
      TextEditingController(text: '768');
  final TextEditingController _maxBytesController =
      TextEditingController(text: '20000');
  final TextEditingController _sendsController =
      TextEditingController(text: '3');

  _GateMode _mode = _GateMode.reliability;
  PayloadEncoding _encoding = PayloadEncoding.base64String;
  bool _running = false;
  GateV2Progress? _progress;
  GateV2Summary? _summary;
  GateV3SweepProgress? _sweepProgress;
  GateV3SweepSummary? _sweepSummary;
  String? _fatal;

  // Held only while a run is in flight so the Stop button can cancel it
  // cooperatively (a wedged native send still cannot be force-killed).
  GateV2Runner? _runner;

  @override
  void dispose() {
    _chunksController.dispose();
    _startBytesController.dispose();
    _maxBytesController.dispose();
    _sendsController.dispose();
    super.dispose();
  }

  void _stop() {
    _runner?.cancel();
  }

  Future<void> _start() async {
    final int? totalChunks;
    final int startBytes;
    final int maxBytes;
    final int sendsPerSize;
    if (_mode == _GateMode.reliability) {
      totalChunks = int.tryParse(_chunksController.text.trim());
      if (totalChunks == null || totalChunks < 1) {
        setState(() => _fatal = 'N must be a positive integer');
        return;
      }
      startBytes = 0;
      maxBytes = 0;
      sendsPerSize = 0;
    } else {
      totalChunks = null;
      final s = int.tryParse(_startBytesController.text.trim());
      final m = int.tryParse(_maxBytesController.text.trim());
      final ms = int.tryParse(_sendsController.text.trim());
      if (s == null || s < 6 || m == null || m < s || ms == null || ms < 1) {
        setState(() => _fatal =
            'Sweep params invalid (start ≥ 6, max ≥ start, M ≥ 1)');
        return;
      }
      startBytes = s;
      maxBytes = m;
      sendsPerSize = ms;
    }

    setState(() {
      _running = true;
      _progress = null;
      _summary = null;
      _sweepProgress = null;
      _sweepSummary = null;
      _fatal = null;
    });
    try {
      // Bridge built per run, only here — never during widget construction,
      // so the screen stays pumpable without platform channels.
      final bridge = GarminSpikeBridge();
      // initialize() is a platform call into the same SDK that can wedge —
      // it gets the same timeout discipline as sends; a hang surfaces as a
      // fatal error instead of freezing the screen in "Running…" forever.
      await bridge.initialize().timeout(const Duration(seconds: 10));
      if (_mode == _GateMode.reliability) {
        final runner = GateV2Runner(
          bridge: bridge,
          encoding: _encoding,
          totalChunks: totalChunks!,
          onProgress: (p) {
            if (mounted) {
              setState(() => _progress = p);
            }
          },
        );
        _runner = runner;
        final summary = await runner.run();
        if (mounted) {
          setState(() => _summary = summary);
        }
      } else {
        // Sweep transport is base64-String only (ADR 0002); Run B is not
        // re-swept — re-running the rejected encoding adds no decision value.
        final runner = GateV2Runner(
          bridge: bridge,
          encoding: PayloadEncoding.base64String,
          onSweepProgress: (p) {
            if (mounted) {
              setState(() => _sweepProgress = p);
            }
          },
        );
        _runner = runner;
        final summary = await runner.runSweep(
          startBytes: startBytes,
          maxBytes: maxBytes,
          sendsPerSize: sendsPerSize,
        );
        if (mounted) {
          setState(() => _sweepSummary = summary);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _fatal = e.toString());
      }
    } finally {
      _runner = null;
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _mode == _GateMode.reliability ? _summary : _sweepSummary;
    return Scaffold(
      appBar: AppBar(title: const Text('Gate V2/V3 — transfer harness')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<_GateMode>(
            segments: const [
              ButtonSegment(
                value: _GateMode.reliability,
                label: Text('V2: reliability'),
              ),
              ButtonSegment(
                value: _GateMode.sweep,
                label: Text('V3: size sweep'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: _running
                ? null
                : (selection) => setState(() => _mode = selection.first),
          ),
          const SizedBox(height: 12),
          if (_mode == _GateMode.reliability)
            ..._reliabilityControls()
          else
            ..._sweepControls(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _running ? null : _start,
                  child: Text(_running ? 'Running…' : 'Start run'),
                ),
              ),
              if (_running) ...[
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _stop,
                  child: const Text('Stop'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          if (_mode == _GateMode.reliability)
            ..._reliabilityReadout()
          else
            ..._sweepReadout(),
          if (_fatal != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _fatal!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (summary != null) ...[
            const Divider(height: 32),
            Text('Run summary (transcribe into docs/gates.md)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(
              _mode == _GateMode.reliability
                  ? _summary!.transcript()
                  : _sweepSummary!.transcript(),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _reliabilityControls() {
    return [
      SegmentedButton<PayloadEncoding>(
        segments: const [
          ButtonSegment(
            value: PayloadEncoding.base64String,
            label: Text('Run A: base64 String'),
          ),
          ButtonSegment(
            value: PayloadEncoding.intList,
            label: Text('Run B: List<int>'),
          ),
        ],
        selected: {_encoding},
        onSelectionChanged: _running
            ? null
            : (selection) => setState(() => _encoding = selection.first),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _chunksController,
        enabled: !_running,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'N (sequential chunk sends)',
          border: OutlineInputBorder(),
        ),
      ),
    ];
  }

  List<Widget> _sweepControls() {
    return [
      _numberField(_startBytesController, 'Start size (SPEC §5 binary bytes)'),
      const SizedBox(height: 12),
      _numberField(_maxBytesController, 'Max size (hard cap, bytes)'),
      const SizedBox(height: 12),
      _numberField(_sendsController, 'M (sends required to ack per size)'),
      const SizedBox(height: 4),
      const Text(
        'Transport: base64 String (ADR 0002). Geometric-coarse then bisect.',
        style: TextStyle(fontSize: 12),
      ),
    ];
  }

  Widget _numberField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      enabled: !_running,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  List<Widget> _reliabilityReadout() {
    final progress = _progress;
    if (progress == null) {
      return const [];
    }
    return [
      _counter('Chunk', '${progress.currentChunk + 1}/${progress.totalChunks}'),
      _counter('Sent (attempts)', '${progress.sent}'),
      _counter('Acked', '${progress.acked}'),
      _counter('Retries', '${progress.retries}'),
      _counter('Defense activations', '${progress.defenseActivations}'),
      _counter('Last error', progress.lastError ?? '—'),
    ];
  }

  List<Widget> _sweepReadout() {
    final p = _sweepProgress;
    if (p == null) {
      return const [];
    }
    return [
      _counter('Phase', p.phase),
      _counter('Current size', '${p.currentBytes} B / ${p.currentWireBytes} B wire'),
      _counter('Sends', '${p.sends}'),
      _counter('Acks', '${p.acks}'),
      _counter('Last-good', p.lastGoodBytes == null ? '—' : '${p.lastGoodBytes} B'),
      _counter('Last outcome',
          '${p.lastOutcome?.name ?? '—'}${p.lastCode == null ? '' : ' (${p.lastCode})'}'),
    ];
  }

  Widget _counter(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

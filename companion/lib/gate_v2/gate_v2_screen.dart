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

class GateV2Screen extends StatefulWidget {
  const GateV2Screen({super.key});

  @override
  State<GateV2Screen> createState() => _GateV2ScreenState();
}

class _GateV2ScreenState extends State<GateV2Screen> {
  final TextEditingController _chunksController =
      TextEditingController(text: '200');

  PayloadEncoding _encoding = PayloadEncoding.base64String;
  bool _running = false;
  GateV2Progress? _progress;
  GateV2Summary? _summary;
  String? _fatal;

  @override
  void dispose() {
    _chunksController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final totalChunks = int.tryParse(_chunksController.text.trim());
    if (totalChunks == null || totalChunks < 1) {
      setState(() => _fatal = 'N must be a positive integer');
      return;
    }
    setState(() {
      _running = true;
      _progress = null;
      _summary = null;
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
      final summary = await GateV2Runner(
        bridge: bridge,
        encoding: _encoding,
        totalChunks: totalChunks,
        onProgress: (p) {
          if (mounted) {
            setState(() => _progress = p);
          }
        },
      ).run();
      if (mounted) {
        setState(() => _summary = summary);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _fatal = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final summary = _summary;
    return Scaffold(
      appBar: AppBar(title: const Text('Gate V2 — transfer reliability')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _running ? null : _start,
            child: Text(_running ? 'Running…' : 'Start run'),
          ),
          const SizedBox(height: 16),
          if (progress != null) ...[
            _counter('Chunk', '${progress.currentChunk + 1}'
                '/${progress.totalChunks}'),
            _counter('Sent (attempts)', '${progress.sent}'),
            _counter('Acked', '${progress.acked}'),
            _counter('Retries', '${progress.retries}'),
            _counter('Defense activations', '${progress.defenseActivations}'),
            _counter('Last error', progress.lastError ?? '—'),
          ],
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
              summary.transcript(),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ],
      ),
    );
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'ui/library/share_receiver.dart';

// Story 2.3: the app now boots into the real library UI (the Gate V2 spike
// harness in `gate_v2/` is preserved but no longer the entry point). Riverpod's
// ProviderScope is the root; the real share-sheet source is injected here so
// tests keep the no-op default (no platform channels).
void main() {
  runApp(
    ProviderScope(
      overrides: [
        shareSourceProvider.overrideWithValue(const PluginShareSource()),
      ],
      child: const PaceTurnerApp(),
    ),
  );
}

import 'package:flutter/material.dart';

import 'gate_v2/gate_v2_screen.dart';

// Spike entry point (Story 1.4): the app currently boots straight into the
// Gate V2 transfer-reliability harness. The real library UI is Epic 2.
void main() {
  runApp(const PaceTurnerApp());
}

class PaceTurnerApp extends StatelessWidget {
  const PaceTurnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PaceTurner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: const GateV2Screen(),
    );
  }
}

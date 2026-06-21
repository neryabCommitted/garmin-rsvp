/// The companion app shell (Story 2.3): Material 3 with a seeded color scheme
/// and system light/dark (architecture.md:204). Boots into the [LibraryScreen]
/// — the Gate V2 spike harness is no longer the entry point (its files and tests
/// are preserved; we just stop booting into it).
library;

import 'package:flutter/material.dart';

import 'ui/library/library_screen.dart';

class PaceTurnerApp extends StatelessWidget {
  const PaceTurnerApp({super.key});

  /// The pivot red (UX-DR3 / DESIGN.md:27) — the single brand chromatic,
  /// softened from RSVPnano's pure red. On the phone it is the *fallback* scheme
  /// seed (dynamic color / Material You is a separate UI-story enhancement).
  static const Color _pivotSeed = Color(0xFFFF5349);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PaceTurner',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _pivotSeed),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _pivotSeed,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const LibraryScreen(),
    );
  }
}

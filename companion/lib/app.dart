/// The companion app shell (Story 2.3): Material 3 with a seeded color scheme
/// and system light/dark (architecture.md:204). Boots into the [LibraryScreen]
/// — the Gate V2 spike harness is no longer the entry point (its files and tests
/// are preserved; we just stop booting into it).
library;

import 'package:flutter/material.dart';

import 'ui/library/library_screen.dart';

class PaceTurnerApp extends StatelessWidget {
  const PaceTurnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PaceTurner',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const LibraryScreen(),
    );
  }
}

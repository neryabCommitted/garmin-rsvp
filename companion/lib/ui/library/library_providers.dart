/// Riverpod wiring for the library (Story 2.3, AC2). Names end in `Provider`
/// (architecture.md:285). The UI layer reaches drift and the import service
/// **only** through these providers — never by importing `data/` directly
/// (layering, architecture.md:452).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../data/stream_store.dart';
import '../../services/import/import_service.dart';

/// The single on-device drift connection. Closed when the scope disposes.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});

/// The flat-file word-stream store (resolves the app support dir at runtime).
final streamStoreProvider = Provider<StreamStore>((ref) => StreamStore());

/// The import orchestrator, composing the database and the stream store.
final importServiceProvider = Provider<ImportService>(
  (ref) => ImportService(
    ref.watch(databaseProvider),
    ref.watch(streamStoreProvider),
  ),
);

/// Reactive library list (FR16-ready), driven by drift's `watchAllBooks`.
final libraryProvider = StreamProvider<List<Book>>(
  (ref) => ref.watch(databaseProvider).watchAllBooks(),
);

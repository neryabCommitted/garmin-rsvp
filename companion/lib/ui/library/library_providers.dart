/// Riverpod wiring for the library (Story 2.3, AC2). Names end in `Provider`
/// (architecture.md:285). The UI layer reaches drift and the import service
/// **only** through these providers — never by importing `data/` directly
/// (layering, architecture.md:452).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../data/stream_store.dart';
import '../../services/import/import_service.dart';
import '../../services/library/library_service.dart';

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

/// Reactive single book for the detail screen (2.5, AC1). Emits null once the
/// row is removed — the detail screen pops on that null.
final bookDetailProvider = StreamProvider.family<Book?, int>(
  (ref, id) => ref.watch(databaseProvider).watchBookById(id),
);

/// Reactive chapter list for the detail screen (2.5, AC1), in reading order.
final chaptersProvider = StreamProvider.family<List<Chapter>, int>(
  (ref, id) => ref.watch(databaseProvider).chaptersForBook(id),
);

/// Library-management service (2.5, AC3) — coordinates Remove behind the
/// ui→services→data layering. Constructor-injected (architecture.md:285).
final libraryServiceProvider = Provider<LibraryService>(
  (ref) => LibraryService(
    ref.watch(databaseProvider),
    ref.watch(streamStoreProvider),
  ),
);

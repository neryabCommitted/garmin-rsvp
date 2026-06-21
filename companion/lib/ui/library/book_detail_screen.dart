/// The book-detail screen (Story 2.5, AC1/AC2/AC4) — the app's second surface,
/// reached by `Navigator.push` from a library row.
///
/// Layering (architecture.md:452): this widget reads the book and its chapters
/// **only** through providers, and mutates **only** via `libraryServiceProvider`
/// — it never imports `data/`/`stream_store`/`drift`. The cover is rendered
/// straight from `book.coverPath` + `Image.file` (the same pattern as the row).
///
/// Scope (2.5): cover header, metadata, **placeholder** progress, and the
/// chapter list. Send-to-watch and jump-to-chapter are rendered **inert** until
/// Epic 4; Restart asks once but performs no state change (no `Positions` table
/// yet — the reposition rides the `position` message in Epic 4).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import 'library_providers.dart';

class BookDetailScreen extends ConsumerWidget {
  const BookDetailScreen({required this.bookId, super.key});

  final int bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookAsync = ref.watch(bookDetailProvider(bookId));
    final chaptersAsync = ref.watch(chaptersProvider(bookId));

    return bookAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Failed to load book: $error')),
      ),
      data: (book) {
        if (book == null) {
          // Removed out from under the screen (Task 5 Remove relies on this):
          // pop back to the library if we can, else show a minimal fallback.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
          return const Scaffold(
            body: Center(child: Text('This book was removed.')),
          );
        }
        return _DetailView(book: book, chaptersAsync: chaptersAsync);
      },
    );
  }
}

class _DetailView extends ConsumerWidget {
  const _DetailView({required this.book, required this.chaptersAsync});

  final Book book;
  final AsyncValue<List<Chapter>> chaptersAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final author = book.author;
    // Resolve the chapters state with error taking precedence over loading.
    // (A StreamProvider in error reports both `isLoading` and `hasError`, so
    // `AsyncValue.when` — which checks loading first — would mask the error.)
    final chapters = chaptersAsync.hasValue ? chaptersAsync.value : null;
    // The metadata line shows the chapter count only once chapters resolve —
    // while loading / on error it falls back to the word count rather than
    // claiming "0 chapters".
    final metaText = chapters != null
        ? '${chapters.length} ${chapters.length == 1 ? 'chapter' : 'chapters'} · ${book.totalWords} words'
        : '${book.totalWords} words';
    // Chapter list, reading order. A load error / in-flight read is rendered as
    // such — never silently flattened to an empty list (which would be
    // indistinguishable from a genuinely chapterless book). Jump-to-chapter is
    // INERT (Epic 4): rows are disabled (no onTap).
    final List<Widget> chapterWidgets;
    if (chaptersAsync.hasError) {
      chapterWidgets = <Widget>[
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Failed to load chapters: ${chaptersAsync.error}'),
        ),
      ];
    } else if (chapters != null) {
      chapterWidgets = <Widget>[
        for (final c in chapters)
          ListTile(
            enabled: false,
            leading: Text('${c.chapterIndex + 1}'),
            title: Text(c.title),
          ),
      ];
    } else {
      chapterWidgets = const <Widget>[
        Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    return Scaffold(
      appBar: AppBar(title: Text(book.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Center(child: _CoverHeader(coverPath: book.coverPath)),
          const SizedBox(height: 16),
          Text(book.title, style: Theme.of(context).textTheme.headlineSmall),
          if (author != null && author.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                author,
                key: const Key('book-author'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            metaText,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          // Progress area — PLACEHOLDER until Epic 4 (no Positions table yet),
          // matching the library row's 0% / "Not started".
          const LinearProgressIndicator(value: 0),
          const SizedBox(height: 4),
          const Text('Not started'),
          const SizedBox(height: 24),
          // Send to watch — prominent M3 filled button, rendered INERT (Epic 4).
          FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.watch),
            label: const Text('Send to watch'),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextButton(
                  onPressed: () => _confirmRestart(context),
                  child: const Text('Restart book'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton(
                  onPressed: () => _confirmRemove(context, ref),
                  child: const Text('Remove'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Chapters', style: Theme.of(context).textTheme.titleSmall),
          ...chapterWidgets,
        ],
      ),
    );
  }

  /// Remove (AC3): confirm once, then delete via the service. The screen pops
  /// itself when `bookDetailProvider` emits null after the row is gone. The
  /// happy path is idempotent and never throws; an unexpected IO/permission
  /// failure is surfaced as a SnackBar (the row may already be gone, so we do
  /// not assume the screen is still mounted) rather than swallowed.
  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${book.title}?'),
        content: const Text('This deletes the book from this device.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    // Capture the messenger before the removeBook await — the row removal makes
    // `bookDetailProvider` emit null and pops this screen, so `context` may be
    // defunct by the time the future settles.
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(libraryServiceProvider).removeBook(book);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not remove ${book.title}: $error')),
      );
    }
  }

  /// Restart (AC4): asks once. The reposition (word index → 0 + watch re-sync)
  /// rides the `position` message in Epic 4 — there is no `Positions` table in
  /// 2.5, so confirming performs no persisted state change.
  Future<void> _confirmRestart(BuildContext context) async {
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Restart ${book.title}?'),
        content: const Text('Reading starts again from the beginning.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            // TODO(epic-4): reposition to word index 0 + position re-sync.
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Restart'),
          ),
        ],
      ),
    );
  }
}

/// The detail-header cover: the cover file when present, else an M3 placeholder.
/// A larger variant of the library row's `_CoverThumbnail`; a missing/unreadable
/// file falls back to the placeholder rather than throwing.
class _CoverHeader extends StatelessWidget {
  const _CoverHeader({required this.coverPath});

  final String? coverPath;

  static const double _width = 140;
  static const double _height = 200;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(8);
    final path = coverPath;
    if (path == null) {
      return _placeholder(context, radius);
    }
    return ClipRRect(
      borderRadius: radius,
      child: Image.file(
        File(path),
        width: _width,
        height: _height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _placeholder(context, radius),
      ),
    );
  }

  Widget _placeholder(BuildContext context, BorderRadius radius) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: _width,
      height: _height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: radius,
      ),
      child: Icon(Icons.menu_book, size: 48, color: scheme.onSurfaceVariant),
    );
  }
}

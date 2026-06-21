/// The library — the first real screen (Story 2.3, AC2/AC3). Lists imported
/// books from the reactive [libraryProvider] and offers the file-picker import.
///
/// Layering (architecture.md:452): this widget reaches drift/import **only**
/// through providers — it never imports `data/` or `stream_store` directly.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../data/db/database.dart';
import '../../services/import/import_service.dart';
import 'book_detail_screen.dart';
import 'library_providers.dart';
import 'share_receiver.dart';

/// Verbatim empty-state copy (AC3) — the product's canonical line; do not reword
/// even though this story only imports txt/md.
const String kEmptyLibraryMessage = 'Add a DRM-free EPUB to begin.';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _importing = false;
  StreamSubscription<List<SharedMediaFile>>? _shareSub;

  /// AC2: the last failed-import message, shown **inline** on the library
  /// surface (not a transient toast). Held in screen state — separate from the
  /// drift-driven [libraryProvider] — so a stream reload never clears it and it
  /// never shadows the list's own loading/error arms. Cleared on the next
  /// successful import or on dismiss.
  String? _lastImportError;

  @override
  void initState() {
    super.initState();
    // Share-sheet entry (AC6): subscribe to warm + cold-start deliveries. The
    // source is a no-op in tests (see share_receiver.dart), so this is inert
    // unless the real plugin is injected by main.dart.
    final source = ref.read(shareSourceProvider);
    _shareSub = source.mediaStream().listen(_handleShared);
    source.initialMedia().then((files) async {
      if (files.isNotEmpty) {
        await _handleShared(files);
      }
      // Reset only after the cold-start payload is fully consumed — clearing the
      // intent before the import completes leaves reset-vs-import ordering undefined.
      source.reset();
    });
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  Future<void> _import() async {
    if (_importing) return;

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['txt', 'md', 'markdown', 'epub'],
      withData: true,
    );
    final file = picked?.files.singleOrNull;
    if (file == null || file.bytes == null) {
      return; // user cancelled, or no data available
    }
    await _runImport(path: file.path ?? file.name, bytes: file.bytes!);
  }

  /// Adapts shared payloads into the already-tested [_runImport]. Shared raw
  /// text arrives as [SharedMediaType.text] with the text in `path`; shared
  /// files arrive as [SharedMediaType.file] with a real file path.
  Future<void> _handleShared(List<SharedMediaFile> files) async {
    for (final f in files) {
      switch (f.type) {
        case SharedMediaType.text:
          final isMd = (f.mimeType ?? '').contains('markdown');
          await _runImport(
            path: isMd ? 'Shared.md' : 'Shared text.txt',
            bytes: utf8.encode(f.path),
          );
        case SharedMediaType.file:
          final file = File(f.path);
          if (await file.exists()) {
            await _runImport(path: f.path, bytes: await file.readAsBytes());
          }
        case SharedMediaType.image:
        case SharedMediaType.video:
        case SharedMediaType.url:
          break; // unsupported here
      }
    }
  }

  /// The single import path shared by the picker and the share sheet.
  Future<void> _runImport({
    required String path,
    required List<int> bytes,
  }) async {
    if (_importing) return;
    setState(() => _importing = true);
    final ImportResult result;
    try {
      result = await ref.read(importServiceProvider).importFile(
            path: path,
            bytes: bytes,
          );
    } finally {
      if (mounted) setState(() => _importing = false);
    }

    if (!mounted) return;
    // AC2: a failure shows an inline message; a success clears any prior one.
    setState(() {
      _lastImportError = result is ImportFailure ? _failureMessage(result) : null;
    });
  }

  /// Canonical copy (EXPERIENCE.md:114): `Couldn't read "{filename}" — {reason}`.
  /// ASCII apostrophe + em-dash; non-blaming, actionable reason text per
  /// `ImportFailureReason` (UX voice — extract-product.md:190).
  String _failureMessage(ImportFailure failure) {
    final reason = switch (failure.reason) {
      ImportFailureReason.emptyContent => "it's empty",
      ImportFailureReason.unreadable =>
        'the file is damaged or not a valid EPUB',
      ImportFailureReason.unsupported =>
        "it's protected (DRM) or uses content we can't read",
      ImportFailureReason.ioError => "it couldn't be saved",
    };
    return 'Couldn\'t read "${failure.filename}" — $reason';
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: Column(
        children: <Widget>[
          // AC2: inline failure message above the list — visible even when the
          // import left the library empty, so a failed import still says why.
          if (_lastImportError != null)
            _ImportErrorBanner(
              message: _lastImportError!,
              onDismiss: () => setState(() => _lastImportError = null),
            ),
          Expanded(
            child: library.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text('Failed to load library: $error')),
              data: (books) => books.isEmpty
                  ? const _EmptyLibrary()
                  : _BookList(books: books),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _import,
        icon: _importing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(_importing ? 'Importing…' : 'Import'),
      ),
    );
  }
}

/// AC2 inline import-failure banner — an M3 [MaterialBanner] rendered in the
/// library body (not a SnackBar), using the error color role (the phone may use
/// the full semantic palette; the one-red rule is watch-only — DESIGN.md:26,111).
class _ImportErrorBanner extends StatelessWidget {
  const _ImportErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MaterialBanner(
      backgroundColor: scheme.errorContainer,
      leading: Icon(Icons.error_outline, color: scheme.onErrorContainer),
      content: Text(
        message,
        style: TextStyle(color: scheme.onErrorContainer),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: onDismiss,
          child: const Text('Dismiss'),
        ),
      ],
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          kEmptyLibraryMessage,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _BookList extends StatelessWidget {
  const _BookList({required this.books});

  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        final author = book.author;
        return ListTile(
          // M3 ListTile with a cover thumbnail (AC4); placeholder when none.
          leading: _CoverThumbnail(coverPath: book.coverPath),
          // Row tap → book detail (Story 2.5). The app has no router; a plain
          // Navigator.push is the M3-idiomatic choice for a two-screen app.
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => BookDetailScreen(bookId: book.id),
            ),
          ),
          title: Text(book.title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // OPF author (AC4); the line is omitted when there is no author.
              if (author != null && author.isNotEmpty) Text(author),
              // last-read placeholder (lastReadEpochS is null until Epic 4).
              const Text('Not started'),
              const SizedBox(height: 4),
              // Thin 0% progress bar (UI placeholder — no Positions table yet).
              const LinearProgressIndicator(value: 0),
            ],
          ),
        );
      },
    );
  }
}

/// The library-row cover thumbnail (AC4): the cover file when present, else an
/// M3 placeholder. A missing/unreadable file falls back to the placeholder via
/// [Image.file]'s `errorBuilder` rather than throwing.
class _CoverThumbnail extends StatelessWidget {
  const _CoverThumbnail({required this.coverPath});

  final String? coverPath;

  static const double _width = 40;
  static const double _height = 56;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(4);
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
      child: Icon(Icons.menu_book, color: scheme.onSurfaceVariant),
    );
  }
}

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
      allowedExtensions: const <String>['txt', 'md', 'markdown'],
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
    if (result is ImportFailure) {
      // Full inline error UX is 2.6; a SnackBar is enough here.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(result))),
      );
    }
  }

  String _failureMessage(ImportFailure failure) {
    final what = switch (failure.reason) {
      ImportFailureReason.emptyContent => 'is empty',
      ImportFailureReason.unreadable => 'could not be read',
      ImportFailureReason.unsupported => 'is not a supported file',
      ImportFailureReason.ioError => 'could not be saved',
    };
    return 'Couldn’t import "${failure.filename}" — it $what.';
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: library.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load library: $error')),
        data: (books) =>
            books.isEmpty ? const _EmptyLibrary() : _BookList(books: books),
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
        return ListTile(
          title: Text(book.title),
          // last-read placeholder (lastReadEpochS is null until Epic 4).
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const <Widget>[
              Text('Not started'),
              SizedBox(height: 4),
              // Thin 0% progress bar (UI placeholder — no Positions table yet).
              LinearProgressIndicator(value: 0),
            ],
          ),
        );
      },
    );
  }
}

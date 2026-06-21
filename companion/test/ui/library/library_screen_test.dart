import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/data/db/database.dart';
import 'package:paceturner_companion/data/stream_store.dart';
import 'package:paceturner_companion/services/import/import_service.dart';
import 'package:paceturner_companion/ui/library/book_detail_screen.dart';
import 'package:paceturner_companion/ui/library/library_providers.dart';
import 'package:paceturner_companion/ui/library/library_screen.dart';
import 'package:paceturner_companion/ui/library/share_receiver.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

Book sampleBook({
  int id = 1,
  String title = 'A Test Book',
  String? author,
  String? coverPath,
}) =>
    Book(
      id: id,
      title: title,
      author: author,
      coverPath: coverPath,
      streamPath: '/streams/abc.stream',
      fingerprint: 'abc12345',
      totalWords: 1000,
      totalBonusMs: 0,
      createdAtEpochS: 100,
    );

Widget harness(Stream<List<Book>> books) => ProviderScope(
      overrides: [
        libraryProvider.overrideWith((ref) => books),
      ],
      child: const MaterialApp(home: LibraryScreen()),
    );

void main() {
  testWidgets('empty library shows the exact AC3 copy + an import affordance',
      (tester) async {
    await tester.pumpWidget(harness(Stream<List<Book>>.value(const <Book>[])));
    await tester.pump();

    expect(find.text('Add a DRM-free EPUB to begin.'), findsOneWidget);
    expect(find.widgetWithText(FloatingActionButton, 'Import'), findsOneWidget);
  });

  testWidgets('a book renders as a ListTile with a 0%-value progress bar',
      (tester) async {
    await tester.pumpWidget(
      harness(Stream<List<Book>>.value(<Book>[sampleBook(title: 'Moby Dick')])),
    );
    await tester.pump();

    expect(find.widgetWithText(ListTile, 'Moby Dick'), findsOneWidget);
    expect(find.text('Add a DRM-free EPUB to begin.'), findsNothing);

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.0);
  });

  testWidgets('a book with an author + cover renders the author and a cover image',
      (tester) async {
    await tester.pumpWidget(
      harness(Stream<List<Book>>.value(<Book>[
        sampleBook(title: 'Moby Dick', author: 'Herman Melville', coverPath: '/covers/abc12345.jpg'),
      ])),
    );
    await tester.pump();

    expect(find.text('Herman Melville'), findsOneWidget);
    // A cover image widget is chosen when coverPath is set (decoding not exercised).
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.menu_book), findsNothing);
  });

  testWidgets('a book with no cover renders the placeholder, no Image.file',
      (tester) async {
    await tester.pumpWidget(
      harness(Stream<List<Book>>.value(<Book>[sampleBook(title: 'Coverless')])),
    );
    await tester.pump();

    expect(find.byIcon(Icons.menu_book), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a book with no author omits the author line', (tester) async {
    await tester.pumpWidget(
      harness(Stream<List<Book>>.value(<Book>[sampleBook(title: 'Anon', coverPath: '/covers/x.jpg')])),
    );
    await tester.pump();

    expect(find.widgetWithText(ListTile, 'Anon'), findsOneWidget);
    // "Not started" placeholder still present; no spurious empty author line.
    expect(find.text('Not started'), findsOneWidget);
  });

  testWidgets('tapping a row pushes the BookDetailScreen (AC1 navigation)',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryProvider.overrideWith((ref) => Stream<List<Book>>.value(
                <Book>[sampleBook(id: 7, title: 'Tappable')],
              )),
          // The pushed detail screen reads these for book id 7.
          bookDetailProvider(7).overrideWith(
            (ref) => Stream.value(sampleBook(id: 7, title: 'Tappable')),
          ),
          chaptersProvider(7).overrideWith(
            (ref) => Stream.value(const <Chapter>[]),
          ),
        ],
        child: const MaterialApp(home: LibraryScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(BookDetailScreen), findsNothing);

    await tester.tap(find.widgetWithText(ListTile, 'Tappable'));
    await tester.pumpAndSettle();

    expect(find.byType(BookDetailScreen), findsOneWidget);
  });

  testWidgets('multiple books all render', (tester) async {
    await tester.pumpWidget(
      harness(Stream<List<Book>>.value(<Book>[
        sampleBook(id: 1, title: 'One'),
        sampleBook(id: 2, title: 'Two'),
      ])),
    );
    await tester.pump();

    expect(find.byType(ListTile), findsNWidgets(2));
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsOneWidget);
  });

  // ── Story 2.6, Task 7 — inline import-failure message (AC2) ──────────────────
  group('2.6 — inline import-failure message', () {
    // Drives a failing/succeeding import through the injectable share-source
    // seam (the same `_runImport` path as the picker), with a fake
    // ImportService returning a preset result.
    late _FakeShareSource share;
    late _FakeImportService importer;

    setUp(() {
      share = _FakeShareSource();
      importer = _FakeImportService();
    });
    tearDown(() async {
      await share.dispose();
      await importer.dispose();
    });

    Widget importHarness() => ProviderScope(
          overrides: [
            libraryProvider.overrideWith(
              (ref) => Stream<List<Book>>.value(const <Book>[]),
            ),
            shareSourceProvider.overrideWithValue(share),
            importServiceProvider.overrideWithValue(importer),
          ],
          child: const MaterialApp(home: LibraryScreen()),
        );

    Future<void> shareSomething(WidgetTester tester) async {
      share.controller.add(<SharedMediaFile>[
        SharedMediaFile(path: 'irrelevant text', type: SharedMediaType.text),
      ]);
      await tester.pumpAndSettle();
    }

    testWidgets('a failed import renders the exact canonical inline message',
        (tester) async {
      importer.result =
          const ImportFailure(ImportFailureReason.unsupported, 'bad.epub');
      await tester.pumpWidget(importHarness());
      await tester.pump();

      await shareSomething(tester);

      // Canonical copy (EXPERIENCE.md:114), exact filename + mapped reason.
      expect(
        find.text(
          'Couldn\'t read "bad.epub" — '
          "it's protected (DRM) or uses content we can't read",
        ),
        findsOneWidget,
      );
      // Inline, not a transient toast.
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(MaterialBanner), findsOneWidget);
      // The bad book never appears in the list.
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('the reason text maps per ImportFailureReason', (tester) async {
      importer.result =
          const ImportFailure(ImportFailureReason.emptyContent, 'hollow.txt');
      await tester.pumpWidget(importHarness());
      await tester.pump();
      await shareSomething(tester);

      expect(
        find.text('Couldn\'t read "hollow.txt" — it\'s empty'),
        findsOneWidget,
      );
    });

    testWidgets('a successful import afterward clears the message',
        (tester) async {
      importer.result =
          const ImportFailure(ImportFailureReason.unreadable, 'broken.epub');
      await tester.pumpWidget(importHarness());
      await tester.pump();
      await shareSomething(tester);
      expect(find.byType(MaterialBanner), findsOneWidget);

      importer.result = const ImportSuccess(1);
      await shareSomething(tester);

      expect(find.byType(MaterialBanner), findsNothing);
    });

    testWidgets('dismiss clears the message', (tester) async {
      importer.result =
          const ImportFailure(ImportFailureReason.ioError, 'oops.txt');
      await tester.pumpWidget(importHarness());
      await tester.pump();
      await shareSomething(tester);
      expect(find.byType(MaterialBanner), findsOneWidget);

      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();

      expect(find.byType(MaterialBanner), findsNothing);
    });
  });
}

/// A share source whose `mediaStream` is driven by the test, so an import can be
/// triggered without the file picker or real platform channels.
class _FakeShareSource implements ShareSource {
  final StreamController<List<SharedMediaFile>> controller =
      StreamController<List<SharedMediaFile>>.broadcast();

  @override
  Stream<List<SharedMediaFile>> mediaStream() => controller.stream;

  @override
  Future<List<SharedMediaFile>> initialMedia() async =>
      const <SharedMediaFile>[];

  @override
  void reset() {}

  Future<void> dispose() => controller.close();
}

/// A drop-in [ImportService] returning a preset [result] (mutable between
/// imports). The injected db/store are never exercised — `importFile` is
/// overridden — but the db is held so the test can close it cleanly.
class _FakeImportService extends ImportService {
  _FakeImportService._(this._db) : super(_db, StreamStore());

  factory _FakeImportService() =>
      _FakeImportService._(AppDatabase(NativeDatabase.memory()));

  final AppDatabase _db;
  ImportResult result = const ImportFailure(ImportFailureReason.ioError, 'x');

  @override
  Future<ImportResult> importFile({
    required String path,
    required List<int> bytes,
  }) async =>
      result;

  Future<void> dispose() => _db.close();
}

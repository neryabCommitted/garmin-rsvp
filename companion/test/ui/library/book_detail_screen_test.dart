import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/data/db/database.dart';
import 'package:paceturner_companion/services/library/library_service.dart';
import 'package:paceturner_companion/ui/library/book_detail_screen.dart';
import 'package:paceturner_companion/ui/library/library_providers.dart';

Book sampleBook({
  int id = 1,
  String title = 'A Test Book',
  String? author,
  String? coverPath,
  int totalWords = 1000,
}) =>
    Book(
      id: id,
      title: title,
      author: author,
      coverPath: coverPath,
      streamPath: '/streams/abc.stream',
      fingerprint: 'abc12345',
      totalWords: totalWords,
      totalBonusMs: 0,
      createdAtEpochS: 100,
    );

Chapter chapter(int index, String title) => Chapter(
      id: index + 1,
      bookId: 1,
      chapterIndex: index,
      title: title,
      wordOffset: index * 100,
      cumulativeBonusMs: 0,
    );

/// A spy LibraryService that records removeBook calls without touching disk.
class _SpyLibraryService implements LibraryService {
  final List<Book> removed = <Book>[];
  @override
  Future<void> removeBook(Book book) async => removed.add(book);
}

Widget harness({
  required Book? book,
  List<Chapter> chapters = const <Chapter>[],
  LibraryService? service,
  int bookId = 1,
}) =>
    ProviderScope(
      overrides: [
        bookDetailProvider(bookId).overrideWith((ref) => Stream.value(book)),
        chaptersProvider(bookId).overrideWith((ref) => Stream.value(chapters)),
        if (service != null) libraryServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(home: BookDetailScreen(bookId: bookId)),
    );

void main() {
  testWidgets('AC1 — shows title, author, cover image, and chapter list',
      (tester) async {
    await tester.pumpWidget(harness(
      book: sampleBook(
        title: 'Moby Dick',
        author: 'Herman Melville',
        coverPath: '/covers/abc12345.jpg',
      ),
      chapters: <Chapter>[chapter(0, 'Loomings'), chapter(1, 'The Carpet-Bag')],
    ));
    await tester.pump(); // resolve book stream
    await tester.pump(); // resolve chapters stream

    expect(find.text('Moby Dick'), findsWidgets); // AppBar + header
    expect(find.text('Herman Melville'), findsOneWidget);
    // Cover present → the cover branch builds a FileImage at the row's path
    // (distinct from the errorBuilder placeholder, which renders no Image).
    final cover = tester.widget<Image>(find.byType(Image));
    expect(cover.image, isA<FileImage>());
    expect((cover.image as FileImage).file.path, '/covers/abc12345.jpg');
    // Chapter rows live below the fold in the test viewport — assert the tree.
    expect(find.text('Loomings', skipOffstage: false), findsOneWidget);
    expect(find.text('The Carpet-Bag', skipOffstage: false), findsOneWidget);
  });

  testWidgets('AC1 — no cover renders the placeholder, no Image.file',
      (tester) async {
    await tester.pumpWidget(harness(book: sampleBook(title: 'Coverless')));
    await tester.pump();

    expect(find.byIcon(Icons.menu_book), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('AC1 — author line (keyed) renders when author is present',
      (tester) async {
    await tester.pumpWidget(harness(
      book: sampleBook(title: 'Named', author: 'Some Author'),
    ));
    await tester.pump();

    expect(find.byKey(const Key('book-author')), findsOneWidget);
    expect(find.text('Some Author'), findsOneWidget);
  });

  testWidgets('AC1 — author line is absent entirely when author is null',
      (tester) async {
    await tester.pumpWidget(harness(book: sampleBook(title: 'Anon')));
    await tester.pump();

    // The whole affordance is omitted — not an empty/blank author line.
    expect(find.byKey(const Key('book-author')), findsNothing);
  });

  testWidgets('AC1 — progress is a placeholder (value 0, Not started)',
      (tester) async {
    await tester.pumpWidget(harness(book: sampleBook()));
    await tester.pump();

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.0);
    expect(find.text('Not started'), findsOneWidget);
  });

  testWidgets('AC2 — Send to watch is a FilledButton rendered disabled',
      (tester) async {
    await tester.pumpWidget(harness(book: sampleBook()));
    await tester.pump();

    final btn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Send to watch'),
    );
    expect(btn.onPressed, isNull); // inert until Epic 4
  });

  testWidgets('AC2 — chapter rows are non-tappable (disabled)', (tester) async {
    await tester.pumpWidget(harness(
      book: sampleBook(),
      chapters: <Chapter>[chapter(0, 'One')],
    ));
    await tester.pump(); // resolve book stream
    await tester.pump(); // resolve chapters stream

    final tile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'One', skipOffstage: false),
    );
    expect(tile.onTap, isNull);
    expect(tile.enabled, isFalse);
  });

  testWidgets('AC3 — Remove confirms then calls removeBook', (tester) async {
    final spy = _SpyLibraryService();
    await tester.pumpWidget(harness(book: sampleBook(title: 'Doomed'), service: spy));
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();

    // Confirmation dialog appears (quiet-librarian copy).
    expect(find.text('Remove Doomed?'), findsOneWidget);
    expect(spy.removed, isEmpty); // not yet — only on confirm

    await tester.tap(find.widgetWithText(TextButton, 'Remove').last);
    await tester.pumpAndSettle();

    expect(spy.removed.single.title, 'Doomed');
  });

  testWidgets('AC4 — Restart asks once then dismisses with no state change',
      (tester) async {
    final spy = _SpyLibraryService();
    await tester.pumpWidget(harness(book: sampleBook(title: 'Again'), service: spy));
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Restart book'));
    await tester.pumpAndSettle();

    expect(find.text('Restart Again?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Restart'));
    await tester.pumpAndSettle();

    expect(find.text('Restart Again?'), findsNothing); // dismissed
    expect(spy.removed, isEmpty); // Restart never removes
  });

  testWidgets('book == null at the root route shows the removed fallback',
      (tester) async {
    // No route to pop back to (detail is the root) → the guard keeps the
    // minimal fallback on screen instead of popping.
    await tester.pumpWidget(harness(book: null));
    await tester.pumpAndSettle();

    expect(find.text('This book was removed.'), findsOneWidget);
  });

  testWidgets('book removed while open → detail pops back to the library',
      (tester) async {
    final controller = StreamController<Book?>();
    addTearDown(controller.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        bookDetailProvider(1).overrideWith((ref) => controller.stream),
        chaptersProvider(1).overrideWith((ref) => Stream.value(const <Chapter>[])),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BookDetailScreen(bookId: 1),
                  ),
                ),
                child: const Text('open detail'),
              ),
            ),
          ),
        ),
      ),
    ));

    controller.add(sampleBook(title: 'Live Book'));
    await tester.tap(find.text('open detail'));
    await tester.pumpAndSettle();
    expect(find.text('Live Book'), findsWidgets); // detail is open

    // Removed out from under the open screen.
    controller.add(null);
    await tester.pumpAndSettle();

    expect(find.text('Live Book'), findsNothing); // detail popped
    expect(find.text('open detail'), findsOneWidget); // back at the library
  });

  testWidgets('chapters load error surfaces — not a silent "0 chapters"',
      (tester) async {
    final chaptersCtrl = StreamController<List<Chapter>>();
    addTearDown(chaptersCtrl.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        bookDetailProvider(1).overrideWith((ref) => Stream.value(sampleBook())),
        chaptersProvider(1).overrideWith((ref) => chaptersCtrl.stream),
      ],
      child: const MaterialApp(home: BookDetailScreen(bookId: 1)),
    ));
    chaptersCtrl.addError(Exception('db boom'));
    await tester.pump(); // resolve book stream
    await tester.pump(); // deliver chapters error
    await tester.pump();

    expect(find.textContaining('Failed to load chapters'), findsOneWidget);
    expect(find.textContaining('0 chapters'), findsNothing);
  });
}

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
    expect(find.byType(Image), findsOneWidget); // cover present
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

  testWidgets('AC1 — null author omits the author affordance', (tester) async {
    await tester.pumpWidget(harness(
      book: sampleBook(title: 'Anon', coverPath: '/covers/x.jpg'),
    ));
    await tester.pump();

    expect(find.text('by '), findsNothing);
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
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/data/db/database.dart';
import 'package:paceturner_companion/ui/library/library_providers.dart';
import 'package:paceturner_companion/ui/library/library_screen.dart';

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
}

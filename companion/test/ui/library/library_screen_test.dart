import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/data/db/database.dart';
import 'package:paceturner_companion/ui/library/library_providers.dart';
import 'package:paceturner_companion/ui/library/library_screen.dart';

Book sampleBook({int id = 1, String title = 'A Test Book'}) => Book(
      id: id,
      title: title,
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

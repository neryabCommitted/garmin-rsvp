import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/app.dart';
import 'package:paceturner_companion/data/db/database.dart';
import 'package:paceturner_companion/ui/library/library_providers.dart';

void main() {
  testWidgets('app boots into the library empty state (Story 2.3)',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryProvider.overrideWith(
            (ref) => Stream<List<Book>>.value(const <Book>[]),
          ),
        ],
        child: const PaceTurnerApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Add a DRM-free EPUB to begin.'), findsOneWidget);
    // The Gate V2 spike harness is no longer the entry point.
    expect(find.text('Gate V2/V3 — transfer harness'), findsNothing);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/main.dart';

void main() {
  testWidgets('boots into the Gate V2 harness without platform calls',
      (WidgetTester tester) async {
    await tester.pumpWidget(const PaceTurnerApp());

    // The harness must be pumpable with no Garmin bridge present — the
    // bridge is only constructed when a run starts.
    expect(find.text('Gate V2 — transfer reliability'), findsOneWidget);
    expect(find.text('Start run'), findsOneWidget);
    expect(find.text('Run A: base64 String'), findsOneWidget);
    expect(find.text('Run B: List<int>'), findsOneWidget);
  });
}

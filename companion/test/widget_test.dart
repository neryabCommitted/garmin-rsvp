import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/main.dart';

void main() {
  testWidgets('boots into the Gate V2 harness without platform calls',
      (WidgetTester tester) async {
    await tester.pumpWidget(const PaceTurnerApp());

    // The harness must be pumpable with no Garmin bridge present — the
    // bridge is only constructed when a run starts.
    expect(find.text('Gate V2/V3 — transfer harness'), findsOneWidget);
    expect(find.text('Start run'), findsOneWidget);
    // Mode toggle present; reliability mode is the default, showing its
    // encoding segments. The Stop button only appears while a run is in flight.
    expect(find.text('V2: reliability'), findsOneWidget);
    expect(find.text('V3: size sweep'), findsOneWidget);
    expect(find.text('Run A: base64 String'), findsOneWidget);
    expect(find.text('Run B: List<int>'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);
  });
}

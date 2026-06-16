// On-device EPUB import verification (Story 2.4 manual hardware check).
//
// NOT part of `flutter test` / CI — run explicitly on a connected phone:
//   flutter test integration_test/epub_import_on_device_test.dart -d <deviceId>
//
// It reads a REAL EPUB staged at <app external files>/sample.epub (pushed via
// adb) and runs the actual ImportService with its DEFAULT runner — i.e. the real
// `compute` isolate, real sqlite (AppDatabase.open), and real cover-file write —
// then prints machine-readable `RSVP_HW:` lines (memory:
// hardware-run-results-machine-readable). The real EPUB is never committed
// (memory: epub-corpus-location).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paceturner_companion/data/db/database.dart';
import 'package:paceturner_companion/data/stream_store.dart';
import 'package:paceturner_companion/services/import/import_service.dart';
import 'package:paceturner_companion/services/import/pipeline.dart';
import 'package:path_provider/path_provider.dart';

/// Runs the EPUB pipeline directly (no isolate) so a parse failure surfaces its
/// real exception type/message instead of being collapsed to a typed failure.
Future<void> runEpubPipelineDiagnostic(List<int> bytes) async {
  await runEpubPipeline(
    EpubPipelineRequest(epubBytes: Uint8List.fromList(bytes), salt: 1),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('import a real EPUB end-to-end on the device', () async {
    final extDir = await getExternalStorageDirectory();
    final epubFile = File('${extDir!.path}/sample.epub');
    final exists = await epubFile.exists();
    // ignore: avoid_print
    print('RSVP_HW: epub_path=${epubFile.path} exists=$exists');
    expect(exists, isTrue,
        reason: 'push the EPUB first: adb push sample.epub ${extDir.path}/');

    final bytes = await epubFile.readAsBytes();
    // ignore: avoid_print
    print('RSVP_HW: epub_bytes=${bytes.length}');

    final db = AppDatabase.open();
    final store = StreamStore();
    final service = ImportService(db, store); // DEFAULT compute runner + salt

    final sw = Stopwatch()..start();
    final result = await service.importFile(path: 'sample.epub', bytes: bytes);
    sw.stop();
    // ignore: avoid_print
    print('RSVP_HW: result=${result.runtimeType} import_ms=${sw.elapsedMilliseconds}');
    if (result is ImportFailure) {
      // ignore: avoid_print
      print('RSVP_HW: failure_reason=${result.reason} filename=${result.filename}');
      // Surface the raw parse exception for diagnosis (direct, no isolate).
      try {
        await runEpubPipelineDiagnostic(bytes);
      } catch (e, st) {
        // ignore: avoid_print
        print('RSVP_HW: raw_parse_error_type=${e.runtimeType}');
        // ignore: avoid_print
        print('RSVP_HW: raw_parse_error=$e');
        // ignore: avoid_print
        print('RSVP_HW: raw_parse_stack=${st.toString().split('\n').take(6).join(' | ')}');
      }
    }

    expect(result, isA<ImportSuccess>(),
        reason: 'real EPUB should import; got $result');

    final book = (await db.watchAllBooks().first)
        .firstWhere((b) => b.id == (result as ImportSuccess).bookId);
    final chapters = await db.select(db.chapters).get();

    final streamExists = await File(book.streamPath).exists();
    final coverExists =
        book.coverPath != null && await File(book.coverPath!).exists();
    final coverSize =
        coverExists ? await File(book.coverPath!).length() : 0;

    // ignore: avoid_print
    print('RSVP_HW: title="${book.title}"');
    // ignore: avoid_print
    print('RSVP_HW: author="${book.author}"');
    // ignore: avoid_print
    print('RSVP_HW: fingerprint=${book.fingerprint} total_words=${book.totalWords}');
    // ignore: avoid_print
    print('RSVP_HW: chapters=${chapters.length}');
    // ignore: avoid_print
    print('RSVP_HW: stream_path=${book.streamPath} stream_exists=$streamExists');
    // ignore: avoid_print
    print('RSVP_HW: cover_path=${book.coverPath} cover_exists=$coverExists cover_bytes=$coverSize');
    final sample = chapters.take(8).map((c) => c.title).toList();
    // ignore: avoid_print
    print('RSVP_HW: first_chapter_titles=$sample');

    // Core assertions for a real, well-formed book.
    expect(book.totalWords, greaterThan(1000));
    expect(chapters.length, greaterThan(1));
    expect(streamExists, isTrue);

    await db.close();
    // ignore: avoid_print
    print('RSVP_HW: DONE');
  });
}

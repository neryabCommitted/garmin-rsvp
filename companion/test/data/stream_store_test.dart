import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/data/stream_store.dart';

void main() {
  late Directory tempDir;
  late StreamStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('stream_store_test');
    store = StreamStore(tempDir);
  });
  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  final bytes = Uint8List.fromList(<int>[1, 2, 3, 4, 250, 0, 99]);
  const jsonl = <String>['{"manifest":1}', '{"w":"hi"}'];

  test('write creates .stream + .jsonl and returns an absolute streamPath',
      () async {
    final stored = await store.write(
      streamBytes: bytes,
      debugJsonl: jsonl,
      fingerprint: 'abc12345',
    );

    expect(isAbsolutePath(stored.streamPath), isTrue);
    expect(stored.streamPath.endsWith('abc12345.stream'), isTrue);
    expect(await File(stored.streamPath).exists(), isTrue);
    expect(await File(stored.jsonlPath).exists(), isTrue);
  });

  test('bytes round-trip equal', () async {
    final stored = await store.write(
      streamBytes: bytes,
      debugJsonl: jsonl,
      fingerprint: 'abc12345',
    );
    final read = await File(stored.streamPath).readAsBytes();
    expect(read, bytes);
  });

  test('jsonl is written newline-delimited', () async {
    final stored = await store.write(
      streamBytes: bytes,
      debugJsonl: jsonl,
      fingerprint: 'abc12345',
    );
    final text = await File(stored.jsonlPath).readAsString();
    expect(text, '{"manifest":1}\n{"w":"hi"}');
  });

  test('files land under a streams/ subdir', () async {
    final stored = await store.write(
      streamBytes: bytes,
      debugJsonl: jsonl,
      fingerprint: 'abc12345',
    );
    expect(stored.streamPath.contains('${Platform.pathSeparator}streams${Platform.pathSeparator}'),
        isTrue);
  });

  test('delete removes both the .stream and the sibling .jsonl', () async {
    final stored = await store.write(
      streamBytes: bytes,
      debugJsonl: jsonl,
      fingerprint: 'abc12345',
    );
    await store.delete(stored.streamPath);
    expect(await File(stored.streamPath).exists(), isFalse);
    expect(await File(stored.jsonlPath).exists(), isFalse);
  });

  test('delete is idempotent — no throw when files are absent', () async {
    final absent = '${tempDir.path}/streams/nope.stream';
    await expectLater(store.delete(absent), completes);
  });

  group('cover (Story 2.4, AC2)', () {
    final coverBytes = Uint8List.fromList(<int>[137, 80, 78, 71, 1, 2, 3]);

    test('writeCover writes covers/<fingerprint>.<ext> and returns abs path',
        () async {
      final path = await store.writeCover(
        bytes: coverBytes,
        fingerprint: 'abc12345',
        format: 'jpg',
      );
      expect(isAbsolutePath(path), isTrue);
      expect(path.endsWith('abc12345.jpg'), isTrue);
      expect(
        path.contains('${Platform.pathSeparator}covers${Platform.pathSeparator}'),
        isTrue,
      );
      expect(await File(path).exists(), isTrue);
      expect(await File(path).readAsBytes(), coverBytes);
    });

    test('writeCover normalizes a format with a leading dot', () async {
      final path = await store.writeCover(
        bytes: coverBytes,
        fingerprint: 'def67890',
        format: '.png',
      );
      expect(path.endsWith('def67890.png'), isTrue);
      expect(path.contains('..'), isFalse);
    });

    test('deleteCover removes the file and is idempotent', () async {
      final path = await store.writeCover(
        bytes: coverBytes,
        fingerprint: 'abc12345',
        format: 'jpg',
      );
      await store.deleteCover(path);
      expect(await File(path).exists(), isFalse);
      await expectLater(store.deleteCover(path), completes);
    });
  });

  test('write leaves no orphan .stream when the .jsonl write fails (AC7)',
      () async {
    // Force the .jsonl write to throw by parking a directory where the sibling
    // file must land — writeAsString onto a directory path fails.
    final streamsDir =
        Directory('${tempDir.path}${Platform.pathSeparator}streams');
    await streamsDir.create(recursive: true);
    final jsonlAsDir = Directory(
        '${streamsDir.path}${Platform.pathSeparator}abc12345.jsonl');
    await jsonlAsDir.create();
    final orphan =
        File('${streamsDir.path}${Platform.pathSeparator}abc12345.stream');

    await expectLater(
      store.write(streamBytes: bytes, debugJsonl: jsonl, fingerprint: 'abc12345'),
      throwsA(isA<FileSystemException>()),
    );

    // The half-written .stream must be cleaned up — no orphan pair survives.
    expect(await orphan.exists(), isFalse);
  });
}

bool isAbsolutePath(String path) =>
    path.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(path);

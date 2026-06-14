/// Final stage of the Epic 2 import pipeline (`… → fingerprint → encode`,
/// AR20): the pure orchestrator that turns flagged [Token]s (grouped into
/// chapters) into the on-disk word-stream artifacts — the SPEC §5 binary stream
/// (via the existing `encodeChunk`), the §4.1 manifest, the §7 fingerprint, and
/// a JSONL debug master.
///
/// This file is an additive pure-orchestrator not enumerated in
/// `architecture.md:412-420` (which lists the leaf stages `pacing`/`orp`/
/// `fingerprint`); keeping orchestration here (pure) preserves AR19
/// host-testability and lets Story 2.3's impure `import_service` stay thin — it
/// will call [bake] inside a `compute` isolate. This story does NOT do file
/// I/O, isolate orchestration, chapter discovery, or envelope wire
/// serialization.
///
/// Pure Dart (no `package:flutter/*`, no global mutable state, no async I/O) so
/// it runs unchanged in the import isolate (AR19).
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../protocol/protocol_keys.dart';
import '../../protocol/stream_codec.dart';
import 'fingerprint.dart';
import 'orp.dart';
import 'pacing.dart';
import 'tokenizer.dart';

/// One chapter handed to [bake]: a title plus its flagged tokens. The baker does
/// NOT discover chapters — Story 2.3 (`.txt`/`.md`, single chapter) and Story
/// 2.4 (EPUB, many) supply them. Each chapter MUST carry at least one token; an
/// empty chapter cannot be represented in a SPEC §4.1 manifest (offsets must be
/// strictly increasing and `< tw`), so the extractor must filter empties.
final class BakeChapter {
  const BakeChapter({required this.title, required this.tokens});

  final String title;
  final List<Token> tokens;

  @override
  bool operator ==(Object other) =>
      other is BakeChapter &&
      other.title == title &&
      _listEquals(other.tokens, tokens);

  @override
  int get hashCode => Object.hash(title, Object.hashAll(tokens));

  @override
  String toString() => 'BakeChapter($title, ${tokens.length} tokens)';
}

/// SPEC §4.1 chapter entry — `o`/`ti`/`cb`.
final class ChapterEntry {
  const ChapterEntry({
    required this.offset,
    required this.title,
    required this.cumulativeBonusMs,
  });

  /// Absolute word index of the chapter's first word (`o`); `ch[0].o == 0`.
  final int offset;

  /// Chapter title (`ti`).
  final String title;

  /// Cumulative `bonusMs` of all words *before* [offset] (`cb`); `ch[0].cb == 0`.
  final int cumulativeBonusMs;

  @override
  bool operator ==(Object other) =>
      other is ChapterEntry &&
      other.offset == offset &&
      other.title == title &&
      other.cumulativeBonusMs == cumulativeBonusMs;

  @override
  int get hashCode => Object.hash(offset, title, cumulativeBonusMs);

  @override
  String toString() =>
      'ChapterEntry(o: $offset, ti: $title, cb: $cumulativeBonusMs)';
}

/// The SPEC §4.1 manifest as a pure model (Epic 4 maps it to the wire dict via
/// `envelope_codec`; this story does NOT serialize the envelope).
final class BookManifest {
  const BookManifest({
    required this.title,
    required this.totalWords,
    required this.totalBonusMs,
    required this.fingerprint,
    required this.chapters,
  });

  final String title;
  final int totalWords;
  final int totalBonusMs;
  final String fingerprint;
  final List<ChapterEntry> chapters;

  @override
  bool operator ==(Object other) =>
      other is BookManifest &&
      other.title == title &&
      other.totalWords == totalWords &&
      other.totalBonusMs == totalBonusMs &&
      other.fingerprint == fingerprint &&
      _listEquals(other.chapters, chapters);

  @override
  int get hashCode => Object.hash(
        title,
        totalWords,
        totalBonusMs,
        fingerprint,
        Object.hashAll(chapters),
      );

  @override
  String toString() => 'BookManifest($title, tw: $totalWords, tb: $totalBonusMs, '
      'fp: $fingerprint, ${chapters.length} chapters)';
}

/// The output of one bake: the binary stream, the manifest (carrying the
/// fingerprint), and the JSONL debug master.
final class BakedBook {
  const BakedBook({
    required this.streamBytes,
    required this.manifest,
    required this.debugJsonl,
  });

  /// SPEC §5 concatenation of all records — the on-disk word stream.
  final Uint8List streamBytes;
  final BookManifest manifest;

  /// Line-delimited JSON debug master (line 0 = manifest, lines 1..n = words).
  /// A debug artifact only — never a wire format; the watch never sees it.
  final List<String> debugJsonl;

  @override
  bool operator ==(Object other) =>
      other is BakedBook &&
      _bytesEqual(other.streamBytes, streamBytes) &&
      other.manifest == manifest &&
      _listEquals(other.debugJsonl, debugJsonl);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(streamBytes),
        manifest,
        Object.hashAll(debugJsonl),
      );

  @override
  String toString() =>
      'BakedBook(${streamBytes.length} bytes, $manifest, '
      '${debugJsonl.length} jsonl lines)';
}

/// Bakes [chapters] into the SPEC §5 stream + §4.1 manifest + §7 fingerprint +
/// JSONL master (AC3/AC4/AC5/AC6).
///
/// [salt] makes a re-bake of identical text produce a fresh fingerprint (SPEC
/// §7); the caller (Story 2.3) supplies it, keeping this function deterministic.
///
/// Throws [ArgumentError] (NFR8 typed failure) when there is nothing valid to
/// bake: no chapters, or any chapter with zero tokens (which cannot be
/// represented in a §4.1 manifest). Records that the wire cannot carry surface
/// as `encodeChunk`'s own [ArgumentError] — those are baking bugs (Task 5).
BakedBook bake({
  required String title,
  required List<BakeChapter> chapters,
  required int salt,
}) {
  if (chapters.isEmpty) {
    throw ArgumentError.value(
      chapters,
      'chapters',
      'SPEC §4.1: a book must have at least one chapter',
    );
  }
  for (var c = 0; c < chapters.length; c++) {
    if (chapters[c].tokens.isEmpty) {
      throw ArgumentError.value(
        chapters[c].title,
        'chapters[$c]',
        'SPEC §4.1: a chapter must have at least one word (empty chapters '
            'break strictly-increasing offsets; the extractor must filter them)',
      );
    }
  }

  // Flatten to a single ordered word stream, recording each word's chapter for
  // the JSONL master and the manifest's cumulative bonuses.
  final records = <WordRecord>[];
  final wordChapterIndex = <int>[];
  final chapterFirstWord = <int>[];

  final flatTokens = <Token>[];
  final flatTokenChapter = <int>[];
  for (var c = 0; c < chapters.length; c++) {
    chapterFirstWord.add(flatTokens.length);
    for (final token in chapters[c].tokens) {
      flatTokens.add(token);
      flatTokenChapter.add(c);
    }
  }
  final chapterStartSet = chapterFirstWord.toSet();

  for (var i = 0; i < flatTokens.length; i++) {
    final token = flatTokens[i];
    final isChapterStart = chapterStartSet.contains(i);
    var flags = 0;
    if (token.sentenceEnd) {
      flags |= ProtocolKeys.flagSentenceEnd;
    }
    if (token.paragraphStart) {
      flags |= ProtocolKeys.flagParagraphStart;
    }
    if (isChapterStart) {
      flags |= ProtocolKeys.flagChapterStart;
    }
    final next = i + 1 < flatTokens.length ? flatTokens[i + 1] : null;
    records.add(
      WordRecord(
        word: token.text,
        flags: flags,
        orpPivot: orpPivot(token.text),
        bonusMs: bonusMsForWord(token, next: next),
      ),
    );
    wordChapterIndex.add(flatTokenChapter[i]);
  }

  // SPEC §5: the on-disk stream IS encodeChunk's concatenation — do not write a
  // second encoder. It validates every record and throws on a baking bug.
  final streamBytes = encodeChunk(records);

  // Manifest (SPEC §4.1): chapter offsets + cumulative bonuses, totals, fp.
  final chapterEntries = <ChapterEntry>[];
  var runningBonus = 0;
  var totalBonus = 0;
  var nextChapter = 0;
  for (var i = 0; i < records.length; i++) {
    if (nextChapter < chapters.length && i == chapterFirstWord[nextChapter]) {
      chapterEntries.add(
        ChapterEntry(
          offset: i,
          title: chapters[nextChapter].title,
          cumulativeBonusMs: runningBonus, // bonus of all words before `i`
        ),
      );
      nextChapter++;
    }
    runningBonus += records[i].bonusMs;
    totalBonus += records[i].bonusMs;
  }

  final fp = fingerprint(streamBytes, salt: salt);
  final manifest = BookManifest(
    title: title,
    totalWords: records.length,
    totalBonusMs: totalBonus,
    fingerprint: fp,
    chapters: chapterEntries,
  );

  final debugJsonl = _buildJsonl(manifest, records, wordChapterIndex);

  return BakedBook(
    streamBytes: streamBytes,
    manifest: manifest,
    debugJsonl: debugJsonl,
  );
}

/// Line 0 = manifest; lines 1..n = one word each. Valid line-delimited JSON,
/// enough to reconstruct/inspect every record. Debug-only (addendum §2 line 19).
List<String> _buildJsonl(
  BookManifest manifest,
  List<WordRecord> records,
  List<int> wordChapterIndex,
) {
  final lines = <String>[
    jsonEncode(<String, Object?>{
      ProtocolKeys.keyTitle: manifest.title,
      ProtocolKeys.keyTotalWords: manifest.totalWords,
      ProtocolKeys.keyTotalBonusMs: manifest.totalBonusMs,
      ProtocolKeys.keyFingerprint: manifest.fingerprint,
      ProtocolKeys.keyChapters: [
        for (final ch in manifest.chapters)
          <String, Object?>{
            ProtocolKeys.keyChapterOffset: ch.offset,
            ProtocolKeys.keyTitle: ch.title,
            ProtocolKeys.keyChapterCumBonusMs: ch.cumulativeBonusMs,
          },
      ],
    }),
  ];
  for (var i = 0; i < records.length; i++) {
    final r = records[i];
    lines.add(jsonEncode(<String, Object?>{
      'i': i,
      'w': r.word,
      'flags': r.flags,
      'orp': r.orpPivot,
      'bonusMs': r.bonusMs,
      'ch': wordChapterIndex[i],
    }));
  }
  return lines;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

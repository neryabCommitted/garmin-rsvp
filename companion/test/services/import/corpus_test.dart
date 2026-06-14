import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paceturner_companion/services/import/text_sanitizer.dart';
import 'package:paceturner_companion/services/import/tokenizer.dart';

/// Story 2.1 AC4 (+ AC1/AC2/AC3) — data-driven from the fixture corpus
/// (`test/fixtures/text/pipeline_cases.json`). Each case runs the real
/// pipeline `sanitize → tokenize` and asserts the full flagged token list, so
/// the corpus can grow without touching code. The corpus is the source of
/// truth for the abbreviation/sentence-end contract the watch trusts verbatim.

void main() {
  final File fixture = File('test/fixtures/text/pipeline_cases.json');

  test('fixture corpus file exists', () {
    expect(fixture.existsSync(), isTrue,
        reason: 'corpus at ${fixture.path} is missing');
  });

  final Map<String, dynamic> root =
      json.decode(fixture.readAsStringSync()) as Map<String, dynamic>;
  final List<dynamic> cases = root['cases'] as List<dynamic>;

  group('pipeline corpus', () {
    for (final dynamic raw in cases) {
      final Map<String, dynamic> c = raw as Map<String, dynamic>;
      final String name = c['name'] as String;
      final String input = c['input'] as String;
      final bool asciiFold = (c['asciiFold'] as bool?) ?? false;
      final List<Token> expected = <Token>[
        for (final dynamic e in c['expected'] as List<dynamic>)
          Token(
            text: (e as Map<String, dynamic>)['text'] as String,
            paragraphStart: e['paragraphStart'] as bool,
            sentenceEnd: e['sentenceEnd'] as bool,
          ),
      ];

      test(name, () {
        final List<Token> actual =
            tokenize(sanitize(input, asciiFold: asciiFold));
        expect(actual, equals(expected));
      });
    }
  });
}

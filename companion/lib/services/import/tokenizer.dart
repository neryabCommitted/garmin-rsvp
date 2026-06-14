/// Stage 2 of the Epic 2 import pipeline (`sanitize → tokenize → …`, AR20):
/// splits sanitized text into words carrying `paragraphStart`/`sentenceEnd`
/// flags. Linguistics only — pacing, ORP pivots, and binary encoding are
/// Story 2.2.
///
/// Pure Dart (no `package:flutter/*`, no global mutable state, no async I/O) so
/// it runs unchanged in the import isolate (AR19). These flags are baked once
/// here and consumed verbatim by the watch (FR17): the watch never recomputes
/// linguistics, so a wrong flag is a permanent on-device defect.
library;

/// An immutable linguistic token. Mirrors the value-type style of `WordRecord`
/// (`protocol/stream_codec.dart`) but stays linguistics-only: it carries no
/// ORP pivot, bonus-ms, or binary flag byte — Story 2.2 maps
/// `paragraphStart → ProtocolKeys.flagParagraphStart` and
/// `sentenceEnd → ProtocolKeys.flagSentenceEnd` when it bakes `WordRecord`s.
final class Token {
  const Token({
    required this.text,
    required this.paragraphStart,
    required this.sentenceEnd,
  });

  /// The word with its trailing punctuation kept on (e.g. `hello.`).
  final String text;

  /// True for the first token of the text and the first token after each
  /// paragraph boundary (a blank line).
  final bool paragraphStart;

  /// True for the last word of a sentence (abbreviation-aware; see
  /// [_endsSentence]).
  final bool sentenceEnd;

  @override
  bool operator ==(Object other) =>
      other is Token &&
      other.text == text &&
      other.paragraphStart == paragraphStart &&
      other.sentenceEnd == sentenceEnd;

  @override
  int get hashCode => Object.hash(text, paragraphStart, sentenceEnd);

  @override
  String toString() =>
      'Token($text, paragraphStart: $paragraphStart, sentenceEnd: $sentenceEnd)';
}

/// One-or-more blank lines = a paragraph boundary. `\s` includes `\n`, so any
/// run of blank lines collapses to a single boundary.
final RegExp _paragraphBreak = RegExp(r'\n\s*\n');

/// Word boundary inside a paragraph.
final RegExp _whitespace = RegExp(r'\s+');

/// A token is kept only if it contains at least one letter or digit
/// (`[\p{L}\p{N}]` semantics); pure-punctuation fragments are dropped.
final RegExp _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Closing quotes/brackets stripped from a token's tail for sentence-end
/// inspection only — they are kept on the stored token text. Covers straight
/// and curly quotes plus `)`/`]`.
const Set<String> _closers = <String>{'"', "'", '”', '’', ')', ']'};

/// Dotted initialism such as `U.S.`, `e.g.`, `i.e.` — two-or-more single
/// letters joined by periods. Requires at least two letters so a lone
/// `a.`/`b.` (a real one-letter word ending a sentence) is NOT suppressed;
/// the single capital initial `J.` is handled by [_singleInitial] instead.
/// (`Ph.D.`-style multi-letter segments are covered via [abbreviations], since
/// this regex matches single-letter segments only.)
final RegExp _dottedInitialism =
    RegExp(r'^\p{L}\.(\p{L}\.?)+$', unicode: true);

/// A single capital initial like `J.` (as in `J. Smith`).
final RegExp _singleInitial = RegExp(r'^\p{Lu}\.$', unicode: true);

/// Trailing terminal dot(s) or ellipsis char, stripped to recover the bare word
/// for abbreviation lookup.
final RegExp _trailingDots = RegExp(r'[.…]+$');

/// Curated abbreviation list (seed; extend via fixtures). Stored lowercase and
/// without trailing periods so the lookup is case-insensitive. Kept in one
/// named const so the fixture corpus can grow it. A period after any of these
/// does **not** end a sentence.
const Set<String> abbreviations = <String>{
  // Titles.
  'mr', 'mrs', 'ms', 'dr', 'prof', 'rev', 'sr', 'jr', 'st',
  // Common.
  'etc', 'vs', 'e.g', 'i.e', 'cf', 'al',
  // Months.
  'jan', 'feb', 'mar', 'apr', 'jun', 'jul', 'aug', 'sep', 'sept', 'oct',
  'nov', 'dec',
  // Units / orgs.
  'inc', 'ltd', 'co', 'corp', 'no',
};

/// Splits [sanitized] text into flagged [Token]s (AC3, AC4).
///
/// NFR8: returns `[]` for empty/whitespace-only input and never throws.
///
/// Terminal-boundary guarantee: the last token of the text is always flagged
/// `sentenceEnd=true`, even when it lacks terminal punctuation or ends with an
/// abbreviation/initialism. This is the bake-time equivalent of rsvpnano's
/// read-time `currentWordEndsSentence() || atEnd()` (App.cpp:1883-1894): our
/// flags are consumed verbatim by the watch (FR17), so the `atEnd()` guard must
/// live in the data. Without it FR8 (two-stage pause coasts to the next
/// `sentenceEnd`) and FR10 (rewind lands on a `sentenceEnd`) would have no final
/// boundary. NB: this is end-of-*text* only — paragraph ends are not forced, and
/// the Epic 3 reader must still OR its pause check with a real `atEnd()` because
/// the end of a buffered chunk is not the end of the book.
List<Token> tokenize(String sanitized) {
  final List<Token> tokens = <Token>[];
  for (final String paragraph in sanitized.split(_paragraphBreak)) {
    bool atParagraphStart = true;
    for (final String raw in paragraph.split(_whitespace)) {
      if (raw.isEmpty || !_letterOrDigit.hasMatch(raw)) {
        continue;
      }
      tokens.add(Token(
        text: raw,
        paragraphStart: atParagraphStart,
        sentenceEnd: _endsSentence(raw),
      ));
      atParagraphStart = false;
    }
  }
  // Terminal-boundary guarantee: force the final token to a sentence end.
  if (tokens.isNotEmpty && !tokens.last.sentenceEnd) {
    final Token last = tokens.last;
    tokens[tokens.length - 1] = Token(
      text: last.text,
      paragraphStart: last.paragraphStart,
      sentenceEnd: true,
    );
  }
  return tokens;
}

/// Decides whether [token] ends a sentence (AC4 algorithm).
///
/// Closing quotes/brackets are stripped for inspection only. `!`/`?` always
/// terminate. A trailing `.` (or `...`/`…`) terminates unless the token is an
/// abbreviation, a dotted initialism, or a single capital initial. A token
/// whose dot is internal (e.g. the decimal `3.14`) never reaches the terminal
/// check because it does not end in a dot.
bool _endsSentence(String token) {
  String s = token;
  while (s.isNotEmpty && _closers.contains(s.substring(s.length - 1))) {
    s = s.substring(0, s.length - 1);
  }
  if (s.isEmpty) {
    return false;
  }
  final String last = s.substring(s.length - 1);
  if (last == '!' || last == '?') {
    return true;
  }
  // '.' or the ellipsis char '…' (when ASCII-fold was off) are terminal dots.
  if (last == '.' || last == '…') {
    return !_isSuppressed(s);
  }
  return false;
}

/// True when a dot-terminated [s] is an abbreviation context that must NOT set
/// `sentenceEnd`.
bool _isSuppressed(String s) {
  if (_dottedInitialism.hasMatch(s) || _singleInitial.hasMatch(s)) {
    return true;
  }
  final String bare = s.replaceAll(_trailingDots, '').toLowerCase();
  return abbreviations.contains(bare);
}

/// Stage 3 of the Epic 2 import pipeline (`sanitize → tokenize → pace → …`,
/// AR20): assigns each word a **WPM-invariant additive** dwell bonus in ms.
///
/// SPEC §5.1 timing model: the watch computes `displayMs = 60000/wpm +
/// bonusMs`. `bonusMs` therefore MUST depend only on the word and its baked
/// flags — never on WPM — so changing reading speed never re-bakes content
/// (AC1). The tiers and percentages are ported from RSVP Nano's
/// `pacingBonusMsForWord` per the addendum; each percentage is applied to a
/// fixed **reference-ms base** (NOT `60000/wpm`), which is exactly what keeps
/// the bonus WPM-independent.
///
/// Pure Dart (no `package:flutter/*`, no global mutable state, no async I/O) so
/// it runs unchanged in the import isolate (AR19).
///
/// Tuning note: these percentages were tuned for Nano's hardware; the addendum
/// flags recalibration on Fenix 8 (Gate V4). Every tier percentage and
/// reference base is a named const below, so retuning is a one-file edit.
library;

import 'tokenizer.dart';

// --- Reference-ms bases (Nano defaults: 200 ms per tier) -------------------
// A tier evaluated at `p`% contributes `p% * base` ms. Bases are fixed
// constants, independent of WPM (AC1).
const int _lengthReferenceMs = 200;
const int _complexityReferenceMs = 200;
const int _punctuationReferenceMs = 200;

// --- Length tier (per word-character count; punctuation excluded) ----------
// Marginal rates: each char in (6,10] costs 6%, in (10,14] costs 9%, beyond 14
// costs 12%. Capped at 170%.
const int _lengthTier1Start = 6;
const int _lengthTier2Start = 10;
const int _lengthTier3Start = 14;
const int _lengthTier1Pct = 6;
const int _lengthTier2Pct = 9;
const int _lengthTier3Pct = 12;
const int _lengthCapPct = 170;

// --- Complexity tier (summed, then capped at 85%) --------------------------
const int _syllablePctPerExtraGroup = 25; // per vowel group beyond the first
const int _syllableCapPct = 50;
const int _mixedAlphanumericPct = 22;
const int _allCapsPct = 14;
const int _compoundJoinerPct = 14;
const int _complexityCapPct = 85;

// --- Punctuation tier (single dominant mark; the sentence pause wins) -------
const int _commaPct = 45;
const int _dashPct = 60;
const int _semicolonColonPct = 80;
const int _ellipsisPct = 110;
const int _periodPct = 135; // terminal period (suppressed for abbreviations)
const int _sentenceEndPct = 150; // flag-driven sentence pause

/// SPEC §5 — bonusMs is a u16 field.
const int _bonusMaxMs = 65535;

// Word-character class (letters + digits), mirroring the ORP/length count and
// the tokenizer's keep rule.
final RegExp _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);
final RegExp _vowelGroup =
    RegExp(r'[aeiouyàáâãäåèéêëìíîïòóôõöùúûüāēīōūœæ]+', unicode: true);
final RegExp _letter = RegExp(r'\p{L}', unicode: true);
final RegExp _digit = RegExp(r'\p{N}', unicode: true);

/// Closing quotes/brackets stripped from the tail before reading the trailing
/// punctuation mark — mirrors the tokenizer's sentence-end inspection so
/// `left."` is read through the closer to the period.
const Set<String> _closers = <String>{'"', "'", '”', '’', ')', ']'};
const Set<String> _dashChars = <String>{'-', '—', '–'};

/// Returns the WPM-invariant additive dwell bonus (ms, u16) for [token] (AC1).
///
/// [next] is accepted for API portability with Nano's next-word-case
/// look-ahead; the ported per-word tiers are self-contained, so it is currently
/// unused (kept so Story 2.3's baker — and a future Gate V4 retune — can wire a
/// look-ahead heuristic without changing this signature).
int bonusMsForWord(Token token, {Token? next}) {
  final int lengthMs = (_lengthPct(token.text) * _lengthReferenceMs) ~/ 100;
  final int complexityMs =
      (_complexityPct(token.text) * _complexityReferenceMs) ~/ 100;
  final int punctuationMs =
      (_punctuationPct(token) * _punctuationReferenceMs) ~/ 100;
  final int total = lengthMs + complexityMs + punctuationMs;
  return total.clamp(0, _bonusMaxMs);
}

int _wordCharCount(String word) => _wordChar.allMatches(word).length;

int _lengthPct(String word) {
  final int n = _wordCharCount(word);
  final int t1 = (n - _lengthTier1Start).clamp(0, _lengthTier2Start - _lengthTier1Start);
  final int t2 = (n - _lengthTier2Start).clamp(0, _lengthTier3Start - _lengthTier2Start);
  final int t3 = (n - _lengthTier3Start).clamp(0, n);
  final int pct =
      t1 * _lengthTier1Pct + t2 * _lengthTier2Pct + t3 * _lengthTier3Pct;
  return pct > _lengthCapPct ? _lengthCapPct : pct;
}

int _complexityPct(String word) {
  final String lower = word.toLowerCase();
  final int groups = _vowelGroup.allMatches(lower).length;
  final int syllablePct =
      ((groups - 1).clamp(0, 1 << 30) * _syllablePctPerExtraGroup)
          .clamp(0, _syllableCapPct);

  int pct = syllablePct;
  final bool hasLetter = _letter.hasMatch(word);
  final bool hasDigit = _digit.hasMatch(word);
  if (hasLetter && hasDigit) {
    pct += _mixedAlphanumericPct;
  }
  if (_isAllCaps(word)) {
    pct += _allCapsPct;
  }
  if (word.contains('-')) {
    pct += _compoundJoinerPct;
  }
  return pct > _complexityCapPct ? _complexityCapPct : pct;
}

/// ALL-CAPS = at least two cased letters and every cased letter is uppercase.
bool _isAllCaps(String word) {
  int cased = 0;
  for (final int rune in word.runes) {
    final String ch = String.fromCharCode(rune);
    final String up = ch.toUpperCase();
    final String lo = ch.toLowerCase();
    if (up == lo) {
      continue; // not a cased letter (digit, hyphen, CJK, …)
    }
    if (ch != up) {
      return false; // a lowercase letter present
    }
    cased++;
  }
  return cased >= 2;
}

int _punctuationPct(Token token) {
  final String stripped = _stripClosers(token.text);
  int raw;
  bool isPeriod = false;
  if (stripped.endsWith('…') || stripped.endsWith('...')) {
    raw = _ellipsisPct;
  } else if (stripped.endsWith('.')) {
    raw = _periodPct;
    isPeriod = true;
  } else if (stripped.endsWith(',')) {
    raw = _commaPct;
  } else if (stripped.endsWith(';') || stripped.endsWith(':')) {
    raw = _semicolonColonPct;
  } else if (stripped.isNotEmpty &&
      _dashChars.contains(stripped[stripped.length - 1])) {
    raw = _dashPct;
  } else {
    raw = 0;
  }

  // A terminal period that is NOT a real sentence end is an abbreviation or a
  // decimal (the tokenizer already left sentenceEnd=false) — no long pause.
  if (isPeriod && !token.sentenceEnd) {
    raw = 0;
  }

  // The flag-driven sentence pause dominates any raw terminal mark (AC1: prefer
  // the 150% sentence pause over the 135% raw period).
  if (token.sentenceEnd) {
    return raw > _sentenceEndPct ? raw : _sentenceEndPct;
  }
  return raw;
}

String _stripClosers(String word) {
  String s = word;
  while (s.isNotEmpty && _closers.contains(s[s.length - 1])) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

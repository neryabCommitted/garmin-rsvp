/// Epic 3 dev fixture — a full baked word stream Story 3.2's `PlaybackView` (and
/// the pure `ReaderEngine` host tests in 3.1) can render before Epic 4's real
/// transfer exists. Resolves the Epic 1 retro prep item ("Story 2.2 emits a full
/// sample baked stream early as Epic 3's dev fixture").
///
/// The prose below is **original, license-clean** text written for this fixture
/// — the real EPUB corpus is copyrighted and never committed (project memory).
/// It is baked through the *real* Epic 2 pipeline (`sanitize → tokenize → bake`),
/// so the artifact is byte-identical to what an imported book of the same text
/// would produce. The chapters are shaped to exercise the reader:
///   - 3 chapters → chapter cards (FR6) and `flagChapterStart`,
///   - varied sentence lengths + terminal punctuation → coast-pause / rewind
///     sentence boundaries (FR8/FR10) and the baked terminal `sentenceEnd`,
///   - blank-line paragraph breaks → `flagParagraphStart`,
///   - a couple of accented words → ORP byte-pivot on multi-byte runes,
///   - one deliberately long word ("counterrevolutionaries") → long-word
///     handling (FR7).
///
/// Pure (no `dart:io`) so it is safe to import from both the verification test
/// and the generator. `generate.dart` writes the committed binary artifacts.
library;

import 'package:paceturner_companion/services/import/text_sanitizer.dart';
import 'package:paceturner_companion/services/import/tokenizer.dart';
import 'package:paceturner_companion/services/import/word_stream_baker.dart';

/// Stable so the baked artifact (and its SPEC §7 fingerprint) is reproducible —
/// the generator and the drift-guard test must agree byte-for-byte.
const int kDevSampleSalt = 0x50414345; // "PACE"

/// The book title — also surfaces in the manifest and the chapter index.
const String kDevSampleTitle = 'The Lantern-Keeper (dev sample)';

/// Each entry: chapter title + its raw prose. Blank lines separate paragraphs
/// (the tokenizer derives `paragraphStart` only from `\n\s*\n`).
const List<({String title, String text})> kDevSampleChapters = [
  (
    title: 'I. The Harbor at Dusk',
    text: '''
The harbor went quiet a little before the lamps came on. Boats nodded at their
moorings, and the water held the last of the light like a held breath.

Mara walked the long pier alone. She counted the planks out of an old habit,
the way her grandmother had taught her, and she did not look up until the first
lantern flickered awake at the far end.

Was it too early? No — the keeper was simply punctual, as he always was.
''',
  ),
  (
    title: 'II. A Café and a Question',
    text: '''
They met, as they had agreed, in the small café behind the customs house. The
coffee was bitter and the room was warm, and for a while neither of them spoke.

"You came," he said at last.

"I said I would." She turned her cup a quarter-turn on its saucer. "I keep my
promises — even the inconvenient ones, the naïve ones, the ones that frighten
me."

He almost smiled. Outside, the counterrevolutionaries were said to be marching
again, but here, for one hour, the war was very far away.
''',
  ),
  (
    title: 'III. What the Tide Returned',
    text: '''
By morning the storm had spent itself. The beach was littered with rope and
pale wood, and one strange thing the tide had carried in and laid down gently,
as if it mattered.

Mara knelt. She brushed the sand away with two fingers, slowly, and understood
all at once what the lantern had been guiding home.

The end.
''',
  ),
];

/// Bakes [kDevSampleChapters] through the real Epic 2 pipeline. Pure — returns
/// the [BakedBook] (stream bytes + manifest + JSONL) for the generator to write
/// and the test to verify.
BakedBook buildDevSampleBook() {
  final chapters = <BakeChapter>[
    for (final c in kDevSampleChapters)
      BakeChapter(title: c.title, tokens: tokenize(sanitize(c.text))),
  ];
  return bake(
    title: kDevSampleTitle,
    chapters: chapters,
    salt: kDevSampleSalt,
  );
}

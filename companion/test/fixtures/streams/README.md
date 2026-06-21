# Dev word-stream fixture (Epic 3)

A full baked word stream for Epic 3 to render before Epic 4's real transfer
exists. Resolves the Epic 1 retro prep item *"Story 2.2 emits a full sample
baked stream early as Epic 3's dev fixture."*

| File | What |
|---|---|
| `dev_sample_book.dart` | Original (license-clean) 3-chapter prose + `buildDevSampleBook()` — bakes through the **real** `sanitize → tokenize → bake` pipeline. |
| `dev_sample_book.stream` | SPEC §5 binary word stream — **the artifact the watch dev path loads** as a canned `WordSource` (Story 3.1/3.2). 228 words, 3 chapters, fp `4bd588b9`. |
| `dev_sample_book.manifest.json` | SPEC §4.1 manifest (title, totals, fingerprint, chapter index) — human-readable. |
| `dev_sample_book.jsonl` | Line-delimited debug master (line 0 = manifest, 1..n = one word). |
| `generate.dart` | `dart run test/fixtures/streams/generate.dart` — regenerates all three artifacts (deterministic, fixed salt). |
| `dev_sample_book_test.dart` | Drift guard (committed `.stream` == fresh bake) + structural contract. |

The prose deliberately exercises the reader: 3 chapters (FR6 cards +
`flagChapterStart`), varied sentence/paragraph boundaries (FR8/FR10 +
`flagParagraphStart`), accented words (`Café`, `naïve` — ORP byte-pivot), and a
long word (`counterrevolutionaries` — FR7 long-word handling).

**The real EPUB corpus is copyrighted and never committed** — this synthetic
sample stands in for it as a checked-in fixture.

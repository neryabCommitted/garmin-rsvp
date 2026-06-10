# Worked Example A — Word-Record Sequence (SPEC §5, §6)

**Normative fixture.** Conformance tests on both sides (Dart
`stream_codec_test.dart`, Monkey C `ProtocolTest.mc`) pin against these exact
bytes. If SPEC §5/§6 change, this file and both test suites change in the
same PR.

Three words demonstrating: an ASCII word, a multi-byte UTF-8 (Hebrew) word —
proving `orpPivot` is a **byte** index — a sentence-end flag, structural
start flags, and a non-zero `bonusMs`.

| # | word | UTF-8 bytes | `wordLen` | `flags` | `orpPivot` | `bonusMs` |
|---|---|---|---|---|---|---|
| 0 | `Pace` | 4 | 4 | `0x06` = paragraphStart \| chapterStart | 1 (→ `a`) | 0 |
| 1 | `turns` | 5 | 5 | `0x00` | 1 (→ `u`) | 0 |
| 2 | `שלום` | 8 (4 chars × 2 B) | 8 | `0x01` = sentenceEnd | 2 (→ byte 2 = first byte of `ל`, the 2nd character) | 350 (= `0x015E` → LE `5E 01`) |

Record values are illustrative (pivot/bonus assignment policy is phone-side);
the *encoding* of these values is what this fixture pins.

## Per-record bytes

```
record 0  "Pace"   (9 bytes)
04 06 01 00 00 50 61 63 65
│  │  │  └─┴─ bonusMs = 0x0000 (u16le)
│  │  └─ orpPivot = 1
│  └─ flags = 0x06 (paragraphStart|chapterStart)
└─ wordLen = 4                  "Pace" = 50 61 63 65

record 1  "turns"  (10 bytes)
05 00 01 00 00 74 75 72 6E 73

record 2  "שלום"   (13 bytes)
08 01 02 5E 01 D7 A9 D7 9C D7 95 D7 9D
│  │  │  └─┴─ bonusMs = 0x015E = 350 ms (u16le: 5E 01)
│  │  └─ orpPivot = 2 → bytes[2] = D7, start of "ל" (byte index, NOT char index)
│  └─ flags = 0x01 (sentenceEnd)
└─ wordLen = 8                  "שלום" = D7 A9 D7 9C D7 95 D7 9D
```

## Full payload (32 bytes, tightly concatenated)

Record byte offsets within the payload: 0, 9, 19.

```
04060100005061636505000100007475726e730801025e01d7a9d79cd795d79d
```

This payload appears as the `chunkData` `p` value in
[`envelopes.md`](envelopes.md) (`off = 1000`, `n = 3`).

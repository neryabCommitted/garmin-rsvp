# Worked Example B — One Envelope per Message Type (SPEC §3, §4)

**Normative fixture.** Envelope conformance tests on both sides pin against
these values (Dart `envelope_codec_test.dart`, Monkey C `ProtocolTest.mc`).

Notation is annotated JSON-ish: on the wire these are Connect IQ app-message
dictionaries (Dart `Map<String, Object?>` / Monkey C `Dictionary`), not JSON
text. `<bytes hex …>` denotes a binary byte array value. Unused envelope
fields are omitted per SPEC §3.

All five examples describe one fictional book, fingerprint `"9f86d081"`,
50 000 words, two chapters, with chapter 2 starting at absolute word index
1000.

## `manifest` (phone → watch) — SPEC §4.1

```jsonc
{
  "t": "manifest",
  "v": 1,
  "fp": "9f86d081",
  "p": {
    "ti": "Example Book",          // book title
    "tw": 50000,                   // total words
    "tb": 412350,                  // total bonusMs, whole book
    "ch": [
      { "o": 0,    "ti": "Chapter 1", "cb": 0    },
      { "o": 1000, "ti": "Chapter 2", "cb": 8350 }   // 8350 ms of bonus before word 1000
    ]
  }
}
```

## `chunkRequest` (watch → phone) — SPEC §4.2

```jsonc
{
  "t": "chunkRequest",
  "v": 1,
  "fp": "9f86d081",
  "off": 1000,                     // first word wanted (absolute index)
  "n": 3                           // record count
}
```

## `chunkData` (phone → watch) — SPEC §4.3

Payload is the 32-byte sequence from
[`word-records.md`](word-records.md) — words 1000..1002 ("Pace", "turns",
"שלום"); word 1000 carries `chapterStart` matching `ch[1].o` above.

```jsonc
{
  "t": "chunkData",
  "v": 1,
  "fp": "9f86d081",
  "off": 1000,
  "n": 3,
  "p": <bytes hex 04060100005061636505000100007475726e730801025e01d7a9d79cd795d79d>
}
```

## `position` (both directions) — SPEC §4.4

```jsonc
{
  "t": "position",
  "v": 1,
  "fp": "9f86d081",
  "off": 1002,                     // word currently displayed
  "p": {
    "ts": 1781049600,              // 2026-06-10T00:00:00Z, epoch seconds
    "src": "watch"                 // "watch" | "phone"
  }
}
```

## `error` (both directions) — SPEC §4.5

A watch-side decode failure of the chunk above; `fp`/`off` carried as context
per SPEC §4.5.

```jsonc
{
  "t": "error",
  "v": 1,
  "fp": "9f86d081",
  "off": 1000,
  "p": {
    "c": "decodeFailure",          // SPEC §8 code
    "m": "record 2: wordLen exceeds remaining payload"   // log context, never parsed
  }
}
```

## Rejection example — unknown version (SPEC §2, AC4)

Any envelope with `v != 1` — e.g. the `chunkRequest` above with `"v": 2` —
MUST be rejected with a typed `versionMismatch` result/error and MUST NOT be
interpreted further. Both sides' tests pin this behavior.

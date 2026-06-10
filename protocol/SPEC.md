# PaceTurner Protocol — SPEC

**Protocol version: 1** (see §2)

This document is the single source of truth for the PaceTurner phone↔watch
protocol: the message envelope, the five message types, the binary word-record
layout, flag-bit assignments, fingerprint semantics, versioning, and error
semantics. Both the reference companion (Flutter/Dart) and the watch app
(Connect IQ / Monkey C) implement *this document* — never each other. A
third party should be able to build a compatible companion from this spec
alone, without reading either implementation.

Implementation rule: every protocol change starts here, in the same PR as the
code that implements it. Both codebases cite section numbers of this spec
(`SPEC §5`, `SPEC §6`, …) at their encode/decode sites; the numbering below is
stable — do not renumber existing sections.

Worked byte-level examples live in [`examples/`](examples/) and are normative:
conformance tests on both sides pin against those exact bytes
([`examples/word-records.md`](examples/word-records.md),
[`examples/envelopes.md`](examples/envelopes.md)).

Key words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are to be interpreted
as in RFC 2119.

---

## §1 Overview

PaceTurner streams a phone-side "baked" word stream to the watch for RSVP
reading. The phone holds the library and does all heavy computation
(tokenization, pacing, ORP pivots, fingerprinting); the watch stores chapters
of pre-baked words and renders them. The protocol therefore has exactly two
jobs:

1. **Content delivery** — phone describes a book (`manifest`), watch pulls
   word ranges (`chunkRequest` → `chunkData`).
2. **Position sync** — either side reports the current reading position
   (`position`), last-write-wins by timestamp.

Anything that goes wrong is reported as a typed `error` message or a typed
local decode failure — never guessed around, never silently retried (§8).

### §1.1 Transport

Messages are Connect IQ app messages: each envelope (§3) is a dictionary
whose top-level values are primitives except `p`, which carries either a
nested dictionary or a binary byte array depending on the message type (§4).
The codec layer specified here is transport-agnostic.

> **Platform note:** sending a `ByteArray` as a message value over
> `Communications.transmit` requires Connect IQ **API ≥ 6.0.0**. Protocol
> *consumers* (transport code) must therefore target API 6.0+; the codec
> itself (encode/decode of §5 records and §3 envelopes) has no such floor and
> builds against earlier API levels.

### §1.2 Units (normative, used throughout)

| Quantity | Unit / form |
|---|---|
| Reading position | 0-based **absolute word index** into the book's word stream — the only position coordinate in the protocol |
| Sync timestamps | Unix epoch **seconds**, integer (fits a signed 32-bit integer until 2038 — see §4.4) |
| Durations / dwell | **milliseconds**, integer |
| Content fingerprint | opaque equality token (§7) |
| ORP pivot | 0-based **byte** index into the word's UTF-8 bytes, precomputed by the phone (§5) |

All protocol integers — envelope fields and payload fields alike (`v`, `off`,
`n`, `tw`, `tb`, `o`, `cb`, `ts`) — are non-negative and MUST fit a **signed
32-bit** integer (≤ 2 147 483 647): the watch runtime's native integer
(Monkey C `Number`) is signed 32-bit. A value outside that range is malformed
(`malformedEnvelope`, §8).

---

## §2 Versioning

- Every envelope carries an explicit integer protocol version `v`. This
  document specifies **`v = 1`**.
- **Compatibility policy (v1): exact match.** A receiver MUST reject any
  envelope whose `v` differs from the version it implements — reject and
  report (error code `versionMismatch`, §8), **never guess**, never attempt
  partial interpretation.
- Any change to the envelope fields, message-type set, payload shapes, binary
  record layout, or flag-bit assignments requires editing this spec and
  bumping the version. There are no implicit extensions: receivers MUST NOT
  ignore-and-continue past unknown structure.

---

## §3 Envelope

Every message is a dictionary (Connect IQ `Dictionary`; Dart
`Map<String, Object?>`) whose keys are drawn from exactly these six — short
literal strings, case-sensitive. Which of them a given message carries is
defined by the per-type matrix below:

| Key | Type | Meaning |
|---|---|---|
| `t` | string | Message type — one of the five camelCase strings in §4 |
| `v` | integer | Protocol version (§2) |
| `fp` | string | Content fingerprint (§7) |
| `off` | integer | 0-based absolute word index |
| `n` | integer | Word count |
| `p` | type per §4 | Payload — dictionary or binary byte array |

No other top-level keys exist or may be added without a spec edit **and** a
version bump (§2). A receiver MUST treat an envelope containing an unknown
top-level key as malformed.

**Required / unused fields per message type:**

| Field | `manifest` | `chunkRequest` | `chunkData` | `position` | `error` |
|---|---|---|---|---|---|
| `t` | required | required | required | required | required |
| `v` | required | required | required | required | required |
| `fp` | required | required | required | required | optional |
| `off` | — | required | required | required | optional |
| `n` | — | required | required | — | — |
| `p` | required (dict) | — | required (bytes) | required (dict) | required (dict) |

“required” = present and non-null. “—” = unused: the sender SHOULD omit the
key (or MAY set it to null); receivers MUST treat an omitted key and a null
value identically, and MUST treat a **non-null** value in an unused field as
malformed (`malformedEnvelope`) — there are no implicit extensions (§2).
“optional” = may carry context when relevant (§4.5).

Where present, `off` MUST be ≥ 0 and `n` MUST be ≥ 1; violations are
malformed.

A receiver validates an envelope in this order:

1. `v` present, integer, equals its own version — else `versionMismatch` (§8).
2. `t` present and one of the five §4 strings — else `unknownType`.
3. Structure for that `t` matches the matrix — required fields present with
   the types above (`off` ≥ 0, `n` ≥ 1, `fp` per §7), unused fields omitted
   or null, no unknown keys — else `malformedEnvelope`.

Step 3 includes the payload's structure: for dictionary payloads, the keys
each §4 table marks required MUST be present with the types it declares
(`ch` non-empty). Value semantics beyond type — chapter ordering, `src`
values, range arithmetic against `tw` — are the consumer's concern, not
envelope validation.

---

## §4 Message Types

Exactly five message types exist. Type strings are camelCase and are the
literal values of `t`:

| `t` | Direction | Purpose |
|---|---|---|
| `manifest` | phone → watch | Describe a book: metadata, chapter map, durations |
| `chunkRequest` | watch → phone | Ask for `n` word records starting at `off` |
| `chunkData` | phone → watch | Deliver those records as a §5 binary payload |
| `position` | both | Report current reading position (last-write-wins) |
| `error` | both | Report a protocol-level failure (§8) |

### §4.1 `manifest` (phone → watch)

Announces the (single) active book. `fp` is the book's fingerprint; `off` and
`n` are unused. `p` is a dictionary:

| Key | Type | Required | Meaning |
|---|---|---|---|
| `ti` | string | yes | Book title (display only) |
| `tw` | integer | yes | Total word count of the book's word stream |
| `tb` | integer | yes | Total of all per-word `bonusMs` (§5) across the book, ms — enables time-remaining estimates |
| `ch` | array | yes | Chapters in reading order (at least one entry) |

Each entry of `ch` is a dictionary:

| Key | Type | Required | Meaning |
|---|---|---|---|
| `o` | integer | yes | Absolute word index of the chapter's first word; `ch[0].o` MUST be 0; entries MUST be strictly increasing and < `tw` |
| `ti` | string | yes | Chapter title (display on chapter-transition card) |
| `cb` | integer | yes | Cumulative `bonusMs` of all words *before* `o`, ms; `ch[0].cb` MUST be 0 |

### §4.2 `chunkRequest` (watch → phone)

Watch asks for word records. `fp`, `off`, `n` required; `p` unused.
Semantics: "send me `n` records starting at absolute word index `off` of the
content identified by `fp`."

- `n` MUST be ≥ 1 and `off` MUST be ≥ 0 — violations are malformed envelopes
  (§3, `malformedEnvelope`). The phone replies with `chunkData` for exactly
  the requested range, or `error` (`rangeUnavailable` if `off + n > tw`;
  `unknownFingerprint` if `fp` doesn't match its active book).
- `n` is chosen by the watch and bounded only by transport message-size
  limits (calibrated outside this spec); the phone MUST NOT answer with a
  different range than requested.

### §4.3 `chunkData` (phone → watch)

Delivers word records. `fp`, `off`, `n` required; `p` is a binary byte array
containing exactly `n` records in the §5 layout, tightly concatenated, where
the first record is the word at absolute index `off`.

The receiver MUST verify that decoding consumes the payload exactly: `n`
records, no bytes left over — any mismatch is a decode failure (§8,
`decodeFailure`).

### §4.4 `position` (both directions)

Reports the current reading position for sync. `fp` and `off` required
(`off` = the word currently/most recently displayed); `n` unused. `p` is a
dictionary:

| Key | Type | Required | Meaning |
|---|---|---|---|
| `ts` | integer | yes | When this position was established — Unix epoch **seconds** |
| `src` | string | yes | Originator: `"watch"` or `"phone"` |

Conflict resolution is last-write-wins on `ts`; equal timestamps resolve in
favor of `"watch"` (the reading device). A receiver MUST ignore a `position`
whose `fp` doesn't match its active content (and SHOULD reply
`unknownFingerprint` so the sender learns of the mismatch).

> Epoch seconds exceed signed 32-bit range in 2038. Monkey C `Number` is
> signed 32-bit; implementations SHOULD parse `ts` into a 64-bit-capable type
> where available. v1 accepts the 2038 horizon.

### §4.5 `error` (both directions)

Reports a protocol-level failure (§8). `p` is a dictionary:

| Key | Type | Required | Meaning |
|---|---|---|---|
| `c` | string | yes | Error code — one of the §8 values |
| `m` | string | no | Human-readable context for logs; never parsed |

`fp` and `off` MAY be set when the error concerns specific content or a
specific range (e.g. a failed chunk decode), and SHOULD be set when known.

---

## §5 Binary Word-Record Layout

The `p` payload of `chunkData` is a sequence of variable-length **word
records**, tightly concatenated with no padding, alignment, length prefix, or
trailer. All multi-byte integers are **little-endian**. One record:

| Offset | Size | Field | Description |
|---|---|---|---|
| 0 | u8 | `wordLen` | Byte length of the UTF-8 word, **1–255**; 0 is invalid |
| 1 | u8 | `flags` | Flag bits per §6 |
| 2 | u8 | `orpPivot` | 0-based **byte** index into the word's UTF-8 bytes of the ORP (optimal-recognition-point) character; MUST be < `wordLen` and MUST point at the first byte of a UTF-8 sequence. Precomputed by the phone; the watch never recomputes pivots |
| 3 | u16le | `bonusMs` | WPM-invariant **additive** dwell bonus, milliseconds, 0–65535 (§5.1) |
| 5 | `wordLen` | `word` | The word, UTF-8 encoded, no terminator |

Record size = 5 + `wordLen` bytes (~9 B/word average for English text).

Decode validation (bounds-check-and-degrade): a decoder MUST bounds-check
every read. A record is malformed if the payload is too short for its header
or its `wordLen` bytes, if `wordLen` is 0, if `orpPivot ≥ wordLen`, or if
reserved flag bits are set (§6). On a malformed record the decoder MUST stop
and surface a typed decode failure (`decodeFailure`, §8) — it MUST NOT throw
past its boundary, guess field values, or silently skip bytes.
Already-decoded records MAY be discarded; v1 treats the whole chunk as failed
(re-request is the recovery, §8).

The UTF-8-boundary requirement on `orpPivot` (first byte of a sequence) is
the **sender's** obligation, enforced at encode time. Decoders MUST NOT
validate or reject on it — the malformed conditions above are exhaustive.

### §5.1 Timing model

The stream stores, per word, the **additive bonus** in ms — never a total
duration. The watch computes display time as:

```
displayMs(word) = 60000 / wpm + bonusMs(word)
```

`bonusMs` is invariant under WPM changes; changing reading speed never
requires re-baking or re-transferring content.

---

## §6 Flag Bits

The `flags` byte of a §5 record:

| Bit | Mask | Name | v1 meaning |
|---|---|---|---|
| 0 | `0x01` | `sentenceEnd` | This word ends a sentence |
| 1 | `0x02` | `paragraphStart` | This word starts a paragraph |
| 2 | `0x04` | `chapterStart` | This word starts a chapter (its index appears as some `ch[i].o` in the manifest) |
| 3 | `0x08` | `continuation` | **Reserved** for long-word splitting; MUST be 0 in v1 |
| 4 | `0x10` | `rtl` | **Reserved** for right-to-left direction; MUST be 0 in v1 |
| 5–7 | `0xE0` | — | Reserved; MUST be 0 |

Senders MUST write 0 to all reserved bits. Receivers MUST treat any set
reserved bit (`flags & 0xF8 ≠ 0`) as a malformed record (§5 decode
validation): version gating (§2) guarantees a same-version sender writes
zeros, so a set reserved bit signals corruption. Activating a reserved bit is
a spec edit + version bump.

---

## §7 Fingerprint

The content fingerprint `fp` identifies one *conversion* of one book — the
exact word stream produced by one bake. Re-importing or re-baking a book
yields a new fingerprint, even for identical source text.

- **Wire form:** a string of exactly **8 lowercase hexadecimal characters**
  (`[0-9a-f]{8}`, representing 32 bits), e.g. `"9f86d081"`. A receiver MUST
  reject any other shape as a malformed envelope.
- **Semantics:** an **opaque equality token**. Consumers — the watch in
  particular — MUST only ever compare fingerprints for string equality; they
  MUST NOT parse, decode, order, or otherwise interpret the value.
- `fp` is carried on every `manifest`, `chunkRequest`, `chunkData`, and
  `position` message. Content with a non-matching fingerprint MUST never be
  mixed: a `chunkData` whose `fp` differs from the watch's active manifest is
  discarded (and reported, §8).
- **Computation** is phone-side and defined by the reference companion; any
  algorithm is conformant provided it emits the wire form above and distinct
  conversions get distinct values with high probability.

---

## §8 Error Semantics

Posture: **every failure surfaces as a named state — never a silent retry,
never a silent `catch {}`.** Local decode failures produce typed results the
caller must handle; peer-visible failures are reported with an `error`
message (§4.5).

Error codes (`p.c` values), v1:

| Code | Meaning | Typical sender |
|---|---|---|
| `versionMismatch` | Envelope `v` differs from receiver's version (§2) | either |
| `unknownType` | Envelope `t` not one of the five §4 types | either |
| `malformedEnvelope` | Required field missing / wrong type / unknown key / bad `fp` shape / non-null unused field / `off` < 0 / `n` < 1 | either |
| `unknownFingerprint` | `fp` doesn't match the receiver's active content | either |
| `rangeUnavailable` | `chunkRequest` range extends past the book (`off + n > tw`) | phone |
| `decodeFailure` | `chunkData` payload malformed per §5 (truncated, bad field, reserved bits, length mismatch) | watch |
| `internal` | Unexpected implementation failure | either |

Rules:

- A receiver detecting any of the above MUST reach a named error state and
  SHOULD send an `error` message to the peer (best-effort; an error message
  never triggers an `error` in response — no error loops).
- Receivers MUST accept an `error` whose `c` value is *unknown* to them and
  treat it as `internal` — codes are extensible values, not structure; new
  codes do not require a version bump (unlike fields, §3).
- Recovery from `decodeFailure` is a clean re-request of the same range
  (`chunkRequest`); recovery from `unknownFingerprint` is a clean re-fetch
  starting from `manifest`. Neither is automatic-silent: both surface in
  state first.

---

## §9 Glossary

- **Absolute word index** — the 0-based position of a word in the book's
  baked word stream, counted from the first word of the book. The protocol's
  *only* position coordinate: chapters map to it (§4.1), chunks are addressed
  by it (§4.2–4.3), sync positions are expressed in it (§4.4).
- **Content fingerprint** — the opaque 8-hex-char equality token identifying
  one conversion of one book (§7).
- **Word stream** — the phone-baked, ordered sequence of word records (§5)
  for a whole book: tokenized words with precomputed ORP pivots, dwell
  bonuses, and structural flags. The watch renders it; it never re-derives
  it.
- **Chapter-transition card** — the watch screen shown when the reading
  position crosses a chapter boundary (a word flagged `chapterStart`, §6); it
  displays the chapter title from the manifest's `ch` entry (§4.1).
- **Bake / conversion** — the phone-side import pipeline run that turns
  source text into a word stream and assigns the fingerprint.

/// Mirrored protocol constants — `protocol/SPEC.md` is the single source of
/// truth; the watch mirror is `watch/source/Protocol.mc`. The two sides never
/// import each other: each is checked against the spec's worked examples by
/// its own conformance tests. Never inline one of these strings at a call
/// site (architecture AR8).
abstract final class ProtocolKeys {
  /// SPEC §2 — versioning. v1 policy: exact match, reject + report otherwise.
  static const int protocolVersion = 1;

  // SPEC §3 — envelope keys {t, v, fp, off, n, p}.
  static const String keyType = 't';
  static const String keyVersion = 'v';
  static const String keyFingerprint = 'fp';
  static const String keyOffset = 'off';
  static const String keyCount = 'n';
  static const String keyPayload = 'p';

  // SPEC §4 — the five message types.
  static const String msgManifest = 'manifest';
  static const String msgChunkRequest = 'chunkRequest';
  static const String msgChunkData = 'chunkData';
  static const String msgPosition = 'position';
  static const String msgError = 'error';

  // SPEC §4.1 — manifest payload keys (`ti` is also the chapter-entry title).
  static const String keyTitle = 'ti';
  static const String keyTotalWords = 'tw';
  static const String keyTotalBonusMs = 'tb';
  static const String keyChapters = 'ch';
  static const String keyChapterOffset = 'o';
  static const String keyChapterCumBonusMs = 'cb';

  // SPEC §4.4 — position payload keys and source values.
  static const String keyTimestamp = 'ts';
  static const String keySource = 'src';
  static const String srcWatch = 'watch';
  static const String srcPhone = 'phone';

  // SPEC §4.5 — error payload keys.
  static const String keyErrorCode = 'c';
  static const String keyErrorMessage = 'm';

  // SPEC §6 — word-record flag bits. Continuation and RTL are reserved and
  // MUST be 0 in v1.
  static const int flagSentenceEnd = 0x01;
  static const int flagParagraphStart = 0x02;
  static const int flagChapterStart = 0x04;
  static const int flagContinuation = 0x08;
  static const int flagRtl = 0x10;
  static const int flagsReservedMask = 0xF8;

  /// SPEC §5 — fixed bytes before the UTF-8 word in a record.
  static const int recordHeaderBytes = 5;

  /// SPEC §7 — fingerprint wire form: exactly 8 lowercase hex chars.
  static const int fingerprintLength = 8;

  // SPEC §8 — error codes.
  static const String errVersionMismatch = 'versionMismatch';
  static const String errUnknownType = 'unknownType';
  static const String errMalformedEnvelope = 'malformedEnvelope';
  static const String errUnknownFingerprint = 'unknownFingerprint';
  static const String errRangeUnavailable = 'rangeUnavailable';
  static const String errDecodeFailure = 'decodeFailure';
  static const String errInternal = 'internal';
}

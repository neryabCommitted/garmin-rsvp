# Deferred Work

## Deferred from: code review of 1-2-protocol-spec-md-and-mirrored-constants (2026-06-10)

- `chunkData` payload check in `decodeEnvelope` is `Uint8List`-exact (`companion/lib/protocol/envelope_codec.dart:280-286`) — rejects byte-valued `List<int>`, the shape platform channels commonly deliver. Decide accept-and-convert vs document-the-edge when wiring `companion/lib/data/ciq_bridge.dart` in Epic 4. The watch side imposes no equivalent constraint.

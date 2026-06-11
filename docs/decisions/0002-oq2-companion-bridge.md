# ADR 0002 — OQ2: keep `watch_connectivity_garmin` (stock) as the companion bridge

**Status:** accepted · 2026-06-11

## Context

OQ2 asked whether the community Flutter bridge `watch_connectivity_garmin`
suffices for the delivery epic, or whether we must build a custom MethodChannel
bridge ("either answer is acceptable; it shifts effort, not requirements").
The plugin (0.1.13) pins the Garmin Android SDK **2.0.3** (Aug 2023; upstream is
2.4.0), whose serializer cannot carry byte arrays — so the protocol's binary
`chunkData.p` (SPEC §5) must ride a wrapper encoding. The Android SDK also has a
documented "first-send-works-then-fails" bug (silent no-callback, wireless,
acknowledged by Garmin, no verified fix), and the plugin's send future hangs
forever when the listener never fires.

Gate V2 (Story 1.4) measured this on real hardware: Fenix 8 47 mm ↔ Samsung
SM-S938B (Android 16), wireless via Garmin Connect Mobile, 200 sequential
~900 B chunkData sends per run, success counted **only on the watch's ack
arriving back on the phone** (the SDK's `SUCCESS` callback is documented to
lie). Defense available to the harness: 10 s timeout → retry-same-chunk →
after 3 consecutive failures re-init → resend.

Measured (2026-06-11, docs/gates.md §V2):

| Run | Transport for `p` | First-try acks | Timeouts / exceptions / re-inits | Wall-clock per chunk |
|---|---|---|---|---|
| A | base64 `String` (~1200 B wire) | **200/200** | 0 / 0 / 0 | **~892 ms** (~1.0 KB/s payload) |
| B | `List<int>` (900 elements) | **200/200** | 0 / 0 / 0 | **~1465 ms** (~0.6 KB/s payload) |

The bug did not appear in 400 consecutive wireless sends; the defense never
activated. The watch decoded every payload through the unchanged
`Protocol.validateEnvelope` + `StreamDecoder.decodeChunk` path — SPEC §5 bytes
survive both transports end-to-end. The watch→phone ack channel (Epic 4's
position-sync direction) was lossless. No `FAILURE_MESSAGE_TOO_LARGE` /
`BLE_REQUEST_TOO_LARGE` at ~1 KB.

## Decision

**Keep the stock plugin** (`watch_connectivity_garmin ^0.1.13`), with the
**base64-String transport** for binary payloads. Do not fork for SDK 2.4.0
byte-array support and do not build a custom MethodChannel bridge now.

Against the pinned criteria:

1. **Reliability** (decisive): 400/400 ack-confirmed first-try. The bug was not
   observed, so plugin-level re-init sufficiency remains unmeasured — but with
   a 100% first-try rate there is nothing the stock plugin fails to deliver.
2. **Payload carriage**: base64's 33% size inflation costs less than the
   per-element serialization of arrays — Run A beat Run B by ~64% wall-clock.
   Native bytes (the fork's main prize) could at best save the 33% inflation on
   the wire; the measured 1.0 KB/s with inflation already meets the research
   baseline.
3. **Failure signaling**: timeout-wrapped futures + `PlatformException` codes
   proved a workable contract for the runner; `TransferEngine` inherits the
   same seam.
4. **Maintenance posture**: the risks (maintainer without Garmin hardware, SDK
   pin three releases behind, no ProGuard keeps, no reachable `shutdown()`) are
   real but none bit during the gate; the fork remains a cheap, documented
   escape hatch (one gradle line: 2.0.3 → 2.4.0).

## Consequences

- ✅ Epic 4's `ciq_bridge.dart`/`TransferEngine` build on the stock plugin +
  base64-String wrapper; the V2 defense (serialize sends, 10 s timeout,
  retry-same-chunk, re-init after 3 consecutive failures, trust only the
  watch's ack) is **mandatory in TransferEngine in one place** regardless —
  FR20 designs for failure, and the bug is acknowledged-not-fixed upstream.
- ✅ No SPEC.md change: both transports are wire-level wrappers around the
  unchanged SPEC §5 payload (§1.1 platform note covers ByteArray transport).
- ⚠️ The re-init arm of the defense is **validated in unit tests but untested
  in anger** — the bug never fired. If Epic 4 meets it and plugin re-init does
  not recover (the plugin cannot reach SDK `shutdown()`), revisit per the row-3
  matrix path: fork-with-shutdown or custom bridge, then re-verify V2.
- ⚠️ **Release-build landmine (Epic 4/5):** ProGuard/R8 strips Garmin SDK
  classes without `-keep class com.garmin.** { *; }` (plugin issue #19; not
  shipped in the plugin). The spike ran debug; add the keep rules before any
  release build.
- ⚠️ **Foreground-service evidence:** Android 16 froze the backgrounded debug
  app mid-run (Dart timers stopped — even timeouts can't fire). Direct
  confirmation of Epic 4's foreground-service requirement for transfers.
- 🔁 **Revisit when**: (a) the silent-hang bug appears in Epic 4 hardening;
  (b) V3 (Story 1.5) finds a chunk-size ceiling where base64's 33% inflation
  meaningfully caps throughput — the fork to SDK 2.4.0 (native
  `MonkeyByteArray`) is the first option in both cases; or (c) the plugin's
  SDK pin blocks an Android-target upgrade.

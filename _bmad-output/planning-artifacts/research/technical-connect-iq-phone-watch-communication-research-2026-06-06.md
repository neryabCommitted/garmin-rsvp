---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments:
  - '_bmad-output/planning-artifacts/briefs/brief-garmin_RSVP-2026-06-05/brief.md'
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'Connect IQ phone↔watch communication (BLE streaming via CIQ Mobile SDK, with a Flutter companion)'
research_goals: 'Determine whether chunked word-stream delivery over the CIQ Mobile SDK can sustain uninterrupted RSVP playback at high WPM; identify throughput/latency/message-size limits, backpressure patterns, and Flutter platform-channel bridging options'
user_name: 'Nerya'
date: '2026-06-06'
web_research_enabled: true
source_verification: true
---

# Research Report: technical

**Date:** 2026-06-06
**Author:** Nerya
**Research Type:** technical

---

## Research Overview

This report investigates whether the Connect IQ (CIQ) phone↔watch communication stack can sustain uninterrupted Spritz-style RSVP playback at 300–700+ WPM (~5–12 words/second) for the garmin_RSVP project: a Garmin Fenix 8 (CIQ API 6.x) watch app fed a word-stream by a Flutter companion app over BLE. Research covered the on-watch `Toybox.Communications` module (transmit/receive model, data types, error codes, size limits), the Connect IQ Mobile SDKs for Android (v2.2.0) and iOS (v1.8.0), real-world throughput/latency reported on the Garmin developer forums, the role of the Garmin Connect Mobile (GCM) app in routing, and Flutter bridging options on pub.dev/GitHub. Methodology: official Garmin developer docs and API reference (fetched via a text-rendering proxy where pages were JS-only), the Garmin Connect IQ developer and bug-report forums (the richest source of real-world numbers), GitHub repos for the official SDKs and community wrappers, and pub.dev for Flutter plugins — with multi-source verification and confidence levels assigned to every uncertain claim.

The headline finding is that **the architecture is feasible, but only because the workload is tiny.** CIQ phone↔watch messaging is slow (developers report on the order of <1 KB/s effective throughput and 1–2 seconds round-trip latency for small messages, dominated by the BLE protocol itself), with a hard cap of ~3 concurrent outstanding transfers and undocumented, device-dependent per-message size ceilings. But an RSVP word stream is bandwidth-trivial: at 700 WPM the watch consumes roughly 60–90 bytes/second of text. The entire challenge is therefore **not bandwidth but buffering and resilience** — pre-fetching a window of words on the watch so that the multi-second, jittery, sometimes-failing message channel is never on the critical path of playback. A pull-based, deeply-buffered, ahead-of-need streaming design makes high-WPM playback comfortably achievable.

The secondary finding concerns Flutter bridging: a maintained community plugin (`watch_connectivity_garmin`, by rexios.dev) already wraps both native Mobile SDKs and exposes a `sendMessage`/`messageStream` Dart API covering Android and iOS — viable as a starting point but thin (v0.1.x, ~9 likes, no app-context support) and a maintenance risk for a project that must "never lie" about reading position. The realistic recommendation is to start on that plugin and be prepared to fork it or drop to a thin custom MethodChannel/EventChannel bridge over the native SDKs. The largest residual risks are the well-documented Android `sendMessage` reliability bugs (listener never firing on subsequent sends) and the BLE ATT MTU truncation bug — both of which the streaming protocol must defensively assume.

---

## Technical Research Scope Confirmation

**Research Topic:** Connect IQ phone↔watch communication — BLE streaming via the Connect IQ Mobile SDK, with a Flutter companion app
**Research Goals:** Determine whether chunked word-stream delivery can sustain uninterrupted RSVP playback at high WPM; identify throughput, latency, and message-size limits; backpressure/buffering patterns; and Flutter platform-channel bridging options for the native Mobile SDK.

**Technical Research Scope:**

- Architecture Analysis - CIQ Communications module, message passing model, streaming topologies
- Implementation Approaches - chunking, buffering, backpressure, retry/resume patterns
- Technology Stack - CIQ Mobile SDK (Android/iOS), Flutter platform channels, existing plugins
- Integration Patterns - phone↔watch protocols, payload limits, serialization
- Performance Considerations - throughput, latency, reliability at high WPM

**Research Methodology:**

- Current web data with rigorous source verification
- Multi-source validation for critical technical claims
- Confidence level framework for uncertain information
- Comprehensive technical coverage with architecture-specific insights

**Scope Confirmed:** 2026-06-06

<!-- Content will be appended sequentially through research workflow steps -->

---

## Technology Stack Analysis

### The on-watch side: `Toybox.Communications` (Monkey C, CIQ API 6.x)

The watch app uses the `Toybox.Communications` module for all phone↔watch messaging. Two complementary APIs matter:

- **`transmit(content, options, listener)`** — sends data from the watch to the phone app. Signature: `transmit(content as TransmitType, options as Dictionary or Null, listener as ConnectionListener) as Void`. The `listener` is a `ConnectionListener` with `onComplete()` and `onError()` callbacks. _Source: https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html (High, accessed 2026-06-06)_
- **`registerForPhoneAppMessages(callback)`** — registers a callback that receives a `PhoneAppMessage` for each message the phone sends to the watch. If messages are waiting when the app registers, the callback fires immediately for each. The payload is read from `PhoneAppMessage.data`. _Source: https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html (High, accessed 2026-06-06)_
- **`makeWebRequest(...)`** — lets the watch perform HTTP(S) GET/PUT/POST/DELETE that is **BLE-proxied through the Garmin Connect Mobile app** on the phone (the phone makes the actual network call). Supports JSON, URL-encoded, FIT, GPX, plain text, audio/HLS response types. _Source: https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html (High, accessed 2026-06-06)_

**Serialization / what crosses the wire.** Transmittable types (`TransmitType`) are: `Number`, `Float`, `Long`, `Double`, `String`, `Boolean`, `Char`, `ByteArray` (since API 6.0.0), `Null`, plus `Array` and `Dictionary` (keys restricted to `TransmitKeyType`) — and these nest arbitrarily (arrays of dictionaries, etc.). No custom-object serialization; you marshal into these primitives. _Source: https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html (High, accessed 2026-06-06)_

**Error codes (numeric).** The most relevant for streaming:

| Constant | Value | Meaning |
|---|---|---|
| UNKNOWN_ERROR | 0 | |
| BLE_ERROR | -1 | Generic BLE failure |
| BLE_HOST_TIMEOUT | -2 | |
| BLE_SERVER_TIMEOUT | -3 | |
| BLE_NO_DATA | -4 | |
| BLE_REQUEST_CANCELLED | -5 | |
| BLE_QUEUE_FULL | -101 | Too many outstanding requests |
| BLE_REQUEST_TOO_LARGE | -102 | Payload exceeds device limit |
| BLE_UNKNOWN_SEND_ERROR | -103 | |
| BLE_CONNECTION_UNAVAILABLE | -104 | Phone not connected |
| NETWORK_REQUEST_TIMED_OUT | -300 | |
| STORAGE_FULL | -1000 | |

_Source: https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html (High, accessed 2026-06-06)_

**Documented size limits: none.** Garmin does not publish a numeric per-message size limit; `BLE_REQUEST_TOO_LARGE (-102)` is the runtime signal that a payload was too big, and the threshold is device- and OS-dependent (see Performance, below). _Source: https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html (Medium — absence-of-limit confirmed in docs, actual ceiling only in forum reports, accessed 2026-06-06)_

### The companion side: Connect IQ Mobile SDKs

There are two **separate, native** SDKs (no shared cross-platform layer):

- **Android — `com.garmin.connectiq:ciq-companion-app-sdk`, latest 2.2.0 (Maven Central).** Gradle: `implementation("com.garmin.connectiq:ciq-companion-app-sdk:2.2.0@aar")`. Core classes: `ConnectIQ` (singleton, initialized with a connection type), `IQDevice`, `IQApp`; outbound `ConnectIQ.sendMessage(...)`; inbound messages arrive via app-event listeners and a `BroadcastReceiver` for the action `com.garmin.android.connectiq.INCOMING_MESSAGE`. Connection types: `IQConnectType.WIRELESS` (real BLE) and `IQConnectType.TETHERED` (ADB to simulator). _Source: https://github.com/garmin/connectiq-android-sdk (High, accessed 2026-06-06)_ _Source: https://github.com/Shhatrat/IQDroid (Medium, accessed 2026-06-06)_
  - Note: a separate search snippet referenced a "2.4 SDK"; the GitHub repo and Maven coordinate both show **2.2.0** as current, so 2.2.0 is treated as authoritative and "2.4" is likely a stale or device-SDK conflation. _Source: https://github.com/garmin/connectiq-android-sdk (Medium — version conflict noted, accessed 2026-06-06)_
- **iOS — `connectiq-companion-app-sdk-ios`, v1.8.0 (released 2026-01-15).** Singleton `ConnectIQ.sharedInstance`, initialized with `initializeWithUrlScheme:uiOverrideDelegate:`. Classes: `IQDevice`, `IQApp` (UUID + device). Register via `registerForDeviceEvents:delegate:` and `registerForAppMessages:delegate:`; outbound `sendMessage`. Message types must be `NSString`, `NSNumber`, `NSArray`, `NSDictionary`, or `NSNull`. Requires `-ObjC` linker flag, a custom URL scheme, `gcm-ciq` in `LSApplicationQueriesSchemes`, and `NSBluetoothPeripheralUsageDescription`. _Source: https://github.com/garmin/connectiq-companion-app-sdk-ios (High, accessed 2026-06-06)_ _Source: https://developer.garmin.com/connect-iq/core-topics/mobile-sdk-for-ios/ (High, accessed 2026-06-06)_

**App ID formatting gotcha:** the same CIQ app UUID is used as a plain string on Android but **must be hyphen-formatted (dashed UUID) on iOS** or communication silently fails. _Source: https://github.com/MatyasKriz/ios-connect-iq-comms (Medium, accessed 2026-06-06)_

### Flutter bridging options

- **`watch_connectivity_garmin` (pub.dev, publisher rexios.dev)** — v0.1.12, published ~3 months before access date, BSD-3-Clause. Wraps both native Mobile SDKs. API: `initialize(GarminInitializationOptions{applicationId, urlScheme})`, `sendMessage(Map)`, `messageStream`, `pairedDevices`, `showDeviceSelection()` (iOS). Messages are `Map` key/value. Maturity: 9 likes, 160 pub points, ~90 weekly downloads; **Application Context is unsupported (throws `UnsupportedError`)**; iOS min 13.0. _Source: https://pub.dev/packages/watch_connectivity_garmin (High, accessed 2026-06-06)_ _Source: https://pub.dev/documentation/watch_connectivity_garmin/latest/ (High, accessed 2026-06-06)_
- **`flutter_watch_garmin_connectiq` (AustrianApps, GitHub)** — explicitly "inspired by" rexios' watch_connectivity_garmin; depends on a `ConnectIQ-pod` fork; 0 stars/forks, essentially inactive/early-stage. Not recommended as a primary dependency. _Source: https://github.com/AustrianApps/flutter_watch_garmin_connectiq/blob/main/README.md (Medium, accessed 2026-06-06)_
- **Custom platform channel** — the fallback: a thin Kotlin (Android) + Swift (iOS) bridge exposing `sendMessage` over a `MethodChannel` and inbound messages over an `EventChannel`, calling the official native SDKs directly. This is the same architecture the plugins use internally. Note: a forum thread titled "Flutter application with Garmin Watch" is about (impossibly) running Flutter *on the watch* and is **not relevant** — Flutter is only ever the companion. _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/240145/flutter-appliacation-with-garmin-watch (High, accessed 2026-06-06)_ _Source: https://vibe-studio.ai/insights/creating-wearable-flutter-apps-for-garmin-devices (Low, accessed 2026-06-06)_

---

## Integration Patterns Analysis

### Does communication route through the Garmin Connect Mobile (GCM) app?

This is the single most consequential operational question, and the sources partially conflict — both views are presented:

- **Official FAQ (covers both platforms):** "The Partner SDKs are designed to work in unison with Garmin Connect Mobile. This means the user of your partner app will need to have Garmin Connect Mobile installed." It also documents the key reliability property: **if the watch CIQ app is not running, a phone→watch message persists in the app's mailbox until the user opens the app.** _Source: https://developer.garmin.com/connect-iq/connect-iq-faq/how-do-i-use-the-connect-iq-mobile-sdk/ (High, accessed 2026-06-06)_
- **iOS SDK guide (more precise for iOS):** GCM is required **for device discovery and app installation**, but **the actual message communication occurs directly via Bluetooth** between the companion app and the watch (not relayed through GCM at message time). If GCM is missing, the SDK shows an alert / triggers a UI-override delegate. _Source: https://developer.garmin.com/connect-iq/core-topics/mobile-sdk-for-ios/ (High, accessed 2026-06-06)_

**Reconciliation (Medium confidence):** On **iOS**, GCM must be installed (for pairing/discovery and to install the watch app) but the companion app holds its own BLE link for messaging. On **Android**, the GCM dependency is tighter — the Android SDK's BLE proxy / `makeWebRequest` path is explicitly routed through GCM, and forum reports of Android `sendMessage` failures are entangled with GCM/firmware behavior. Practical takeaway either way: **GCM must be installed and the watch paired through it; treat GCM as a required dependency on both platforms.** _Source: https://developer.garmin.com/connect-iq/connect-iq-faq/how-do-i-use-the-connect-iq-mobile-sdk/ (Medium, accessed 2026-06-06)_

### `makeWebRequest` is BLE-proxied through GCM

When the watch calls `makeWebRequest`, the request is tunneled over BLE to GCM, which performs the HTTP call and returns the response over BLE. Forum bug reports confirm this proxy (e.g., FIT content-type handling on `127.0.0.1`/localhost via the Android GCM proxy). This means `makeWebRequest` from the watch carries all the same BLE latency/throughput limits as `transmit`, plus a dependency on GCM's network. _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/301590/garmin-connect-mobile-android-bluetooth-proxy-comm-http_response_content_type_fit-makewebrequest-broken-on-127-0-01-localhost (Medium, accessed 2026-06-06)_

### Background / killed-app behavior

- **iOS:** Apps that opt into the "Uses Bluetooth LE accessories" Background Mode can be **woken in the background when the connected device has data to send.** However, backgrounded apps get **extremely low BLE priority** — foreground apps see much lower transmission delay than background apps. _Source: https://developer.garmin.com/connect-iq/core-topics/mobile-sdk-for-ios/ (High, accessed 2026-06-06)_ _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/2444/communications-transmit-queue-full (Medium, accessed 2026-06-06)_
- **Mailbox persistence:** phone→watch messages survive the watch app being closed (delivered on next open), supporting position-sync resilience. _Source: https://developer.garmin.com/connect-iq/connect-iq-faq/how-do-i-use-the-connect-iq-mobile-sdk/ (High, accessed 2026-06-06)_

### Known reliability issues (integration risk register)

- **Android `sendMessage` "works once then stops":** developers report the first phone→watch transfer succeeding and **all subsequent transfers failing — the result listener is never called and no data arrives** (e.g., Vivoactive 5 / Android 14, Aug 2024). Also `sendMessage` returning *both* SUCCESS and FAILURE_UNKNOWN. _Source: https://forums.garmin.com/developer/connect-iq/i/bug-reports/android-connectiq-sdk-no-transfer-of-data-to-the-watch-after-the-first-attempt (Medium, accessed 2026-06-06)_ _Source: https://forums.garmin.com/developer/connect-iq/i/bug-reports/android-mobile-sdk---connectiq-sendmessage-return-with-success-and-failure_unknown (Medium, accessed 2026-06-06)_
- **`Raw.sendMessage()` is broken** and should not be used; use the higher-level managed path. _Source: https://github.com/Shhatrat/IQDroid (Medium, accessed 2026-06-06)_
- **BLE ATT MTU truncation bug:** the Garmin BLE stack does not span ATT packets across Link Layer packets, so if a larger MTU is negotiated, payloads not fitting a single ATT packet are **truncated (historically at ~20 bytes of GATT payload)**. Relevant if doing low-level BLE; mostly abstracted away by the CIQ message APIs but a cautionary signal about the stack's fragility. _Source: https://forums.garmin.com/developer/connect-iq/i/bug-reports/messages-from-btle-gatt-server-truncated-at-20-bytes (Medium, accessed 2026-06-06)_
- **Android SDK init failure** on certain compile-SDK/OS combos (e.g., targetSdk 30 on Android 11). _Source: https://forums.garmin.com/developer/connect-iq/i/bug-reports/android-mobile-sdk-fails-to-initialize-connect-iq-if-compiling-using-android-sdk-30-and-running-on-android-11-devices (Low, accessed 2026-06-06)_

---

## Architectural Patterns Analysis

### Performance envelope (the numbers that size the design)

| Metric | Reported value | Source confidence |
|---|---|---|
| Effective throughput | "less than 1 KB/second" | Medium (forum, attributed to BLE) |
| Round-trip latency, small msg | ~1–2 seconds (single char request + <500 B response); ~75% of delay is BLE protocol, outside dev control | Medium (forum testing) |
| Max concurrent outstanding transfers (watch→phone) | **3** (configurable per device; applies to device→phone direction) | Medium (forum, Garmin staff) |
| Queue-full behavior | warning logged + `onError()` (`BLE_QUEUE_FULL`/-101) | High (forum + API docs) |
| `makeWebRequest` response cap (-402) | ~32 KB on Fenix 7 Pro/Android; ~44 KB on Epix 2 Pro; one dev "thought ~8k"; **undocumented, device/OS-dependent** | Medium (forum, conflicting) |
| `transmit` per-message cap | undocumented; `BLE_REQUEST_TOO_LARGE`/-102 on overflow; practical safe chunk ≈ few hundred bytes to ~1 KB | Low–Medium (forum) |

_Sources: https://forums.garmin.com/developer/connect-iq/f/discussion/2444/communications-transmit-queue-full ; https://forums.garmin.com/developer/connect-iq/f/discussion/414966/understanding--402-response-limit-for-makewebrequest (both Medium, accessed 2026-06-06)_

### The workload is trivially small — by design

RSVP at 700 WPM ≈ **~11.7 words/second**. Average English word ≈ 5 letters + space ≈ 6 bytes; with per-word timing metadata (a small int for dwell-ms, ORP pivot index) call it ~10–16 bytes/word. So sustained demand ≈ **~120–190 bytes/second** at the top end — one to two orders of magnitude *below* even the pessimistic <1 KB/s channel. **Bandwidth is not the constraint; latency and reliability are.** _Derived from brief WPM targets; channel figures per forum sources above (High confidence in the arithmetic, Medium in channel figures)._

### Recommended topology: watch-pull with deep look-ahead buffering

The right pattern is a **pull-based, high-water/low-water buffered stream**, not a steady phone-push:

1. **Watch keeps a ring buffer** of N pre-fetched words (each word = `{text, dwellMs, orpIndex}` or a compact encoding). Size N for *seconds of playback*, not for memory thrift — e.g., 200–600 words buffers ~17–50 s at 700 WPM, covering several worst-case 1–2 s round trips plus retries. Fenix 8 memory budget (to confirm from `devices.json`) comfortably holds this (a few KB of text).
2. **Low-water trigger:** when the buffer drops below a threshold (e.g., 30–40% remaining, i.e., still ~10+ seconds of runway), the watch issues a single `transmit` "request next chunk from offset X, count K" to the phone.
3. **Phone replies with a batched chunk** (K words in one message — batch to amortize the ~1–2 s round trip and stay well under the size cap; e.g., K such that payload ≈ a few hundred bytes to ~1 KB).
4. **Concurrency discipline:** never have more than ~1–2 outstanding requests (stay safely under the 3-transfer cap); only request the next chunk after `onComplete()` (or a timeout-driven retry).
5. **Playback never blocks on the network** — the renderer only ever reads from the local buffer; an empty buffer is a *failure mode to design against*, not a normal state.

This pull model also gives natural **backpressure** (the watch asks only when it has room) and clean **resume** semantics (every request carries an absolute word offset).

### Position sync and resume ("must never lie")

- Treat **word offset (absolute index into the book's word stream)** as the single source of truth for position; sync it both directions.
- Watch→phone: periodically (e.g., every few seconds or every chapter/paragraph boundary, and on pause) `transmit` the current offset. Rely on phone-side persistence as the durable store.
- Use the **mailbox persistence** property: phone can push the authoritative resume offset; it waits in the watch mailbox and is applied on app open. _Source: https://developer.garmin.com/connect-iq/connect-iq-faq/how-do-i-use-the-connect-iq-mobile-sdk/ (High, accessed 2026-06-06)_
- Also persist offset in watch-local storage (`Toybox.Storage`/`Application.Properties`) so a disconnect/reboot doesn't lose position before the next sync. Reconcile on reconnect by taking the **max(committed offsets)** with explicit conflict logging.

### Disconnect / retry / resume after BLE drop

- On `BLE_CONNECTION_UNAVAILABLE` (-104) or repeated timeouts: pause requesting, keep playing from buffer, surface a subtle "buffering" indicator only if the buffer actually nears empty.
- Retry with backoff on `onError`; re-issue the *same* offset-based request (idempotent because requests are absolute-offset, not "next").
- Because phone→watch messages persist in the mailbox, a chunk sent during a flap is delivered on reconnect rather than lost. _Source: https://developer.garmin.com/connect-iq/connect-iq-faq/how-do-i-use-the-connect-iq-mobile-sdk/ (High, accessed 2026-06-06)_

### Alternatives / complements

- **Bulk pre-load instead of streaming:** for a personal/MVP use case, the phone could push an entire chapter (or whole short book) into watch storage up front via file transfer, eliminating mid-playback round trips entirely. Given the ~32–44 KB `makeWebRequest`/transfer ceilings and slow throughput, this works best **chapter-at-a-time** (a chapter of compact word-stream text is typically well under tens of KB). Trades a one-time multi-second transfer for rock-solid uninterrupted playback. **Strong candidate for MVP.** _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/414966/understanding--402-response-limit-for-makewebrequest (Medium, accessed 2026-06-06)_
- **`makeWebRequest` from watch:** lets the watch pull directly from a local HTTP server the Flutter app runs (BLE-proxied via GCM). Avoids writing the phone→watch `sendMessage` path, but inherits GCM proxy quirks and the same latency, and ties the design to GCM's network proxy. Lower priority than the SDK message path. _Source: https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html (High, accessed 2026-06-06)_
- **CIQ background service for sync:** CIQ supports background services for periodic sync; relevant for committing position when the foreground app isn't active, but not on the playback hot path. _Source: https://developer.garmin.com/connect-iq/connect-iq-faq/how-do-i-create-a-connect-iq-background-service/ (Low, accessed 2026-06-06)_

---

## Implementation Research

**Practical, code-level guidance and gotchas for garmin_RSVP:**

1. **Marshal the word stream as compact arrays, not verbose dicts.** A chunk like `[[ "word", dwellMs, orpIdx ], ...]` (array of arrays) is a legal `TransmitType` and avoids repeating dictionary keys per word, stretching how many words fit under the size cap. Or pack into a `ByteArray` (API 6.0+) for maximum density. _Source: https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html (High, accessed 2026-06-06)_

2. **Make every request idempotent and offset-addressed.** Never send "give me the next chunk" — send "give me K words starting at absolute index X." This makes retries safe and resume trivial, and tolerates duplicate deliveries from the persistent mailbox.

3. **Respect the 3-transfer limit explicitly.** Keep a counter of outstanding `transmit` calls; do not exceed 1–2 in flight. Only issue the next request from inside `onComplete()` (success) or a watchdog timer (timeout). Treat `BLE_QUEUE_FULL` (-101) as "back off, you over-issued." _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/2444/communications-transmit-queue-full (Medium, accessed 2026-06-06)_

4. **Budget for 1–2 s round trips and worse when backgrounded.** Buffer depth must cover several round trips plus retries; size the low-water mark so the watch starts fetching with ≥10 s of playback still buffered. Assume the companion may be backgrounded on iOS with degraded BLE priority. _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/2444/communications-transmit-queue-full (Medium, accessed 2026-06-06)_

5. **Empirically calibrate the chunk size** against `BLE_REQUEST_TOO_LARGE` (-102) on the actual Fenix 8 — the limit is undocumented and device-specific. Start conservative (a few hundred bytes / ~20–40 words) and grow until you see -102 or instability, then back off. _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/414966/understanding--402-response-limit-for-makewebrequest (Medium, accessed 2026-06-06)_

6. **Defend against the Android "first send works, rest fail" bug.** Add a per-request timeout + retry on the phone side; if the result listener never fires, re-init the SDK / re-establish the `IQApp` and resend. Build an integration test that sends many sequential messages early to detect this on the target device/firmware. _Source: https://forums.garmin.com/developer/connect-iq/i/bug-reports/android-connectiq-sdk-no-transfer-of-data-to-the-watch-after-the-first-attempt (Medium, accessed 2026-06-06)_

7. **iOS app-ID dashing.** When/if porting the companion to iOS, format the CIQ app UUID with dashes; the un-dashed string silently fails on iOS while working on Android. _Source: https://github.com/MatyasKriz/ios-connect-iq-comms (Medium, accessed 2026-06-06)_

8. **For the Flutter plugin path, don't depend on Application Context** — `watch_connectivity_garmin` throws `UnsupportedError` for it. Use `sendMessage`/`messageStream` only, and design the protocol entirely on discrete messages. _Source: https://pub.dev/documentation/watch_connectivity_garmin/latest/ (High, accessed 2026-06-06)_

9. **Reference implementations to study:** Garmin's official `Comm` watch sample (in the device SDK) and `Comm Android` sample; the iOS examples `garmin/Garmin-ExampleApp-Swift` and `MatyasKriz/ios-connect-iq-comms`; the Kotlin wrapper `Shhatrat/IQDroid` (shows the managed `IQDataManager` pattern and the `INCOMING_MESSAGE` BroadcastReceiver). _Source: https://github.com/garmin/connectiq-android-sdk ; https://github.com/dougw/Garmin-ExampleApp-Swift ; https://github.com/Shhatrat/IQDroid (Medium, accessed 2026-06-06)_

10. **AndroidManifest:** register `com.garmin.android.connectiq.INCOMING_MESSAGE` to receive launches/messages; declare BLE/Bluetooth permissions. _Source: https://github.com/Shhatrat/IQDroid (Medium, accessed 2026-06-06)_

---

## Research Synthesis

### Executive Summary

Uninterrupted high-WPM RSVP playback over Connect IQ is **feasible**, and the reason is decisive: the channel is slow (<1 KB/s, 1–2 s round trips, max 3 concurrent transfers) but the RSVP workload is tiny (~120–190 bytes/s at 700 WPM). The architecture's entire job is to **decouple the jittery, occasionally-failing message channel from the playback clock** via a deep on-watch look-ahead buffer fed by idempotent, offset-addressed pull requests. Bandwidth is a non-issue; the real engineering is buffering, backpressure, retry/resume, and working around documented SDK reliability bugs (notably Android `sendMessage` failing after the first send, and BLE-stack fragility). For an MVP, **bulk per-chapter pre-load is an even safer alternative** that can eliminate mid-playback round trips entirely. On Flutter, a maintained-but-thin community plugin (`watch_connectivity_garmin`) already bridges both native Mobile SDKs; start there, plan to fork or replace with a custom MethodChannel/EventChannel bridge if it proves limiting.

### Key Findings

- CIQ phone↔watch messaging uses `Communications.transmit` (watch→phone) and `registerForPhoneAppMessages` (phone→watch), exchanging only primitive/array/dict/`ByteArray` types — no documented size limit, with `BLE_REQUEST_TOO_LARGE` (-102) as the runtime overflow signal. _Source: https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html (High)_
- Real-world performance: <1 KB/s effective throughput, ~1–2 s small-message round trips, max 3 concurrent transfers, queue-full → `onError`. _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/2444/communications-transmit-queue-full (Medium)_
- RSVP demand at 700 WPM is ~120–190 B/s — far below channel capacity; buffering, not bandwidth, is the design problem. _(Derived; High on arithmetic, Medium on channel figures)_
- GCM (Garmin Connect Mobile) must be installed; on iOS it's needed for discovery/install while messages flow direct over BLE; on Android the dependency (incl. `makeWebRequest` BLE proxy) is tighter — sources partially conflict and both are documented. _Sources: FAQ (High) + iOS guide (High); reconciliation Medium._
- Phone→watch messages **persist in the watch mailbox** if the app is closed, delivered on next open — valuable for resilient position sync. _Source: FAQ (High)_
- iOS companions can be woken in background for BLE data but get low BLE priority when backgrounded. _Source: iOS guide (High) + forum (Medium)_
- Documented reliability bugs to design around: Android `sendMessage` "works once then stops" / dual SUCCESS+FAILURE_UNKNOWN; `Raw.sendMessage` broken; BLE ATT MTU truncation. _Sources: Garmin bug-report forum + IQDroid (Medium)_
- `makeWebRequest` response cap is undocumented and device-dependent (~32 KB Android / ~44 KB iOS reported); same BLE limits apply since it's GCM-proxied. _Source: makeWebRequest -402 thread (Medium)_
- SDK versions: Android Mobile SDK 2.2.0 (Maven Central); iOS SDK 1.8.0 (2026-01-15). (One snippet's "2.4" treated as stale/conflated.) _Sources: GitHub repos (High); version conflict Medium._
- Flutter: `watch_connectivity_garmin` v0.1.12 (rexios.dev) bridges both platforms with `sendMessage`/`messageStream` — usable but thin (9 likes, no app-context); `flutter_watch_garmin_connectiq` is inactive; custom MethodChannel/EventChannel is the fallback. _Sources: pub.dev (High); AustrianApps repo (Medium)_

### Recommendations for garmin_RSVP

1. **Adopt watch-pull + deep buffer.** Render only from a local ring buffer (target ~200–600 words / 17–50 s at 700 WPM); fetch the next chunk at a low-water mark with ≥10 s runway remaining. Bandwidth is not the bottleneck; never let playback block on BLE.
2. **For MVP, strongly consider per-chapter bulk pre-load** (phone pushes a whole chapter into watch storage before play). This sidesteps mid-playback round trips, the 3-transfer cap, and most reliability bugs — best fit for the "finish a real book, uninterrupted" success criterion.
3. **Make the protocol offset-addressed and idempotent**; absolute word index is the position source of truth, synced both ways, with watch-local persistence + mailbox-delivered authoritative offset for crash/disconnect/reboot resilience ("resume never lies").
4. **Encode compactly** (array-of-arrays or `ByteArray`) and empirically calibrate chunk size against -102 on the real Fenix 8.
5. **Flutter bridging:** start on `watch_connectivity_garmin`; vendor/fork it or drop to a thin custom platform-channel bridge if you hit its limits — and budget time for the Android `sendMessage` reliability workaround (timeout + re-init + resend, exercised by an early multi-send integration test).
6. **Confirm Fenix 8 memory budget** from the SDK `devices.json`; the buffer sizes above are small (single-digit KB of text) and should fit comfortably, but verify.

### Risks and Open Questions

- **HIGH — Android `sendMessage` reliability.** "First send works, rest fail" is reported on recent devices/firmware; could directly break a continuous stream. Mitigate with bulk pre-load and/or robust re-init+retry; validate on the actual Fenix 8 + current GCM early. _Source: Garmin bug-report forum (Medium)_
- **MEDIUM — Flutter plugin maturity.** `watch_connectivity_garmin` is low-adoption and lacks app context; a position-critical app may outgrow it. Be ready to fork/replace. _Source: pub.dev (High on facts, Medium on risk)_
- **MEDIUM — undocumented size/throughput limits** vary by device/OS/firmware; the Fenix 8's exact `transmit` ceiling and round-trip latency are unknown until measured. _Source: forum (Medium)_
- **MEDIUM — GCM dependency & background behavior.** Requires GCM installed and the watch paired; backgrounded companion gets degraded BLE on iOS. Quantify on-device. _Sources: FAQ + iOS guide (High/Medium)_
- **LOW — version drift.** SDK versions (Android 2.2.0 / iOS 1.8.0) and the "2.4" discrepancy should be re-confirmed at implementation time. _Source: GitHub repos (Medium)_
- **OPEN — exact Fenix 8 memory budget** for the word buffer (from `devices.json`). _(brief flags this; not yet measured)_

### Source Documentation

| URL | What it supports | Confidence | Accessed |
|---|---|---|---|
| https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html | transmit/registerForPhoneAppMessages signatures, TransmitType, error codes, makeWebRequest | High | 2026-06-06 |
| https://developer.garmin.com/connect-iq/core-topics/communicating-with-mobile-apps/ | (JS-only nav; index reference) | Low | 2026-06-06 |
| https://developer.garmin.com/connect-iq/core-topics/mobile-sdk-for-ios/ | iOS SDK init, classes, GCM-for-discovery, background BLE | High | 2026-06-06 |
| https://developer.garmin.com/connect-iq/core-topics/mobile-sdk-for-android/ | Android SDK guide (index/ADB tether detail) | Medium | 2026-06-06 |
| https://developer.garmin.com/connect-iq/connect-iq-faq/how-do-i-use-the-connect-iq-mobile-sdk/ | GCM requirement both platforms, mailbox persistence, sendMessage | High | 2026-06-06 |
| https://developer.garmin.com/connect-iq/connect-iq-faq/how-do-i-create-a-connect-iq-background-service/ | CIQ background service for sync | Low | 2026-06-06 |
| https://github.com/garmin/connectiq-android-sdk | Android SDK v2.2.0, Maven coords, samples | High | 2026-06-06 |
| https://github.com/garmin/connectiq-companion-app-sdk-ios | iOS SDK v1.8.0 (2026-01-15) | High | 2026-06-06 |
| https://github.com/Shhatrat/IQDroid | Android wrapper: IQDataManager, connection types, INCOMING_MESSAGE, Raw.sendMessage broken | Medium | 2026-06-06 |
| https://github.com/MatyasKriz/ios-connect-iq-comms | iOS app-ID dash formatting gotcha; two-way comm example | Medium | 2026-06-06 |
| https://github.com/dougw/Garmin-ExampleApp-Swift | iOS Swift example app | Low | 2026-06-06 |
| https://forums.garmin.com/developer/connect-iq/f/discussion/2444/communications-transmit-queue-full | <1KB/s, 1–2s latency, 3 concurrent transfers, queue-full behavior, iOS background priority | Medium | 2026-06-06 |
| https://forums.garmin.com/developer/connect-iq/f/discussion/414966/understanding--402-response-limit-for-makewebrequest | makeWebRequest size cap ~32KB Android / ~44KB iOS, device-dependent | Medium | 2026-06-06 |
| https://forums.garmin.com/developer/connect-iq/i/bug-reports/android-connectiq-sdk-no-transfer-of-data-to-the-watch-after-the-first-attempt | Android first-send-works-then-fails bug | Medium | 2026-06-06 |
| https://forums.garmin.com/developer/connect-iq/i/bug-reports/android-mobile-sdk---connectiq-sendmessage-return-with-success-and-failure_unknown | dual SUCCESS+FAILURE_UNKNOWN | Medium | 2026-06-06 |
| https://forums.garmin.com/developer/connect-iq/i/bug-reports/messages-from-btle-gatt-server-truncated-at-20-bytes | BLE ATT MTU truncation bug | Medium | 2026-06-06 |
| https://forums.garmin.com/developer/connect-iq/i/bug-reports/android-mobile-sdk-fails-to-initialize-connect-iq-if-compiling-using-android-sdk-30-and-running-on-android-11-devices | Android init failure on certain SDK/OS combos | Low | 2026-06-06 |
| https://forums.garmin.com/developer/connect-iq/f/discussion/301590/garmin-connect-mobile-android-bluetooth-proxy-comm-http_response_content_type_fit-makewebrequest-broken-on-127-0-01-localhost | makeWebRequest BLE-proxied through GCM (localhost) | Medium | 2026-06-06 |
| https://forums.garmin.com/developer/connect-iq/f/discussion/240145/flutter-appliacation-with-garmin-watch | Flutter-on-watch not possible (companion-only confirmation) | High | 2026-06-06 |
| https://pub.dev/packages/watch_connectivity_garmin | Flutter plugin v0.1.12, platforms, maturity, no app-context | High | 2026-06-06 |
| https://pub.dev/documentation/watch_connectivity_garmin/latest/ | plugin API surface (sendMessage, messageStream, init) | High | 2026-06-06 |
| https://github.com/AustrianApps/flutter_watch_garmin_connectiq/blob/main/README.md | alternative Flutter plugin (inactive) | Medium | 2026-06-06 |
| https://vibe-studio.ai/insights/creating-wearable-flutter-apps-for-garmin-devices | companion+MethodChannel architecture pattern (secondary) | Low | 2026-06-06 |

# Reconciliation: CIQ Phone↔Watch Communication Research vs. PRD + Addendum

**Input:** `technical-connect-iq-phone-watch-communication-research-2026-06-06.md`
**Against:** `prd.md` and `addendum.md` (prd-garmin_RSVP-2026-06-06)
**Date:** 2026-06-06
**Scope of this pass:** Find substantive INPUT content carried into NEITHER the PRD nor the addendum that *should* be — i.e., constraints affecting requirements, unregistered risks, or dropped decisions / hard numbers. Implementation detail that correctly lives downstream is noted only when it changes requirements, risks, or scope, or when a number is wrong/omitted.

---

## Method note

The PRD and addendum are, on the whole, faithful. The streaming topology (pull-based, chapter-granular, offset-addressed, idempotent), the throughput-is-trivial / reliability-is-the-problem framing, the three headline hazards (Android first-send bug, -102 size ceiling, 3-transfer cap), 1–2 s latency, mailbox persistence, GCM-required prerequisite, the Flutter bridge choice and its no-app-context limitation, and the SDK versions are all present and well-mapped to FRs (FR16–FR20), NFRs, and risks R2/R3. The gaps below are the residue: items in the INPUT that move a requirement, a risk, or a hard number and that I could not find reflected in either downstream doc.

---

## Gaps found (carried into NEITHER doc, and should be)

### GAP 1 — iOS backgrounded companion gets degraded BLE priority (constraint that affects FR4 / FR18 / iOS-in-reach claim) — MEDIUM
**INPUT:** "backgrounded apps get **extremely low BLE priority** — foreground apps see much lower transmission delay than background apps" (Background/killed-app behavior; Risks: "MEDIUM — GCM dependency & background behavior … backgrounded companion gets degraded BLE on iOS").
**PRD/Addendum:** Neither doc mentions background-vs-foreground BLE priority. The addendum §3 covers mailbox persistence and the 5-min background-sync interval, but not the *priority degradation* when the companion is backgrounded.
**Why it matters:** The PRD repeatedly treats "iOS in reach" as a near-term design constraint (NFR6, addendum §1, scope "Later: iOS companion") and FR18 promises phone-free reading with reconnect sync. The research flags that on iOS the *companion being backgrounded* (not just absent) materially degrades transfer timing — directly relevant to whether mid-chapter background prefetch (FR17) and reconnect sync behave acceptably on iOS. This is a real constraint the research registered as a MEDIUM risk and that is currently unregistered. Even though iOS is "Later," the word-stream/protocol decisions are being locked now; the constraint should at least be a noted open item.
**Recommendation:** Add a one-line risk/constraint note (R-series or addendum §3) that the iOS companion, when backgrounded, gets low BLE priority — prefetch-ahead-of-need depth must account for it, and it should be quantified during the eventual iOS port.

### GAP 2 — `makeWebRequest` (watch-pulls-over-HTTP via GCM proxy) as an alternative delivery path — DECISION NOT RECORDED — LOW/MEDIUM
**INPUT:** Two distinct mentions: (a) `makeWebRequest` is BLE-proxied through GCM and inherits the same latency/throughput limits plus a GCM-network dependency; (b) as an alternative, the watch could `makeWebRequest` against a local HTTP server the Flutter app runs — "Lower priority than the SDK message path."
**PRD/Addendum:** The addendum §6 "Options Considered & Set Aside" lists Readium, max-index reconciliation, fixed timer, tiny-window streaming, and Kotlin companion — but does **not** list the `makeWebRequest`/local-HTTP-server delivery alternative that the research explicitly evaluated and set aside.
**Why it matters:** This is a researched-and-rejected architecture option. The addendum's stated purpose is to hold "rejected-alternative rationale that informs architecture." A future architect (or contributor reading the documented protocol per FR27) may re-propose `makeWebRequest` without knowing it was considered and deprioritized for the GCM-proxy-quirk + same-latency reasons. Low-stakes but it's a dropped decision that belongs in §6.
**Recommendation:** Add one bullet to addendum §6: "watch-side `makeWebRequest` against a phone-local HTTP server — rejected/deprioritized vs. the SDK message path; BLE-proxied through GCM so it inherits the same latency and adds GCM-network-proxy quirks."

### GAP 3 — BLE ATT MTU ~20-byte truncation bug is dropped from the risk register — LOW (informational, but a hard number)
**INPUT:** "BLE ATT MTU truncation bug: … payloads not fitting a single ATT packet are **truncated (historically at ~20 bytes of GATT payload)** … mostly abstracted away by the CIQ message APIs but a cautionary signal about the stack's fragility." Listed among "Documented reliability bugs to design around."
**PRD/Addendum:** Not present in either. The addendum §3 lists the -102, -101, first-send, and latency hazards but omits the MTU/20-byte truncation entirely.
**Why it matters:** The research itself qualifies this as "mostly abstracted away" by the managed message APIs — so it does NOT affect the chosen SDK-message path and is correctly low priority. It becomes relevant only if anyone drops to low-level BLE. Flagging it as a *gap* mainly so the omission is a conscious choice rather than silent. Acceptable to leave out given the chosen path; include if the addendum wants a complete hazard inventory.
**Recommendation:** Optional one-liner in addendum §3 hazards: "BLE ATT MTU truncation (~20-byte GATT payload) — abstracted away by managed message APIs; only a concern if dropping to raw BLE. Do not."

### GAP 4 — `Raw.sendMessage()` is broken / use the managed path — IMPLEMENTATION GUARDRAIL not captured — LOW
**INPUT:** "`Raw.sendMessage()` is broken and should not be used; use the higher-level managed path." Also implementation item 9 points at IQDroid's managed `IQDataManager` pattern.
**PRD/Addendum:** Not mentioned. Addendum §1 names the bridge plugin but does not record the "use managed, not raw" guardrail.
**Why it matters:** This is a concrete "don't do this" that guards the very reliability the protocol depends on. It's genuinely implementation-level and could legitimately live only in downstream architecture — but it's a known-broken API that a fork/custom-bridge author (the explicit fallback in addendum §1 and OQ2) could easily hit. Borderline; flagged for completeness.
**Recommendation:** If/when the custom MethodChannel bridge is specced, note "use the managed sendMessage path; `Raw.sendMessage()` is broken." Not required in the PRD.

---

## Checked and correctly NOT a gap (no action)

- **Error-code table, TransmitType list, compact array-of-arrays/ByteArray encoding, chunk-size calibration** — present or correctly summarized (addendum §2, §3; NFR2/NFR3).
- **3-transfer cap, -101/-102, 1–2 s latency, <1 KB/s throughput, ~120–190 B/s demand** — all carried (addendum §3).
- **Mailbox persistence** — carried (addendum §3; FR13/FR14).
- **GCM required on both platforms** — carried (NFR6; addendum implicit). The INPUT's nuance that on iOS messaging is *direct BLE* while GCM is only for discovery/install, vs. tighter Android coupling, is simplified to "GCM installed is a prerequisite." Acceptable simplification for a single-platform (Android-first) MVP; the iOS nuance becomes relevant only at the iOS port and overlaps GAP 1.
- **Android init failure on certain compile-SDK/OS combos (targetSdk 30 / Android 11)** — INPUT rates this LOW; it's a build-config detail correctly left to implementation, not a requirement/scope/risk change. Not flagged.
- **iOS app-ID dash-formatting gotcha; AndroidManifest INCOMING_MESSAGE registration; -ObjC linker flag / URL scheme / LSApplicationQueriesSchemes** — pure implementation detail, correctly downstream. Not flagged.
- **Reference implementations to study (Comm samples, IQDroid, Garmin-ExampleApp-Swift)** — implementation aid; correctly downstream (addendum §4 already names CI exemplars).
- **SDK versions (Android 2.2.0 / iOS 1.8.0) and the "2.4" discrepancy** — addendum §1 cites SDK 9.1.0 (device SDK) and the bridge plugin v0.1.12; the Mobile SDK component versions and the "2.4" version-drift open question are not separately recorded, but the INPUT itself rates version-drift LOW and "re-confirm at implementation time." Not a requirement/risk change. Borderline-low; noted here rather than escalated.
- **Fenix 8 memory budget open question** — the INPUT leaves it OPEN; the addendum *resolves* it (786,432 B / 768 KB watch-app heap, NFR2 ≤600 KB). This is the documents being *more* complete than the input, not a gap.

---

## Bottom line

Four candidate gaps, none scope-breaking. The only one rising to a registrable **risk/constraint** is **GAP 1 (iOS backgrounded → degraded BLE priority)**, which the research explicitly logged as MEDIUM and neither doc carries. **GAP 2 (makeWebRequest/local-HTTP alternative)** is a dropped *decision* that belongs in the addendum's set-aside-options section. GAPs 3 and 4 are low-priority hazard/guardrail omissions, acceptable to leave out given the chosen managed-message path but listed so the omission is deliberate.

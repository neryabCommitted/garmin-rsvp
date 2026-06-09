---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments:
  - '_bmad-output/planning-artifacts/briefs/brief-garmin_RSVP-2026-06-05/brief.md'
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'Garmin Fenix 8 watch-app constraints (memory, storage, CIQ API 6.x capabilities, AMOLED considerations)'
research_goals: 'Pin down the Fenix 8 memory budget per CIQ app type, storage/persistence APIs and limits, rendering and input capabilities relevant to an RSVP reader, and AMOLED constraints (burn-in, always-on)'
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

This report pins down the hard constraints that shape an RSVP (Rapid Serial Visual Presentation) speed-reader on the Garmin Fenix 8 (47mm AMOLED, 454×454, Connect IQ API 6.0). The scope covers per-app-type memory budgets, persistence/storage limits, the timer-and-render loop needed to flash one word every ~85–200 ms, button/touch input, AMOLED burn-in and screen-on behaviour during a long reading session, and background services for position sync. Methodology was current-web research with source verification: figures were cross-checked against the official Connect IQ API docs (developer.garmin.com), Garmin developer forums (forums.garmin.com), the community-maintained `flocsy/garmin-dev-tools` device-memory CSVs (which mirror the SDK `devices.json`/`compiler.json` values), and Fenix-8 firmware release notes. The device-memory CSV rows were read directly from raw GitHub to confirm exact byte values.

The headline finding is that memory is not a meaningful constraint for this app: the Fenix 8 **watch-app heap is 786,432 bytes (768 KB)** — roughly 6× the 128 KB data-field limit that the brief worried about. That is large enough to hold an entire compact word-stream chapter (a 5,000-word chapter ≈ 39 KB) many times over, and even an in-RAM buffer of tens of thousands of words is feasible, so the streaming architecture is a UX/sync choice rather than a memory necessity. Timing is comfortable too: the `Timer` minimum interval is 50 ms on all devices, while 700 WPM needs only ~85.7 ms between words (≈12 updates/sec) — well within reach via `WatchUi.requestUpdate()` driven by a single-shot/periodic timer. The principal *risk* is not compute or memory but the AMOLED display: a normal watch-app cannot legally hold the screen lit indefinitely (burn-in protection throws after ~1 minute of forced backlight), and apps launched from the glance/menu list are auto-terminated after a short idle. The viable mitigation is to structure the reader as an **activity-style app that starts an `ActivityRecording` session**, which is the supported way to keep the display active and prevent the app from timing out during a sustained, hands-off reading session. The remainder of this report details these numbers, the API surface behind them, and concrete recommendations.

---

## Technical Research Scope Confirmation

**Research Topic:** Garmin Fenix 8 watch-app constraints — memory, storage, CIQ API 6.x capabilities, AMOLED considerations
**Research Goals:** Pin down the memory budget per CIQ app type (from SDK `devices.json` and official sources), storage/persistence APIs and their limits, rendering/timer/input capabilities relevant to an RSVP reader, and AMOLED display constraints.

**Technical Research Scope:**

- Architecture Analysis - CIQ app types (app/widget/etc.) and their resource envelopes
- Implementation Approaches - memory management in Monkey C, persistence strategies
- Technology Stack - CIQ API 6.x modules: Graphics, Storage, Timer, Input, Attention
- Integration Patterns - Storage vs Application.Properties vs file-like persistence
- Performance Considerations - render loop at high WPM, AMOLED burn-in/always-on, battery

**Research Methodology:**

- Current web data with rigorous source verification
- Multi-source validation for critical technical claims
- Confidence level framework for uncertain information
- Comprehensive technical coverage with architecture-specific insights

**Scope Confirmed:** 2026-06-06

<!-- Content will be appended sequentially through research workflow steps -->

---

## Technology Stack Analysis

### Device profile: Fenix 8 (47mm AMOLED)

The Fenix 8 family is listed on Garmin's official Compatible Devices page at **Connect IQ API Level 6.0**, **454×454** resolution, **AMOLED** screen technology. The 47mm/51mm/43mm Fenix 8, plus tactix 8, quatix 8, Fenix E and Enduro 3 share this generation.
_Source: https://developer.garmin.com/connect-iq/compatible-devices/ (accessed 2026-06-06)_ — Confidence: High

Connect IQ "System 8" / CIQ 8 is the platform generation for the 2025 devices; the Fenix 8 ships on the System-7-class runtime with the AMOLED always-on improvements (luminance-controlled 10% pixel budget). For app development purposes, the device's declared API level is what `manifest.xml` targets — **6.0** for Fenix 8.
_Source: https://www.notebookcheck.net/Garmin-Connect-IQ-System-7-arrives-with-new-features.785586.0.html (accessed 2026-06-06)_ — Confidence: Medium
_Source: https://the5krunner.com/2025/01/07/connect-iq-8-what-we-know-so-far-about-system-8/ (accessed 2026-06-06)_ — Confidence: Low (forward-looking trade reporting)

### Per-app-type memory limits (the core verdict)

The SDK's per-device memory limits are stored in `compiler.json`/`simulator.json` inside the SDK and aggregated by the community in `flocsy/garmin-dev-tools`. The exact byte values for the Fenix 8 variants, read directly from the raw CSVs:

| App type | Fenix 8 limit (bytes) | = KB | Source CSV |
|---|---|---|---|
| **watch-app** | **786,432** | **768 KB** | `device2memory-watchApp.csv` |
| data field | 131,072 | 128 KB | `device2memory-datafield.csv` |
| glance | 65,536 | 64 KB | `device2memory-glance.csv` |
| background | 65,536 | 64 KB | `device2memory-background.csv` |
| widget | (empty / not defined) | — | `device2memory-widget.csv` |
| watch face | 131,072 (Fenix 7/8 class) | 128 KB | forum-reported |

Values verified identical across `fenix843mm`, `fenix847mm`, `fenix8pro47mm`, `fenix8solar47mm`, `fenix8solar51mm`.
_Source: https://github.com/flocsy/garmin-dev-tools/blob/main/csv/device2memory-watchApp.csv (raw read, accessed 2026-06-06)_ — Confidence: High
_Source: https://github.com/flocsy/garmin-dev-tools/blob/main/csv/device2memory-glance.csv (accessed 2026-06-06)_ — Confidence: High
_Source: https://github.com/flocsy/garmin-dev-tools/blob/main/csv/device2memory-background.csv (accessed 2026-06-06)_ — Confidence: High

Two facts worth flagging:

1. **The "scary" 128 KB number in the brief is the *data-field* limit, not the watch-app limit.** A full watch-app gets 768 KB — 6× more. The data-field limit on Fenix 8 was actually *reduced* from the Fenix 7's 256 KB, but deliberately, because the Fenix 8 now runs 4 simultaneous data fields sharing the budget rather than 2 (per Garmin's Kyle.ConnectIQ on the forums). This does not affect a standalone reader app.
   _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/382120/fenix-8-data-field (accessed 2026-06-06)_ — Confidence: High

2. The **widget** slot is empty for Fenix 8 — consistent with Garmin's move (CIQ 3.1+) away from standalone widgets toward the **glance + full-app** model. An RSVP reader should therefore not target the widget type at all.
   _Source: https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/connect-iq-3-1-now-available (accessed 2026-06-06)_ — Confidence: Medium

### Relevant CIQ 6.x modules

- **Toybox.Graphics** — `Dc` drawing context, `drawText`, built-in fonts (`FONT_XTINY`…`FONT_NUMBER_THAI_HOT`), `getTextWidthInPixels` for ORP pivot positioning. Custom fonts supported via BMFont-produced `.fnt`/`.png` placed in a `fonts` resource folder. On CIQ 4+ devices `loadResource` returns a `FontReference` (graphics-pool reference).
  _Source: https://developer.garmin.com/connect-iq/connect-iq-faq/how-do-i-use-custom-fonts/ (accessed 2026-06-06)_ — Confidence: High
- **Toybox.Timer** — periodic/one-shot timers, 50 ms minimum interval. _Source: forum, below._ — Confidence: High
- **Toybox.WatchUi** — `View`, `BehaviorDelegate`/`InputDelegate`, `requestUpdate()`. — Confidence: High
- **Toybox.Application.Storage** — key/value persistence (API ≥ 2.4.0). — Confidence: High
- **Toybox.Attention** — `backlight(true/false)`, vibrate/tone. — Confidence: High
- **Toybox.Background** — temporal background events for sync. — Confidence: High
- **Toybox.Communications** + **Toybox.BluetoothLowEnergy** — phone↔watch transport (BLE GATT or the Connect IQ message transport). — Confidence: High

---

## Integration Patterns Analysis (storage, persistence, background sync)

### Application.Storage — the right home for reading position

`Toybox.Application.Storage` is the modern persistent key/value store (replaces the legacy `App.getProperty/setProperty` object store). Key facts:

- **Per-value limit: 32 KB.** Storing a value larger than 32 KB fails.
- **Total object-store limit: device-specific, historically ~100 KB**; exceeding it throws `StorageFullException`. (The exact Fenix 8 total is not separately published; treat ~100 KB+ as the safe planning figure and rely on the much larger app heap for working data.)
- Supported value types include Number/Float/Long/Double/String/Boolean/Char, **ByteArray**, Array, Dictionary, and graphics/bitmap resources.
- Legacy `setProperty` object store is capped much lower (~8 KB total) — **do not use it** for anything but small config.
- The Fenix 8 still exposes "only 32 storage spaces" in the on-watch app-settings UI, but that is a Connect-IQ-settings-slots limit, unrelated to `Storage` key count.

_Source: https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html (accessed 2026-06-06)_ — Confidence: High (32 KB/value, StorageFullException)
_Source: https://forums.garmin.com/developer/connect-iq/f/discussion/167651/storage-querk (accessed 2026-06-06)_ — Confidence: Medium (~100 KB total)
_Source: https://forums.garmin.com/developer/connect-iq/f/discussion/4594/object-store-space-and-setproperty (accessed 2026-06-06)_ — Confidence: Medium (legacy ~8 KB)
_Source: https://forums.garmin.com/outdoor-recreation/outdoor-recreation/f/fenix-8-series/386658/still-only-32-storage-spaces (accessed 2026-06-06)_ — Confidence: Medium

**Implication for RSVP:** per-book reading position, WPM preference, and a small "last N words" rewind ring buffer are tiny (bytes to a few KB) and belong in `Storage`. Resume-state must survive app restart and watch reboot — `Storage` does this.

### PersistedContent is NOT a text cache

`Toybox.PersistedContent` only exposes FIT/GPX **courses, waypoints, workouts** saved on the device — it cannot store arbitrary book text. It is irrelevant to caching word-stream chunks.
_Source: https://developer.garmin.com/connect-iq/api-docs/Toybox/PersistedContent.html (accessed 2026-06-06)_ — Confidence: High

### Caching word-stream chunks — realistic numbers

Working estimates (avg English word ≈ 5 chars; compact word-stream entry incl. per-word timing ≈ 8 bytes):

| Unit | Words | Compact size (~8 B/word) |
|---|---|---|
| One 32 KB Storage value | 4,096 | 32 KB |
| Chapter (3k–5k words) | 3,000–5,000 | 23–39 KB |
| Whole novel | 90,000 | ~703 KB |
| 400 KB in-RAM buffer | ~51,200 | 400 KB |

_Source: derived calculation from word-count and per-entry size assumptions (accessed 2026-06-06)_ — Confidence: Medium (depends on chosen stream encoding)

Conclusions:
- **A whole chapter fits comfortably in RAM** and also in a single `Storage` value (a 5k-word chapter ≈ 39 KB exceeds one 32 KB value, so split into ≤4k-word chunks if persisting whole chapters).
- **A whole novel (~703 KB) technically *almost* fits the 768 KB heap**, but you must leave headroom for code, fonts, the framework, and BLE buffers — so do not try to hold a whole book in RAM. The streaming + small-window design in the brief is the right call, driven by prudence, not a hard limit.
- Practical buffer: hold a **few hundred to a few thousand words** in RAM (tens of KB), request more when the window drops below a threshold. This leaves the bulk of the 768 KB free.

### Background sync

`Toybox.Background.registerForTemporalEvent` runs sync when the app is closed, with two hard limits:
- **Minimum interval: 5 minutes** between temporal events (scheduling sooner throws).
- **Background heap: 32 KB** — very tight; only do minimal work (e.g., push the latest reading position, fetch a tiny manifest), not bulk word streaming.
- Only **one** temporal event registration is active at a time (re-registering overwrites).

_Source: https://developer.garmin.com/connect-iq/api-docs/Toybox/Background.html (accessed 2026-06-06)_ — Confidence: High

**Implication:** background is suitable for low-frequency position/library sync, NOT for streaming book content. Bulk transfer should happen in the foreground while the app is open and connected.

---

## Architectural Patterns Analysis (app type, lifecycle, render loop)

### App-type decision: full watch-app, structured as an activity app

| Option | Heap | Screen-on behaviour | Verdict |
|---|---|---|---|
| Watch face | 128 KB | Heavily restricted; once/min in low-power; timers/animation disabled in low power; AMOLED burn-in rules | ❌ wrong model entirely |
| Data field | 128 KB | Lives inside an activity; no free-form UI/input | ❌ |
| Glance | 64 KB | Tiny preview only | ❌ |
| Widget | (n/a on Fenix 8) | — | ❌ |
| **Watch-app** | **768 KB** | Full UI, buttons+touch, timers, `requestUpdate` | ✅ **chosen** |

Within "watch-app", the **launch context matters**:
- Apps launched from the **glance/app list time out** after a short idle and are terminated by the system (you must also run your own inactivity timer + `System.exit()`).
- Apps launched/registered as **activity apps (from the activity menu) do NOT time out** — the user must explicitly exit. This is the supported way to sustain a long, hands-off reading session.

_Source: https://forums.garmin.com/developer/connect-iq/f/discussion/314782/is-it-possible-to-refresh-the-screen-to-stay-on-longer (accessed 2026-06-06)_ — Confidence: High
_Source: https://forums.garmin.com/developer/connect-iq/f/discussion/283299/is-the-fenix-7-able-to-run-apps-while-recording-an-activity (accessed 2026-06-06)_ — Confidence: Medium

### Lifecycle / what survives backgrounding

- A watch-app is a foreground process; when the user leaves it, it is **suspended/terminated**, not kept running with the screen on in the background. There is no "keep running in background with UI" mode for general apps.
- Persisted state (`Storage`) survives; in-RAM buffers do not. Save reading position on pause, on `onStop()`, and periodically.
- **Known Fenix-8 quirk (from Epix 2 / Fenix 7 lineage):** if the user navigates to the watch-face/glance carousel from a running activity app, the activity is **stopped and the app state is lost** (session is saved as on a crash). Design for abrupt termination — persist position eagerly.
  _Source: https://forums.garmin.com/developer/connect-iq/i/bug-reports/bug-if-user-goes-to-watch-face-glance-carousel-from-activity-app-the-app-exits-session-is-saved-etc (accessed 2026-06-06)_ — Confidence: Medium

### Render-loop design for RSVP

Timing math (one word per tick):

| WPM | ms/word | updates/sec |
|---|---|---|
| 300 | 200 ms | 5.0 |
| 500 | 120 ms | 8.3 |
| 700 | 85.7 ms | 11.7 |

- **Timer minimum interval is 50 ms on all devices**, so even 700 WPM (85.7 ms) has comfortable margin; you could push past 1000 WPM (60 ms) before hitting the floor.
  _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/3834/fr230-minimum-supported-timer-interval (accessed 2026-06-06)_ — Confidence: High
- Pattern: a `Timer.Timer` fires at the current word's dwell interval → advance index → `WatchUi.requestUpdate()` → `View.onUpdate(dc)` draws the single word with the ORP pivot letter centred at a fixed x. Use **variable per-word timing** by re-arming a one-shot timer with each word's own dwell, rather than a fixed periodic timer.
- **`onPartialUpdate` is not available to AMOLED apps** the way it is on MIP — but RSVP doesn't need partial updates; it does full `onUpdate` redraws of a near-empty screen (one word), which is cheap. Drawing a single word per frame at ~12 fps is well within `Dc` performance even with a large custom font.
  _Source: https://developer.garmin.com/connect-iq/user-experience-guidelines/watch-faces/ (accessed 2026-06-06)_ — Confidence: High
- Pre-resolve/measure font glyph widths once (cache `getTextWidthInPixels` for ORP alignment) rather than per-frame, to keep each redraw trivial.

---

## Implementation Research (practical guidance, gotchas)

### Input mapping (Fenix 8 = 5 buttons + touch)

Use a `WatchUi.BehaviorDelegate` (or `InputDelegate`) and implement both physical and touch handlers:
- `onKey(KeyEvent)` → `KeyEvent.getKey()` returns `KEY_*` enums (`KEY_ENTER`/`KEY_START`, `KEY_UP`, `KEY_DOWN`, `KEY_ESC`, `KEY_MENU`, `KEY_LIGHT`).
- `onTap`, `onSwipe`, `onFlick`, `onHold` for touch.
- Garmin's guidance for dual input: implement `onTap()` and `onKey()` but **not** `onSelect()`, and treat `KEY_ENTER`/`KEY_START` as "select" inside `onKey`.

Suggested RSVP mapping: START/ENTER = play/pause; UP/DOWN = WPM ±; BACK/ESC short = rewind a few words (long = exit); touch tap = play/pause; swipe = rewind/skip. The LIGHT button is special on AMOLED (backlight) — avoid binding core actions to it.
_Source: https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/BehaviorDelegate.html (accessed 2026-06-06)_ — Confidence: High
_Source: https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/InputDelegate.html (accessed 2026-06-06)_ — Confidence: High
_Source: https://forums.garmin.com/developer/connect-iq/f/discussion/365554/supporting-both-physical-button-and-touch-input (accessed 2026-06-06)_ — Confidence: High

### AMOLED screen-on: the central gotcha

This is the single biggest implementation risk for a *reading* app on AMOLED:

- Apps **cannot programmatically change the system display timeout** ("look but don't touch").
- `Attention.backlight(true)` can force the backlight on, but **on devices with burn-in protection (all AMOLED Fenix 8), forcing the display on for too long (~1 minute) throws an exception**. So you cannot just hammer the backlight to keep a 30-minute reading session lit.
  _Source: https://forums.garmin.com/developer/connect-iq/i/bug-reports/allow-for-the-setting-of-backlight-mode-and-level (accessed 2026-06-06)_ — Confidence: Medium
- AMOLED always-on idle mode keeps only ~10% of pixels lit (luminance-budgeted in System 7) and **still times out to black** for burn-in protection.
  _Source: https://forums.garmin.com/outdoor-recreation/outdoor-recreation/f/fenix-8-series/385282/ (accessed 2026-06-06)_ — Confidence: Medium
- The robust pattern other long-running interactive/sport apps use: **start a `Toybox.ActivityRecording.Session`** so the watch treats the app as an active activity. Activity apps keep the display in the activity power state and **do not auto-time-out** (user must exit). This is the recommended path to a sustained reading session that stays visible. RSVP would start a lightweight session on "play" and stop it on "exit".
  _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/283299/is-the-fenix-7-able-to-run-apps-while-recording-an-activity (accessed 2026-06-06)_ — Confidence: Medium
  _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/314782/is-it-possible-to-refresh-the-screen-to-stay-on-longer (accessed 2026-06-06)_ — Confidence: Medium

Open verification item: confirm in the Fenix 8 simulator/on hardware that an active recording session genuinely suppresses the AMOLED timeout during continuous (non-touch) playback, and whether RSVP-style high-luminance single-word rendering (mostly dark screen, one bright word, pivot letter coloured) stays within the 10% always-on luminance budget if the screen does drop to AON. Burn-in mitigation tactics from watch-face guidance (thin fonts, shift pixels) may apply to any always-on rendering.

### Burn-in mitigation for RSVP content

Even in active mode, sustained single-position bright text risks uneven wear. Mitigations: small per-word horizontal jitter of the whole word block, alternate exact pixel positions over time, keep the screen mostly dark (RSVP already does this), avoid a persistent static progress bar in the same pixels.
_Source: https://developer.garmin.com/connect-iq/user-experience-guidelines/watch-faces/ (accessed 2026-06-06)_ — Confidence: Medium

### Battery

Sustained screen-on at high luminance plus an active recording session is the dominant battery draw; expect reading sessions to consume battery at roughly activity-tracking rates (display + CPU + BLE), far above idle. The ~12 fps redraw of one word is cheap CPU-wise; the **display and BLE** dominate. No precise mW figure is published for CIQ apps; treat battery as "activity-grade" during reading.
_Source: https://www.garmin.com/en-US/blog/developer/improve-your-app-performance/ (accessed 2026-06-06)_ — Confidence: Low (qualitative)

### Firmware stability note

Fenix 8 System Software **12.35** (Dec 2024) fixed "potential ConnectIQ application crash", "CIQ app ability to close with Palm Cover", and a CIQ watch-face display issue after reset. Target recent firmware and test on it; early Fenix 8 firmware had CIQ crash issues.
_Source: https://garminrumors.com/fenix-8-stable-software-12-35-released-fixes-connectiq-crashing-issues/ (accessed 2026-06-06)_ — Confidence: Medium

---

## Research Synthesis

### Executive Summary

The Fenix 8 is a comfortable target for an RSVP reader. The memory fear in the brief was based on the **data-field** limit (128 KB); the relevant number is the **watch-app heap of 768 KB**, which is ~6× larger and far more than this app needs. Timing is a non-issue — the 50 ms minimum timer interval leaves wide margin over the 85.7 ms/word needed at 700 WPM. Storage for reading position and preferences is trivially handled by `Application.Storage` (32 KB/value, ~100 KB total, survives reboot). The real engineering challenge is **not** compute, memory, or storage — it is the **AMOLED display lifecycle**: keeping the screen lit and the app alive through a long, hands-off reading session without tripping burn-in protection or the app-idle timeout. The recommended architecture is a full **watch-app launched/registered as an activity app that opens an `ActivityRecording` session** during playback, which is the supported mechanism for sustained screen-on and no auto-timeout.

### Key Findings

1. **Fenix 8 watch-app memory: 786,432 B (768 KB).** Data field 128 KB, glance 64 KB, background 64 KB, watch face 128 KB; widget not offered. _High confidence (raw SDK-derived CSV)._
2. **The brief's 128 KB worry = data-field limit, not watch-app.** A standalone reader gets 768 KB. _High._
3. **Application.Storage: 32 KB per value, ~100 KB total, `StorageFullException` on overflow.** Use it for position/prefs, not bulk text. Legacy `setProperty` (~8 KB) avoided. _High / Medium._
4. **PersistedContent cannot store book text** (FIT/GPX courses/waypoints/workouts only). _High._
5. **Timer minimum interval = 50 ms.** 700 WPM = 85.7 ms/word ≈ 12 redraws/sec — easily achievable; headroom to ~1000+ WPM. _High._
6. **Single-word full redraw via `requestUpdate` → `onUpdate(dc)` is cheap.** `onPartialUpdate` is unavailable on AMOLED but not needed. Custom bitmap fonts supported (BMFont). _High._
7. **Input:** `BehaviorDelegate` with both `onKey` (5 physical buttons, `KEY_*`) and `onTap`/`onSwipe`; treat ENTER/START as select; don't use `onSelect` when supporting both. _High._
8. **AMOLED screen-on is the key risk:** apps can't set display timeout; `Attention.backlight(true)` throws after ~1 min on burn-in-protected AMOLED; always-on idle is 10% luminance-budgeted and still times out to black. _Medium._
9. **Mitigation: run as an activity app with an `ActivityRecording` session** — these do not auto-time-out and keep the display in active state. _Medium._
10. **Background sync: 5-minute minimum interval, 32 KB background heap, one temporal event.** Good for position/library sync, not streaming. _High._
11. **Lifecycle gotcha:** navigating to watch-face/glance carousel from an activity app stops the activity and loses app state (Epix2/Fenix7 lineage). Persist position eagerly. _Medium._
12. **Firmware:** Fenix 8 12.35 fixed CIQ crashes; target/test recent firmware. _Medium._
13. **Whole-novel-in-RAM (~703 KB) nearly fits 768 KB but shouldn't be attempted** — streaming with a small window is the prudent design (chapter ≈ 23–39 KB; keep a few hundred–few thousand words buffered). _Medium._

### Recommendations for garmin_RSVP

1. **Build a full watch-app (Monkey C), not a widget/data-field/watch-face.** Target API 6.0, manifest device `fenix8` family.
2. **Register it as an activity app and open a lightweight `ActivityRecording.Session` on play**, stop on exit — this is the path to sustained screen-on and no idle timeout. Verify this on hardware/sim early; it is the project's #1 technical unknown.
3. **Memory is not a constraint** — stop sizing the design around 128 KB. Keep a streaming window of a few hundred–few thousand words; the 768 KB heap leaves ample room for fonts, BLE buffers, and code.
4. **Persist reading position to `Application.Storage` eagerly** (on pause, on `onStop`, periodically, and on each chunk boundary) keyed per book. Assume abrupt termination. Keep each value < 32 KB.
5. **Drive playback with a one-shot timer re-armed per word** (variable dwell), not a fixed periodic timer — this is how the brief's variable timing is implemented; well above the 50 ms floor at all target WPMs.
6. **Use a custom bitmap font (BMFont)** sized for the 454×454 screen; precompute glyph widths for ORP pivot alignment; redraw only the single word per frame.
7. **Input:** START/ENTER=play-pause, UP/DOWN=WPM±, BACK short=rewind / long=exit, plus touch tap/swipe mirrors. Avoid the LIGHT button for core actions.
8. **Add burn-in jitter** (small per-word position shifts) even though the screen is mostly dark, and avoid static on-screen elements in fixed pixels.
9. **Use `Background` only for low-frequency sync** (position/manifest), respecting the 5-min/32 KB limits; do all bulk word streaming in the foreground over BLE.
10. **Test on Fenix 8 firmware ≥ 12.35** and in the CIQ 6.x simulator's burn-in/AON modes.

### Risks and Open Questions

- **[HIGH] Sustained AMOLED screen-on during hands-off reading.** Does an active `ActivityRecording` session reliably keep the Fenix 8 display lit for a full reading session, or does AON/burn-in still force black? Must be validated on hardware. If not, RSVP playback may require periodic user touch or accept the screen dropping to AON. _Medium confidence in the mitigation; needs empirical confirmation._
- **[MED] Exact total Object Store size on Fenix 8** is not separately published (~100 KB assumed). Low impact since position data is tiny, but confirm if caching multiple chapters in `Storage`.
- **[MED] 10% luminance budget vs RSVP rendering** if the screen drops to always-on: a single bright word + coloured pivot may or may not fit the budget; may render dim/black in AON.
- **[MED] Activity-app state loss** on carousel navigation — mitigated by eager persistence but is a real UX wrinkle.
- **[LOW] Battery cost** of activity-grade screen-on + BLE during long sessions is not precisely quantified.
- **[LOW] BLE throughput** for uninterrupted high-WPM streaming is out of scope of this device-constraints report (covered by the BLE/Communications research track) but interacts with buffer sizing.

### Source Documentation

Accessed 2026-06-06.

- https://developer.garmin.com/connect-iq/compatible-devices/ — Fenix 8 API 6.0, 454×454, AMOLED — High
- https://github.com/flocsy/garmin-dev-tools/blob/main/csv/device2memory-watchApp.csv — watch-app 786,432 B — High
- https://github.com/flocsy/garmin-dev-tools/blob/main/csv/device2memory-datafield.csv — data field 131,072 B — High
- https://github.com/flocsy/garmin-dev-tools/blob/main/csv/device2memory-glance.csv — glance 65,536 B — High
- https://github.com/flocsy/garmin-dev-tools/blob/main/csv/device2memory-background.csv — background 65,536 B — High
- https://github.com/flocsy/garmin-dev-tools/blob/main/csv/device2memory-widget.csv — widget undefined for Fenix 8 — High
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html — 32 KB/value, StorageFullException, types, API 2.4.0 — High
- https://developer.garmin.com/connect-iq/api-docs/Toybox/PersistedContent.html — FIT/GPX only — High
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Background.html — 5-min min, 32 KB heap — High
- https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/BehaviorDelegate.html — onKey/onTap — High
- https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/InputDelegate.html — touch events — High
- https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/KeyEvent.html — KEY_* enums — High
- https://developer.garmin.com/connect-iq/connect-iq-faq/how-do-i-use-custom-fonts/ — BMFont custom fonts — High
- https://developer.garmin.com/connect-iq/user-experience-guidelines/watch-faces/ — AMOLED burn-in / onPartialUpdate not on AMOLED — High
- https://developer.garmin.com/connect-iq/api-docs/Toybox/Attention.html — backlight API — Medium
- https://forums.garmin.com/developer/connect-iq/f/discussion/3834/fr230-minimum-supported-timer-interval — 50 ms timer min — High
- https://forums.garmin.com/developer/connect-iq/f/discussion/382120/fenix-8-data-field — 128 KB data field rationale (Garmin Kyle.ConnectIQ) — High
- https://forums.garmin.com/developer/connect-iq/f/discussion/314782/is-it-possible-to-refresh-the-screen-to-stay-on-longer — screen-on, backlight exception — Medium
- https://forums.garmin.com/developer/connect-iq/f/discussion/283299/is-the-fenix-7-able-to-run-apps-while-recording-an-activity — activity session + app behaviour — Medium
- https://forums.garmin.com/developer/connect-iq/f/discussion/365554/supporting-both-physical-button-and-touch-input — dual input pattern — High
- https://forums.garmin.com/developer/connect-iq/i/bug-reports/bug-if-user-goes-to-watch-face-glance-carousel-from-activity-app-the-app-exits-session-is-saved-etc — activity-app state loss — Medium
- https://forums.garmin.com/developer/connect-iq/f/discussion/418612/device-memory-limits — how to find limits; modern devices 128–256 KB — High
- https://forums.garmin.com/developer/connect-iq/f/discussion/167651/storage-querk — ~100 KB object store — Medium
- https://forums.garmin.com/developer/connect-iq/f/discussion/4594/object-store-space-and-setproperty — legacy ~8 KB — Medium
- https://forums.garmin.com/outdoor-recreation/outdoor-recreation/f/fenix-8-series/386658/still-only-32-storage-spaces — 32 settings slots (unrelated to Storage keys) — Medium
- https://forums.garmin.com/outdoor-recreation/outdoor-recreation/f/fenix-8-series/385282/ — AON black-screen / burn-in timeout — Medium
- https://garminrumors.com/fenix-8-stable-software-12-35-released-fixes-connectiq-crashing-issues/ — 12.35 CIQ crash fixes — Medium
- https://support.garmin.com/en-US/?faq=tFmJJnTfs83yuPc8kttAh7 — CIQ app limits overview — Medium
- https://www.garmin.com/en-US/blog/developer/improve-your-app-performance/ — performance guidance — Low
- https://www.notebookcheck.net/Garmin-Connect-IQ-System-7-arrives-with-new-features.785586.0.html — System 7 AON 10% luminance — Medium
- https://the5krunner.com/2025/01/07/connect-iq-8-what-we-know-so-far-about-system-8/ — CIQ 8 forward-looking — Low

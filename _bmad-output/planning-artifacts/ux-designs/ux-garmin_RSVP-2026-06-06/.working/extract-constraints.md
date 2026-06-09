# UX Constraint Extraction — Garmin Fenix 8 RSVP Reader

Sources:
- `research/technical-fenix-8-watch-app-constraints-research-2026-06-06.md`
- `research/technical-connect-iq-phone-watch-communication-research-2026-06-06.md`
- `architecture.md`

Confidence tags carried from sources: High / Medium / Low. Where a number is undocumented or platform-variable, it is marked.

---

## 1. Display

| Property | Value | Confidence |
|---|---|---|
| Device | Garmin Fenix 8, 47mm AMOLED (43/47/51mm family share specs) | High |
| Resolution | **454 × 454 px** | High |
| Shape | **Round** | High |
| Screen tech | **AMOLED** (NOT MIP — this is the central UX risk driver) | High |
| Connect IQ API level | **6.0** | High |
| Firmware floor | **≥ 12.35** (Dec 2024; fixed CIQ crashes) | Medium |

Always-on / burn-in behavior (UX-critical):
- **A normal watch-app CANNOT hold the screen lit indefinitely.** `Attention.backlight(true)` throws an exception after **~1 minute** of forced backlight on burn-in-protected AMOLED. You cannot hammer the backlight to keep a 30–60 min reading session visible. (Medium)
- **Apps cannot programmatically change the system display timeout.** (Medium)
- Always-on (AON) idle mode keeps only **~10% of pixels lit** (luminance-budgeted, System 7) and **still times out to black** for burn-in protection. (Medium)
- The supported workaround: run as an **activity app that opens an `ActivityRecording.Session`** during playback — activity apps keep the display in active power state and do NOT auto-time-out (user must explicitly exit). This is the project's #1 unvalidated technical risk (gate V1). (Medium)
- **Open risk (V1):** whether an active recording session reliably keeps the Fenix 8 lit for a full hands-off session is NOT confirmed on hardware. Fallback may be a dim-AON view or periodic-touch requirement, and AON legibility of a single bright word + colored pivot is itself unvalidated against the 10% luminance budget.
- **Burn-in mitigation for RSVP rendering (Medium):** apply small per-word horizontal jitter to the whole word block; alternate exact pixel positions over time; keep the screen mostly dark (RSVP already does); avoid persistent static elements (e.g., a fixed progress bar in the same pixels). UX must NOT place any static element in fixed pixels for a long session.

Color depth: not stated numerically in sources; AMOLED full color is implied (colored ORP pivot letter is assumed feasible in active mode; uncertain in AON).

---

## 2. Input

Fenix 8 = **5 physical buttons + touchscreen**.

Buttons (CIQ `KEY_*` enums, handled via `BehaviorDelegate.onKey(KeyEvent)`):
- `KEY_ENTER` / `KEY_START` — the START button (top-right); platform "select" / start-stop semantics
- `KEY_UP` (top-left)
- `KEY_DOWN` (bottom-left)
- `KEY_ESC` — the BACK button (bottom-right); platform back / lap semantics
- `KEY_MENU` (long-press UP, conventionally)
- `KEY_LIGHT` — the LIGHT button (top-left-ish on Fenix); **special on AMOLED (backlight) — do NOT bind core actions to it.** (High)

Touch (handled via `BehaviorDelegate` / `InputDelegate`): `onTap`, `onSwipe`, `onFlick`, `onHold`.

Garmin platform conventions / dual-input rule (High):
- Implement BOTH `onTap()` and `onKey()`, but **NOT `onSelect()`** — treat `KEY_ENTER`/`KEY_START` as "select" inside `onKey`.
- START/ENTER = start/stop/select; BACK/ESC = back/cancel (short) and exit (held); START is the conventional "primary action" button.

Recommended RSVP mapping (from research, NOT final — UX-revisable per architecture):
- START/ENTER = play/pause
- UP/DOWN = WPM ± (instant change)
- BACK/ESC short = rewind a few words / a sentence; BACK held (long) = exit
- Touch tap = play/pause (mirror); swipe = rewind/skip (mirror)
- LIGHT button avoided for core actions.

No rotating crown on Fenix 8 (button-and-touch device). Architecture fixes input mapping intent in `input/PlaybackDelegate.mc` (START=play/pause, UP/DOWN=WPM, BACK=rewind) but flags views/input as UX-revisable.

---

## 3. Fonts & Rendering

- Module: `Toybox.Graphics` — `Dc` drawing context, `drawText`, `getTextWidthInPixels` (for ORP pivot alignment).
- Built-in fonts: `FONT_XTINY` … up through large/number fonts. (High)
- **Custom fonts supported** via BMFont-produced `.fnt`/`.png` placed in a `fonts/` resource folder. On CIQ 4+ devices `loadResource` returns a `FontReference` (graphics-pool reference). Architecture commits to a **custom bitmap font (BMFont)** sized for the 454×454 screen, with **precomputed glyph widths** for ORP pivot alignment. (High)
- **Timer minimum interval = 50 ms on all devices** (the hard rendering-rate floor). (High)
- **Max usable word flash rate:** 50 ms floor → ~20 words/sec ceiling ≈ **up to ~1000+ WPM** before hitting the floor. RSVP targets are comfortably inside this:

| WPM | ms/word | updates/sec |
|---|---|---|
| 300 | 200 ms | 5.0 |
| 500 | 120 ms | 8.3 |
| 700 | 85.7 ms | 11.7 |
| ~1000 | ~60 ms | ~16.7 |

- Render pattern: a one-shot `Timer` re-armed per word with that word's own dwell (variable timing) → advance index → `WatchUi.requestUpdate()` → `View.onUpdate(dc)` draws the single word with the ORP pivot letter at a fixed x. (High)
- **Single-word full redraw is cheap** — screen is near-empty (one word). Drawing one word at ~12 fps is well within `Dc` performance even with a large custom font. (High)
- **`onPartialUpdate` is NOT available on AMOLED** (it is a MIP feature) — but RSVP does not need it (full redraws of a near-empty screen). (High)
- Performance discipline: pre-measure/cache glyph widths once (not per-frame); architecture forbids per-word `System.println` (logging budget ~10 KB, would tank the loop). Word advancement happens only in timer callbacks; `onUpdate` only draws the already-selected word. (High)
- Timing fidelity model (NFR1): drift-free `lastAdvance += duration` advance with capped catch-up — solid at 700 WPM, headroom to 1000. Watch never computes dwell from text; **all timing/pivot metadata is baked upstream by the phone** (UTF-8 byte-index pivot precomputed phone-side; watch never recomputes).

---

## 4. Memory / CPU Budgets

Per-app-type heap limits on Fenix 8 (SDK-derived, High):

| App type | Heap |
|---|---|
| **watch-app** | **786,432 B (768 KB)** ← chosen type |
| data field | 131,072 B (128 KB) |
| glance | 65,536 B (64 KB) |
| background | 65,536 B (64 KB) |
| watch face | 131,072 B (128 KB) |
| widget | not offered on Fenix 8 |

- **The brief's "128 KB" fear was the data-field limit, NOT the watch-app limit.** A full watch-app gets **768 KB — 6× more**. Memory is effectively a non-constraint for this app. (High)
- Architecture targets **≤600 KB peak heap of the 768 KB** (NFR2), leaving headroom for code, fonts, framework, BLE buffers.
- CPU: single-word redraw at ~12 fps is trivial; display + BLE dominate cost, not compute.

Content-size implications (word ≈ 5 chars; compact word-stream entry ≈ 8–16 B incl. timing/pivot):
- Chapter (3k–5k words) ≈ 23–39 KB.
- Whole novel (~90k words) ≈ ~703 KB — *almost* fits 768 KB heap but **must NOT be held whole in RAM** (no headroom). Streaming/windowed design is mandated by prudence.
- Practical heap working set: a few hundred to a few thousand words buffered (tens of KB).

GC note: reference-counting GC with **no cycle collection** → WeakReference discipline (views never strong-ref back to engine). Affects component design, not visible UX.

---

## 5. Connect IQ App Types & Lifecycle / Interruption

App type decision (architecture, locked): **full watch-app (Monkey C), launched/registered as an activity app**, NOT widget / data field / watch face / glance. (High)

Lifecycle behavior UX must design around:
- Apps launched from the **glance/app list time out** after short idle and are terminated by the system. Apps run as **activity apps do NOT time out** — only explicit exit. (chosen path) (High/Medium)
- A watch-app is a foreground process: when the user leaves it, it is **suspended/terminated**, NOT kept running with screen on in background. There is no "keep running with UI in background" mode. (High)
- In-RAM buffers do NOT survive backgrounding; **persisted `Storage` state does**. Save reading position on pause, on `onStop()`, and periodically.
- **Carousel-navigation kill path (UX-significant, Medium):** if the user navigates to the watch-face / glance carousel from a running activity app, **the activity is stopped and app state is lost** (saved as on a crash). Abrupt termination is a NORMAL lifecycle event — UX cannot assume a clean exit, and resume must be seamless.
- Notifications/alarms: standard system interruptions can suspend/interrupt the foreground app; combined with the carousel kill path, this reinforces eager persistence.

Architecture treats abrupt termination as "on the happy path" → eager persistence: position committed via `SyncManager.commitPosition(force)` — debounced ~15 s while playing, forced on pause/exit/rewind/chunk-boundary/disconnect/`onStop`.

Background service (for sync only): **5-min minimum interval, 32 KB background heap, one temporal event at a time.** Good for low-frequency position/library sync; **NOT for streaming content.** (High)

---

## 6. Phone ↔ Watch Communication

On-watch API: `Toybox.Communications` — `transmit()` (watch→phone), `registerForPhoneAppMessages()` (phone→watch), `makeWebRequest()` (BLE-proxied via Garmin Connect Mobile). Managed API only — `Raw.sendMessage()` is broken/forbidden. (High)

Performance envelope (the numbers that size UX expectations):

| Metric | Value | Confidence |
|---|---|---|
| Effective throughput | **< 1 KB/s** | Medium |
| Round-trip latency (small msg) | **~1–2 seconds** (~75% is BLE protocol, not controllable) | Medium |
| Max concurrent outstanding transfers | **3** (architecture uses ≤2 to stay safe) | Medium |
| Per-message size cap | **Undocumented / device-dependent**; `BLE_REQUEST_TOO_LARGE` (-102) on overflow; start ≤1 KB / ~20–40 words and calibrate (gate V3) | Low–Medium |
| `makeWebRequest` response cap | ~32 KB (Fenix 7 Pro/Android), ~44 KB (Epix 2 Pro) — undocumented, device-dependent | Medium |

The decisive fact: **RSVP demand at 700 WPM is only ~120–190 B/s** — one to two orders of magnitude below the slow channel. **Bandwidth is NOT the constraint; latency, reliability, and buffering are.**

Reliability issues UX must tolerate (Medium):
- **Android `sendMessage` "works once then stops"** — first transfer succeeds, subsequent ones silently fail (listener never fires). Major risk to continuous streaming; mitigated by timeout + SDK re-init + resend, and/or bulk pre-load. (gate V2)
- BLE ATT MTU truncation bug (~20 bytes) — cautionary, mostly abstracted by CIQ message APIs.
- `BLE_CONNECTION_UNAVAILABLE` (-104) on phone disconnect.

Resilience properties that ENABLE good UX:
- **Mailbox persistence:** phone→watch messages persist if the watch app is closed, delivered on next open. Enables resilient resume/position sync. (High)
- Transfers can work mid-session, but transfer is architecturally **never on playback's critical path** — playback reads only from the local resident buffer. An empty buffer is a designed failure state (`Buffering`), not a normal one.

Pairing / connection UX implications:
- **Garmin Connect Mobile (GCM) must be installed and the watch paired through it** — a hard prerequisite on both platforms (required for discovery + app install; on iOS messaging is direct BLE, on Android the dependency is tighter). UX onboarding must account for GCM as a precondition. (High/Medium)
- iOS companion backgrounded → degraded BLE priority (slower transfers). Android-first for MVP.
- Recommended transfer topology: **watch-pull with deep look-ahead buffer** (200–600 words ≈ 17–50 s at 700 WPM); fetch at low-water mark with ≥10 s runway. **Bulk per-chapter pre-load is a strong MVP alternative** that eliminates mid-playback round trips entirely (best fit for "finish a real book uninterrupted").

---

## 7. Battery Implications

- Sustained screen-on at high luminance + an active `ActivityRecording` session is the **dominant battery draw** — expect reading sessions to consume battery at roughly **activity-tracking rates** (display + CPU + BLE), far above idle/watch-face. (Low confidence — qualitative; no precise mW published)
- The ~12 fps single-word redraw is cheap; **display and BLE dominate**, not CPU.
- UX implication: long reading sessions are "activity-grade" battery events. Consider surfacing/managing session length expectations; do not assume all-day-watch-face battery economics. AMOLED brightness directly affects both burn-in risk and battery.

---

## 8. Architecture Decisions That Pre-empt / Fix UX Choices

These are decided and constrain UX; UX revises only the explicitly-open surfaces.

Locked (UX must design within):
- **App type:** full watch-app run as an **activity app** with `ActivityRecording.Session` for screen-on (DisplayStrategy seam; gate V1 may swap to dim-AON fallback). (`display/DisplayStrategy.mc`, `ActivitySessionStrategy.mc`)
- **Sync model / position:** **absolute word index, 0-based integer, is the single universal position coordinate** everywhere (render, rewind, persistence, sync, transfer addressing, progress display). Never chapter+offset pairs in APIs/storage. LWW reconciliation, watch-wins tiebreak. Resume "never lies" (NFR4): never overshoot, trail ≤ one persistence interval.
- **Content format on watch:** binary word-stream records; per-word metadata = `{text, dwellMs (int), orpIndex (UTF-8 byte index)}` + flag bits (`sentenceEnd`, `paragraphStart`, `chapterStart`, reserved `continuation`/`direction`). Defined once in `protocol/SPEC.md`. UTF-8 everywhere. Script-agnostic (NFR7) — no Latin assumptions; direction bits reserved.
- **All linguistic intelligence is upstream (phone).** Watch does NOT compute pivots, dwell, or sentence boundaries — it consumes baked metadata. So pause-coasting-to-sentence-end, sentence rewind, and pacing all depend on phone-segmenter flags.
- **Content residency:** current + next chapter persist to `Storage` in ≤32 KB buckets, hard-capped ~80 KB of ~100 KB total store; heap holds only the decoded reading window + render state. Enables phone-free reading (FR19) and ≤3 s cold open (NFR5).
- **Settings ownership:** WPM preference + reading position persist in watch `Application.Storage` (`pos_<bookId>`, `settings`, `meta_<bookId>` keys). The companion (Flutter) owns library/import/conversion and durable position store (drift DB); positions sync both ways. WPM is changed on-watch (UP/DOWN) instantly.
- **Transfer:** pull-based, chapter-granular, offset-addressed, idempotent; ≤2 in-flight; transfer never blocks playback.
- **Performance contracts:** ≤3 s open-to-first-word (NFR5); ≤60 min hands-off display (FR4, gate-conditional on V1); drift-free timing to 700 WPM, headroom to 1000 (NFR1).

Named UX states the design MUST provide (error/lifecycle posture, NFR8 — never crash, always a named state):
- Watch: `WaitingForPhone`, `Buffering`, `BookChanged` ("book changed — refreshing"), `StorageFull`, `Finished` (explicit end state, FR5).
- Companion: typed import/transfer failures, each with a user-facing message + actionable next step (FR26).

Explicitly UX-revisable (open for the UX phase — the engine/service seams are fixed, the visuals/flows are not):
- Watch views: `PlaybackView` (ORP render, suggested anchor ~35%, burn-in jitter), `PausedContextView` (context-on-pause), `ChapterCardView` (chapter-transition card), `StatusViews` (Finished / WaitingForPhone / Buffering / empty).
- Watch input mapping details (`PlaybackDelegate`, `PausedDelegate`).
- Companion screens: library (list + live progress + last-read), import (picker / share-sheet, progress, errors), transfer (send-to-watch + delivery progress), settings.
- Two-stage pause coasting to sentence end and context-on-pause are specified behaviors but their presentation is open (FR11/FR6 are demote-able under the PRD cut line).

---

## Quick reference: the constraints that most shape UX

1. **AMOLED can't stay lit naively** — screen-on for a long hands-off read depends on an unvalidated activity-session trick; plan for an AON/dim or touch-to-wake fallback, and never put static elements in fixed pixels (burn-in).
2. **Round screen, 454×454, 5 buttons + touch** — single-word ORP layout on a circle; button-first with touch mirrors; LIGHT button off-limits; no crown.
3. **Abrupt termination is normal** (carousel kill, suspension) — resume must be seamless and instant; no reliance on graceful exit.
4. **Slow, flaky, 1–2 s BLE** with the Android first-send bug — every network-dependent moment needs a visible named state; playback must never wait on BLE (deep buffer or pre-load).
5. **GCM is a hard pairing prerequisite** and reading is an activity-grade battery event — both must be set up-front in onboarding/expectations.

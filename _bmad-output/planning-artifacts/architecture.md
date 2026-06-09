---
stepsCompleted: [1, 2, 3, 4, 5, 6, 7, 8]
lastStep: 8
status: 'complete'
completedAt: '2026-06-06'
inputDocuments:
  - '_bmad-output/planning-artifacts/prds/prd-garmin_RSVP-2026-06-06/prd.md'
  - '_bmad-output/planning-artifacts/prds/prd-garmin_RSVP-2026-06-06/addendum.md'
  - '_bmad-output/planning-artifacts/prds/prd-garmin_RSVP-2026-06-06/reconcile-brief.md'
  - '_bmad-output/planning-artifacts/prds/prd-garmin_RSVP-2026-06-06/reconcile-ciq-comms.md'
  - '_bmad-output/planning-artifacts/prds/prd-garmin_RSVP-2026-06-06/reconcile-epub-parsing.md'
  - '_bmad-output/planning-artifacts/prds/prd-garmin_RSVP-2026-06-06/reconcile-fenix8-constraints.md'
  - '_bmad-output/planning-artifacts/prds/prd-garmin_RSVP-2026-06-06/reconcile-monkeyc.md'
  - '_bmad-output/planning-artifacts/prds/prd-garmin_RSVP-2026-06-06/reconcile-nano-teardown.md'
  - '_bmad-output/planning-artifacts/prds/prd-garmin_RSVP-2026-06-06/review-adversarial.md'
  - '_bmad-output/planning-artifacts/prds/prd-garmin_RSVP-2026-06-06/review-rubric.md'
  - '_bmad-output/planning-artifacts/briefs/brief-garmin_RSVP-2026-06-05/brief.md'
  - 'rsvp-garmin-idea-brief.md'
  - '_bmad-output/planning-artifacts/research/technical-connect-iq-phone-watch-communication-research-2026-06-06.md'
  - '_bmad-output/planning-artifacts/research/technical-fenix-8-watch-app-constraints-research-2026-06-06.md'
  - '_bmad-output/planning-artifacts/research/technical-monkey-c-development-landscape-research-2026-06-06.md'
  - '_bmad-output/planning-artifacts/research/technical-epub-parsing-flutter-dart-research-2026-06-06.md'
  - '_bmad-output/planning-artifacts/research/technical-rsvpnano-reader-teardown-research-2026-06-06.md'
  - '_bmad-output/planning-artifacts/ux-designs/ux-garmin_RSVP-2026-06-06/DESIGN.md'
  - '_bmad-output/planning-artifacts/ux-designs/ux-garmin_RSVP-2026-06-06/EXPERIENCE.md'
workflowType: 'architecture'
project_name: 'garmin_RSVP'
user_name: 'Nerya'
date: '2026-06-06'
notes: 'UX spec reconciled 2026-06-06 (see UX Reconciliation Addendum): LWW retained over max-index; Android foreground service for transfers; six additive changes folded in. Watch input map stays provisional until first hardware test.'
---

# Architecture Decision Document

_This document builds collaboratively through step-by-step discovery. Sections are appended as we work through each architectural decision together._

## Project Context Analysis

### Requirements Overview

**Functional Requirements:**

28 FRs in six clusters, with sharply uneven architectural weight:

- **A. RSVP Playback (FR1–7)** — the watch-side render engine: ORP-anchored single-word display, stream-supplied variable timing, instant WPM changes, ≥60-min hands-off display, explicit end state, chapter-transition card, long-word handling. Architecturally: a drift-free one-shot-timer render loop reading exclusively from a local buffer; *all linguistic intelligence is upstream on the phone*. FR4 (hands-off display) is conditional on unresolved risk R1 — its architecture must be isolatable until gate V1 passes.
- **B. Reading Controls (FR8–12)** — button-first input with touch mirrors, two-stage pause coasting to sentence end, sentence rewind, context-on-pause. Architecturally: depends on *sentence-end flags baked into the stream by the phone segmenter* — control correctness is a parsing-pipeline obligation, not a watch feature. FR11 and FR6 are designated demote-able under the PRD's cut line.
- **C. Resume & Position Sync (FR13–16)** — the system invariant. Absolute word index as universal coordinate; eager persistence (debounced ~15 s while playing, forced on every transition); timestamped last-writer-wins reconciliation with watch-wins tiebreak inside the skew window. Architecturally a small two-device replication problem; the carousel-navigation kill path makes abrupt termination a *normal* lifecycle event to design for.
- **D. Book Delivery (FR17–21)** — pull-based, chapter-granular, offset-addressed, idempotent transfer keyed to a per-conversion content fingerprint. Designed around documented platform failures (Android first-send bug, -102 size ceiling, 3-transfer cap). Transfer is never on playback's critical path. This cluster + the stream format is the documented-protocol deliverable (FR28).
- **E. Companion Library (FR22–26)** — Flutter app: EPUB/.txt/.md import, isolate-based parse pipeline (structure via epub_pro, DIY DOM-pre-filtered text extraction, Unicode sanitation, RSVP-Nano-derived pacing baked as WPM-invariant bonuses), library list, send-to-watch, survivable import failures.
- **F. Openness (FR27–28)** — CIQ Store + MIT GitHub release; protocol documented to third-party-implementable standard. Release machinery (developer key, Garmin verification, beta channel, ERA crash monitoring) is a build-pipeline concern from day one, not an afterthought.

**Non-Functional Requirements:**

- **NFR1 (timing fidelity):** drift-free over a full session; solid at 700 WPM, headroom to 1000 — drives the `lastAdvance += duration` advance model with capped catch-up.
- **NFR2/NFR3 (memory/storage ceilings):** ≤600 KB peak heap of 768 KB; 32 KB/value & ~100 KB total Storage — drives chapter-resident buffering, ≤4k-word storage buckets, and an unresolved budget question (two-chapter residency vs ~100 KB total Storage) flagged below.
- **NFR4 (position durability):** never overshoot, trail ≤ one persistence interval — the precise form of "resume never lies."
- **NFR5 (responsiveness):** ≤3 s open-to-first-word; ≤30 s non-blocking import of a 100k-word novel.
- **NFR6 (compatibility):** Fenix 8 / CIQ 6.0 / firmware ≥12.35; Android-first Flutter; GCM prerequisite.
- **NFR7 (script-agnostic stream):** per-word pivot/dwell metadata, direction bits reserved — format must not encode Latin assumptions.
- **NFR8 (crash posture):** bounds-check and degrade, never crash mid-read — a coding standard for every data-ingesting boundary on both devices.

**Scale & Complexity:**

- Primary domain: wearable embedded app (Monkey C/CIQ) + mobile companion (Flutter/Android) + custom device-to-device protocol
- Complexity level: **medium** — small feature surface; complexity concentrated in embedded constraints, two-device state correctness, and a new language for the developer (solo, R5)
- Estimated architectural components: ~9–11 (watch: render loop, chunked word source, input, persistence/sync, session/display manager; phone: import/parse pipeline, stream store, transfer engine, position sync, library UI; shared: protocol + stream format spec)

### Technical Constraints & Dependencies

- **Platform ceilings (verified):** 768 KB watch-app heap; 32 KB/value & ~100 KB total Storage; 50 ms timer floor; background service 5-min/32 KB; no `PersistedContent` for text; `onUpdate` watchdog; reference-counting GC with no cycle collection (WeakReference discipline).
- **BLE channel:** <1 KB/s effective, 1–2 s round trips, ≤3 concurrent transfers, undocumented per-message cap (start ≤1 KB, calibrate — gate V3), Android first-send reliability bug (gate V2), managed Communications API only (`Raw.sendMessage` broken), mailbox persistence available for sync recovery.
- **Display lifecycle:** AMOLED burn-in protection forbids naive screen-on (~1-min backlight exception); ActivityRecording-session strategy is medium-confidence (gate V1); dim-AON fallback legibility itself unvalidated; carousel navigation kills activity apps with state loss.
- **Toolchain:** CIQ SDK 9.1.0, Monkey C Strict typing from commit 1, markw65 optimizer, BMFont custom font, `matco/action-connectiq-tester` CI, 4096-bit RSA developer key + Garmin developer verification as release preconditions.
- **Companion stack (decided in PRD addendum):** Flutter/Dart; `watch_connectivity_garmin` v0.1.12 bridge to start (fork/custom MethodChannel fallback — OQ2 resolves during V2); epub_pro + DIY `html` extraction; drift/sqflite for metadata/positions, flat files for streams; parse in isolates.
- **Dependencies on external parties:** Garmin Connect Mobile installed and paired; Garmin store verification/review for the "Published" goal.
- **Sequencing constraint (from PRD §7 + adversarial review C1):** playback and transfer architecture must remain *gate-conditional* — V1 (screen-on + AON-fallback legibility) and V2 (multi-send reliability) pass on hardware before those designs harden or their epics are story-split. Companion pipeline, stream format, and protocol-on-paper may proceed in parallel.

### Cross-Cutting Concerns Identified

1. **Absolute word index** — the universal coordinate spanning render, rewind, persistence, sync, transfer addressing, and progress display on both devices.
2. **Content fingerprint** — every chunk, request, and position record is keyed to a conversion fingerprint; stale-vs-new must never blend (FR20/NFR4).
3. **Sentence-end & structure flags** — produced once by the phone segmenter (abbreviation-aware), consumed by pause coasting, rewind, chunk-boundary alignment, and pacing. Flag quality is a cross-device correctness dependency.
4. **Eager persistence discipline** — debounce-while-playing + force-on-every-transition, on both devices, because abrupt termination is on the happy path.
5. **Bounds-check-and-degrade posture (NFR8)** — every boundary that ingests bytes (BLE chunks, EPUB files, Storage reads) on both devices.
6. **Gate-conditional architecture** — V1/V2 outcomes can rework the display strategy or transfer mechanics; affected components need explicit seams so a gate failure replaces a module, not the architecture.
7. **Protocol as public contract** — FR28 makes the phone↔watch protocol a documented, versioned, third-party-implementable artifact; it must be designed (and versioned) as such from the start.
8. **UX-revisable surfaces (reconciled 2026-06-06)** — Sally's UX spec (DESIGN.md + EXPERIENCE.md) now specifies screen composition and flows on both apps; the seams held as designed and absorbed the spec without structural rework. Residual revisability: the watch input map is provisional until the first on-hardware test — the input *principles* (BACK sacred, buttons-always-work, touch opt-in mirror) are fixed.
9. **Memory/storage budget reconciliation** — open thread from review M1: two-chapter residency (FR18) vs the ~100 KB total Storage cap vs the 600 KB heap target needs an explicit residency model (what lives in heap vs Storage) early in design.

## Starter Template Evaluation

### Primary Technology Domain

Dual-codebase wearable system: **Connect IQ watch app (Monkey C)** + **Flutter companion (Android-first)**, joined by a custom BLE protocol. No single starter covers this; each codebase gets its own scaffold, evaluated separately.

### Starter Options Considered

**Watch app (Connect IQ / Monkey C):**

| Option | Verdict |
|---|---|
| VS Code Monkey C extension — "New Project" generator (official) | ✅ **Selected.** The canonical scaffold: generates `manifest.xml`, `monkey.jungle`, source/resource skeleton for a watch-app targeting the chosen device family. No alternative generator ecosystem exists. |
| `matco/badminton` as pattern exemplar | ✅ **Adopted as reference, not fork.** Copy its structure: UI-free, unit-tested model classes + GitHub Actions CI via `matco/action-connectiq-tester`. Already named in the PRD addendum as the CI exemplar. |
| `garmin/connectiq-apps` samples (incl. `Comm` sample) | Reference material for the Communications wiring; not a project base. |
| Forking an existing CIQ app as base | ❌ Rejected — no RSVP-adjacent OSS CIQ app exists; inherited structure would fight the clean reader/view/input/sync separation the addendum mandates. |

**Companion (Flutter):**

| Option | Verdict |
|---|---|
| `flutter create` (official scaffold) | ✅ **Selected.** Minimal, current, no foreign opinions. The app is a single-purpose pipeline + small library UI; architecture-heavy starters add nothing. |
| Community starters (e.g. very_good_cli) | ❌ Rejected — opinionated layering (bloc, mason, l10n scaffolding) outweighs benefit for a solo, small-surface companion. Worth borrowing its *lint strictness* idea only (`very_good_analysis` or strict `analysis_options.yaml`). |

### Selected Starters

**Rationale:** Both choices follow the "boring technology" principle — official scaffolds, zero abandonment risk, no architectural opinions to undo. All meaningful stack decisions were already made in the PRD addendum; the starters' job is to not interfere with them.

**Initialization Commands:**

```bash
# Watch app — prerequisites first (one-time):
#   1. Install Connect IQ SDK Manager → download latest SDK
#      (9.1.0 per 2026-06-06 research; CONFIRM exact version in SDK Manager at init)
#      + Fenix 8 device files
#   2. VS Code: install "Monkey C" (garmin) + "Prettier Monkey C" (markw65) extensions
#   3. Command palette → "Monkey C: Generate a Developer Key" (4096-bit RSA — hard build prerequisite)
# Then scaffold:
#   Command palette → "Monkey C: New Project" → watch-app → API 6.0 → fenix8 family
# Immediately after scaffold:
#   - Set type-check level to Strict (level 3) in project settings / build flags (commit 1 requirement)
#   - Add CI workflow copied from matco/badminton (.github/workflows/test.yml, action-connectiq-tester)

# Companion app:
flutter create paceturner_companion \
  --org dev.paceturner \
  --platforms android,ios \
  --template app
# (iOS platform folder generated but untargeted for MVP — keeps the port cheap, costs nothing now)
# Flutter stable 3.44.0 (verified 2026-06-06)
```

**Architectural Decisions Provided by Starters:**

- **Language & Runtime:** Monkey C on CIQ API 6.0 (Strict typing — our addition on top of scaffold); Dart 3.x / Flutter 3.44.0.
- **Build Tooling:** `monkey.jungle` + `monkeyc` via VS Code extension, markw65 optimizer in the loop before size measurement; standard Flutter Gradle build.
- **Testing:** `Toybox.Test` with `:test` annotations, run headless in CI via `action-connectiq-tester` (badminton pattern); `flutter_test` built in, isolate-friendly pure-Dart pipeline classes.
- **Code Organization:** scaffolds provide only skeletons — the reader/view/input/sync separation (watch) and pipeline/store/transfer/UI separation (phone) are *our* decisions, made in the next step.
- **Development Experience:** CIQ simulator + breakpoint debugging (Start Debugging only) + memory viewer; Flutter hot reload; both CI-able from day one.

**Notes:**
- Project initialization (both scaffolds + developer key + CI skeleton) should be the **first implementation story**.
- **Repo topology** (monorepo `watch/` + `companion/` + `protocol/` docs vs. split repos) is deliberately deferred to the architectural decisions step — PRD Goal 3 says "a public GitHub repo" (singular), which hints monorepo, but it deserves a conscious decision next.
- The CIQ SDK version discrepancy (9.1.0 research vs 8.x search snippets) is noted; resolve at SDK Manager install — no architectural impact either way, manifest targets API 6.0 regardless.

## Core Architectural Decisions

### Decision Priority Analysis

**Critical Decisions (Block Implementation):**
- Watch content residency model (resolves PRD-review M1 contradiction)
- Protocol message envelope (blocks protocol spec, transfer engine, and V2/V3 gate tests)
- Repo topology (blocks first implementation story)

**Important Decisions (Shape Architecture):**
- Phone DB layer (drift), Flutter state management (Riverpod)

**Deferred Decisions (Post-MVP):**
- Custom MethodChannel bridge (only if `watch_connectivity_garmin` fails during V2 — OQ2)
- Multi-device jungle matrix specifics (structure for it now via `has` discipline; decide per-device later)
- iOS transfer/prefetch redesign for background-BLE priority (registered constraint, decided at port time)

### Data Architecture

| Decision | Choice | Rationale |
|---|---|---|
| Phone DB | **drift** (latest 2.x — pin at pubspec creation) over sqflite | Reactive queries make FR16 (live progress in library) nearly free; compile-time-checked SQL; codegen cost acceptable solo |
| Phone bulk data | Flat files (word stream binary + debuggable JSONL master), paths referenced from drift | Addendum decision, ratified — never multi-MB blobs in SQLite |
| Cover art (phone-only) | `cover_extractor.dart` pipeline stage → cover image file in stream store, `cover_path` column on drift `Books`; never enters the protocol or the watch | UX book detail + library rows show EPUB covers (EXPERIENCE.md, 2026-06-06) |
| **Watch content residency** | **Resident chapters persist to `Storage` in ≤32 KB buckets: current + next chapter, hard-capped at ~80 KB of the ~100 KB total store. Heap holds only the decoded reading window + render state.** Position/prefs/manifest take remaining Storage headroom. Oversized chapters are split *virtually* by the delivery layer (offset addressing is chapter-agnostic). | Heap-only residency would break NFR5 (≤3 s cold open) and FR19 (phone-free reading) across app restarts; Storage-backed residency satisfies both within NFR3's caps. Resolves review M1. |
| Data validation | Bounds-check-and-degrade at every ingest boundary (BLE chunk, Storage read, EPUB parse) per NFR8; chunk header validation (fingerprint, offset, length) before commit | RSVP Nano's proven posture |
| Migrations | drift schema migrations (phone); `Storage` layout carries a schema-version key (watch) — mismatch wipes content cache (re-fetchable), never position records | Position is the only sacred state (NFR4) |

### Authentication & Security

Not applicable — no server, no accounts, no PII beyond book files the user owns. Security posture: validate all inbound bytes (NFR8); no network calls except BLE-to-phone; MIT-licensed source as the transparency mechanism.

### API & Communication Patterns (Protocol)

| Decision | Choice | Rationale |
|---|---|---|
| Envelope | **CIQ `Dictionary` envelope + binary `ByteArray` payload**: `{t: msgType, v: protocolVersion, fp: fingerprint, off: absWordIndex, n: count, p: ByteArray}` | Self-describing headers for FR28's third-party implementers and for debugging; word data stays binary-packed (~9 B/word); overhead is noise vs the ≤1 KB chunk budget |
| Versioning | Explicit `v` field from message one; unknown version → reject + report, never guess | Protocol is a public contract (FR28) |
| Message types (MVP) | `manifest` (book meta, chapter index, cumulative durations, fingerprint), `chunkRequest` (fp, off, n), `chunkData` (fp, off, n, payload), `position` (fp, off, timestamp, source), `error` | Minimal complete set for FR17–21 + FR15 |
| Position reconciliation | **Timestamped LWW retained** (epoch-second timestamps, watch-wins tiebreak in the skew window). UX-proposed max-index-wins considered and rejected: it cannot express the deliberate backwards repositions the UX itself specifies (Restart book, jump-to-chapter). Phone-initiated repositions reuse the `position` message — no new message type | UX reconciliation, decided with Nerya 2026-06-06 |
| Flow control | ≤2 outstanding transfers (under the 3-cap); next request only from `onComplete()` or watchdog timeout; phone-side per-request timeout + SDK re-init + resend (the V2 bug defense) | Addendum §3, ratified |
| Error handling standard | Every error path lands in a *named UI state* ("waiting for phone", "buffering", "book changed — refreshing"), never silent retry loops | FR20's visible-degradation requirement |
| Documentation | `protocol/` directory in the monorepo: spec markdown + worked byte-level examples; updated in the same PR as any implementation change | FR28; atomicity is the monorepo's purpose |

### Frontend Architecture

**Companion (Flutter):**
- **State management: Riverpod (flutter_riverpod 3.3.1)** — providers compose drift streams + import/transfer progress; service-layer DI (parser, transfer engine, sync) via providers, keeping services constructor-injected and testable
- Layering: `ui/` → `services/` (import pipeline, transfer engine, position sync) → `data/` (drift, stream files, CIQ bridge). UI never touches the bridge directly
- **UI per UX spec (2026-06-06):** Material 3 with dynamic color, system light/dark, M3 defaults throughout (DESIGN.md); surfaces = Library, Book detail, Import, Transfer, Settings (EXPERIENCE.md). The service/provider seam absorbed the spec unchanged
- **Android foreground service for active transfers** — pull-based transfer needs a live phone process to answer chunk requests; a foreground service (with the transfer-bar notification as its required notification) keeps the app alive until delivery completes, honoring the UX's "survives backgrounding" promise and Flow 1's walk-away demo. Decided with Nerya 2026-06-06

**Watch (Monkey C):** four-class separation from day one (anti-monolith, addendum §5): `ReaderEngine` (pure logic: pacing, position, sentence boundaries, start ramp — host-testable), `ChunkedWordSource` (BookWordSource seam over Storage-backed chunks + BLE fetch), `Views` + `InputDelegates` (thin; composition per DESIGN.md/EXPERIENCE.md, input map provisional until hardware), `SyncManager` (persistence + protocol client). `DisplayStrategy` isolated behind its own seam — gate V1's outcome (ActivityRecording vs dim-AON fallback) swaps a module, not the architecture.

UX additions (2026-06-06): a `Settings` model over the reserved `"settings"` Storage key + `SettingsMenu` (Menu2) view — WPM, pause mode, chapter-card resume, touch on/off, font size, handedness, focus highlight, phantom words, anchor position; settings are **per-device, never synced**. Typography: Atkinson Hyperlegible as BMFont resources across all roles plus a ±2-step user word size — **only the active word-display size is heap-resident** (load-on-demand on size change); fallback to the largest native Garmin font is the documented escape hatch if resource cost breaks the NFR2 budget. Font memory joins the on-device validation list.

### Infrastructure & Deployment

| Decision | Choice |
|---|---|
| Repo | **Monorepo**, public, MIT: `watch/`, `companion/`, `protocol/`, `docs/` |
| CI | GitHub Actions: `action-connectiq-tester` (watch, badminton pattern) + `flutter test` + analyze (companion); both green from first commit |
| Release path | Developer key + Garmin developer verification started *early* (FR27); beta-channel listing for hardware validation → public; ERA crash monitoring enabled from first store build |
| Environments | None beyond local + CI — no server infrastructure exists |

### Decision Impact Analysis

**Implementation Sequence:**
1. Monorepo + both scaffolds + developer key + CI skeleton (first story)
2. Protocol spec on paper (envelope above) — unblocks V2/V3 gate tests and companion transfer engine in parallel
3. **Gates V1 + V2 on hardware** — before playback/transfer architecture hardens or epics split
4. Companion parse pipeline + stream format (gate-independent, parallel with 3)
5. Watch reader engine over a `FakeWordSource` (host-testable, gate-independent)
6. Integration: ChunkedWordSource + transfer + sync; views/ui built to DESIGN.md + EXPERIENCE.md (input map re-validated on first sideload)

**Cross-Component Dependencies:**
- Envelope decision → protocol spec → both transfer implementations + V2/V3 test harnesses
- Residency model → ChunkedWordSource design + chunk bucket sizing ↔ V3's empirical message-size calibration
- drift reactive streams → Riverpod providers → library UI (FR16)
- Sentence-end flags (phone segmenter) → watch pause/rewind correctness (FR8/FR10)
- Gate V1 outcome → DisplayStrategy module only (by design)

## Implementation Patterns & Consistency Rules

### Pattern Categories Defined

**Critical Conflict Points Identified:** 7 areas where AI agents could make different choices — cross-language naming, protocol constants, units/types, binary layout authority, persistence keys, error-state naming, and test placement.

### Naming Patterns

**Cross-language code naming (follow each platform's native idiom — never import the other's):**

| | Dart (companion) | Monkey C (watch) |
|---|---|---|
| Classes | `PascalCase` (`TransferEngine`) | `PascalCase` (`ReaderEngine`) |
| Methods/vars | `camelCase` | `camelCase` (private fields `_camelCase`) |
| Files | `snake_case.dart` (`transfer_engine.dart`) | `PascalCase.mc`, one public class per file (`ReaderEngine.mc`) |
| Constants | `lowerCamelCase` or `kPascalCase` in class scope | `UPPER_SNAKE` module consts |

**Database naming (drift):** Dart table classes `PascalCase` plural (`Books`, `Positions`); SQL columns `snake_case` (`book_id`, `word_index`, `updated_at_epoch_s`). Foreign keys: `<entity>_id`.

**Protocol naming:** message-type and field keys are defined **once** in `protocol/SPEC.md` and mirrored as constants on both sides (`ProtocolKeys` in Dart, `Protocol` module in Monkey C). Agents never inline-type a protocol string/key — they reference the constant. Message types: `manifest`, `chunkRequest`, `chunkData`, `position`, `error` (camelCase strings).

**Watch Storage keys:** prefix-namespaced, defined in one `StorageKeys` module: `"pos_<bookId>"`, `"chunk_<bookId>_<bucketIndex>"`, `"meta_<bookId>"`, `"schemaVersion"`, `"settings"`. Never ad-hoc string literals at call sites.

### Structure Patterns

**Monorepo organization (detailed structure next step; rules here):**
- `watch/` and `companion/` are self-contained projects; nothing imports across them — the only shared artifact is `protocol/SPEC.md` + mirrored constants
- Tests: Dart in `companion/test/` mirroring `lib/` paths (`test/services/transfer_engine_test.dart`); Monkey C in `watch/source-test/` with `(:test)` annotations, linked via the jungle's test config and excluded from release builds
- Pure logic stays UI-free on both sides: `ReaderEngine` and pipeline classes must be constructible without `Toybox.WatchUi` / Flutter imports — this is what makes them CI-testable

### Format Patterns

**Units & types (the silent-killer category — these are absolute):**

| Quantity | Canonical form | Rule |
|---|---|---|
| Position | **absolute word index**, 0-based integer | The only position coordinate, everywhere (FR13). Never chapter+offset pairs in APIs or storage |
| Time-of-day / sync timestamps | **Unix epoch seconds, integer** (`Time.now().value()` on watch) | LWW comparisons (FR15) must compare like units; never mix ms epochs in |
| Durations / dwell | **milliseconds, integer** | Base `60000/wpm` + bonus-ms; never float seconds |
| Fingerprint | integer/string hash as defined in SPEC.md, opaque to the watch | Watch compares for equality only, never parses |
| Text | UTF-8 everywhere; ORP pivot is a **byte index into the UTF-8 word** as precomputed by the phone | Watch never recomputes pivots |

**Binary stream layout:** `protocol/SPEC.md` is the **single source of truth** — byte order (little-endian), per-word record layout, flag-bit assignments (bit positions for `sentenceEnd`, `paragraphStart`, `chapterStart`, reserved `continuation`/`direction` bits). Both implementations cite spec section numbers in comments at their encode/decode sites. An agent who needs a new flag bit **edits the spec first**, in the same PR.

**Envelope format:** exactly the step-4 shape — `{t, v, fp, off, n, p}`. No agent adds ad-hoc fields; new fields go through the spec + version bump.

### Communication Patterns

**State management (Riverpod):** providers named `<thing>Provider` (`libraryProvider`, `transferProgressProvider`); state classes immutable with `copyWith`; services exposed via providers and constructor-injected for tests — never located via globals/singletons.

**Watch internal communication:** views *read* engine state; input delegates *call* engine methods; the engine never references views (WeakReference if a back-pointer is unavoidable — refcount GC). `onUpdate` draws the already-selected word only; all advancement happens in timer callbacks.

**Logging:** Dart — `dart:developer log` with service-name prefixes, free in debug. Monkey C — `System.println` is **budgeted** (~10 KB on-device log): log state transitions and errors only, never per-word events; guard verbose logs behind a `(:debug)` annotation excluded from release.

### Process Patterns

**Error handling:** every failure surfaces as a member of a **named, enumerated state set** per the step-4 decision — watch: `WaitingForPhone`, `Buffering`, `BookChanged`, `StorageFull`, `Finished`; companion: typed import/transfer failure results with user-facing message + actionable next step (FR26). No silent `catch {}` anywhere; bounds-check-and-degrade per NFR8 (skip/refetch/report — never crash mid-read).

**Persistence discipline (watch):** any code path that changes position **must** route through `SyncManager.commitPosition(force: bool)` — debounced (~15 s) while playing, `force: true` on pause/exit/rewind/chunk-boundary/disconnect/`onStop`. Agents never write a position to Storage directly.

**Retry pattern:** offset-addressed idempotent re-request with timeout + bounded backoff; on the phone, the V2 defense (timeout → SDK re-init → resend) lives in **one** place (`TransferEngine`), not scattered per call site.

**Loading states:** the renderer reads only from the resident buffer; an empty buffer shows `Buffering` — playback code never awaits BLE.

**Input principles (fixed, from EXPERIENCE.md 2026-06-06):** BACK keeps its Garmin meaning everywhere; every action is reachable by buttons (touch is an opt-in mirror behind a setting and can be off); LIGHT is off-limits; `onKey` + `onTap`, never `onSelect`. The concrete key/gesture *map* is provisional until the first on-hardware test — delegates stay thin so remaps are cheap.

**Settings locality:** watch settings live behind the `Settings` model over the `"settings"` Storage key; phone defaults live phone-side. Settings never cross the protocol — per-device, never synced.

**Font loading (watch):** Atkinson Hyperlegible BMFont resources; only the active word-display size is heap-resident at once — load-on-demand on size change, never all steps at startup. Native-font fallback is the documented escape hatch (NFR2).

### Enforcement Guidelines

**All AI agents MUST:**
1. Reference protocol/storage/flag constants — never inline magic strings, keys, or bit positions
2. Keep `ReaderEngine` and pipeline logic free of UI imports (host-testability is load-bearing)
3. Route every position write through `commitPosition`; every byte-ingest through validation
4. Edit `protocol/SPEC.md` in the same PR as any protocol-touching code change
5. Compile Monkey C at Strict (level 3) — a build that needs the level lowered is a defect
6. Use the managed Communications API only — `Raw.sendMessage()` is forbidden (known-broken)

**Pattern Enforcement:** CI runs both test suites + `flutter analyze` (strict `analysis_options.yaml`); protocol spec section references in encode/decode comments make drift greppable; pattern updates land as PRs touching this document.

### Pattern Examples

**Good:** `chunk_5f3a_12` written only via `StorageKeys.chunkKey(bookId, bucket)`; a new `tocRequest` message added to SPEC.md §4 + both constant mirrors + version bump in one PR.

**Anti-patterns:** computing dwell on the watch from word text (phone's job); a view holding a strong ref back to its delegate (leak); persisting a chunk into the position key's namespace; `catch (e) {}` around a Storage read; per-word `System.println` at 700 WPM.

## Project Structure & Boundaries

### Complete Project Directory Structure

```
paceturner/                              # public monorepo, MIT
├── README.md                            # architecture story (Goal 3); links to protocol spec
├── LICENSE                              # MIT
├── .gitignore
├── .github/
│   └── workflows/
│       ├── watch-ci.yml                 # matco/action-connectiq-tester (badminton pattern)
│       └── companion-ci.yml             # flutter analyze + flutter test
│
├── protocol/                            # THE public contract (FR28)
│   ├── SPEC.md                          # envelope, message types, binary word-record layout,
│   │                                    #   flag bits, fingerprint, versioning, error semantics
│   └── examples/                        # worked byte-level encode/decode examples
│
├── docs/
│   ├── gates.md                         # V1–V4 validation gates: procedure, status, results
│   ├── setup.md                         # SDK manager, developer key, sideload, CI
│   └── decisions/                       # ADR-style notes for post-architecture decisions
│
├── watch/                               # Connect IQ watch app (Monkey C, Strict)
│   ├── manifest.xml                     # watch-app, API 6.0, fenix8 family
│   ├── monkey.jungle                    # build config incl. source-test linkage, (:debug) excludes
│   ├── source/
│   │   ├── PaceTurnerApp.mc             # AppBase: lifecycle, onStart/onStop persistence hooks
│   │   ├── engine/
│   │   │   ├── ReaderEngine.mc          # pure logic: drift-free advance, WPM, sentence
│   │   │   │                            #   boundaries, seek/rewind, start ramp, catch-up cap
│   │   │   │                            #   (FR1–3,8–10)
│   │   │   ├── BookWordSource.mc        # 3-method seam: wordCount/wordAt/prefetchAround
│   │   │   └── AppStates.mc             # enumerated states incl. WaitingForPhone, Buffering,
│   │   │                                #   BookChanged, StorageFull, Finished (FR5, FR20)
│   │   ├── source_data/
│   │   │   ├── ChunkedWordSource.mc     # BookWordSource over Storage buckets + fetch requests
│   │   │   ├── StreamDecoder.mc         # binary word-record decode (cites SPEC.md sections)
│   │   │   └── StorageKeys.mc           # ALL Storage key construction; schema-version key
│   │   ├── sync/
│   │   │   ├── SyncManager.mc           # commitPosition(force) discipline; LWW reconcile (FR13–15)
│   │   │   └── ProtocolClient.mc        # envelope encode/decode, transmit/receive, flow control
│   │   ├── display/
│   │   │   ├── DisplayStrategy.mc       # seam: gate-V1-conditional screen-on behavior
│   │   │   └── ActivitySessionStrategy.mc  # primary path: ActivityRecording session (R1)
│   │   ├── views/                       # thin; composition per DESIGN.md/EXPERIENCE.md
│   │   │   ├── PlaybackView.mc          # ORP render, anchor 35% (tunable 30–60%), guide marks,
│   │   │   │                            #   phantom words, session jitter (FR1)
│   │   │   ├── PausedContextView.mc     # context-on-pause scroll view (FR11)
│   │   │   ├── ChapterCardView.mc       # transition card, Auto/Wait resume + prefetch window (FR6)
│   │   │   ├── SettingsMenu.mc          # Menu2: WPM, pause mode, chapter-card resume, touch,
│   │   │   │                            #   font size, handedness, focus highlight, phantoms, anchor
│   │   │   └── StatusViews.mc           # Finished / WaitingForPhone / Buffering / empty states
│   │   ├── input/                       # map provisional until hardware test; principles fixed
│   │   │   ├── PlaybackDelegate.mc      # START=pause-coast, UP/DOWN=WPM, swipe-right=rewind,
│   │   │   │                            #   BACK=exit (FR12)
│   │   │   └── PausedDelegate.mc        # START=resume(ramp), UP=rewind, DOWN=context view
│   │   ├── Settings.mc                  # settings model over "settings" key; per-device, no sync
│   │   └── Protocol.mc                  # mirrored protocol constants (keys, types, version)
│   ├── source-test/                     # (:test) host-side tests, excluded from release
│   │   ├── ReaderEngineTest.mc          # pacing application, advance, rewind, boundaries
│   │   ├── ChunkedWordSourceTest.mc     # cache hit/miss, bucket bounds, fingerprint mismatch
│   │   ├── SyncManagerTest.mc           # LWW cases, debounce/force, clock-skew tiebreak
│   │   └── FakeWordSource.mc            # test double (Nano pattern)
│   └── resources/
│       ├── fonts/                       # Atkinson Hyperlegible BMFont — all roles + word-size
│       │                                #   steps; precomputed glyph widths; load-on-demand
│       ├── drawables/                   # launcher icon
│       └── strings/
│
└── companion/                           # Flutter app (Android-first, iOS kept in reach)
    ├── pubspec.yaml                     # flutter 3.44.0; riverpod 3.3.1, drift 2.x, epub_pro,
    │                                    #   html, archive, xml, markdown, file_picker,
    │                                    #   receive_sharing_intent, watch_connectivity_garmin
    ├── analysis_options.yaml            # strict lints
    ├── android/                         # INCOMING_MESSAGE receiver, share-sheet intent filters,
    │                                    #   transfer foreground-service declaration
    ├── ios/                             # generated, untargeted for MVP
    ├── lib/
    │   ├── main.dart
    │   ├── app.dart                     # ProviderScope, routing
    │   ├── protocol/
    │   │   ├── protocol_keys.dart       # mirrored protocol constants
    │   │   ├── envelope_codec.dart      # Dictionary envelope ↔ Dart maps (cites SPEC.md)
    │   │   └── stream_codec.dart        # binary word-record encode (cites SPEC.md)
    │   ├── services/
    │   │   ├── import/                  # THE pipeline (FR17, FR22, FR26) — pure Dart, isolate-run
    │   │   │   ├── import_service.dart  # orchestrates; returns typed result or typed failure
    │   │   │   ├── epub_extractor.dart  # epub_pro structure + DOM pre-filter spine walk
    │   │   │   ├── cover_extractor.dart # EPUB cover → file in stream store (phone-only)
    │   │   │   ├── text_sanitizer.dart  # NFC, soft-hyphen/zero-width strip, NBSP, ASCII fold
    │   │   │   ├── tokenizer.dart       # Unicode \p{L}\p{N}; abbreviation-aware sentence flags
    │   │   │   ├── pacing.dart          # Nano algorithm port → WPM-invariant bonus-ms
    │   │   │   ├── orp.dart             # length→pivot table → UTF-8 byte index
    │   │   │   └── fingerprint.dart     # conversion fingerprint (FR20)
    │   │   ├── transfer/
    │   │   │   ├── transfer_engine.dart # chunking, ≤2 in-flight, timeout+re-init+resend (V2),
    │   │   │   │                        #   chunk-size calibration hook (V3), progress (FR21)
    │   │   │   └── foreground_session.dart  # Android foreground-service handle — keeps the
    │   │   │                            #   app alive while a transfer is active (UX: "survives
    │   │   │                            #   backgrounding"; notification = the transfer bar)
    │   │   └── sync/
    │   │       └── position_sync.dart   # LWW reconcile, mailbox recovery (FR15)
    │   ├── data/
    │   │   ├── db/
    │   │   │   ├── database.dart        # drift: Books (incl. cover_path), Chapters, Positions
    │   │   │   └── *.g.dart             # codegen
    │   │   ├── stream_store.dart        # flat-file word streams + JSONL debug master
    │   │   └── ciq_bridge.dart          # watch_connectivity_garmin wrapper (swap seam, OQ2)
    │   └── ui/                          # Material 3 + dynamic color, per DESIGN.md/EXPERIENCE.md
    │       ├── library/                 # list, progress, last-read (FR23, FR16)
    │       ├── import/                  # picker/share-sheet entry, progress, errors (FR22, FR26)
    │       ├── transfer/                # send-to-watch, delivery progress (FR24, FR21)
    │       └── settings/
    └── test/
        ├── services/import/             # extractor, sanitizer, tokenizer, pacing, orp, fingerprint
        ├── services/transfer/           # retry/idempotency/fingerprint-mismatch simulations
        ├── services/sync/               # LWW cases mirroring watch tests
        ├── protocol/                    # codec round-trips against SPEC.md examples
        └── fixtures/epubs/              # ugly-EPUB corpus (R6)
```

### Architectural Boundaries

- **Protocol boundary (the system's spine):** `watch/source/Protocol.mc` + `sync/ProtocolClient.mc` ⟷ `companion/lib/protocol/` — both are *implementations of* `protocol/SPEC.md`, never of each other. Cross-folder imports are forbidden; conformance is verified by round-trip tests against SPEC.md's worked examples on both sides.
- **Watch internal:** `engine/` is pure (no Toybox.WatchUi, no Communications) → testable host-side. `source_data/` owns bytes (Storage + decode); `sync/` owns the radio + persistence; `views/`+`input/` are thin shells over engine state. `display/` is the gate-V1 swap seam.
- **Companion internal:** `ui/ → services/ → data/`, enforced by review; `ui/` never imports `ciq_bridge.dart` or drift directly. `services/import/` is pure Dart (no Flutter imports) so it runs in isolates and tests trivially.
- **Data boundaries:** drift owns metadata/positions; `stream_store` owns bulk bytes; watch `Storage` owns resident chapters (≤80 KB budget) + position records — each with a single owning module.

### Requirements to Structure Mapping

| FR cluster | Watch | Companion |
|---|---|---|
| A. Playback (FR1–7) | `engine/ReaderEngine`, `views/PlaybackView`, `display/` | `services/import/pacing,orp` (timing/pivot source) |
| B. Controls (FR8–12) | `input/`, `engine/` (sentence logic) | `services/import/tokenizer` (sentence flags) |
| C. Resume/Sync (FR13–16) | `sync/SyncManager`, `StorageKeys` | `services/sync/position_sync`, drift `Positions` |
| D. Delivery (FR17–21) | `source_data/ChunkedWordSource`, `sync/ProtocolClient` | `services/transfer/transfer_engine`, `protocol/` |
| E. Library (FR22–26) | — | `services/import/`, `ui/library`, `ui/import`, drift |
| F. Openness (FR27–28) | — | — (lives in `protocol/SPEC.md`, `README.md`, `.github/`) |
| Gates V1–V4 | `display/`, `sync/` test harnesses | `transfer_engine` calibration hooks; `docs/gates.md` tracks |

### Integration Points & Data Flow

**Book delivery:** file → `import_service` (isolate) → sanitize/tokenize/pace/encode → `stream_store` + drift rows → `transfer_engine` chunks (envelope + binary payload) → CIQ bridge → BLE → `ProtocolClient` → validate (fingerprint/offset/bounds) → `Storage` buckets → `ChunkedWordSource` heap window → `ReaderEngine` → `PlaybackView`.

**Position:** `ReaderEngine` index change → `SyncManager.commitPosition` (debounce/force) → `Storage` + `position` message → `position_sync` → drift → library UI via Riverpod stream. Reverse path on reconnect via LWW; mailbox persistence covers closed-app delivery.

**External integrations:** Garmin Connect Mobile (pairing prerequisite), CIQ Store + ERA (release/ops) — no others.

### Development Workflow Integration

- **Dev loop:** watch — VS Code + simulator, sideload to Fenix 8 early (simulator lies about memory/watchdog); companion — `flutter run`, hot reload; protocol changes start in `SPEC.md`.
- **Build:** watch CI builds + tests per push (test-mode build in headless sim); export `.iq` via optimizer for store packaging. Companion: standard Flutter Android build.
- **Gate workflow:** `docs/gates.md` is the single status page for V1–V4; gate-blocked work (hardening playback/transfer, story-splitting their epics) references it.

## Architecture Validation Results

### Coherence Validation ✅

**Decision Compatibility:** No contradictions found. The chain holds: inverted topology → baked WPM-invariant bonuses → compact binary stream → Dictionary envelope → chapter-granular pull transfer → Storage-bucket residency → heap window → drift-free render loop. Versions are mutually compatible (Flutter 3.44.0 / Dart 3.x supports riverpod 3.3.1 and drift 2.x; CIQ API 6.0 ⊂ SDK 9.1.0 toolchain). The step-4 residency model *resolved* the one inherited contradiction (review M1: FR18 two-chapter residency vs NFR3's ~100 KB cap) via the ~80 KB bucket budget + virtual chapter splitting.

**Pattern Consistency:** Patterns enforce the decisions rather than fighting them — `commitPosition` discipline implements FR14/NFR4; constants-only protocol access implements FR28's single-source spec; UI-free engine/pipeline rules implement the CI strategy; units table prevents the LWW epoch-mismatch failure (H3's clock-skew concern is bounded by FR15's watch-wins tiebreak plus same-unit timestamps).

**Structure Alignment:** Every pattern has a home in the tree (StorageKeys.mc, Protocol.mc/protocol_keys.dart mirrors, source-test/, fixtures/epubs/). The two gate-sensitive modules are physically isolated seams: `display/` (V1) and `ciq_bridge.dart`/`transfer_engine.dart` (V2/OQ2) — a gate failure swaps a module, not the architecture.

### Requirements Coverage Validation ✅

**Functional Requirements:** All 28 FRs map to named components (Requirements to Structure Mapping). Spot-checks of the trickiest: FR7 (long-word) → PlaybackView scale-down+extend with continuation flag reserved in SPEC.md; FR19 (phone-free reading) → Storage-backed residency, satisfied across app restarts; FR20 (fingerprint) → carried in envelope, validated before commit, mismatch → `BookChanged` state; FR26 (survivable import) → typed failure results + ugly-EPUB corpus; FR28 → `protocol/SPEC.md` + round-trip conformance tests.

**Non-Functional Requirements:** NFR1 → ReaderEngine drift-free advance (host-tested); NFR2 → residency model + optimizer + simulator memory checks + early sideloading; NFR3 → ≤32 KB buckets, ~80 KB cap; NFR4 → commitPosition + schema-version wipe rule (content wiped, position never); NFR5 → Storage residency (cold open) + isolate pipeline (import); NFR6 → manifest + firmware floor; NFR7 → per-word pivot/dwell metadata + reserved direction bits in SPEC.md; NFR8 → enumerated-state error posture at every ingest boundary.

**Cross-cutting concerns (step 2's nine):** all addressed — items 1–7 and 9 by decisions/patterns/structure above; item 8 (UX-revisable surfaces) closed by the 2026-06-06 UX reconciliation — the views/ui seams absorbed Sally's spec as designed (see UX Reconciliation Addendum).

### Implementation Readiness Validation ✅

**Decision Completeness:** All critical decisions documented with rationale; versions verified where they exist (two deliberate soft-pins: drift "latest 2.x" and the CIQ SDK 9.1.0-vs-8.x snippet discrepancy — both resolve mechanically at init, neither affects design).

**Structure Completeness:** Full tree to file level for both codebases plus protocol/docs/CI; boundaries and ownership singular per data store.

**Pattern Completeness:** The 7 conflict clusters covered with examples and anti-patterns; enforcement is CI-backed, not aspirational.

### Gap Analysis Results

**Critical Gaps:** none open. *(The V1/V2 hardware gates are unresolved by nature, but the architecture is explicitly structured so they gate hardening, not starting — the C1 trap from the adversarial review is closed structurally.)*

**Important Gaps:**
1. **UX spec pending — RESOLVED 2026-06-06.** Sally's spec (DESIGN.md + EXPERIENCE.md) reconciled into this document; the seams absorbed it without structural rework — see UX Reconciliation Addendum. Residual: the watch input map is provisional until the first on-hardware test (principles fixed, map revisable).
2. **SPEC.md itself is unwritten.** The architecture defines its required contents (envelope, message types, record layout, flag bits, versioning); authoring it is implementation story #2 and prerequisite to V2/V3 harnesses.
3. **Chunk/bucket size numbers are provisional** until V3's empirical calibration — the calibration hook in `transfer_engine` is the designed landing spot.

**Nice-to-Have Gaps:** glossary inheritance from the PRD review (architecture consistently uses *chapter-transition card*, *absolute word index*, *word stream*, *content fingerprint* — a SPEC.md glossary section would close the rubric's finding); ADR habit (`docs/decisions/`) for post-architecture choices.

### Validation Issues Addressed

- **M1 (storage budget contradiction)** → resolved by the residency model (Core Architectural Decisions).
- **H1 (carousel 0–15 s loss)** → architecture matches the PRD's tightened NFR4 promise (trail ≤ one persistence interval, never overshoot); `commitPosition(force)` on every catchable transition minimizes the window; cannot be closed further on this platform.
- **H3 (LWW clock skew)** → same-unit epoch-second timestamps + watch-wins tiebreak + SyncManagerTest cases on both sides.
- **C1 (gate sequencing)** → encoded in Decision Impact sequence, `docs/gates.md`, and module seams.

### Architecture Completeness Checklist

**Requirements Analysis**
- [x] Project context thoroughly analyzed
- [x] Scale and complexity assessed
- [x] Technical constraints identified
- [x] Cross-cutting concerns mapped

**Architectural Decisions**
- [x] Critical decisions documented with versions
- [x] Technology stack fully specified
- [x] Integration patterns defined
- [x] Performance considerations addressed

**Implementation Patterns**
- [x] Naming conventions established
- [x] Structure patterns defined
- [x] Communication patterns specified
- [x] Process patterns documented

**Project Structure**
- [x] Complete directory structure defined
- [x] Component boundaries established
- [x] Integration points mapped
- [x] Requirements to structure mapping complete

### Architecture Readiness Assessment

**Overall Status:** READY FOR IMPLEMENTATION — with the standing discipline that playback/transfer designs harden only after gates V1/V2 pass on hardware.

**Confidence Level:** Medium-high — high on everything the team controls; the residual uncertainty is exactly where the PRD says it is (R1/R2, hardware-only answers).

**Key Strengths:** gate failures swap modules, not architecture; the protocol is a first-class versioned artifact; both codebases' core logic is host-testable from day one; every prior review finding (C1, H1, H3, M1) has a structural answer.

**Areas for Future Enhancement:** input-map hardware pass on first sideload (UX map is provisional by design); iOS transfer/prefetch redesign (registered constraint); multi-device jungle matrix; SPEC.md glossary.

### Implementation Handoff

**AI Agent Guidelines:**

- Follow all architectural decisions exactly as documented
- Implementation patterns are mandatory (see Enforcement Guidelines)
- Respect project structure and boundaries — they are not suggestions
- Protocol changes start in `protocol/SPEC.md`, in the same PR as the code
- Refer to this document for all architectural questions

**First Implementation Priority:** Story 1 = monorepo + both scaffolds (Starter Template commands) + developer key + CI skeleton. Story 2 = author `protocol/SPEC.md`. Then V1/V2 hardware spikes before any playback/transfer hardening or epic story-splitting.

## UX Reconciliation Addendum (2026-06-06)

Sally's UX spec (`ux-designs/ux-garmin_RSVP-2026-06-06/`: DESIGN.md, EXPERIENCE.md, key-playback mockup) landed after this architecture completed and has been reconciled into the sections above. The UX was authored *against* this document (it cites the architecture as a source), and the bet paid off: the seams held, and no structural rework was required. All changes below were decided with Nerya, 2026-06-06.

### Conflict Resolved

**Position reconciliation — timestamped LWW retained over UX-proposed max-index-wins.** EXPERIENCE.md preferred "max word index wins" (re-reading a paragraph is cheap; losing your place is not). Rejected because the UX's own book-detail screen specifies deliberate *backwards* repositions — Restart book and jump-to-chapter — which max-index would silently undo on the next reconnect. The UX's underlying concern (never lose your place to a stale phone record) is already covered structurally by the watch-wins tiebreak inside the clock-skew window. LWW stands; repositions ride the existing `position` message. Sally's rationale is recorded here as considered-and-absorbed.

### New Decision

**Android foreground service for active transfers.** EXPERIENCE.md requires transfer to survive app backgrounding (Flow 1: phone goes face-down before delivery completes). Pull-based transfer needs a live phone process to answer chunk requests, and Android suspends backgrounded apps. A foreground service — with the transfer bar's text as its notification — keeps the process alive until delivery completes. `foreground_session.dart` + Android manifest declaration added to structure. Boring technology doing exactly its job.

### Additive Changes Folded In

1. **Watch settings surface** — `SettingsMenu.mc` (Menu2) + `Settings.mc` model over the reserved `"settings"` Storage key: WPM, pause mode, chapter-card resume (Auto/Wait), touch on/off, font size, handedness, focus highlight, phantom words, anchor position. Settings are per-device, never synced (pattern rule added).
2. **Font resource budget** — Atkinson Hyperlegible BMFont across all roles plus ±2 word-size steps; load-on-demand discipline (one word-size font heap-resident); native-font fallback as documented escape hatch; joins the on-device NFR2 validation list.
3. **Cover art extraction** — `cover_extractor.dart`, cover file in stream store, `cover_path` on drift `Books`; phone-only, never enters the protocol.
4. **Start ramp** — 3-beat lead-in on resume/play, implemented in `ReaderEngine` (host-testable like the rest of the engine).
5. **Jump-to-chapter** — manifest chapter index → absolute word index → existing `position` message; no protocol change.
6. **Input principles fixed, map provisional** — BACK sacred, buttons-always-work, touch opt-in mirror, every gesture has a button path, LIGHT off-limits, `onKey`+`onTap` never `onSelect` (pattern rules added). The concrete map awaits the first hardware test.

### Validation Delta

Every UX-introduced behavior maps to an existing component or one of the additions above; no new gates. The enumerated state set, dim/AON fallback behavior, persistence discipline, residency model, chunking, and one-active-book rule in the UX match this document verbatim. Status remains **READY FOR IMPLEMENTATION**, gated on V1/V2 as before.

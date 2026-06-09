# Reconciliation — Monkey C Technical Research vs PRD + Addendum

**Input:** `_bmad-output/planning-artifacts/research/technical-monkey-c-development-landscape-research-2026-06-06.md`
**Against:** `prd.md` and `addendum.md` (prd-garmin_RSVP-2026-06-06)
**Date:** 2026-06-06

## Method

This is a technical research report. By design, most implementation detail (memory model, render loop, BLE protocol mechanics, debugging story, learning path) correctly lives in the addendum or downstream architecture docs and is **not** flagged here. Only items that change **requirements, risks, or scope**, or that constitute a hard constraint/number the documents omitted or got wrong, are reported as gaps.

## Items confirmed carried (no action)

These substantive research findings are present in the PRD and/or addendum and need no action:

- Strict typing from commit 1 — PRD R5, addendum §1.
- Reference counting, no cycle collection, weak references for back-pointers — addendum §4.
- Memory budget includes compiled resources; Fenix 8 budget — research said "~128–256 KB class, verify in device files (Confidence: Medium)"; **the addendum corrected this to the authoritative 786,432 B / 768 KB watch-app heap** (§1, NFR2). Research open question resolved, not a gap.
- `onUpdate` watchdog + timer-driven advancement — addendum §4, PRD recommendations.
- SDK 9.1.0 (May 2026) — addendum §1.
- markw65 Prettier/optimizer extension — addendum §4.
- CI via `matco/action-connectiq-tester`, `matco/badminton` exemplar, UI-free testable model classes — addendum §4, §5; PRD R5.
- BLE chunking / `BLE_REQUEST_TOO_LARGE` — PRD R3, addendum §3 (addendum also adds `BLE_QUEUE_FULL`/3-concurrent and round-trip latency beyond the research).
- Storage API caps (32 KB/value, ~100 KB total) — NFR3, addendum §3.
- Direct `Dc` drawing over XML layouts — PRD recommendations, addendum §4.
- BLE throughput at high WPM (research open question, Confidence Low) — resolved in addendum §3 ("throughput is a non-issue, ~120–190 B/s needed"). Not a gap.

## Gaps — substantive content in NEITHER document that affects requirements/risk/scope

### GAP 1 (HIGH) — Connect IQ Store developer-verification requirement (Feb 2025 policy change)

Research "Store publishing workflow" and Key Finding #9 / Risk: *"in February 2025 Garmin tightened requirements and a wave of (mostly paid) apps were temporarily removed pending a **developer verification** process; free/open-source apps are simpler to clear but plan for identity verification."* The report also lists this as an open risk ("2025 store-verification specifics for a free OSS app are not fully documented publicly; confirm current requirements at submission time. Confidence: Low").

**Why it matters:** The PRD makes publication a hard goal (Goal 3) and a release requirement (FR26 — "ships on the Connect IQ Store"). Neither the PRD nor the addendum registers developer verification as a publication precondition or risk. This is a release-FR-affecting constraint: it can block or delay the single "Published" success criterion. Recommend adding it to FR26's acceptance context and to the risk register / open questions (mirrors the report's own open question).

### GAP 2 (MEDIUM) — Beta distribution channel not captured

Research "Store publishing workflow": *"Connect IQ supports beta-published apps for limited testing distribution before public release."*

**Why it matters:** The PRD's whole validation strategy rests on hardware gates (V1–V4) and the author dogfooding a full book (Goal 2). The beta-publish channel is the supported mechanism for distributing pre-release builds (e.g., to early adopters or for wider hardware testing before the public free release). It is absent from scope and from the release requirements. Worth a one-line note in §4 Scope or FR26 so the release plan accounts for a beta phase rather than going straight to public.

### GAP 3 (LOW/MEDIUM) — Post-release crash monitoring (ERA) not in release/ops requirements

Research "Debugging & crash analysis": ERA (Error Reporting Application, since CIQ 3.1) *"aggregates crash reports from published apps in a viewer on the developer dashboard after users sync — proactive post-release crash monitoring."*

**Why it matters:** The PRD addresses pre-release crash posture (NFR8: bounds-check and degrade, never crash mid-read) but has no post-release crash-monitoring expectation. For a publish-quality OSS app whose top success metric is "resume never lies" across real-world disconnects/reboots, ERA is the only field-crash signal available. Not a strict requirement, but a cheap ops requirement that fits NFR8/Goal 3. Optional to add.

### GAP 4 (LOW) — Developer key is a hard build prerequisite

Research week-1 pitfalls #5: *"You cannot build/run without generating a 4096-bit RSA developer key first... A trivial but mandatory first step that blocks everything."*

**Why it matters:** Pure setup detail, correctly downstream of the PRD. Flagged only for completeness because it is a hard, total blocker for the first build spike (where gate V1 runs). No PRD change warranted; ensure it appears in architecture/setup docs.

## Items deliberately NOT flagged (correctly downstream)

Language semantics (modules vs classes, symbols/`has`, no generics, `as`/nullability), jungle build system, barrels, on-device log size limits and `pc:`-stack decode via `debug.xml`, SDK Manager/Linux AppImage, lifecycle method details, learning path, exemplar repos, simulator memory viewer. These are implementation/architecture material and either appear in the addendum or belong in downstream architecture docs. The `has`/jungle multi-device discipline is tied to the "additional CIQ devices" item already in the PRD's "Later" scope.

## Recommendation summary

- Add developer-verification (GAP 1) to FR26 context and the risk/open-questions section — highest priority, gates the "Published" goal.
- Add a beta-publish phase note (GAP 2) to Scope / release plan.
- Consider ERA post-release crash monitoring (GAP 3) as an ops line under NFR8/Goal 3.
- GAP 4 is informational; route to architecture/setup docs.

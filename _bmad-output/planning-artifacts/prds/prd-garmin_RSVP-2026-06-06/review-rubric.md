# PRD Quality Review — PaceTurner

## Overall verdict
This is a genuinely strong solo/hobby PRD: it has a real thesis (free, open-source, book-first RSVP; "the watch renders, the phone thinks"), it surfaces its hardest bets as hardware-gated risks before architecture hardens, and nearly every FR carries a testable consequence. What holds up is the engineering honesty — risks, counter-metric, deferred decisions, and rejected alternatives are all explicit and well-reasoned. What's mildly at risk is downstream traceability hygiene (no Glossary, no Assumptions Index roundtrip, a couple of named concepts used loosely) and a small number of FRs whose "done" still leans on a hardware measurement that hasn't happened yet — acknowledged, but it means some acceptance bounds are provisional rather than fixed.

## Decision-readiness — strong
A decision-maker can act on this. Decisions are stated as decisions, not buried: §4 Scope cleanly separates MVP / Fast-follow / Later / Out of scope, and the founding architectural bet ("Phone does the heavy lifting," FR17; "inverted topology is the founding architecture decision," addendum §5 Rejected) is named as load-bearing rather than implied. Trade-offs name what was given up: last-writer-wins is chosen *because* "max-index would fight deliberate rewinds" (FR15, addendum §6); chapter residency is chosen over tiny-window streaming with the heap-budget reasoning given (addendum §6). The counter-metric in §3 is unusually honest — it's labeled "validation gate, not promise" and tied to a real threshold (≤10%/hour) flagged as an assumption pending hardware.

The two Open Questions are actually open: OQ1 (competitor teardown deferred) and OQ2 (bridge sufficiency) both name an owner and a revisit trigger, and neither answers itself. R1's framing — "If both the primary path and the fallback fail, the product premise needs rework" — is the opposite of a smoothed-to-neutral PRD.

No findings.

## Substance over theater — strong
Content is earned. §2 Users explicitly refuses persona theater ("No further persona work is warranted at these stakes; User #1's daily use is the validation instrument") — three user classes, each tied to a real decision (User #1 = validation instrument; adopters = beta channel; contributors = documented protocol + MIT). The differentiation claim is honest about its own thinness: OQ1 admits "differentiation claims stay directional ... until someone does the teardown" rather than inventing novelty. NFRs are product-specific with real thresholds, not boilerplate: NFR2 cites the 768 KB heap with a 600 KB ceiling; NFR3 cites the 32 KB/value and ~100 KB platform caps; NFR1 names 700 WPM sustained with headroom to 1000. The Vision/one-liner is specific to this product and could not swap into another PRD.

No findings.

## Strategic coherence — strong
There is a clear thesis and the features serve it. The arc — invert the topology so the watch only renders, bake timing at parse time, make resume unloseable, design the transfer protocol around documented platform failures — is consistent from §1 through the addendum. Prioritization follows the thesis, not ease: the riskiest premise-defining items (screen-on, transfer reliability) are gated first (§7), and the offset-addressed protocol is built random-access-ready on day one even though scrub/seek is deferred (FR20, "Later" in §4) — that's thesis-driven, not backlog-driven. Success criteria validate the thesis rather than measuring activity: "finishes one real book entirely on the watch" and "Resume never lies" are the right metrics for a frictionless-reading bet, and a counter-metric (battery) is named.

### Findings
- **low** Success criteria are binary/demo-shaped, not instrumented (§3) — All four goals are pass/fail events ("demo works," "finishes one book," "Published," "resume never lies"). Appropriate for the stakes, but "frictionless" has no observable proxy beyond the author's say-so. *Fix:* optionally name one lightweight signal already mentioned in the addendum — e.g. ERA crash-rate on "resume never lies" violations (addendum §4) — as the post-release validation signal.

## Done-ness clarity — adequate
Most FRs carry a testable consequence, which is strong for this dimension. FR1 anchors the ORP pivot at "~35% of text width" and requires the anchor "does not shift between words" — both verifiable. FR5/FR6 specify explicit states ("Finished" card; ~1.4 s transition card). FR14 enumerates the exact failure modes position must survive (reboot, crash, BLE drop, app restart, navigate-away). FR20 is testable down to idempotency and fingerprint-forced re-fetch. NFR5 gives a hard ≤3 s open-to-first-word bound. This is well above the bar for a hobby PRD and downstream story creation can lean on it.

The soft spots are where "graceful" stands in for a bound, and where acceptance depends on a not-yet-taken measurement.

### Findings
- **medium** "Graceful" / "gracefully" used as the acceptance bar in three places (FR7 "handled gracefully," NFR8 "degrade gracefully," R6 context) — In FR7 and NFR8 the surrounding text mostly rescues it (FR7 names scale-down-and-extend; NFR8 names "skip, refetch, or report"), so this is not broken — but the word itself carries the acceptance weight. *Fix:* in FR7, state the testable outcome directly (e.g. "no word is ever clipped; outlier words scale to fit and extend dwell") and treat the split-flag as the documented fallback.
- **medium** FR4 "readable without user interaction for a full session" has no bound on "full session" and its acceptance is gated on unresolved R1 (§5, §7) — The fallback ("dim AON + single button restores") is itself flagged as unvalidated ("the 'dim AON' floor is itself an assumption until tested," R1). So FR4's "done" is genuinely undetermined until V1. This is honestly disclosed, but an engineer cannot write a passing acceptance test today. *Fix:* none required pre-spike; after V1, replace FR4's acceptance with the measured outcome (lit-duration achieved, or the specific AON luminance/legibility floor that passed).
- **low** FR2 "varies with word length/complexity" defers the actual model to the addendum (§2 pacing algorithm) — Correct call to keep it out of the PRD, but the FR has no standalone testable threshold without the addendum. *Fix:* fine as-is given the addendum is named input to architecture; just ensure the addendum's pacing table is treated as the acceptance source.

## Scope honesty — strong
Omissions are explicit and do real work. §4 has a dedicated "Out of scope" line (Kindle/DRM, read-it-later, multi-book watch library, Hebrew/RTL) and — importantly — couples each deferral to a forward-compat constraint so it isn't silently assumed: RTL is deferred "but the word-stream format must not preclude them, see NFR7"; scrub/seek is deferred but "the transfer protocol is designed for random access from day one." Deferred decisions are attributed and dated (addendum §5 "Deferred (PM decisions, 2026-06-06)"). Rejected alternatives get their own section (addendum §6) with reasons, which is rare and valuable.

Open-items density is low and appropriate: ~7 `[ASSUMPTION]` tags, 2 Open Questions, 0 `[NOTE FOR PM]` callouts — well within tolerance for a green-light-to-build hobby PRD, especially since the riskiest assumptions are converted into named hardware gates (V1–V4) rather than left dangling.

### Findings
- **low** Assumptions are tagged inline but not collected into an index (§3, §5 FR3/FR7/FR12, NFR5) — The rubric's "Assumptions Index roundtrip" can't be checked because no index exists. At this volume it's not a real cost, but downstream tooling may expect one. *Fix:* add a short "Assumptions Index" tail section listing each `[ASSUMPTION]` with its FR/NFR ID, or explicitly note the inline tags are the canonical list.

## Downstream usability — adequate
This PRD is explicitly chain-top (§9 names it as input to architecture; the addendum is "input to architecture"), so traceability matters here. The good: FR/NFR IDs are contiguous and unique (FR1–FR28, NFR1–NFR8, R1–R6, V1–V4, OQ1–OQ2 with no gaps or dupes); cross-references resolve (FR4→R1, FR6→FR18, FR20→R2, NFR7 throughout, addendum sections cite the FRs they sit behind). Sections are largely self-contained. The gap is the absence of a Glossary, which the rubric calls out specifically — and there is mild noun drift as a result (see below).

### Findings
- **medium** No Glossary, on a PRD that feeds architecture and story creation (whole doc) — Core domain nouns (ORP / "ORP pivot" / "pivot letter" / "pivot index"; "word stream" / "timed word stream" / "word-stream format"; "chapter-transition beat" / "chapter-transition card"; "absolute word index" / "absolute position") are used with minor variation across PRD and addendum. None is ambiguous to a human reader, but a source-extracting workflow keys on exact terms. *Fix:* add a short Glossary (ORP, word stream, content fingerprint, absolute word index, chapter-transition card, gate) and use each term identically thereafter.
- **low** "chapter-transition beat" (FR6, §4) vs "chapter-transition card" (FR6 body, addendum §2/§3/§5) — Same concept, two names; the FR title and FR body even disagree. *Fix:* pick one ("card") and apply it.
- **low** "two-way sync" / "position sync" / "reconciliation" / "last-writer-wins" cluster (FR15, FR13, NFR4) — Coherent but spread; a reader extracting the sync contract must assemble it from three FRs. *Fix:* the Glossary entry for "position sync" can point to FR13–FR15 as the canonical contract.

## Shape fit — strong
The PRD is correctly shaped for what it is: a solo, capability-spec-heavy product with one guaranteed user. It does *not* over-formalize — it deliberately skips UJs (no named-protagonist user journeys), which is the right call given §2's reasoning that User #1 is the validation instrument and there is no multi-stakeholder coordination to model. For this product the FR/NFR/Risk-gate structure is load-bearing and the missing UJs are not a gap. It also doesn't under-formalize: the openness requirements (FR27/FR28) and the documented-protocol goal are treated as first-class deliverables because "publishable, contributor-friendly open source" is part of the thesis. Rigor is calibrated light (no formal acceptance section, lean personas) while the substance bar is clearly met — exactly the hobby/solo profile the rubric describes. The Flutter pivot is correctly reflected (NFR6, addendum §1) and matches the user's memory note that Flutter supersedes the brief's Kotlin decision.

No findings.

## Mechanical notes
- **ID continuity:** clean. FR1–FR28, NFR1–NFR8, R1–R6, V1–V4 (gates, referenced from §3 and §7), OQ1–OQ2 — no gaps, no duplicates. Cross-references (FR4↔R1, FR6↔FR18, FR15↔FR19/FR20, FR20↔R2, NFR7↔FR/addendum) all resolve.
- **Glossary:** absent — primary driver of the Downstream findings above.
- **Assumptions Index roundtrip:** cannot be performed (no index). Inline `[ASSUMPTION]` tags appear at §3 (battery threshold), FR3 (WPM range), FR7 (long-word handling), FR12 (touch map), NFR5 (import time). All are well-placed; only the collected index is missing.
- **Glossary drift:** "chapter-transition beat/card"; "ORP pivot/pivot letter/pivot index"; "word stream/word-stream format/timed word stream"; "absolute position/absolute word index." All low severity — human-unambiguous, machine-relevant.
- **UJ protagonists:** none present; correct for this product shape (see Shape fit), not a defect.
- **Required sections:** Why/Users/Goals/Scope/FR/NFR/Risks/Open Questions/Document Map all present and appropriate for the stakes. The deliberate omissions (Glossary, Assumptions Index, UJs, formal Acceptance section) are defensible for a hobby/solo chain-top PRD; only the Glossary omission carries real downstream cost.

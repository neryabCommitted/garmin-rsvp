# Reconciliation: Brief → PRD + Addendum

**Input:** `brief-garmin_RSVP-2026-06-05/brief.md`
**Reconciled against:** `prd.md` + `addendum.md` (prd-garmin_RSVP-2026-06-06)
**Date:** 2026-06-06

## Covered summary

The vast majority of the brief's substance is preserved across the PRD and addendum. Confirmed carried through:

- **Vision & philosophy** — "open an e-book, raise your wrist, read it without friction"; "the watch does exactly one thing well: display the next word at the right moment"; companion does the heavy lifting (PRD one-liner, intro, FR16).
- **Inverted storage/conversion topology** vs RSVP Nano (PRD §1; addendum §5 "Rejected: on-device format conversion" as the *founding architecture decision*).
- **Why this exists** — builder's itch, personal-first/product-second, one unsatisfying paid competitor + one page-based app, years of forum requests, positioning "free, open-source, book-first" (PRD §1).
- **Users** — all three cohorts (author / adopters / contributors) including the contributor enablers: clean architecture, documented protocol, permissive license (PRD §2).
- **MVP scope table** — Fenix 8 specifics, Flutter/Android-first companion + bridge plugin, EPUB first-class with .txt/.md and Kindle/DRM out (Calibre path), chapter-chunk pre-load so BLE is off playback's critical path, absolute word index (PRD §4, FR16–FR19, addendum §1/§3).
- **MVP features 1–6** — ORP/pivot (FR1), variable timing (FR2), on-watch controls (FR3/FR7/FR8), per-book resume + sync (FR12–FR14), quick/sentence rewind + "pause coasts to sentence end" (FR7/FR9), bare-bones phone library (FR21–FR25).
- **Roadmap tiers** — fast-follow chapter/paragraph nav, later (covers/metadata/typography/stats/iOS), not-in-scope (Kindle/DRM, iOS, read-it-later) (PRD §4).
- **Success criteria 1–4** — demo moment, finish one real book, published (CIQ Store + GitHub/MIT + README + documented protocol), "resume never lies" (PRD §3, FR26/FR27, FR13/NFR4).
- **All six brief risks** — memory budget (NFR2/addendum), BLE reliability-not-bandwidth (R2/addendum §3), AMOLED screen-on as #1 risk + ActivityRecording mitigation (R1/addendum §4), Monkey C newness + strict typing/matco-CI (R5/addendum §4/§6), Kotlin→Flutter pivot (addendum §1/§6; explicitly noted as a deliberate supersession, not a gap), differentiation hygiene (OQ1).
- **Technical research inputs** — the five reports are named as required source inputs (PRD §9 Document Map); their settled conclusions are absorbed into FRs/NFRs and the addendum.

The PRD/addendum also *add* substance beyond the brief (battery counter-metric, RTL/Hebrew deferral with format-preservation, explicit "Finished" state, context-on-pause, long-word handling), which is out of scope for this reconciliation but worth noting as net additions.

## Gaps (substance in the brief absent from BOTH PRD and addendum)

The gaps below are minor — all qualitative/rationale fragments rather than dropped requirements or scope. No functional requirement, constraint, success criterion, or decision was silently lost.

### Gap 1 — The "robotic" rationale for variable timing (qualitative / motivating "why")

> "longer dwell on long words and punctuation/sentence boundaries; baked into the word-stream format from day one (**flat WPM is what makes RSVP feel robotic**)."

The *requirement* (variable timing, baked phone-side) is fully covered (FR2, addendum §2). What's dropped is the experiential justification: variable timing exists because **flat WPM feels robotic** — it's a feel/quality argument, not a feature spec. This is exactly the kind of qualitative "why" a requirements structure tends to flatten. It matters because it's the design north-star that tells an implementer *why* the pacing curve must not be skippable or simplified to flat WPM "for v1" — the un-robotic feel is the point, and the rationale guards against that shortcut. Low severity but worth a one-line note in FR2 or the addendum's timing model.

### Gap 2 — ".txt/.md support is 'nearly free'" rationale (scope-cost framing)

> "**EPUB** first-class; `.txt` / `.md` support **nearly free**; Kindle formats out of scope (DRM)"

The PRD lists .txt/.md as supported import formats (FR21) but drops the brief's framing that they are *nearly free* — i.e., a near-zero-cost byproduct of the EPUB text-extraction pipeline, not separately-budgeted features. This matters for prioritization/effort estimation: it signals these formats should fall out of the tokenizer for free and should not be cut under schedule pressure or treated as additional work. Low severity (effort hint, not a requirement).

### Gap 3 — "Builder's itch / personal-first" emotional framing, partially flattened

> "Honest founding motivation: **builder's itch.** The author saw RSVP Nano, owns a Garmin Fenix 8, and wants the Garmin version to exist. This is a personal, open-source project first; a product for others second."

Mostly covered (PRD §1 keeps "builder's itch" and "personal open-source project with publish-quality ambitions"). The nuance that thins out is the explicit ordering — **"a personal project first; a product for others second"** and "**wants the Garmin version to exist.**" The PRD reframes toward "publish-quality ambitions," which subtly raises the stakes vs. the brief's deliberate stakes-lowering. This matters because it calibrates how much polish/process is warranted (the brief repeatedly right-sizes scope to "personal open-source"). Low severity — tone/calibration, not substance loss.

### Gap 4 — Contributor payoff framing: "turn 'my project' into 'a project others can adopt'" (largely covered)

> "a documented phone↔watch streaming protocol — **the things that turn 'my project' into 'a project others can adopt.'**"

The deliverables (documented protocol, README, MIT) are fully covered (FR26/FR27, success criterion 3). The dropped element is the *purpose framing*: these openness artifacts exist specifically to make the project **adoptable by others**, not as bureaucratic checkboxes. FR27 captures part of this ("documented well enough for a third party to build a compatible companion"), so this is near-fully covered — flagged only for completeness. Very low severity.

## Verdict

No substantive requirement, scope item, constraint, decision, or success criterion from the brief is missing. The only genuine omissions are small qualitative rationales — chiefly **Gap 1 (the "flat WPM feels robotic" design north-star)** and **Gap 2 (.txt/.md as "nearly free")** — both worth a one-line restoration in the PRD/addendum but neither blocking.

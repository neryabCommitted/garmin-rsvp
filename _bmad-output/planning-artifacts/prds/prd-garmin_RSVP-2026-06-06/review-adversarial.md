# Adversarial Review — PaceTurner PRD (2026-06-06)

Reviewer stance: cynical adversary. Stakes calibrated to a one-developer, free, open-source
hobby project. No enterprise ceremony demanded. But within those stakes, this PRD is graded as a
*build contract*: every FR is a promise someone (the same someone) has to keep.

**Gate verdict:** CONDITIONAL PASS — the document is unusually disciplined for a hobby PRD and
all ten addendum cross-references resolve correctly, but it carries one structural sequencing trap
(V1 can invalidate the whole premise *after* epics are built on it), several "testable-sounding"
requirements that hide unmeasurable promises, and a handful of week-one failure modes with no
home in any FR.

---

## Cross-reference audit (the renumbering check)

The FRs were recently renumbered 1–28. The addendum cites FR5, FR6, FR7, FR8, FR10, FR14, FR17,
FR20, FR26, FR27. I checked every one against its intended target:

| Citation | Addendum context | PRD FR title | Verdict |
|---|---|---|---|
| FR5 | "Nano's silent end-of-book… gaps to fix" | Explicit ending | ✓ correct |
| FR6 | chapter-transition card / pre-fetch trigger | Chapter-transition beat | ✓ correct |
| FR7 | scale-down-and-extend for long words | Long-word handling | ✓ correct |
| FR8 | two-stage pause | Play/pause, two-stage | ✓ correct |
| FR10 | sentence rewind | Sentence rewind | ✓ correct |
| FR14 | persistence list includes navigate-away | Eager persistence | ✓ correct |
| FR17 | extraction pre-filter behind it | Phone does the heavy lifting | ✓ correct |
| FR20 | content fingerprint | Resilient transfer | ✓ correct |
| FR26 | error posture | Import failures survivable | ✓ correct |
| FR27 | release machinery | Published artifacts | ✓ correct |

**Result: zero broken cross-references.** All ten survive the renumbering. The PRD's own internal
references (FR4→R1, FR6→FR18, FR15 cited from FR10/FR19, FR20→R2, R6→addendum §2) also all point at
the right targets. Credit where due — this is the one place I expected to find rot and didn't.

---

## CRITICAL

### C1 — V1 (screen-on) is a premise-killing gate wired in series, but the PRD lets architecture/epics build on top of it concurrently.

R1 says, in plain text: *"If both the primary path and the fallback fail, the product premise needs
rework."* That is not a risk — that is a **go/no-go on the entire product**. The mitigation
(ActivityRecording.Session) is self-described as *medium confidence*, and the fallback (dim AON at
~10% luminance) is *also* an untested assumption that "may render a single bright word illegible."

So the honest dependency graph is: **almost every watch-side FR (FR1, FR2, FR4, FR6, FR8–FR12) is
conditional on a coin-flip that hasn't been flipped.** FR4 even bakes the unvalidated fallback into
its own acceptance criteria ("display drops to dim always-on and a single button press restores
it"). If V1's fallback fails, FR4 is unsatisfiable *as written* and the PRD is internally
contradictory after the fact.

The document acknowledges "validate before architecture hardens" (R1, addendum §4) — good — but it
provides **no instruction that V1/V2 must be closed before epic generation or architecture design
proceeds.** A reader handing this to the architect skill tomorrow gets no signal to stop. For a
one-developer project this is the single most expensive mistake available: building the stream
format, protocol, companion importer, and sync engine, then discovering the watch can't stay lit.

**Fix:** Add an explicit phase gate to §7 or §4: "No epic depending on FR1/FR2/FR4 is authored
until V1 (incl. fallback legibility) and V2 pass on hardware. Spike first; PRD-driven build second."
Right now the sequencing discipline lives only in the author's head, not in the contract.

---

## HIGH

### H1 — "Resume never lies" is a goal and an NFR, but no FR actually guarantees it under the failure that the addendum admits silently discards state.

§3 Goal 4 and NFR4 make an absolute promise: *"Reading position is never lost, full stop."* FR14
enumerates the survival cases (reboot, crash, BLE drop, restart, navigate-away). But addendum §4
("Carousel hazard") concedes: *"navigating from an activity app to the watch-face/glance carousel
**stops the session and discards state**."* The mitigation is FR14's eager persistence + debounce.

Here's the gap: FR14 persists "on every pause, app exit, chunk boundary, and disconnect" plus a
~15 s debounce while playing (addendum §4). The carousel jump is none of those events — it's an
OS-initiated kill. **If the user swipes to the carousel mid-word, 0–15 s of playback position can be
lost** (whatever accumulated since the last debounce flush). For RSVP at 700 WPM that's up to ~175
words. "Resume never lies" then lies by up to a sentence or three.

This is the exact daily-use case (User #1, the validation instrument). The goal is absolute; the
mechanism is best-effort with a 15 s window. **Either tighten the promise** ("position is never lost
beyond the last N seconds of playback") **or add an FR** requiring a force-persist hook on the
session-stop / app-suspend lifecycle callback (if Garmin fires one before kill). As written, the
headline goal overclaims what the FRs deliver.

### H2 — FR4 "a full session" is presented as testable but is undefined and self-contradicting with the battery counter-metric.

FR4: "the display stays readable without user interaction **for a full session**." What is a
session? Goal 2 implies "one real book." R4/§3 measure "a 1-hour reading session." NFR1 says
"a full session." Three different implicit durations. A tester cannot write a pass/fail for
"full session" without a number. **Pick one** (suggest: "≥60 min continuous, screen lit, no
interaction" to align with R4) and reference it everywhere.

Worse, FR4's fallback ("dim always-on") interacts with R4's ≤10%/hour battery target: AON for an
hour may or may not hit budget, and the PRD never says which mode the 10%/hour applies to. Is the
target for full-brightness screen-on (the primary path) or the dim fallback? These have very
different draw. The counter-metric is currently unmeasurable because the *mode under test* is
unspecified.

### H3 — A product decision is hiding inside an `[ASSUMPTION]` in FR15 (sync reconciliation).

FR15's `[ASSUMPTION] Timestamped last-writer-wins`. This is not a parameter to tune later — it is
**the** correctness rule for the product's headline feature ("resume never lies"). Tagging it
`[ASSUMPTION]` signals "we might change this," but the entire two-device durability story, FR13's
absolute-index coordinate, and the rejection of max-index (addendum §6) are already built on LWW.
Clock skew between phone and watch (no NTP guarantee on either; watch RTC drifts) can make
last-writer-wins pick the *wrong* writer and silently roll a reader backward or forward. That's a
"resume lies" event caused by the chosen reconciliation rule itself.

This deserves a real requirement, not an assumption tag: define the tiebreaker when timestamps are
within clock-skew tolerance, and state whether watch or phone time is authoritative. The decision is
already made (addendum §6 calls max-index "rejected"); the `[ASSUMPTION]` framing is dishonest about
how load-bearing it is. Also note the latent contradiction: FR15 rejects max-index "which would
fight deliberate rewinds," yet LWW + clock skew can *also* fight a deliberate rewind if the rewinding
device has the slower clock.

### H4 — Scope vs. one-developer capacity: 28 FRs + 8 NFRs across three codebases (Monkey C watch app, Flutter companion, binary protocol) in a new language, with a custom bitmap font and DIY EPUB extraction, is an aggressive MVP for one person.

I won't moralize about ambition, but the contract should be honest. The MVP scope line (§4)
silently includes: custom binary word-stream format, custom bitmap font with per-glyph width
precompute and ORP geometry on a round display, DIY Unicode-aware tokenizer (no library exists per
addendum), two-device timestamped sync, idempotent offset-addressed BLE protocol with fingerprinting,
context-on-pause scroll view, AND a Flutter importer with an "ugly-EPUB fixture corpus." Each of
those is a project. R5 ("Monkey C is new") is rated MEDIUM and "mitigated by strict typing" — strict
typing prevents null crashes, it does not buy domain experience with CIQ's power/graphics/BLE model.

The PRD already does the right thing by deferring phantom words, scrub/seek, and full library mgmt.
But there is no stated **cut line under schedule pressure** — no "if forced, these MVP FRs degrade to
fast-follow." For a solo project, "what gets dropped when V1 eats three weeks" is a requirement, not
an afterthought. Recommend marking 2–3 MVP FRs as "demote-able" (candidates: FR11 context-on-pause,
FR6 chapter card, FR7 long-word scaling — none block the core demo moment).

---

## MEDIUM

### M1 — Missing failure-mode FRs a real user hits in week one.

The PRD covers import failure (FR26), transfer failure (FR20), and crash posture (NFR8). But several
obvious week-one failures have no FR:

- **Active book deleted/re-imported while resident on the watch.** FR25 (Remove) + FR24 (one active
  book) + FR20 (fingerprint forces re-fetch) gesture at this, but no FR states what the *watch* shows
  when its active book vanishes or its fingerprint goes stale mid-read. "Clean re-fetch" with the
  phone disconnected (FR19) = stranded reader with no stated UX.
- **Watch storage full / book too large for the 32 KB-value, ~100 KB-total caps (NFR3).** A long
  novel's resident chapter plus next-chapter pre-fetch against a ~100 KB total app-storage cap is
  not obviously safe, and no FR says what happens when a chapter won't fit. Addendum §3 says
  ">32 KB chapters split into buckets," but the *total* budget under FR18's two-chapter residency is
  never reconciled against NFR3. Potential NFR2/NFR3 vs FR18 contradiction.
- **First-ever launch with no book / phone never paired.** No empty-state FR for the watch.
- **WPM at 900 vs the 50 ms timer floor.** NFR1 claims headroom to 1000 WPM; addendum §4 cites a
  50 ms platform floor (= 1200 WPM ceiling for a 0-bonus word, but punctuation/long words add dwell).
  Fine — but "drift-free at 700, headroom to 1000" (NFR1) vs FR3's 900 WPM cap vs "headroom past
  1000" (addendum) are three different speed claims. Pick the contract number.

### M2 — NFR5 buries a second, unrelated, unvalidated requirement inside an `[ASSUMPTION]`.

NFR5 is "open to first word ≤3 s," then `[ASSUMPTION] importing a 100k-word novel ≤30 s on phone
without blocking UI." Two different requirements (watch responsiveness vs phone import throughput)
share one NFR, and the second is the one with real risk (DIY extraction + tokenization + binary
packing + isolate, per addendum §1/§2). It deserves its own NFR with its own validation, not a
parenthetical assumption on an unrelated latency target.

### M3 — The battery counter-metric is explicitly "not a promise" but is also the only quantified guardrail against the product being unusable.

§3: ≤10%/hour is a `[ASSUMPTION]` and a "validation gate, not promise." Fair for a hobby project.
But combined with R4 (MEDIUM, unquantified) and the screen-on strategy being the *whole* battery
question, "10%/hour" with no fallback plan if the real number is, say, 25%/hour means there's no
stated decision rule for "battery makes this not worth shipping." Compare R1, which *does* state the
no-go ("premise needs rework"). R4 should state its equivalent threshold-of-abandonment, or admit
there isn't one.

### M4 — FR2/NFR1 "drift-free" is testable; the variable-timing correctness is not.

FR2 bakes per-word dwell from a 12-bonus pacing algorithm (addendum §2) tuned for *different
hardware* ("expect recalibration on Fenix 8, medium risk"). There is no FR or NFR defining what
"correct" timing *is* or how you'd know it regressed — it's pure feel. That's acceptable for a feel
feature, but then FR2 should not imply objective correctness. The one objectively-testable part
(sentence-end / abbreviation flagging, on which FR8 and FR10 depend per addendum §2) has no FR
asserting an accuracy bar. If abbreviation detection mis-flags "Dr." or "U.S." as sentence ends,
two-stage pause and sentence rewind land on the wrong boundary — a visible bug with no acceptance
criterion.

---

## LOW

### L1 — Goal 3 / FR27 release path depends on Garmin developer verification, an external party with unknown latency.

FR27 correctly notes verification is "a store precondition since Feb 2025" and addendum §4 says
"complete early." Good. But Goal 3 ("Published") is partly hostage to Garmin's review/verification
turnaround, which the solo dev does not control. Not a defect — just flag that "Published" is the
one success criterion with an external dependency, and the PRD treats it as fully in scope.

### L2 — OQ1 (competitor teardown deferred) quietly undercuts the positioning in §1.

§1 leans on "tried, found unsatisfying" and "free, open-source, book-first" as the differentiator,
while OQ1 admits "what the existing paid CIQ RSVP reader concretely gets wrong remains uncaptured."
For a hobby project, fine to defer — but §1 states the competitor was "tried, found unsatisfying" as
if evaluated, while OQ1 says the teardown hasn't happened. Mild internal tension between the
confident framing and the open question. Harmless to the build; relevant only to the store listing.

### L3 — "First-class" EPUB vs the admitted reality of EPUB-in-the-wild (R6).

FR22 calls EPUB "first-class"; R6 (MEDIUM) and addendum §2 make clear real EPUBs are "malformed,
obfuscated, footnote-riddled." The honest MVP claim is "EPUB best-effort with a graceful failure
path," not "first-class." Minor wording, but a build contract that promises first-class EPUB invites
the author to over-invest in extraction robustness the MVP doesn't need (User #1 controls his own
DRM-free library).

### L4 — NFR2 number drift.

NFR2 says the Fenix 8 watch-app budget is 768 KB; addendum §1 says 786,432 B (= 768 KiB). Consistent,
just flag the KB-vs-KiB to avoid a future "is it 768,000 or 786,432" off-by-2% argument when
measuring against the ≤600 KB ceiling. Trivial.

---

## Severity counts

- **Critical:** 1 (C1)
- **High:** 4 (H1–H4)
- **Medium:** 4 (M1–M4)
- **Low:** 4 (L1–L4)
- **Cross-reference defects:** 0 of 10 addendum citations — all correct.

## Bottom line

This is a genuinely well-built PRD for its stakes — the cross-references survived renumbering,
the risk gates are real and self-aware, and the scope deferrals are disciplined. The one thing that
can actually waste the developer's life is **C1**: nothing in the document stops architecture and
epics from being built on a premise (screen-on) that R1 itself says might require "premise rework."
Close that sequencing gate, make "resume never lies" honest about the carousel/debounce window (H1),
and promote the two load-bearing `[ASSUMPTION]`s that are really decisions (H3 sync rule, NFR5 import
budget). Everything else is polish.

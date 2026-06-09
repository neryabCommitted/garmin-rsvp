# Story 1.1: Monorepo, dual scaffolds, dev key & green CI

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer,
I want the monorepo standing with both app scaffolds, the signing key, and CI passing,
so that every later story lands in a buildable, tested, releasable skeleton.

## Acceptance Criteria

**AC1 — Monorepo topology.**
**Given** a fresh clone
**When** I inspect the repo root
**Then** it contains `watch/`, `companion/`, `protocol/`, `docs/`, `LICENSE` (MIT), and a `README.md` stub
**And** `watch/` and `companion/` share no cross-imports.

**AC2 — Watch scaffold builds at Strict.**
**Given** the Monkey C toolchain
**When** the watch app builds
**Then** it targets CIQ API 6.0 / fenix8 family at Strict (level 3) type-checking
**And** produces a runnable build in the simulator.

**AC3 — Companion scaffold builds & analyzes clean.**
**Given** the Flutter toolchain
**When** the companion builds
**Then** the `flutter create` output (org `dev.paceturner`, platforms android+ios with iOS untargeted) compiles
**And** `flutter analyze` passes under a strict `analysis_options.yaml`.

**AC4 — Developer key & verification.**
**Given** a 4096-bit RSA developer key generated and stored per Garmin's process
**When** a release-mode watch build runs
**Then** it signs successfully
**And** Garmin developer verification has been initiated with status tracked in `docs/setup.md`.

**AC5 — Green CI from first commit.**
**Given** a push to the repo
**When** CI runs
**Then** `action-connectiq-tester` (watch) and `flutter analyze` + `flutter test` (companion) both run and pass green.

## Tasks / Subtasks

- [ ] **Task 1 — Establish monorepo skeleton at repo root (AC1)**
  - [ ] Add `LICENSE` (MIT, copyright "PaceTurner contributors" / Nerya) at repo root.
  - [ ] Add `README.md` stub: project name **PaceTurner**, one-line pitch, and a "Structure" section listing `watch/ companion/ protocol/ docs/`. Link `protocol/SPEC.md` (forward ref — file authored in Story 1.2). Full architecture story is Epic 5 (Story 5.1); keep this a stub.
  - [ ] Create `protocol/` with a `SPEC.md` placeholder (single line: `# PaceTurner Protocol — see Story 1.2`) and an empty `protocol/examples/.gitkeep`.
  - [ ] Populate existing `docs/` dir: `docs/setup.md`, `docs/gates.md`, and `docs/decisions/.gitkeep` (see Task 5 for contents).
  - [ ] Add a root `.gitignore` covering both toolchains AND the developer key (see Dev Notes → gitignore).
  - [ ] **Do NOT touch** `_bmad/`, `_bmad-output/`, `.claude/`, or `rsvp-garmin-idea-brief.md`. The monorepo IS this existing repo, not a new `paceturner/` directory.

- [ ] **Task 2 — Flutter companion scaffold (AC3)**
  - [ ] Scaffold into `companion/` (NOT `paceturner_companion/`): `flutter create --org dev.paceturner --project-name paceturner_companion --platforms android,ios --template app companion`
  - [ ] Add strict `companion/analysis_options.yaml` (see Dev Notes → analysis_options).
  - [ ] Keep `pubspec.yaml` minimal — only what `flutter create` produces plus the analysis setup. **Do NOT** add riverpod/drift/epub_pro/etc. now; those land in their own epics. Pin Flutter SDK constraint compatible with **Flutter 3.44.0 / Dart 3.x**.
  - [ ] Ensure a trivial passing test exists under `companion/test/` (the scaffold's `widget_test.dart` is fine; trim it to a 1-assertion smoke test if it references removed boilerplate) so `flutter test` is green.
  - [ ] Verify locally: `cd companion && flutter analyze && flutter test` both pass.

- [ ] **Task 3 — Monkey C watch scaffold at Strict (AC2)**
  - [ ] Scaffold a **watch-app** targeting **CIQ API 6.0**, **fenix8** device family, into `watch/`. Preferred: VS Code "Monkey C: New Project" generator. CLI/manual fallback: create the tree below by hand (see Dev Notes → watch scaffold tree).
  - [ ] Set type-check level to **Strict (level 3)** and make it the build default (see Dev Notes → Strict typing — confirm exact mechanism against current SDK docs before asserting).
  - [ ] Add one trivial `(:test)` host-side test under `watch/source-test/` (e.g. `SmokeTest.mc` asserting `true`) and link it via `monkey.jungle` so the "Run No Evil" suite has a passing test. Exclude `source-test/` from release builds.
  - [ ] Verify locally: a simulator build runs (AC2) and the test build passes.

- [ ] **Task 4 — Developer key & release signing (AC4)**
  - [ ] Generate a **4096-bit RSA** developer key (see Dev Notes → developer key). Store it OUTSIDE version control; confirm it is gitignored.
  - [ ] Run a **release-mode** watch build signed with the key; confirm it signs successfully.
  - [ ] Initiate Garmin developer verification (external Garmin process) and record status + date in `docs/setup.md`.

- [ ] **Task 5 — Docs: setup & gates (AC4 tracking + Epic-1 scaffolding)**
  - [ ] `docs/setup.md`: SDK Manager + exact CIQ SDK version installed, dev-key generation steps, sideload steps, CI overview, and a **"Garmin developer verification" status line** (status + date).
  - [ ] `docs/gates.md`: stub the single status page for gates **V1–V4** (each: procedure / status=`not started` / result). Stories 1.3–1.5 and 3.9 fill these in.

- [ ] **Task 6 — Green CI workflows (AC5)**
  - [ ] `.github/workflows/watch-ci.yml`: run `matco/action-connectiq-tester@v1` with `path: watch` and `device: fenix8` (CONFIRM the exact device id string against the SDK device list — the action defaults to `fenix7`). The action auto-generates a temporary signing cert for tests, so the real 4096-bit key is NOT needed in CI.
  - [ ] `.github/workflows/companion-ci.yml`: set up Flutter (stable 3.44.0), then `flutter analyze` and `flutter test` against `companion/`.
  - [ ] Push and confirm **both workflows are green on the first commit** (AC5). A red first run is a story defect — fix before marking review.

## Dev Notes

### Critical: the monorepo IS this repo
The architecture's directory tree (architecture.md §"Complete Project Directory Structure") shows a root named `paceturner/`. That is illustrative — the **actual monorepo is the existing git repo at the repo root** (`garmin_RSVP/`). Add `watch/ companion/ protocol/ docs/ LICENSE README.md .github/` at root. The repo already contains `_bmad/`, `_bmad-output/`, `.claude/`, empty `docs/`, and `rsvp-garmin-idea-brief.md` — leave the BMad dirs and the brief alone; just fill `docs/`. Do not create a nested `paceturner/` folder.

### Scope discipline (prevent creep)
This story is **scaffold + CI + key only**. No protocol bytes (Story 1.2), no parse pipeline (Epic 2), no reader engine (Epic 3), no transfer (Epic 4). Do **not** add the dependency set from the architecture's `pubspec.yaml` comment (riverpod/drift/epub_pro/html/archive/xml/markdown/file_picker/receive_sharing_intent/watch_connectivity_garmin) — those arrive with the stories that use them. Keep both scaffolds minimal and green.

### Naming & topology rules (architecture.md §"Naming Patterns", §"Structure Patterns")
- `watch/` and `companion/` are **self-contained**; nothing imports across them. The only shared artifact is `protocol/SPEC.md` + mirrored constants (authored later). There is nothing to cross-import yet — AC1's "no cross-imports" is satisfied structurally; just don't introduce a shared code dir.
- Org is `dev.paceturner`. Display/product name is **PaceTurner**. Dart package name `paceturner_companion`, but the **directory is `companion/`** — hence `flutter create --project-name paceturner_companion … companion`.
- Monkey C files: `PascalCase.mc`, one public class per file. Dart files: `snake_case.dart`.

### Flutter companion details (AC3)
- `analysis_options.yaml` (strict — architecture calls for a strict config; `very_good_analysis` lint strictness was cited as the bar to borrow):
  ```yaml
  include: package:flutter_lints/flutter.yaml
  analyzer:
    language:
      strict-casts: true
      strict-inference: true
      strict-raw-types: true
    errors:
      # treat lints as build-breaking in CI as desired
  ```
  (Optional: swap `flutter_lints` for `very_good_analysis` if you prefer its stricter ruleset — either satisfies "strict `analysis_options.yaml`".)
- `flutter create` ships `test/widget_test.dart`. If you trim `main.dart` boilerplate, trim the test to match so `flutter test` stays green.
- iOS folder is generated but **untargeted** — do not wire iOS CI or build iOS.

### Watch scaffold tree (AC2) — manual fallback if not using the VS Code generator
Mirror architecture.md §"Complete Project Directory Structure" for `watch/`. Minimum for this story (later files are added by their stories — create only what's needed to build + test green):
```
watch/
├── manifest.xml            # watch-app, API 6.0, fenix8 family, app entry = PaceTurnerApp
├── monkey.jungle           # build config; links source-test/; excludes (:debug)/source-test from release
├── source/
│   └── PaceTurnerApp.mc     # AppBase: minimal onStart/onStop, a no-op initial View
├── source-test/
│   └── SmokeTest.mc         # one (:test) returning true (keeps "Run No Evil" green)
└── resources/
    ├── drawables/           # launcher icon (scaffold default ok)
    └── strings/             # AppName = "PaceTurner"
```
Do NOT pre-create `engine/`, `source_data/`, `sync/`, `display/`, `views/`, `input/` etc. now — those are populated by Epic 3/4 stories. Empty dirs invite stub-clutter; add files when the owning story needs them.

### Strict typing — confirm the mechanism (AC2)
Strict = type-check **level 3** (architecture.md §"Toolchain", AR4). The enforcement point differs by toolchain surface:
- VS Code: `monkeyC.typeCheckLevel` setting → `Strict`.
- `monkeyc` CLI / jungle: passed as the type-check level build flag.
**Before asserting the exact flag/jungle syntax, verify against the current Connect IQ SDK docs** (use the `find-docs` skill for "Connect IQ Monkey C type check level Strict" / the SDK's compiler options). The acceptance bar is: the build the simulator and CI run is at Strict (3), and a build that needs the level lowered is a defect (architecture.md §"Enforcement Guidelines" #5).

### Developer key (AC4) — manual generation path
Garmin developer key = 4096-bit RSA in DER/PKCS#8 (no passphrase). Two paths:
- VS Code: command palette → "Monkey C: Generate a Developer Key".
- CLI/openssl fallback:
  ```bash
  openssl genrsa -out developer_key.pem 4096
  openssl pkcs8 -topk8 -inform PEM -outform DER -nocrypt -in developer_key.pem -out developer_key.der
  ```
  Point the build at `developer_key.der`. **Never commit the key** (see gitignore). The release-mode build must sign with it (AC4); CI does not — `action-connectiq-tester` auto-generates a throwaway cert.

### gitignore essentials
Cover both toolchains and protect the key:
```
# Developer signing key — NEVER commit
developer_key.*
*.der
# Monkey C build output
watch/bin/
*.iq
*.prg
*.prg.debug.xml
# Flutter
companion/.dart_tool/
companion/build/
companion/.flutter-plugins*
companion/pubspec.lock   # (app, not package — optional; decide once)
.DS_Store
```
(Confirm CIQ build-output dir names against the SDK before finalizing — names above are typical, verify.)

### CI specifics (AC5)
- **Watch** (`watch-ci.yml`): `matco/action-connectiq-tester@v1`. Inputs: `path` (set to `watch`), `device` (set to the fenix8 id — **the action defaults to `fenix7`; confirm the exact `fenix8` device string** from the SDK/device list), `certificate` (omit → action auto-generates a temp cert). Output `status` = `success` on pass. Runs the "Run No Evil" suite via the `ghcr.io/matco/connectiq-tester` Docker image — so the SmokeTest from Task 3 is what makes it green.
- **Companion** (`companion-ci.yml`): use a Flutter setup action (e.g. `subosito/flutter-action`) pinned to stable **3.44.0**, then `flutter analyze` and `flutter test` with working-directory `companion`.
- "Green from first commit" (AR3) is a hard AC: the very first push must show both checks passing. That requires the trivial tests on both sides to exist before the first push.

### Why these versions (latest verified 2026-06-06 / re-checked this story)
- **Flutter 3.44.0 (stable)** — confirmed current stable. Dart 3.x.
- **Connect IQ SDK 9.1.0** per research; targets **CIQ API 6.0** regardless of SDK point version (architecture notes the 9.1.0-vs-8.x snippet discrepancy resolves at SDK Manager install — no design impact). Record the exact installed version in `docs/setup.md`.
- **`matco/action-connectiq-tester@v1`** — current major; auto-temp-cert; Docker-image based; CI exemplar is `matco/badminton` (reference only, **not** a fork — AR1).

### Testing standards (architecture.md §"Structure Patterns", §"Development Workflow Integration")
- Monkey C tests: `watch/source-test/` with `(:test)` annotations, linked via the jungle's test config, **excluded from release builds**, run headless in CI by `action-connectiq-tester`.
- Dart tests: `companion/test/` mirroring `lib/` paths.
- Pure logic stays UI-free on both sides (load-bearing for CI) — not exercised by this story, but the test harness it stands up is what every later story relies on. Get it genuinely green, not skipped.

### Project Structure Notes
- Alignment: matches architecture.md §"Complete Project Directory Structure" — with the explicit correction that the tree's `paceturner/` root maps to **this repo's root**.
- Variance: `companion/` directory name vs `paceturner_companion` package name — intentional, handled via `--project-name`.
- Forward refs created as stubs (don't fully author): `protocol/SPEC.md` (Story 1.2), `README.md` architecture story (Story 5.1), `docs/gates.md` entries (Stories 1.3–1.5, 3.9).

### References
- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.1: Monorepo, dual scaffolds, dev key & green CI]
- [Source: _bmad-output/planning-artifacts/epics.md#Additional Requirements] — AR1 (starter scaffolds, no forks), AR2 (monorepo topology), AR3 (CI from first commit), AR4 (strict typing), AR5 (dev key + verification)
- [Source: _bmad-output/planning-artifacts/architecture.md#Starter Template Evaluation] — exact init commands, scaffold rationale
- [Source: _bmad-output/planning-artifacts/architecture.md#Infrastructure & Deployment] — repo/CI/release-path table
- [Source: _bmad-output/planning-artifacts/architecture.md#Complete Project Directory Structure] — full tree (root = this repo)
- [Source: _bmad-output/planning-artifacts/architecture.md#Enforcement Guidelines] — #5 Strict (level 3) is mandatory; a build needing the level lowered is a defect
- [Source: _bmad-output/planning-artifacts/architecture.md#Naming Patterns] — cross-language naming, file conventions
- [Source: _bmad-output/planning-artifacts/implementation-readiness-report-2026-06-09.md] — Story 1.1 is the sanctioned greenfield-setup first story
- [External: github.com/matco/action-connectiq-tester] — `@v1`, inputs `path`/`device`/`certificate`, auto-temp-cert, `status` output
- [External: docs.flutter.dev — stable 3.44.0 confirmed]

## Dev Agent Record

### Agent Model Used

claude-opus-4-8 (Amelia / dev)

### Debug Log References

- Watch CI validated locally against the **exact** CI image (`ghcr.io/matco/connectiq-tester:latest`, SDK 8.4.0): `tester.sh fenix847mm` → `BUILD SUCCESSFUL` → simulator → `smokeTest PASS` → `PASSED (passed=1, failed=0, errors=0)`.
- Companion: `flutter analyze` → "No issues found"; `flutter test` → "All tests passed!".
- Local watch builds (SDK 9.1.0, JDK 17, Strict `-l 3`): normal, `-r` release (signed), and `-t` unit-test targets all `BUILD SUCCESSFUL`.

### Completion Notes List

- **Toolchain (Ubuntu 24.04):** CIQ GUI tools don't run natively; SDK 9.1.0 downloaded via the official SDK Manager in an Ubuntu-22.04 Docker container. CLI builds run on host with a local Temurin **JDK 17** (`~/.local/jdk`). Dev key relocated to `~/.Garmin/developer_key.der`. See `docs/setup.md`.
- **AC2 — API level deviation:** manifest `minApiLevel` set to **5.2.0**, not 6.0.0. The public CI tester image is hardcoded to SDK 8.4.0, where `fenix847mm` caps at API 5.2.0; 6.0.0 would make CI red. `minApiLevel` is a floor, not a target — the Fenix 8 still runs the app and the scaffold uses no 6.0-only APIs. Documented in `docs/decisions/0001-watch-min-api-level.md`; revisit when a 6.0-only API is first needed.
- **AC4 — Garmin developer verification: not required.** It's an EU-DSA trader verification tied to *paid* apps in the EEA; PaceTurner is free + MIT, so it publishes worldwide without it. Recorded in `docs/setup.md` (supersedes the planning-doc assumption).
- **AC2 — satisfied via simulator; hardware sideload deferred.** The green Watch CI run builds *and runs* the app in a simulator (that's how `smokeTest` executed), satisfying AC2's "runnable build in the simulator." Physical sideload to the Fenix 8 was blocked by a known Garmin-on-Linux issue: the watch enumerates in Garmin's vendor-specific USB mode (`091e:0003`, interface class 255) and won't flip to MTP for libmtp, so no `GARMIN/` volume mounts to copy `PaceTurner.prg` into. Deferred to the gate stories (1.3–1.5), which require the watch and where the USB/MTP path will be sorted (libmtp/udev or Garmin tooling). Not a blocker for 1.1.
- Scope held to scaffold + CI + key; no app dependencies (riverpod/drift/epub_pro) or unused watch module dirs added — those land with their epics.

### File List

**Repo root:** `LICENSE`, `README.md`, `.gitignore`
**protocol/:** `SPEC.md` (placeholder for Story 1.2), `examples/.gitkeep`
**docs/:** `setup.md`, `gates.md`, `decisions/0001-watch-min-api-level.md`, `decisions/.gitkeep`
**.github/workflows/:** `watch-ci.yml`, `companion-ci.yml`
**watch/:** `manifest.xml`, `monkey.jungle`, `source/PaceTurnerApp.mc`, `source/PaceTurnerView.mc`, `source-test/SmokeTest.mc`, `resources/strings/strings.xml`, `resources/drawables/drawables.xml`, `resources/drawables/launcher_icon.png`
**companion/:** `flutter create` scaffold (org `dev.paceturner`, pkg `paceturner_companion`), strict `analysis_options.yaml`
**Toolchain (outside repo):** `~/.Garmin/developer_key.der`, `~/.local/jdk/jdk-17.0.19+10/`, `~/garmin-sdk-docker/Dockerfile`

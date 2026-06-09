---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments:
  - '_bmad-output/planning-artifacts/briefs/brief-garmin_RSVP-2026-06-05/brief.md'
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'Monkey C development landscape (language, tooling, testing, newcomer pitfalls)'
research_goals: 'Map the Monkey C learning curve for an experienced developer new to the language: language semantics and gotchas, VS Code tooling and simulator workflow, testing/CI options, debugging story, and community resources'
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

This report maps the Monkey C development landscape for an experienced mobile developer (Kotlin/Dart background) who is new to the language and building an RSVP speed-reader watch app for the Garmin Fenix 8 (Connect IQ API 6.x). It covers the language and its type system, the current Connect IQ SDK and toolchain, the VS Code workflow and debugging story, testing and CI options, store publishing, and — most importantly — the newcomer pitfalls that will bite in week 1 versus month 2. The framing throughout is practical: what is genuinely different from a modern mobile stack, where the rough edges are, and how to move fast without falling into the traps that the Garmin developer forum is full of.

**Methodology.** Research was conducted in June 2026 using web search and direct source fetches, prioritizing primary sources (Garmin's official `developer.garmin.com` documentation, the Garmin Connect IQ developer forum, and the official `garmin/connectiq-apps` GitHub repository) and corroborating with high-quality community sources (third-party tooling repos, tutorial sites, and developer blogs). Note: several official `developer.garmin.com` pages render as JavaScript single-page apps and returned only navigation chrome to the fetch tool; for those topics the substance was triangulated from forum posts, the Garmin developer blog, community tutorials, and search-result snippets, and is flagged with appropriate confidence levels. Critical claims (memory limits, SDK version, type-check levels, CI tooling) were verified against at least two independent sources where possible.

**Key findings at a glance.** Monkey C is an object-oriented, reference-counted, historically duck-typed language that since Connect IQ 4 offers an opt-in gradual static type system ("Monkey Types") with four strictness levels — turning it on early is the single highest-leverage decision for a newcomer because it converts a class of silent runtime crashes into compile-time errors. The dominant risk is not language syntax (which a Kotlin/Dart developer will find familiar) but the embedded-systems reality underneath it: tight per-app memory budgets, a reference-counting GC that leaks on cycles (the simulator detects cycles but will not collect them), a watchdog that kills slow `onUpdate` callbacks, and a per-device build matrix. The tooling is a competent official VS Code extension (build/run/debug with breakpoints, variable inspection, and a profiler against a desktop simulator) meaningfully augmented by the community `markw65` Prettier/optimizer extension. Testing exists (the `Toybox.Test` framework with `:test` annotations, runnable headlessly), and a turnkey GitHub Actions path exists via `matco/action-connectiq-tester`. For this project specifically, the Fenix 8 is one of the more generously-resourced targets and the `Toybox.Communications` BLE companion-messaging API is exactly the integration surface the RSVP streaming design needs.

---

## Technical Research Scope Confirmation

**Research Topic:** Monkey C development landscape — language, tooling, testing, newcomer pitfalls
**Research Goals:** Map the learning curve for an experienced developer new to Monkey C: language semantics and gotchas, type system, VS Code tooling and simulator workflow, testing/CI options, debugging story, and community resources.

**Technical Research Scope:**

- Architecture Analysis - CIQ app lifecycle, Monkey C runtime model
- Implementation Approaches - idiomatic patterns, common newcomer pitfalls
- Technology Stack - SDK versions, VS Code extension, simulator, monkeyc compiler
- Integration Patterns - build system, CI pipelines, store submission workflow
- Performance Considerations - typed vs untyped Monkey C, memory profiling tools

**Research Methodology:**

- Current web data with rigorous source verification
- Multi-source validation for critical technical claims
- Confidence level framework for uncertain information
- Comprehensive technical coverage with architecture-specific insights

**Scope Confirmed:** 2026-06-06

<!-- Content will be appended sequentially through research workflow steps -->

---

## Technology Stack Analysis

### The Monkey C language

Monkey C was introduced by Garmin in 2014 as an object-oriented, memory-managed, **duck-typed** language designed specifically for resource-constrained wearables. The compiler historically performed no compile-time type checking, which makes code flexible but pushes type errors to runtime — the classic source of "Unexpected Type" crashes on real hardware. _Source: https://developer.garmin.com/connect-iq/monkey-c/monkey-types/ (accessed 2026-06-06)_ _(Confidence: High)_

For a developer coming from **Kotlin or Dart**, the surface syntax is familiar: C-style braces, `class`/`module` declarations, `var`/`const`, `function`, inheritance, and a standard library (the **Toybox** API) organized into modules. The mental-model differences that matter:

- **Duck typing by default, optional static typing.** Without Monkey Types enabled, any variable can hold any type and method calls are resolved at runtime. This is the opposite of Kotlin's compiler-enforced types and will feel unsafe. _Source: https://developer.garmin.com/connect-iq/monkey-c/monkey-types/ (accessed 2026-06-06)_ _(Confidence: High)_
- **`module` vs `class`.** Toybox is organized into modules (namespaces) such as `Toybox.Graphics`, `Toybox.WatchUi`, `Toybox.Communications`, `Toybox.Application`, `Toybox.Lang`. Modules are singletons/namespaces; classes are instantiable. _Source: https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/AppBase.html (accessed 2026-06-06)_ _(Confidence: High)_
- **Symbols and `has`.** Monkey C has a first-class symbol type (`:foo`) used for annotations (e.g. `:test`) and for runtime capability checks via the `has` operator — the idiomatic mechanism for API-level gating across device/firmware variation (see Implementation Research). _Source: https://developer.garmin.com/connect-iq/monkey-c/annotations/ (accessed 2026-06-06)_ _(Confidence: High)_
- **No generics (historically).** Monkey C does not provide user-defined generic types the way Kotlin/Dart do; typed containers are expressed via type annotations on the built-in `Array` and `Dictionary` (e.g. `Array<String>`) rather than user-authored generic classes. _Source: https://developer.garmin.com/connect-iq/monkey-c/monkey-types/ (accessed 2026-06-06)_ _(Confidence: Medium — corroborated by community discussion; Garmin docs do not advertise user-defined generics)_

### Memory model — reference counting and cycles

Monkey C uses **reference counting**, not a tracing garbage collector. An object starts with a reference count of 1; the count increments when new references are made and decrements when references go out of scope; at 0 the object is deallocated immediately. _Source: https://pauguillamon.com/2016/04/26/monkey-c-and-monkey-do-a-reflection-about-weak-references/ (accessed 2026-06-06)_ _(Confidence: High)_

The critical consequence: **reference counting cannot reclaim circular references.** If object A references B and B references A (directly or indirectly), neither count ever reaches 0 and the memory leaks for the life of the app. Since Connect IQ 1.2.x, Monkey C provides **weak references** (`Toybox.Lang.WeakReference`) to break cycles. _Source: https://pauguillamon.com/2016/04/26/monkey-c-and-monkey-do-a-reflection-about-weak-references/ (accessed 2026-06-06)_ _(Confidence: High)_

A notable gotcha: the **simulator can detect circular references but deliberately does not collect them** — Garmin's stance is that developers should fix cycles with weak references rather than rely on cycle collection. This means a leak that "works" in casual testing can accumulate until an out-of-memory crash on device. _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/6257/garbage-collection-in-monkey-c (accessed 2026-06-06)_ _(Confidence: Medium — community/forum consensus)_

### Monkey Types: the opt-in static type system

Connect IQ 4 introduced **Monkey Types**, a gradual static type system with **four type-check levels**, configurable per build:

| Level | Behavior |
|---|---|
| **None** (`0`) | Default; no compile-time type checking (pure duck typing). |
| **Gradual** (`1`) | Type-checker only checks safety where typed code interacts with typed code. |
| **Informative** (`2`) | Checks typed interactions and warns about untyped definitions. |
| **Strict** (`3`) | Requires all member variables, function parameters, and return values to be typed; validates all functional code and Toybox API calls. |

_Source: https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/the-road-to-strict-typing-is-paved-with-good-intentions (accessed 2026-06-06)_ _(Confidence: High)_

Types are declared with the **`as` keyword** and are checked **solely at compile time** (erased at runtime). Nullability is explicit via the `?` suffix (e.g. `WatchUi.Text?`). Typed containers use angle-bracket annotations:

```monkeyc
var view = View.findDrawableById("TimeLabel") as WatchUi.Text;
var arr = [] as Lang.Array<Lang.String>;
private var _timeLabel as WatchUi.Text?;
```

The type-checker is "much more aggressive" about flagging potential null-pointer issues — e.g. `Activity.getActivityInfo().currentHeartRate` may be `Number` or `null`, and strict mode forces a null guard or cast. For a **new project by an experienced developer**, Garmin explicitly recommends strict typing because it "requires minimal effort" on greenfield code and "encourages defensive coding." _Source: https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/the-road-to-strict-typing-is-paved-with-good-intentions (accessed 2026-06-06)_ _(Confidence: High)_ A standing community feature request is that the type-check level historically was set via build flag rather than the jungle file. _Source: https://forums.garmin.com/developer/connect-iq/i/bug-reports/feature-request-allow-to-spedify-type-checking-level-in-the-monkey-jungle-file (accessed 2026-06-06)_ _(Confidence: Medium)_

### Current Connect IQ SDK (mid-2026)

The current SDK is **Connect IQ 9.1.0**, last updated **May 12, 2026** (a representative build tag observed was `9.1.0-2026-03-09-...`). _Source: https://developer.garmin.com/connect-iq/sdk/ (accessed 2026-06-06)_ _Source: https://www.notebookcheck.net/Garmin-Connect-IQ-8-1-0-for-enhanced-smart-notifications-now-available.973626.0.html (accessed 2026-06-06)_ _(Confidence: High for version; Medium for exact build string)_

- **SDK Manager** is the entry point and is available for **Windows, macOS, and Linux**. It downloads the SDK and the per-device files (the `devices` definitions used by the build matrix and simulator). _Source: https://developer.garmin.com/connect-iq/sdk/ (accessed 2026-06-06)_ _(Confidence: High)_ On Linux, a community-maintained AppImage packaging exists. _Source: https://github.com/pcolby/connectiq-sdk-manager (accessed 2026-06-06)_ _(Confidence: High)_
- **In the box:** the `monkeyc` compiler, the device **simulator**, the per-device device files, sample code, tools, and libraries. _Source: https://developer.garmin.com/connect-iq/sdk/ (accessed 2026-06-06)_ _(Confidence: High)_
- **Release cadence:** Garmin ships frequent point releases and announces them on the forum's News & Announcements board; there is no fixed public calendar, but updates land roughly every few months. _Source: https://forums.garmin.com/developer/connect-iq/b/news-announcements (accessed 2026-06-06)_ _(Confidence: Medium)_

### Tooling: VS Code Monkey C extension

The **official Monkey C extension** (publisher `garmin`) turns VS Code into the primary Connect IQ IDE: syntax highlighting, build integration, simulator launch, and debugging. _Source: https://marketplace.visualstudio.com/items?itemName=garmin.monkey-c (accessed 2026-06-06)_ _(Confidence: High)_

- **Run/Debug:** Use Run > Start Debugging (or Run Without Debugging, Ctrl/Cmd+F5), select **Monkey C** debugger and a target device; the app launches in the simulator. _Source: https://www.ottorinobruni.com/getting-started-with-garmin-connect-iq-development-build-your-first-watch-face-with-monkey-c-and-vs-code/ (accessed 2026-06-06)_ _(Confidence: High)_
- **Breakpoints and variable inspection** work, but **only under "Start Debugging"** — breakpoints are ignored in "Run Without Debugging." _Source: https://marketplace.visualstudio.com/items?itemName=garmin.monkey-c (accessed 2026-06-06)_ _(Confidence: High)_
- **Command palette** exposes Monkey C commands including **Generate Developer Key**, build, run in simulator, and **Export Project** (build the `.iq` store package). _Source: https://developer.garmin.com/connect-iq/connect-iq-basics/getting-started/ (accessed 2026-06-06)_ _(Confidence: Medium — official getting-started page rendered partially)_
- **Simulator** reproduces device behavior (time formats, backlight, low-battery states) and shows **peak memory usage** (File > View memory) — the primary in-loop memory check. _Source: https://www.garmin.com/en-US/blog/developer/improve-your-app-performance/ (accessed 2026-06-06)_ _(Confidence: High)_

**Community augmentation — strongly recommended:** the **`markw65` Prettier Monkey C** extension adds a source-to-source **optimizer** and a **formatter**. The optimizer inlines `const`/`enum` values, constant-folds expressions, and removes dead code to reduce compiled size and improve performance; it can export an optimized project and build the `.iq`. Installing it auto-installs the official Garmin extension and the Prettier base extension. _Source: https://github.com/markw65/prettier-extension-monkeyc (accessed 2026-06-06)_ _Source: https://marketplace.visualstudio.com/items?itemName=markw65.prettier-extension-monkeyc (accessed 2026-06-06)_ _(Confidence: High)_ A **JetBrains/IntelliJ** plugin also exists for developers preferring that IDE. _Source: https://plugins.jetbrains.com/plugin/8253-monkey-c-garmin-connect-iq- (accessed 2026-06-06)_ _(Confidence: High)_

---

## Integration Patterns Analysis

### Build system: jungle files

Builds are configured through **jungle files** (`monkey.jungle`) — a domain-specific language Garmin describes as "Monkey Make." Unlike `make`, jungles exist primarily to manage **build configuration across many Garmin devices**: they control source paths, resource paths, excludes, annotations, and barrel (library) linkage, using lazy evaluation of properties. _Source: https://developer.garmin.com/connect-iq/reference-guides/jungle-reference/ (accessed 2026-06-06)_ _(Confidence: High)_ The jungle is where per-device customization lives — e.g. different resource folders or excluded source for different screen shapes/sizes/memory budgets. _Source: https://starttorun.info/tackling-connect-iq-versions-screen-shapes-and-memory-limitations-the-jungle-way/ (accessed 2026-06-06)_ _(Confidence: High)_

A typical command-line build invokes `monkeyc` with `-d <device>`, `-f <jungle>`, `-o <output.prg>`, and `-y <developer_key>`. _Source: https://medium.com/@bgallois/garmin-app-development-without-the-visual-studio-code-85628e4b6ba1 (accessed 2026-06-06)_ _(Confidence: High)_

### Resources vs direct drawing

App assets — strings, fonts, layouts, drawables, bitmaps — are declared in XML resource files (e.g. `resources/strings.xml`, layout XML) and compiled into the app; **compiled resource size counts against the per-app memory budget.** Layouts can be defined declaratively in XML or drawn imperatively against the device context (`dc`) in `onUpdate`. For an RSVP reader with a single dynamic word at a fixed focal point, **direct `Dc` drawing** is the natural fit and avoids layout-inflation overhead. _Source: https://www.garmin.com/en-US/blog/developer/improve-your-app-performance/ (accessed 2026-06-06)_ _(Confidence: High)_

### Barrels (shareable libraries)

**Monkey Barrels** are Monkey C's package/library mechanism: source plus resources bundled for reuse across projects. To consume one you declare a dependency in the **manifest** and link it in the **jungle file**. Barrels carry their own internal jungle for build configuration; a barrel built from multiple jungles must be referenced with bracket syntax (`qualifier.barrelPath=[a.jungle;b.jungle]`). _Source: https://developer.garmin.com/connect-iq/core-topics/shareable-libraries/ (accessed 2026-06-06)_ _Source: https://github.com/garmin/connectiq-apps/tree/master/barrels (accessed 2026-06-06)_ _(Confidence: High)_ For garmin_RSVP, barrels are optional at MVP but a clean way to later share the streaming-protocol parsing/buffer code.

### Phone companion messaging (the integration that matters here)

The **`Toybox.Communications`** module is the watch-side API for talking to a paired phone over BLE; the phone may relay to the internet or exchange data directly. Two relevant surfaces: `makeWebRequest` (phone-as-bridge to HTTP) and **direct app-to-companion messaging** (`transmit` plus a registered message listener), which is what the RSVP streaming design needs (companion pushes word chunks; watch requests more; position syncs back). _Source: https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html (accessed 2026-06-06)_ _Source: https://developer.garmin.com/connect-iq/core-topics/communicating-with-mobile-apps/ (accessed 2026-06-06)_ _(Confidence: High)_

The phone side uses the **Connect IQ Mobile SDK** (separate Android and iOS SDKs). The companion registers a listener for messages from the CIQ app and can send messages to it — bidirectional. _Source: https://developer.garmin.com/connect-iq/connect-iq-faq/how-do-i-use-the-connect-iq-mobile-sdk/ (accessed 2026-06-06)_ _Source: https://github.com/garmin/connectiq-android-sdk (accessed 2026-06-06)_ _(Confidence: High)_

**Known constraint to design around:** large transmits can fail with `BLE_REQUEST_TOO_LARGE`; messages must be chunked, which aligns with the "small buffered window + request more" streaming model in the brief. _Source: https://forums.garmin.com/developer/connect-iq/i/bug-reports/started-getting-a-lot-of-ble_request_too_large---outgoing-makewebrequest-doesn-t-even-pass-to-server (accessed 2026-06-06)_ _(Confidence: Medium)_ A worked two-way watch↔phone example exists for iOS. _Source: https://github.com/MatyasKriz/ios-connect-iq-comms (accessed 2026-06-06)_ _(Confidence: High)_

### Testing & CI

- **Framework:** `Toybox.Test`. Tests are plain functions annotated `(:test)`, receive a `Logger`, and return a boolean (with `Test.assert*` helpers). Test functions are stripped from non-test builds. _Source: https://developer.garmin.com/connect-iq/api-docs/Toybox/Test.html (accessed 2026-06-06)_ _Source: https://developer.garmin.com/connect-iq/core-topics/unit-testing/ (accessed 2026-06-06)_ _(Confidence: High)_
- **Running tests:** historically via the Eclipse "Run No Evil" profile; in the modern toolchain tests run in a **test-mode build** executed in the simulator, which prints a RESULTS table (test name, status, pass/fail counts). _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/319988/unit-test-example-how-to-run-it (accessed 2026-06-06)_ _Source: https://starttorun.info/tutorial-run-connect-iq-unit-tests/ (accessed 2026-06-06)_ _(Confidence: High)_
- **CI (turnkey):** `matco/action-connectiq-tester@v1` runs CIQ tests on GitHub Actions with a `device` input (e.g. `fenix7`); it wraps the Docker image `ghcr.io/matco/connectiq-tester` to run the SDK + headless simulator. A real, copyable workflow lives in the **`matco/badminton`** repo (`.github/workflows/test.yml`: checkout → run tester action on `fenix7`). _Source: https://github.com/marketplace/actions/connectiq-tester (accessed 2026-06-06)_ _Source: https://raw.githubusercontent.com/matco/badminton/dev/.github/workflows/test.yml (accessed 2026-06-06)_ _(Confidence: High)_
- **Maturity caveat:** the testing story is real but thin compared to Kotlin/Dart — no rich mocking ecosystem, UI testing is limited, and the practical pattern is to keep **pure model/logic in testable classes** (e.g. word-stream pacing, buffer management) and unit-test those, exactly as the badminton app tests its `Match` model. _Source: https://github.com/matco/badminton/blob/dev/.github/workflows/test.yml (accessed 2026-06-06)_ _(Confidence: Medium)_

### Store publishing workflow

- **Submission** is via the developer dashboard at `developer.garmin.com/connect-iq/submit-an-app/`. _Source: https://developer.garmin.com/connect-iq/submit-an-app/ (accessed 2026-06-06)_ _(Confidence: High)_
- **Review time:** apps are normally approved within **a couple of business days**; apps declaring ANT+ profiles take longer due to a separate ANT certification step (not relevant to an RSVP reader). _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/225073/what-is-the-app-approval-time-in-covid-19 (accessed 2026-06-06)_ _(Confidence: Medium)_
- **2025 policy change:** in February 2025 Garmin tightened requirements and a wave of (mostly paid) apps were temporarily removed pending a **developer verification** process; free/open-source apps are simpler to clear but plan for identity verification. _Source: https://the5krunner.com/2025/02/17/many-garmin-paid-for-apps-disappear-from-connect-iq-store/ (accessed 2026-06-06)_ _(Confidence: Medium)_
- **Beta distribution:** Connect IQ supports beta-published apps for limited testing distribution before public release. _Source: https://forums.garmin.com/developer/connect-iq/i/bug-reports/garmin-beta-published-connect-iq-app-crashes (accessed 2026-06-06)_ _(Confidence: Medium)_

---

## Architectural Patterns Analysis

### App lifecycle

A Connect IQ app is anchored by an **`AppBase`** subclass plus one or more **`WatchUi.View`** classes and input **delegates**:

- **`AppBase.onStart()`** — called at startup before the initial view; initialize/load app-level state (object store). **`onStop()`** — called on exit; persist state. Both are also invoked by the background process if one exists. _Source: https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/AppBase.html (accessed 2026-06-06)_ _(Confidence: High)_
- **`AppBase.getInitialView()`** — returns the initial `View` (and input delegate). Only invoked by the main app, never by a background process. _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/214445/a-little-help-understanding-app-view-lifecycles (accessed 2026-06-06)_ _(Confidence: High)_
- **View lifecycle:** `onLayout(dc)` (one-time setup; load resources), `onShow()` (foregrounded; load resources/state), `onUpdate(dc)` (render — keep it cheap), `onHide()` (backgrounded; free resources/save state). _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/214445/a-little-help-understanding-app-view-lifecycles (accessed 2026-06-06)_ _(Confidence: High)_

### Idiomatic structure for garmin_RSVP

The RSVP reader is a foreground **application** (not a watch face or data field — which have stricter memory caps and update constraints). A clean structure:

- **`AppBase`** subclass: owns the BLE `Communications` connection and the word-buffer model; loads resume position in `onStart`, persists it in `onStop`.
- **`View`** (RSVP renderer): in `onUpdate(dc)`, draw the current word with the ORP/pivot letter highlighted at a fixed x-anchor; drive word advancement with a **`Timer`** rather than blocking, so timing stays decoupled from the render watchdog.
- **`InputDelegate`** (`BehaviorDelegate`/`InputDelegate`): map buttons/touch to play/pause, WPM up/down, and quick-rewind.
- **Model classes** (pure logic): word-stream pacing (variable dwell), ring-buffer of the streaming window, position tracking — keep these free of UI/`Toybox` UI types so they are unit-testable and CI-friendly. _Source: https://github.com/matco/badminton/blob/dev/.github/workflows/test.yml (accessed 2026-06-06)_ _(Confidence: Medium — synthesized from lifecycle docs + testable-model pattern)_

Render budget is a hard architectural constraint: drawing a single screen can take **hundreds of milliseconds**, and heavy `onUpdate` work makes the app unresponsive or trips the watchdog. Pre-compute everything possible in `onLayout`/`onShow`, cache, and keep `onUpdate` to "draw the already-decided next word." _Source: https://www.garmin.com/en-US/blog/developer/improve-your-app-performance/ (accessed 2026-06-06)_ _(Confidence: High)_

### Per-device build matrix and capability gating

Multi-device support is a first-class architectural concern handled by the jungle (resources/excludes per device) and by **runtime `has` checks** for API/feature availability, so a single codebase degrades gracefully across firmware/device variation. _Source: https://developer.garmin.com/connect-iq/monkey-c/annotations/ (accessed 2026-06-06)_ _Source: https://starttorun.info/tackling-connect-iq-versions-screen-shapes-and-memory-limitations-the-jungle-way/ (accessed 2026-06-06)_ _(Confidence: High)_ Since garmin_RSVP targets **only the Fenix 8** at MVP, the matrix is trivial initially — but structuring resources and using `has` from day one makes the later "other CIQ devices" expansion cheap.

---

## Implementation Research

### Memory limits — the dominant constraint

Each device has its own per-app memory budget that varies by **app type**: e.g. a Fenix 5 allows ~92 kB for a watch face but only ~28 kB for a data field. The exact limits live in the device's definition file in the SDK device folder. _Source: https://www.garmin.com/en-US/blog/developer/improve-your-app-performance/ (accessed 2026-06-06)_ _Source: https://support.garmin.com/en-US/?faq=tFmJJnTfs83yuPc8kttAh7 (accessed 2026-06-06)_ _(Confidence: High)_ The **compiled app plus all loaded resources** (fonts, strings, settings) counts against this limit — custom fonts and large localization tables are common silent over-budget causes. _Source: https://www.garmin.com/en-US/blog/developer/improve-your-app-performance/ (accessed 2026-06-06)_ _(Confidence: High)_

The **Fenix 8** is comparatively generous: reports indicate ~**128 KB / 256 KB** budgets for data-field-class apps (a large jump over older devices), and full applications get more headroom than data fields. The authoritative figure for garmin_RSVP should be read directly from the Fenix 8 entry in the SDK device files (the brief's open question). _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/382120/fenix-8-data-field (accessed 2026-06-06)_ _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/418612/device-memory-limits (accessed 2026-06-06)_ _(Confidence: Medium — forum-reported; verify in `devices` files)_ Practically: a streaming RSVP reader that buffers only a small word window is well within budget; the risk is in fonts and accidental retention, not the text stream itself.

### The week-1 vs month-2 pitfall map

**What will bite in week 1 (fast to hit, fast to learn):**

1. **"Unexpected Type" / symbol-not-found runtime crashes.** With duck typing, a typo or wrong-type assumption compiles fine and crashes on device/sim. *Mitigation:* enable Monkey Types at **Gradual or Strict** from the first commit. _Source: https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/the-road-to-strict-typing-is-paved-with-good-intentions (accessed 2026-06-06)_ _(Confidence: High)_
2. **Null surprises.** API calls return nullable values (`getActivityInfo().currentHeartRate` etc.); without strict typing these blow up at runtime. *Mitigation:* strict typing forces the guards. _Source: https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/the-road-to-strict-typing-is-paved-with-good-intentions (accessed 2026-06-06)_ _(Confidence: High)_
3. **`findDrawableById` returns base `Drawable`.** You must cast (`as WatchUi.Text`) to use specific members — a constant friction point that the type system surfaces. _Source: https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/the-road-to-strict-typing-is-paved-with-good-intentions (accessed 2026-06-06)_ _(Confidence: High)_
4. **Breakpoints silently ignored.** Forgetting that breakpoints only work under "Start Debugging" (not "Run Without Debugging") wastes time. _Source: https://marketplace.visualstudio.com/items?itemName=garmin.monkey-c (accessed 2026-06-06)_ _(Confidence: High)_
5. **Developer key setup.** You cannot build/run without generating a 4096-bit RSA developer key first (`Tools > Generate Developer Key` or OpenSSL). A trivial but mandatory first step that blocks everything. _Source: https://forums.garmin.com/developer/connect-iq/w/wiki/4/new-developer-faq (accessed 2026-06-06)_ _(Confidence: High)_

**What will bite in month 2 (subtle, costly, hardware-only):**

1. **Out-of-memory crashes on device that the sim didn't show.** Driven by reference cycles and resource bloat accumulating over a long reading session. *Mitigation:* weak references for back-pointers (View↔model, delegate↔view), watch the simulator's peak-memory readout, run the optimizer. _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/6257/garbage-collection-in-monkey-c (accessed 2026-06-06)_ _Source: https://github.com/markw65/prettier-extension-monkeyc (accessed 2026-06-06)_ _(Confidence: Medium)_
2. **Watchdog/`onUpdate` time limits.** Expensive per-frame work (re-layout, string processing during render) makes the app sluggish or gets it killed — especially relevant at 700+ WPM where frames are ~85 ms apart. *Mitigation:* timer-driven advancement, pre-computed pacing, minimal `onUpdate`. _Source: https://www.garmin.com/en-US/blog/developer/improve-your-app-performance/ (accessed 2026-06-06)_ _(Confidence: High)_
3. **BLE chunking limits (`BLE_REQUEST_TOO_LARGE`).** Streaming design must chunk and flow-control rather than pushing whole chapters. _Source: https://forums.garmin.com/developer/connect-iq/i/bug-reports/started-getting-a-lot-of-ble_request_too_large---outgoing-makewebrequest-doesn-t-even-pass-to-server (accessed 2026-06-06)_ _(Confidence: Medium)_
4. **Resume-position durability.** Persisting to the object store/Storage API correctly across `onStop`, disconnects, and reboots is the brief's "resume never lies" requirement; legacy storage is tiny (~6 kB) vs the newer Storage API (~100 kB total, ~8 kB/entry). _Source: https://www.garmin.com/en-US/blog/developer/improve-your-app-performance/ (accessed 2026-06-06)_ _(Confidence: Medium)_
5. **Per-device expansion.** When moving beyond Fenix 8, screen shape/size/memory differences surface; the jungle + `has` discipline pays off here. _Source: https://starttorun.info/tackling-connect-iq-versions-screen-shapes-and-memory-limitations-the-jungle-way/ (accessed 2026-06-06)_ _(Confidence: High)_

### Debugging & crash analysis story

- **In-sim:** breakpoints, variable inspection, console (`System.println`), and a profiler/memory viewer. _Source: https://www.garmin.com/en-US/blog/developer/improve-your-app-performance/ (accessed 2026-06-06)_ _(Confidence: High)_
- **On-device logs:** `System.println` writes to `/GARMIN/APPS/LOGS/<APPNAME>.TXT`; crashes write `/GARMIN/APPS/LOGS/CIQ_LOG.YML` (older devices: `.TXT`) containing a call stack. Logs roll to `.BAK` past ~5 kB, so practical log space is ~10 kB — log sparingly. _Source: https://forums.garmin.com/developer/connect-iq/w/wiki/4/new-developer-faq (accessed 2026-06-06)_ _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/231129/so-you-have-a-ciq_log-file-but-all-you-see-is-pc-without-a-friendly-stack-trace---what-to-do/1095959 (accessed 2026-06-06)_ _(Confidence: High)_
- **Raw `pc:` stacks:** a crash log without symbols shows only hex program-counter values; you decode them with the `debug.xml` produced for that target (bundled inside the `.iq` you submit). _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/231129/so-you-have-a-ciq_log-file-but-all-you-see-is-pc-without-a-friendly-stack-trace---what-to-do/1095959 (accessed 2026-06-06)_ _(Confidence: High)_
- **ERA (Error Reporting Application):** introduced in CIQ 3.1 (April 2019), ERA aggregates crash reports from published apps in a viewer on the developer dashboard after users sync — proactive post-release crash monitoring. _Source: https://developer.garmin.com/connect-iq/core-topics/exception-reporting-tool/ (accessed 2026-06-06)_ _(Confidence: High)_

### Learning resources & quality

- **Official docs** (`developer.garmin.com/connect-iq`): the Monkey C reference, Core Topics (unit testing, communicating with mobile apps, shareable libraries, debugging, security), the Jungle reference, and the **Toybox API docs** (`/connect-iq/api-docs/`). Generally solid and the canonical source, though some guide pages are terse and a few areas (barrels/jungle) have acknowledged documentation gaps. _Source: https://developer.garmin.com/connect-iq/reference-guides/ (accessed 2026-06-06)_ _Source: https://forums.garmin.com/developer/connect-iq/i/bug-reports/barrel-jungle-documentation-is-unclear (accessed 2026-06-06)_ _(Confidence: High / Medium)_
- **Sample apps:** the official **`garmin/connectiq-apps`** repo (apps + barrels) and the community **`douglasr/connectiq-samples`** (snippets, quasi-libraries, more complete examples). _Source: https://github.com/garmin/connectiq-apps (accessed 2026-06-06)_ _Source: https://github.com/douglasr/connectiq-samples (accessed 2026-06-06)_ _(Confidence: High)_
- **Curated index:** **`bombsimon/awesome-garmin`** lists apps, tools, and notably **two-way iOS-companion communication examples** — directly relevant to the streaming protocol. _Source: https://github.com/bombsimon/awesome-garmin (accessed 2026-06-06)_ _(Confidence: High)_
- **Community:** the **Garmin Connect IQ developer forum** is the primary, high-signal Q&A venue (App Development Discussion, Bug Reports, News & Announcements, Wiki/New Developer FAQ). Tutorial sites (Start To Run, Ottorino Bruni) and Medium series (Eduardo Arellano's "Monkey C Fundamentals"/"Next Steps") fill gaps. _Source: https://forums.garmin.com/developer/connect-iq (accessed 2026-06-06)_ _Source: https://starttorun.info/connect-iq-apps-with-source-code/ (accessed 2026-06-06)_ _Source: https://medium.com/@earel329/garmin-iq-and-monkey-c-fundamentals-ffe83eebb3fc (accessed 2026-06-06)_ _(Confidence: High)_

### Recommended learning path (for a Kotlin/Dart developer)

1. **Day 0:** Install SDK Manager → pull SDK 9.1.0 + Fenix 8 device files; install the official Monkey C extension **and** `markw65` Prettier Monkey C; generate the developer key. _Source: https://developer.garmin.com/connect-iq/sdk/ (accessed 2026-06-06)_
2. **Day 1:** Build/run the "your first app" walkthrough in the simulator; learn the Start-Debugging breakpoint workflow and the memory viewer. _Source: https://developer.garmin.com/connect-iq/connect-iq-basics/your-first-app/ (accessed 2026-06-06)_
3. **Week 1:** Turn on **Monkey Types (Strict)** immediately; read the strict-typing post and the AppBase/View lifecycle docs; prototype a timer-driven single-word `onUpdate` render with the ORP highlight. _Source: https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/the-road-to-strict-typing-is-paved-with-good-intentions (accessed 2026-06-06)_
4. **Week 2:** Study `Toybox.Communications` + the iOS comms example + an `awesome-garmin` companion app; stand up the BLE message loop against the Android companion. _Source: https://developer.garmin.com/connect-iq/core-topics/communicating-with-mobile-apps/ (accessed 2026-06-06)_
5. **Week 3+:** Extract pure model classes (pacing, buffer, position) and wire `matco/action-connectiq-tester` CI; sideload a `.prg` to the real Fenix 8 and validate memory + watchdog behavior on hardware. _Source: https://github.com/marketplace/actions/connectiq-tester (accessed 2026-06-06)_

### Exemplar open-source repositories to study

- **`matco/badminton`** — clean app with unit-tested model classes and a working GitHub Actions CI; best template for testing + CI. _Source: https://github.com/matco/badminton/blob/dev/.github/workflows/test.yml (accessed 2026-06-06)_
- **`garmin/connectiq-apps`** — official apps + barrels; canonical idioms and the barrels pattern. _Source: https://github.com/garmin/connectiq-apps (accessed 2026-06-06)_
- **`douglasr/connectiq-samples`** — community snippets/quasi-libraries for common functionality. _Source: https://github.com/douglasr/connectiq-samples (accessed 2026-06-06)_
- **`MatyasKriz/ios-connect-iq-comms`** — end-to-end two-way watch↔phone messaging example (companion protocol reference). _Source: https://github.com/MatyasKriz/ios-connect-iq-comms (accessed 2026-06-06)_
- **`bombsimon/awesome-garmin`** — curated index to find more companion-messaging apps. _Source: https://github.com/bombsimon/awesome-garmin (accessed 2026-06-06)_
- **`markw65/prettier-extension-monkeyc`** / **`monkeyc-optimizer`** — tooling to adopt, and a reference for what the optimizer changes. _Source: https://github.com/markw65/prettier-extension-monkeyc (accessed 2026-06-06)_

---

## Research Synthesis

### Executive Summary

Monkey C will not be the hard part of garmin_RSVP — the embedded constraints around it will be. For an experienced Kotlin/Dart developer, the language reads as a familiar OO language with modules, classes, and a standard library (Toybox); the genuinely new material is (a) a duck-typed-by-default runtime with an **opt-in gradual static type system** that should be switched to **Strict on day one**, (b) **reference-counting memory management** that leaks on cycles and is bounded by tight per-app budgets, and (c) a **render watchdog** that punishes heavy `onUpdate`. The toolchain is mature enough: the official VS Code extension provides build/run/debug-with-breakpoints/variable-inspection against a desktop simulator with a memory viewer, augmented by the community `markw65` optimizer; testing exists (`Toybox.Test`) and there is a turnkey GitHub Actions path (`matco/action-connectiq-tester`). The store review is light (a couple of business days for a free app, modulo the 2025 developer-verification tightening). The Fenix 8 is a generously-resourced target, and `Toybox.Communications` is exactly the BLE companion-messaging surface the streaming architecture needs — provided messages are chunked to avoid `BLE_REQUEST_TOO_LARGE`.

### Key Findings

1. **Enable Monkey Types (Strict) immediately.** It converts the language's biggest newcomer hazard — runtime "Unexpected Type"/null crashes — into compile-time errors, at near-zero cost on greenfield code. _Source: https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/the-road-to-strict-typing-is-paved-with-good-intentions_ _(Confidence: High)_
2. **Reference counting + no cycle collection = design for weak references.** The simulator detects but won't collect cycles; long reading sessions are exactly where leaks become OOM crashes. _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/6257/garbage-collection-in-monkey-c_ _(Confidence: Medium)_
3. **Memory budget includes resources.** Fonts and strings count; Fenix 8 is roomy (reported ~128–256 KB class) but verify in the SDK device files. _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/382120/fenix-8-data-field_ _(Confidence: Medium)_
4. **`onUpdate` is on a watchdog.** Single-screen draws can take hundreds of ms; drive RSVP advancement with a `Timer` and keep render trivial. _Source: https://www.garmin.com/en-US/blog/developer/improve-your-app-performance/_ _(Confidence: High)_
5. **SDK 9.1.0 (May 2026) is current**, with cross-platform SDK Manager and the standard toolchain in the box. _Source: https://developer.garmin.com/connect-iq/sdk/_ _(Confidence: High)_
6. **Tooling is good enough**, and meaningfully better with the `markw65` optimizer/formatter. _Source: https://github.com/markw65/prettier-extension-monkeyc_ _(Confidence: High)_
7. **CI is solved out-of-the-box** via `matco/action-connectiq-tester`, with `matco/badminton` as a copyable reference. _Source: https://github.com/marketplace/actions/connectiq-tester_ _(Confidence: High)_
8. **BLE companion messaging is first-class** (`Toybox.Communications` + Mobile SDK) but must be chunked. _Source: https://developer.garmin.com/connect-iq/core-topics/communicating-with-mobile-apps/_ _(Confidence: High)_
9. **Store review is fast and light** for a free app; budget for developer verification post-2025. _Source: https://the5krunner.com/2025/02/17/many-garmin-paid-for-apps-disappear-from-connect-iq-store/_ _(Confidence: Medium)_
10. **Crash debugging is workable but rough:** size-limited on-device logs, hex `pc:` stacks needing `debug.xml` decode, and ERA for post-release aggregation. _Source: https://developer.garmin.com/connect-iq/core-topics/exception-reporting-tool/_ _(Confidence: High)_

### Recommendations for garmin_RSVP

1. **Strict typing from commit 1.** Non-negotiable for a newcomer; it is the cheapest bug-prevention available.
2. **Build it as a full foreground application**, not a watch face/data field — more memory headroom and fewer update constraints.
3. **Timer-driven render loop.** Pre-compute pacing (variable dwell baked into the stream per the brief); `onUpdate` only draws the already-selected word + ORP pivot. Use direct `Dc` drawing, not XML layouts.
4. **Weak references for back-pointers** (view↔model, delegate↔view) to prevent session-length leaks; watch the sim memory viewer and run the `markw65` optimizer before measuring size.
5. **Chunked, flow-controlled BLE protocol** (small buffered word window + "request more"), explicitly handling `BLE_REQUEST_TOO_LARGE`; study `MatyasKriz/ios-connect-iq-comms` and an `awesome-garmin` companion app.
6. **Persist resume position robustly** via the Storage API in `onStop` and on safe checkpoints; treat "resume never lies" as a tested invariant.
7. **Keep model logic UI-free and unit-tested**, wired into `matco/action-connectiq-tester` CI from early on, mirroring `matco/badminton`.
8. **Structure resources + use `has` now** even though only Fenix 8 ships first, to make multi-device expansion cheap later.
9. **Sideload to the real Fenix 8 early** — memory and watchdog behavior differ from the simulator; do not trust sim-only validation.

### Risks and Open Questions

- **Exact Fenix 8 app memory budget** is forum-reported, not yet confirmed from the SDK device files — read it from the Fenix 8 entry in the installed SDK `devices`/device XML to size the word buffer. _Source: https://forums.garmin.com/developer/connect-iq/f/discussion/418612/device-memory-limits_ _(Confidence: Medium)_
- **BLE throughput/latency at high WPM** (700+ → ~85 ms/word) under chunked delivery is unverified for this workload; prototype and measure on hardware. _Source: https://forums.garmin.com/developer/connect-iq/i/bug-reports/started-getting-a-lot-of-ble_request_too_large---outgoing-makewebrequest-doesn-t-even-pass-to-server_ _(Confidence: Low)_
- **Several official doc pages render as SPAs** and could not be fetched directly; type-level, lifecycle, and tooling details were triangulated from forum/blog/snippet sources and should be reconfirmed against the live docs during build. _(Confidence: Medium)_
- **Generics absence** is asserted from community signal + absence in official docs rather than an explicit Garmin statement. _(Confidence: Medium)_
- **2025 store-verification specifics** for a free open-source app are not fully documented publicly; confirm current requirements at submission time. _(Confidence: Low)_

### Source Documentation

Official Garmin (accessed 2026-06-06):
- Monkey Types — https://developer.garmin.com/connect-iq/monkey-c/monkey-types/ _(High)_
- Strict typing announcement — https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/the-road-to-strict-typing-is-paved-with-good-intentions _(High)_
- Annotations / `has` — https://developer.garmin.com/connect-iq/monkey-c/annotations/ _(High)_
- Get the SDK — https://developer.garmin.com/connect-iq/sdk/ _(High)_
- Toybox.Application.AppBase — https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/AppBase.html _(High)_
- Toybox.Communications — https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html _(High)_
- Communicating with Mobile Apps — https://developer.garmin.com/connect-iq/core-topics/communicating-with-mobile-apps/ _(High)_
- How Do I Use the Connect IQ Mobile SDK — https://developer.garmin.com/connect-iq/connect-iq-faq/how-do-i-use-the-connect-iq-mobile-sdk/ _(High)_
- Toybox.Test — https://developer.garmin.com/connect-iq/api-docs/Toybox/Test.html _(High)_
- Unit Testing — https://developer.garmin.com/connect-iq/core-topics/unit-testing/ _(High)_
- Shareable Libraries (barrels) — https://developer.garmin.com/connect-iq/core-topics/shareable-libraries/ _(High)_
- Jungle Reference — https://developer.garmin.com/connect-iq/reference-guides/jungle-reference/ _(High)_
- VS Code Extension reference — https://developer.garmin.com/connect-iq/reference-guides/visual-studio-code-extension/ _(Medium — SPA, partial fetch)_
- Getting Started / SDK Manager — https://developer.garmin.com/connect-iq/connect-iq-basics/getting-started/ _(Medium)_
- Your First App — https://developer.garmin.com/connect-iq/connect-iq-basics/your-first-app/ _(Medium)_
- App performance blog — https://www.garmin.com/en-US/blog/developer/improve-your-app-performance/ _(High)_
- ERA (Exception Reporting) — https://developer.garmin.com/connect-iq/core-topics/exception-reporting-tool/ _(High)_
- Submit an App — https://developer.garmin.com/connect-iq/submit-an-app/ _(High)_
- Reference Guides index — https://developer.garmin.com/connect-iq/reference-guides/ _(High)_

Garmin forum (accessed 2026-06-06):
- App/View lifecycle — https://forums.garmin.com/developer/connect-iq/f/discussion/214445/a-little-help-understanding-app-view-lifecycles _(High)_
- Garbage collection / cycles — https://forums.garmin.com/developer/connect-iq/f/discussion/6257/garbage-collection-in-monkey-c _(Medium)_
- Device memory limits — https://forums.garmin.com/developer/connect-iq/f/discussion/418612/device-memory-limits _(Medium)_
- Fenix 8 data field memory — https://forums.garmin.com/developer/connect-iq/f/discussion/382120/fenix-8-data-field _(Medium)_
- BLE_REQUEST_TOO_LARGE — https://forums.garmin.com/developer/connect-iq/i/bug-reports/started-getting-a-lot-of-ble_request_too_large---outgoing-makewebrequest-doesn-t-even-pass-to-server _(Medium)_
- Unit test example & how to run — https://forums.garmin.com/developer/connect-iq/f/discussion/319988/unit-test-example-how-to-run-it _(High)_
- Crash log `pc:` decode — https://forums.garmin.com/developer/connect-iq/f/discussion/231129/so-you-have-a-ciq_log-file-but-all-you-see-is-pc-without-a-friendly-stack-trace---what-to-do/1095959 _(High)_
- New Developer FAQ (wiki) — https://forums.garmin.com/developer/connect-iq/w/wiki/4/new-developer-faq _(High)_
- Approval time — https://forums.garmin.com/developer/connect-iq/f/discussion/225073/what-is-the-app-approval-time-in-covid-19 _(Medium)_
- Type-check level feature request — https://forums.garmin.com/developer/connect-iq/i/bug-reports/feature-request-allow-to-spedify-type-checking-level-in-the-monkey-jungle-file _(Medium)_
- Barrel/jungle docs unclear — https://forums.garmin.com/developer/connect-iq/i/bug-reports/barrel-jungle-documentation-is-unclear _(Medium)_
- News & Announcements board — https://forums.garmin.com/developer/connect-iq/b/news-announcements _(Medium)_
- Forum root — https://forums.garmin.com/developer/connect-iq _(High)_

GitHub / tooling (accessed 2026-06-06):
- matco/action-connectiq-tester (marketplace) — https://github.com/marketplace/actions/connectiq-tester _(High)_
- matco/badminton CI workflow — https://raw.githubusercontent.com/matco/badminton/dev/.github/workflows/test.yml _(High)_
- garmin/connectiq-apps — https://github.com/garmin/connectiq-apps _(High)_
- garmin/connectiq-apps barrels — https://github.com/garmin/connectiq-apps/tree/master/barrels _(High)_
- garmin/connectiq-android-sdk — https://github.com/garmin/connectiq-android-sdk _(High)_
- douglasr/connectiq-samples — https://github.com/douglasr/connectiq-samples _(High)_
- bombsimon/awesome-garmin — https://github.com/bombsimon/awesome-garmin _(High)_
- MatyasKriz/ios-connect-iq-comms — https://github.com/MatyasKriz/ios-connect-iq-comms _(High)_
- markw65/prettier-extension-monkeyc — https://github.com/markw65/prettier-extension-monkeyc _(High)_
- markw65/monkeyc-optimizer — https://github.com/markw65/monkeyc-optimizer _(High)_
- pcolby/connectiq-sdk-manager (Linux AppImage) — https://github.com/pcolby/connectiq-sdk-manager _(High)_

Marketplace / community / blogs (accessed 2026-06-06):
- Official Monkey C VS Code extension — https://marketplace.visualstudio.com/items?itemName=garmin.monkey-c _(High)_
- Prettier Monkey C (markw65) — https://marketplace.visualstudio.com/items?itemName=markw65.prettier-extension-monkeyc _(High)_
- IntelliJ Monkey C plugin — https://plugins.jetbrains.com/plugin/8253-monkey-c-garmin-connect-iq- _(High)_
- Ottorino Bruni getting-started — https://www.ottorinobruni.com/getting-started-with-garmin-connect-iq-development-build-your-first-watch-face-with-monkey-c-and-vs-code/ _(High)_
- Benjamin Gallois (CLI without extension) — https://medium.com/@bgallois/garmin-app-development-without-the-visual-studio-code-85628e4b6ba1 _(Medium)_
- Start To Run (jungle / multi-device) — https://starttorun.info/tackling-connect-iq-versions-screen-shapes-and-memory-limitations-the-jungle-way/ _(High)_
- Start To Run (run unit tests) — https://starttorun.info/tutorial-run-connect-iq-unit-tests/ _(High)_
- Start To Run (apps with source) — https://starttorun.info/connect-iq-apps-with-source-code/ _(High)_
- Pau Guillamon (weak references) — https://pauguillamon.com/2016/04/26/monkey-c-and-monkey-do-a-reflection-about-weak-references/ _(High)_
- Eduardo Arellano (Monkey C Fundamentals) — https://medium.com/@earel329/garmin-iq-and-monkey-c-fundamentals-ffe83eebb3fc _(Medium)_
- the5krunner (2025 store removals) — https://the5krunner.com/2025/02/17/many-garmin-paid-for-apps-disappear-from-connect-iq-store/ _(Medium)_
- Garmin Customer Support (app limits) — https://support.garmin.com/en-US/?faq=tFmJJnTfs83yuPc8kttAh7 _(High)_
- Notebookcheck (CIQ version news) — https://www.notebookcheck.net/Garmin-Connect-IQ-8-1-0-for-enhanced-smart-notifications-now-available.973626.0.html _(Medium)_
